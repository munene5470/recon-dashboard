# Staged Docker workflow

## What this foundation includes

- SQLite-backed scan records
- SQLite-backed stage tracking for all 16 pipeline phases
- dashboard display for stage status, progress, and logs
- safe staged runner that emits stage events
- Docker-first setup

## Pipeline phases

1. 01-subdomains
2. 02-dns
3. 03-alive
4. 04-ports
5. 05-crawl
6. 06-params
7. 07-tech
8. 08-tls
9. 09-api
10. 10-misconfig
11. 11-injection
12. 12-access-control
13. 13-takeover
14. 14-secrets
15. 15-nuclei
16. 16-report

## Run with Docker

```bash
docker compose build
docker compose up
```

Open:

```text
http://localhost:4000
```

## Local runner test

```bash
bash -n scripts/recon-runner.sh
./scripts/recon-runner.sh example.com --out /tmp/recon-example
```

This creates stage output and a safe `findings.json` skeleton. The next implementation will replace the foundation stage with real subdomain enumeration and comparison logic.
