# Recon Dashboard

This repository contains a React + Vite frontend and an Express + SQLite backend for launching and tracking Elite Recon scans. The application is designed to trigger the Bash-based recon script, capture scan logs and summaries, and present findings in a simple dashboard.

## What this project includes

- React + Vite frontend for the web UI
- Express API for scan orchestration
- SQLite database for persistent scan metadata and summary storage
- Bash scan launcher for `EliteV11.sh`
- OWASP-style findings summary in the UI
- Sample output and documentation for the JavaScript download fix

## Tech stack

- Frontend: React 18 + Vite
- Backend: Node.js + Express
- Database: SQLite3
- Target scanner: Bash script runner for Elite Recon

## Quick start

1. Install dependencies:

```bash
npm install
```

2. Start the app in development mode:

```bash
npm run dev
```

3. Open the app in a browser:

- Frontend: http://localhost:5173
- API health check: http://localhost:4000/api/health

## Project layout

```text
.
├── src/
│   ├── App.jsx
│   ├── index.css
│   └── main.jsx
├── server/
│   └── index.js
├── scripts/
│   └── EliteV11.sh
├── docs/
│   └── architecture.md
├── index.html
├── package.json
├── vite.config.js
├── .gitignore
├── README.md
└── data/
    └── recon.db
```

## API endpoints

### GET /api/health
Returns service status.

### GET /api/scans
Returns all stored scans, newest first.

### GET /api/scans/:id
Returns one scan record.

### POST /api/scans
Creates a scan request and starts the target script.

Example request body:

```json
{
  "target": "example.com",
  "scopeFile": "/path/to/scope.txt",
  "resumeDir": "",
  "diffDir": "",
  "aggressive": false
}
```

## Important JavaScript fix

The original JavaScript download loop had a critical bug:

```bash
((count++))
```

This expression can return a non-zero result in shell arithmetic, which is exactly the kind of thing that triggers `set -e` and aborts the script early. That is why JS downloads can appear to stop before downloading anything.

Use this instead:

```bash
count=$((count + 1))
```

or:

```bash
((++count))
```

The URL extraction logic was also too narrow. The original pattern only matched `.js` strings that ended immediately in `.js`, which misses common cases like:

- `/assets/app.js?v=123`
- `/main.js#chunk`
- URLs with query strings or fragments

Use a safer regex such as:

```bash
grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?' "$OUT/urls/all_urls.txt" \
  | sed 's/[),;>]$//' \
  | sort -u > "$OUT/js/js_urls.txt"
```

This preserves query/hash suffixes and prevents the extraction stage from silently dropping valid JavaScript files.

## Security and operations notes

- The dashboard should not be exposed publicly without authentication.
- Restrict the `target` field to approved domains or an allow-list in production.
- Only run aggressive recon modules when you have explicit authorization.
- Store output under a controlled directory and avoid unrestricted file writes.

## Production deployment advice

For production use, add the following before exposing the app:

- authentication/authorization middleware
- rate limiting on scan creation requests
- validation of target names against an allow-list
- separate user accounts and per-user scan history
- safe file system isolation for each output directory

## License

This project is released under the MIT license.
