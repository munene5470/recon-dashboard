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
const PORT = Number(process.env.PORT || 4000);
const app = express();
const db = new sqlite3.Database(DB_PATH);

const STAGES = [
  ['01-subdomains', 'Subdomain enumeration', 'HIGH'],
  ['02-dns', 'DNS resolution and scope filtering', 'HIGH'],
  ['03-alive', 'Alive host discovery', 'HIGH'],
  ['04-ports', 'Port and service enumeration', 'HIGH'],
  ['05-crawl', 'Web crawling and URL discovery', 'HIGH'],
  ['06-params', 'Parameter and endpoint discovery', 'MEDIUM'],
  ['07-tech', 'Technology fingerprinting', 'HIGH'],
  ['08-tls', 'TLS and crypto audit', 'HIGH'],
  ['09-api', 'API and GraphQL discovery', 'HIGH'],
  ['10-misconfig', 'Security misconfiguration audit', 'HIGH'],
  ['11-injection', 'Injection testing', 'HIGH'],
  ['12-access-control', 'Broken access control candidates', 'HIGH'],
  ['13-takeover', 'Subdomain takeover checks', 'HIGH'],
  ['14-secrets', 'Sensitive data exposure', 'HIGH'],
  ['15-nuclei', 'Template-based vulnerability scanning', 'HIGH'],
  ['16-report', 'Reporting and aggregation', 'HIGH'],
];

fs.mkdirSync(DATA_DIR, { recursive: true });

