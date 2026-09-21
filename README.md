# Recon Dashboard

React + Vite dashboard and Express/SQLite API for launching and tracking authorized Elite Recon scans.

## Start

```bash
npm install
npm run dev
```

Open `http://localhost:5173`. The API is available at `http://localhost:4000`.

## Features

- Launch scans with target, scope, resume, diff, and safe/aggressive options.
- Store scan records, statuses, logs, and structured findings in SQLite.
- Poll running scans automatically.
- Filter scan history by status.
- View OWASP category summaries and live output.
- Download completed Markdown reports.
- Correct JavaScript collection logic for `set -e` Bash scripts.

## API

- `GET /api/health`
- `GET /api/scans`
- `GET /api/scans/:id`
- `GET /api/scans/:id/report`
- `POST /api/scans`

Example:

```bash
curl -X POST http://localhost:4000/api/scans \
  -H 'Content-Type: application/json' \
  -d '{"target":"example.com","aggressive":false}'
```

## JavaScript download bug

Do not use this with `set -e`:

```bash
((count++))
```

Use:

```bash
count=$((count + 1))
```

The extractor should also support cache-busted URLs:

```bash
grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?' "$OUT/urls/all_urls.txt" \
  | sed 's/[),;>]$//' \
  | sort -u > "$OUT/js/js_urls.txt"
```

## Security notice

Only scan systems for which you have explicit authorization. The backend should be deployed behind authentication, target allow-listing, rate limiting, and isolated worker execution before production use. See [`docs/architecture.md`](docs/architecture.md).
