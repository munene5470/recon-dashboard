# Staged Docker workflow

## What changed

The dashboard now models the recon process as a dependency-ordered pipeline. Each scan creates 16 stage records in SQLite, and the UI displays every phase as queued, running, completed, failed, or skipped.

The current foundation runner implements Phase 1 as a smoke/foundation stage. Phases 2–16 are explicitly marked skipped with their required dependency. This is intentional: real tools will be added one phase at a time so an error in one tool does not hide failures elsewhere.

## Run with Docker

```bash
docker compose build
docker compose up
```

Open `http://localhost:3000`.

Check the API:

```bash
curl http://localhost:3000/api/health
```

Start a scan from the dashboard or API:

```bash
curl -X POST http://localhost:3000/api/scans \
  -H 'Content-Type: application/json' \
  -d '{"target":"example.com"}'
```

View stages:

```bash
curl http://localhost:3000/api/scans/1 | jq
```

## Local runner test

```bash
bash -n scripts/recon-runner.sh
./scripts/recon-runner.sh example.com --out /tmp/recon-example
```

## Pipeline contract

Each stage must:

1. declare its required input files;
2. write tool-specific output files;
3. preserve raw output;
4. write normalized/comparison output;
5. emit a stage status event;
6. refuse to run when required input is empty;
7. never silently convert a tool failure into a successful stage.

The next implementation stage is Phase 1 enumeration using subfinder, assetfinder, amass, crt.sh, waybackurls, and gau, followed by comparison and DNS filtering.

Only scan domains for which you have explicit authorization. Keep Docker bound to a protected network while active tools are being added.
