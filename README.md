# Architecture

The app is split into a frontend and a backend to keep security tooling away from the browser while still making results easy to view.

## Components

- `src/App.jsx` — React UI for launching scans, filtering results, and showing structured findings.
- `server/index.js` — Express API, SQLite storage, target validation, and child-process management.
- `scripts/EliteV11.sh` — Bash scan entrypoint.
- `data/recon.db` — SQLite file created automatically on first start.

## Execution flow

1. User submits a target from the dashboard.
2. API validates the domain and stores a new scan row in SQLite.
3. API launches `scripts/EliteV11.sh` as a child process.
4. stdout/stderr are captured and stored as the live log.
5. The scanner writes `findings/findings.json` and the report under that target's output directory.
6. The frontend polls the API every 5 seconds.
7. The user can view findings and download the Markdown report.

## Operational notes

- This project should only be deployed behind authentication.
- Enforce an allow-list of domains to scan.
- Keep the output directories under a controlled root.
- Use least-privilege service accounts and restrict shell execution.
- Protect report downloads with auth and rate limiting.

## JavaScript fix

Under `set -e`, this expression can exit early:

```bash
((count++))
```

Use:

```bash
count=$((count + 1))
```

And the JS URL extraction should support query strings and hash fragments:

```bash
grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?'
```