db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS scans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued',
    output_dir TEXT,
    aggressive INTEGER NOT NULL DEFAULT 0,
    scope_file TEXT,
    resume_dir TEXT,
    diff_dir TEXT,
    log TEXT DEFAULT '',
    summary TEXT DEFAULT '{}',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )`);
  db.run(`CREATE TABLE IF NOT EXISTS scan_stages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id INTEGER NOT NULL,
    stage_key TEXT NOT NULL,
    phase INTEGER NOT NULL,
    name TEXT NOT NULL,
    priority TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued',
    message TEXT DEFAULT '',
    input_files TEXT DEFAULT '[]',
    output_files TEXT DEFAULT '[]',
    started_at DATETIME,
    completed_at DATETIME,
    exit_code INTEGER,
    FOREIGN KEY(scan_id) REFERENCES scans(id),
    UNIQUE(scan_id, stage_key)
  )`);
});

app.use(cors());
app.use(express.json({ limit: '2mb' }));

const cleanTarget = (value) => String(value || '').trim().replace(/^https?:\/\//i, '').replace(/\/$/, '');
const validTarget = (value) => value.length <= 253 && /^[a-zA-Z0-9.-]+$/.test(value) && !value.startsWith('.') && !value.endsWith('.');
const outputName = (target) => `recon_${target}_${new Date().toISOString().replace(/[:.]/g, '').slice(0, 15)}`;

function updateScan(id, fields) {
  const keys = Object.keys(fields);
  if (!keys.length) return;
  const values = [...keys.map((key) => fields[key]), new Date().toISOString(), id];
  db.run(`UPDATE scans SET ${keys.map((key) => `${key} = ?`).join(', ')}, updated_at = ? WHERE id = ?`, values);
}

function updateStage(scanId, key, fields) {
  const keys = Object.keys(fields);
  if (!keys.length) return;
  const values = [...keys.map((field) => fields[field]), scanId, key];
  db.run(`UPDATE scan_stages SET ${keys.map((field) => `${field} = ?`).join(', ')} WHERE scan_id = ? AND stage_key = ?`, values);
}

function createStages(scanId) {
  const statement = db.prepare(`INSERT OR IGNORE INTO scan_stages (scan_id, stage_key, phase, name, priority) VALUES (?, ?, ?, ?, ?)`);
  STAGES.forEach(([key, name, priority], index) => statement.run(scanId, key, index + 1, name, priority));
  statement.finalize();
}

function readFile(file) {
  try { return fs.readFileSync(file, 'utf8'); } catch { return '{}'; }
}

function startScan(scan) {
  const script = path.join(ROOT_DIR, 'scripts', 'recon-runner.sh');
  if (!fs.existsSync(script)) {
    updateScan(scan.id, { status: 'failed', log: `Missing runner: ${script}` });
    return;
  }

  const args = [script, scan.target, '--out', scan.output_dir];
  const child = spawn('bash', args, { cwd: ROOT_DIR, stdio: ['ignore', 'pipe', 'pipe'] });
  let log = '';
  const append = (chunk) => {
    log = `${log}${chunk}`.slice(-20000);
    updateScan(scan.id, { log });
    String(chunk).split('\n').filter(Boolean).forEach((line) => {
      if (!line.startsWith('STAGE_EVENT|')) return;
      const [, key, status, message = ''] = line.split('|');
      const fields = { status, message };
      if (status === 'running') fields.started_at = new Date().toISOString();
      if (['completed', 'failed', 'skipped'].includes(status)) fields.completed_at = new Date().toISOString();
      updateStage(scan.id, key, fields);
    });
  };
  child.stdout.on('data', append);
  child.stderr.on('data', append);
  child.on('error', (error) => updateScan(scan.id, { status: 'failed', log: `${log}\n${error.message}` }));
  child.on('close', (code) => {
    const summary = readFile(path.join(ROOT_DIR, scan.output_dir, 'findings', 'findings.json'));
    updateScan(scan.id, { status: code === 0 ? 'completed' : 'failed', summary, log: `${log}\nProcess exited with code ${code}` });
  });
}

app.get('/api/health', (_, res) => res.json({ ok: true, service: 'elite-recon-dashboard' }));
app.get('/api/scans', (_, res) => db.all('SELECT * FROM scans ORDER BY created_at DESC', [], (error, rows) => error ? res.status(500).json({ error: error.message }) : res.json({ scans: rows })));
app.get('/api/scans/:id', (req, res) => db.get('SELECT * FROM scans WHERE id = ?', [req.params.id], (error, scan) => {
  if (error) return res.status(500).json({ error: error.message });
  if (!scan) return res.status(404).json({ error: 'Scan not found' });
  db.all('SELECT * FROM scan_stages WHERE scan_id = ? ORDER BY phase', [req.params.id], (stageError, stages) => {
    if (stageError) return res.status(500).json({ error: stageError.message });
    res.json({ scan, stages });
  });
}));
app.get('/api/scans/:id/report', (req, res) => db.get('SELECT output_dir, target FROM scans WHERE id = ?', [req.params.id], (error, scan) => {
  if (error) return res.status(500).json({ error: error.message });
  if (!scan) return res.status(404).json({ error: 'Scan not found' });
  const reportPath = path.resolve(ROOT_DIR, scan.output_dir, 'report', 'report.md');
  if (!reportPath.startsWith(`${ROOT_DIR}${path.sep}`) || !fs.existsSync(reportPath)) return res.status(404).json({ error: 'Report not available yet' });
  res.download(reportPath, `${scan.target}-report.md`);
}));
app.post('/api/scans', (req, res) => {
  const { target, scopeFile = '', resumeDir = '', diffDir = '', aggressive = false } = req.body || {};
  const cleanedTarget = cleanTarget(target);
  if (!validTarget(cleanedTarget)) return res.status(400).json({ error: 'Enter a valid hostname such as example.com.' });
  const outputDir = resumeDir || outputName(cleanedTarget);
  const record = { target: cleanedTarget, status: 'queued', output_dir: outputDir, aggressive: aggressive ? 1 : 0, scope_file: scopeFile, resume_dir: resumeDir, diff_dir: diffDir };
  db.run('INSERT INTO scans (target, status, output_dir, aggressive, scope_file, resume_dir, diff_dir, log, summary) VALUES (?, ?, ?, ?, ?, ?, ?, "", "{}")', Object.values(record), function (error) {
    if (error) return res.status(500).json({ error: error.message });
    const scan = { id: this.lastID, ...record };
    createStages(scan.id);
    updateScan(scan.id, { status: 'running', log: `Starting staged pipeline for ${scan.target}` });
    startScan(scan);
    res.status(201).json({ scan });
  });
});

if (fs.existsSync(path.join(ROOT_DIR, 'dist'))) {
  app.use(express.static(path.join(ROOT_DIR, 'dist')));
  app.get('*', (req, res, next) => req.path.startsWith('/api') ? next() : res.sendFile(path.join(ROOT_DIR, 'dist', 'index.html')));
}

app.listen(PORT, () => console.log(`Recon dashboard API running on http://localhost:${PORT}`));
