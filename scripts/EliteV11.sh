import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import sqlite3 from 'sqlite3';
import express from 'express';
import cors from 'cors';
import { spawn } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, '..');
const DB_PATH = path.join(ROOT_DIR, 'data', 'recon.db');

const app = express();
const PORT = process.env.PORT || 4000;
const db = new sqlite3.Database(DB_PATH);

function initializeDatabase() {
  fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
  db.serialize(() => {
    db.run(`
      CREATE TABLE IF NOT EXISTS scans (
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
      )
    `);
  });
}

function updateScanStatus(id, fields) {
  const updates = [];
  const values = [];

  for (const [key, value] of Object.entries(fields)) {
    updates.push(`${key} = ?`);
    values.push(value);
  }

  values.push(new Date().toISOString(), id);

  db.run(
    `UPDATE scans SET ${updates.join(', ')}, updated_at = ? WHERE id = ?`,
    values,
    (error) => {
      if (error) {
        console.error('Update scan failed:', error.message);
      }
    }
  );
}

function readJsonIfExists(filePath) {
  if (!fs.existsSync(filePath)) return '{}';
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return '{}';
  }
}

function safeTargetValue(value) {
  return String(value || '').trim().replace(/^https?:\/\//i, '').replace(/\/$/, '');
}

function isTargetValid(value) {
  if (!value || value.length > 253) return false;
  const pattern = /^[a-zA-Z0-9.-]+$/;
  return pattern.test(value) && !value.startsWith('.') && !value.endsWith('.');
}

function createScanOutputDir(target) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '').slice(0, 15);
  return `recon_${safeTargetValue(target)}_${stamp}`;
}

function startScan(scan) {
  const scriptPath = path.join(ROOT_DIR, 'scripts', 'EliteV11.sh');

  if (!fs.existsSync(scriptPath)) {
    updateScanStatus(scan.id, {
      status: 'failed',
      log: `Missing script: ${scriptPath}`,
    });
    return;
  }

  const args = [scriptPath, scan.target];
  if (scan.scope_file) args.push('--scope', scan.scope_file);
  if (scan.resume_dir) args.push('--resume', scan.resume_dir);
  if (scan.diff_dir) args.push('--diff', scan.diff_dir);
  if (scan.aggressive) args.push('--aggressive');

  const proc = spawn('bash', args, {
    cwd: ROOT_DIR,
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: false,
  });

  let logBuffer = '';

  proc.stdout.on('data', (chunk) => {
    const text = String(chunk);
    logBuffer += text;
    updateScanStatus(scan.id, { log: logBuffer.slice(-20000) });
  });

  proc.stderr.on('data', (chunk) => {
    const text = String(chunk);
    logBuffer += text;
    updateScanStatus(scan.id, { log: logBuffer.slice(-20000) });
  });

  proc.on('error', (error) => {
    updateScanStatus(scan.id, {
      status: 'failed',
      log: `${logBuffer}\n${error.message}`,
    });
  });

  proc.on('close', (code) => {
    const outputDir = scan.resume_dir || scan.output_dir || createScanOutputDir(scan.target);
    const findingsPath = path.join(ROOT_DIR, outputDir, 'findings', 'findings.json');
    const summaryText = readJsonIfExists(findingsPath);

    updateScanStatus(scan.id, {
      status: code === 0 ? 'completed' : 'failed',
      output_dir: outputDir,
      summary: summaryText || '{}',
      log: `${logBuffer}\nProcess exited with code ${code}`,
    });
  });
}

initializeDatabase();

app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/api/health', (_, res) => {
  res.json({ ok: true, service: 'elite-recon-dashboard' });
});

app.get('/api/scans', (_, res) => {
  db.all('SELECT * FROM scans ORDER BY created_at DESC', [], (error, rows) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json({ scans: rows });
  });
});

app.get('/api/scans/:id', (req, res) => {
  db.get('SELECT * FROM scans WHERE id = ?', [req.params.id], (error, row) => {
    if (error) return res.status(500).json({ error: error.message });
    if (!row) return res.status(404).json({ error: 'Scan not found' });
    res.json({ scan: row });
  });
});

app.post('/api/scans', (req, res) => {
  const { target, scopeFile, resumeDir, diffDir, aggressive } = req.body || {};
  const safeTarget = safeTargetValue(target);

  if (!safeTarget || !isTargetValid(safeTarget)) {
    return res.status(400).json({ error: 'A valid target domain is required.' });
  }

  const outputDir = resumeDir || createScanOutputDir(safeTarget);
  const record = {
    target: safeTarget,
    status: 'queued',
    output_dir: outputDir,
    aggressive: aggressive ? 1 : 0,
    scope_file: scopeFile || '',
    resume_dir: resumeDir || '',
    diff_dir: diffDir || '',
  };

  db.run(
    `INSERT INTO scans (target, status, output_dir, aggressive, scope_file, resume_dir, diff_dir, log, summary)
     VALUES (?, ?, ?, ?, ?, ?, ?, '', '{}')`,
    [record.target, record.status, record.output_dir, record.aggressive, record.scope_file, record.resume_dir, record.diff_dir],
    function (error) {
      if (error) {
        return res.status(500).json({ error: error.message });
      }

      const scan = {
        id: this.lastID,
        ...record,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };

      updateScanStatus(scan.id, { status: 'running', log: `Queued and starting scan for ${scan.target}` });
      startScan(scan);
      res.status(201).json({ scan });
    }
  );
});

app.listen(PORT, () => {
  console.log(`Recon dashboard API running on http://localhost:${PORT}`);
});
