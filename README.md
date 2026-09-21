# Architecture

This project is intentionally split into a small frontend and a backend service so the scan orchestration logic stays away from the browser.

## High-level flow

1. A user submits a target domain and optional scan arguments in the React UI.
2. The frontend sends a request to the Express API at `/api/scans`.
3. The backend validates the target and stores a scan record in SQLite.
4. The backend invokes the Bash scanner script (`scripts/EliteV11.sh`) as a child process.
5. The Bash script writes output into an output directory such as `recon_example.com_...`.
6. The API captures stdout/stderr and updates the scan status while the process is running.
7. When the scan ends, the backend reads any `findings.json` it created and stores the summary in SQLite.
8. The frontend polls `/api/scans` and renders the latest scan results.

## Components

### Frontend

- `src/App.jsx`: scan form, list of scans, selected scan view, and summary rendering.
- `src/index.css`: layout and dashboard styling.
- `index.html`: app entry point.

### Backend

- `server/index.js`: Express API, SQLite initialization, startup logic, and process launching.

### Scan runner

- `scripts/EliteV11.sh`: the Bash orchestrator that creates output files and performs the scanning steps.

### Data storage

- SQLite database in `data/recon.db`
- A table called `scans` stores:
  - `id`
  - `target`
  - `status`
  - `output_dir`
  - `aggressive`
  - `scope_file`
  - `resume_dir`
  - `diff_dir`
  - `log`
  - `summary`
  - `created_at`
  - `updated_at`

## Why this structure works well

- The browser never directly runs security tooling.
- The server can enforce validation and safety checks before launching a scan.
- Any output directory can be traced back to a specific database record.
- The UI stays lightweight while the backend manages long-running shell processes.

## Production hardening ideas

- Add authentication before exposing the app.
- Add rate limiting to scan creation.
- Restrict targets to an allow-list.
- Use a dedicated service account to run the Bash tools.
- Isolate output by user and target domain.
- Add audit logging and permission checks on output files.
