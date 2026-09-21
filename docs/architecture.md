# Architecture and operations

## Components

- `src/App.jsx`: React dashboard, scan history, status filtering, structured findings, live log, and report download.
- `server/index.js`: Express API, SQLite persistence, target validation, child-process management, and report delivery.
- `scripts/EliteV11.sh`: Bash scanner entrypoint.
- `data/recon.db`: created automatically on first backend start; it is ignored by Git.

## Flow

1. The browser submits a target to `POST /api/scans`.
2. The API validates the hostname and stores a queued record.
3. The API starts the Bash process without invoking a shell around user input.
4. stdout and stderr are capped at the latest 20,000 characters and persisted.
5. The scanner writes its output directory and `findings/findings.json`.
6. The API marks the scan completed/failed and stores the summary.
7. The dashboard polls every five seconds and can download `report/report.md`.

## Run locally

```bash
npm install
npm run dev
```

Frontend: `http://localhost:5173`  
API: `http://localhost:4000/api/health`

## JavaScript collection fix

With `set -e`, this is unsafe at the beginning of a loop:

```bash
((count++))
```

The expression returns the previous value. On the first iteration that value is zero, producing a failing status and potentially terminating the script. Use:

```bash
count=$((count + 1))
```

The extractor also accepts query strings and fragments:

```bash
grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?'
```

## Production checklist

This project launches authorized security tooling and must not be exposed publicly as-is. Before deployment:

- add authentication and authorization;
- enforce an approved target allow-list;
- run scans in isolated workers/containers;
- rate-limit scan creation;
- restrict scope/resume/diff paths to approved directories;
- use a dedicated least-privilege service account;
- retain audit logs and protect report downloads.
