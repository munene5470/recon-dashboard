import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import sqlite3 from 'sqlite3';
import express from 'express';
import cors from 'cors';
import { spawn } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, '..');
const DATA_DIR = path.join(ROOT_DIR, 'data');
const DB_PATH = path.join(DATA_DIR, 'recon.db');
const app = express();
const port = Number(process.env.PORT || 4000);
fs.mkdirSync(DATA_DIR, { recursive: true });
const db = new sqlite3.Database(DB_PATH);

db.run(`CREATE TABLE IF NOT EXISTS scans (id INTEGER PRIMARY KEY AUTOINCREMENT, target TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'queued', output_dir TEXT, aggressive INTEGER NOT NULL DEFAULT 0, scope_file TEXT, resume_dir TEXT, diff_dir TEXT, log TEXT DEFAULT '', summary TEXT DEFAULT '{}', created_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)`);
app.use(cors());
app.use(express.json({ limit: '2mb' }));

const targetName = (value) => String(value || '').trim().replace(/^https?:\/\//i, '').replace(/\/$/, '');
const validTarget = (value) => value.length <= 253 && /^[a-zA-Z0-9.-]+$/.test(value) && !value.startsWith('.') && !value.endsWith('.');
const outputName = (target) => `recon_${target}_${new Date().toISOString().replace(/[:.]/g, '').slice(0, 15)}`;

function updateScan(id, fields) {
  const keys = Object.keys(fields);
  const values = keys.map((key) => fields[key]);
  db.run(`UPDATE scans SET ${keys.map((key) => `${key} = ?`).join(', ')}, updated_at = ? WHERE id = ?`, [...values, new Date().toISOString(), id], (error) => { if (error) console.error(error.message); });
}
function readFile(file) { try { return fs.readFileSync(file, 'utf8'); } catch { return '{}'; } }
function startScan(scan) {
  const script = path.join(ROOT_DIR, 'scripts', 'EliteV11.sh');
  if (!fs.existsSync(script)) return updateScan(scan.id, { status: 'failed', log: `Missing scanner: ${script}` });
  const args = [script, scan.target];
  if (scan.scope_file) args.push('--scope', scan.scope_file);
  if (scan.resume_dir) args.push('--resume', scan.resume_dir);
  if (scan.diff_dir) args.push('--diff', scan.diff_dir);
  if (scan.aggressive) args.push('--aggressive');
  const child = spawn('bash', args, { cwd: ROOT_DIR, stdio: ['ignore', 'pipe', 'pipe'] });
  let log = '';
  const append = (chunk) => { log = `${log}${chunk}`.slice(-20000); updateScan(scan.id, { log }); };
  child.stdout.on('data', append); child.stderr.on('data', append);
  child.on('error', (error) => updateScan(scan.id, { status: 'failed', log: `${log}\n${error.message}` }));
  child.on('close', (code) => {
    const directory = scan.resume_dir || scan.output_dir;
    const summary = readFile(path.join(ROOT_DIR, directory, 'findings', 'findings.json'));
    updateScan(scan.id, { status: code === 0 ? 'completed' : 'failed', output_dir: directory, summary, log: `${log}\nProcess exited with code ${code}` });
  });
}

app.get('/api/health', (_, res) => res.json({ ok: true, service: 'elite-recon-dashboard' }));
app.get('/api/scans', (_, res) => db.all('SELECT * FROM scans ORDER BY created_at DESC', [], (error, rows) => error ? res.status(500).json({ error: error.message }) : res.json({ scans: rows })));
app.get('/api/scans/:id', (req, res) => db.get('SELECT * FROM scans WHERE id = ?', [req.params.id], (error, row) => error ? res.status(500).json({ error: error.message }) : row ? res.json({ scan: row }) : res.status(404).json({ error: 'Scan not found' })));
app.get('/api/scans/:id/report', (req, res) => db.get('SELECT output_dir, target FROM scans WHERE id = ?', [req.params.id], (error, scan) => {
  if (error) return res.status(500).json({ error: error.message });
  if (!scan) return res.status(404).json({ error: 'Scan not found' });
  const report = path.resolve(ROOT_DIR, scan.output_dir, 'report', 'report.md');
  if (!report.startsWith(`${ROOT_DIR}${path.sep}`) || !fs.existsSync(report)) return res.status(404).json({ error: 'Report is not available yet' });
  res.download(report, `${scan.target}-report.md`);
}));
app.post('/api/scans', (req, res) => {
  const { scopeFile = '', resumeDir = '', diffDir = '', aggressive = false } = req.body || {};
  const target = targetName(req.body?.target);
  if (!validTarget(target)) return res.status(400).json({ error: 'Enter a valid hostname, for example example.com.' });
  const record = { target, status: 'queued', output_dir: resumeDir || outputName(target), aggressive: aggressive ? 1 : 0, scope_file: scopeFile, resume_dir: resumeDir, diff_dir: diffDir };
  db.run('INSERT INTO scans (target,status,output_dir,aggressive,scope_file,resume_dir,diff_dir) VALUES (?,?,?,?,?,?,?)', Object.values(record), function (error) {
    if (error) return res.status(500).json({ error: error.message });
    const scan = { id: this.lastID, ...record }; updateScan(scan.id, { status: 'running', log: `Starting scan for ${target}` }); startScan(scan); res.status(201).json({ scan });
  });
});
app.listen(port, () => console.log(`Recon dashboard API running on http://localhost:${port}`));
