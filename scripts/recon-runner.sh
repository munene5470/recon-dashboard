#!/usr/bin/env bash
set -euo pipefail

TARGET=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      [[ $# -ge 2 ]] || { echo "--out requires a directory" >&2; exit 2; }
      OUT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 <domain> --out <directory>"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
        shift
      else
        echo "Unexpected extra argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

[[ -n "$TARGET" && -n "$OUT" ]] || { echo "Target and --out are required" >&2; exit 2; }
[[ "$TARGET" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid target: $TARGET" >&2; exit 2; }

mkdir -p "$OUT"/{logs,findings,report,subs,dns,alive,ports,crawl,params,tech,tls,api,graphql,headers,cors,vulns,403,idor,takeover,secrets,report}

log(){
  echo "[$(date +%H:%M:%S)] $1" | tee -a "$OUT/logs/run.log"
}

stage(){
  echo "STAGE_EVENT|$1|$2|$3"
}

log "Staged pipeline started for $TARGET"
stage "01-subdomains" "running" "Stage 1 smoke foundation"
printf '%s\n' "$TARGET" > "$OUT/subs/all.txt"
cat > "$OUT/subs/comparison.json" <<EOF
{
  "total_unique": 1,
  "by_tool": {
    "seed": 1
  },
  "consensus": {
    "found_by_3_or_more_tools": [],
    "found_by_2_tools": [],
    "found_by_1_tool": ["$TARGET"]
  }
}
EOF
stage "01-subdomains" "completed" "Foundation ready; enumeration tools will be added in the next stage"

for entry in \
  '02-dns|Waiting for Phase 1 outputs' \
  '03-alive|Waiting for DNS outputs' \
  '04-ports|Waiting for alive hosts' \
  '05-crawl|Waiting for alive URLs' \
  '06-params|Waiting for crawled URLs' \
  '07-tech|Waiting for alive URLs' \
  '08-tls|Waiting for alive hosts' \
  '09-api|Waiting for crawled URLs' \
  '10-misconfig|Waiting for alive URLs' \
  '11-injection|Waiting for parameterized URLs' \
  '12-access-control|Waiting for URL candidates' \
  '13-takeover|Waiting for DNS outputs' \
  '14-secrets|Waiting for JavaScript and git outputs' \
  '15-nuclei|Waiting for discovery outputs' \
  '16-report|Waiting for completed stages'; do
  key="${entry%%|*}"
  message="${entry#*|}"
  stage "$key" "skipped" "$message"
done

cat > "$OUT/findings/findings.json" <<EOF
{
  "target": "$TARGET",
  "generated": "$(date -Iseconds)",
  "pipeline_status": "foundation-complete",
  "findings": {}
}
EOF

cat > "$OUT/report/report.md" <<EOF
# Recon Report

Target: $TARGET

Pipeline foundation completed successfully.

This is the safe staged foundation for the dashboard. Real enumeration and security tools are intentionally staged behind the dependency pipeline.
EOF

log "Foundation pipeline completed"
