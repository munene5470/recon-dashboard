# Recon Dashboard

This repository contains a small React + Vite frontend plus an Express API for launching the Elite Recon Bash scanner and tracking results in SQLite.

## Features

- React + Vite frontend
- Express backend API with SQLite storage
- Task queue for launching recon scans
- Scan log and summary tracking
- OWASP-style findings view
- `EliteV11.sh` runner with corrected JS download bug fix

## Quick start

```bash
npm install
npm run dev
```

Then open:

- Frontend: http://localhost:5173
- API: http://localhost:4000/api/health

## Important JavaScript fix

The original scan script had a counter bug in the JS download loop:

```bash
((count++))
```

This returns a failing exit status. Use:

```bash
count=$((count + 1))
```

Also, the JS URL extraction should handle query strings and hashes by using a regex such as:

```bash
grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?' "$OUT/urls/all_urls.txt" \
  | sed 's/[),;>]$//' \
  | sort -u > "$OUT/js/js_urls.txt"
```

## Production note

The Bash scan is intentionally launched server-side and stores output under the repo root in a dedicated output directory. In production, you should restrict the `target` field to an approved allow-list and enforce authentication.
