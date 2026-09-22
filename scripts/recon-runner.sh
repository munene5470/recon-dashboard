#!/usr/bin/env bash
set -euo pipefail
TARGET=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) [[ $# -ge 2 ]] || { echo "--out requires a directory" >&2; exit 2; }; OUT="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 <domain> --out <directory>"; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) [[ -z "$TARGET" ]] && TARGET="$1" || { echo "Unexpected extra argument: $1" >&2; exit 2; }; shift ;;
  esac
done
[[ -n "$TARGET" && -n "$OUT" ]] || { echo "Target and --out are required" >&2; exit 2; }
[[ "$TARGET" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid target: $TARGET" >&2; exit 2; }
mkdir -p "$OUT"/{logs,findings,report,subs/raw,dns,alive,ports,crawl,params,tech,tls,api,graphql,headers,cors,vulns,403,idor,takeover,secrets}
log(){ echo "[$(date +%H:%M:%S)] $1" | tee -a "$OUT/logs/run.log"; }
stage(){ echo "STAGE_EVENT|$1|$2|$3"; }
normalize(){ sed -E 's#^[[:space:]]+##; s#[[:space:]]+$##; s#^https?://##; s#^[*.]+##; s#/.*##' | tr '[:upper:]' '[:lower:]' | grep -E "(^|\.)${TARGET//./\\.}$" || true; }
record_tool(){ printf '{"tool":"%s","status":"%s","count":%s}\n' "$1" "$2" "${3:-0}" >> "$OUT/subs/tool-status.ndjson"; }
run_text_tool(){
  local name="$1"; shift; local file="$OUT/subs/raw/$name.txt"
  stage 01-subdomains running "Running tool: $name"; log "Running tool: $name"
  if "$@" > "$file" 2> "$OUT/subs/raw/$name.err"; then
    normalize < "$file" > "$file.clean" || true; mv "$file.clean" "$file"
    record_tool "$name" completed "$(wc -l < "$file" | tr -d ' ')"; log "$name completed"
  else
    record_tool "$name" failed 0; log "$name failed; see subs/raw/$name.err"
  fi
}
run_crtsh(){
  local file="$OUT/subs/raw/crtsh.txt"; local err="$OUT/subs/raw/crtsh.err"
  stage 01-subdomains running "Running tool: crt.sh"; log "Running tool: crt.sh"
  if curl -fsSL --retry 2 --connect-timeout 8 --max-time 30 "https://crt.sh/?q=%25.${TARGET}&output=json" > "$file" 2> "$err"; then
    if jq -e . >/dev/null 2> "$err.jq" < "$file"; then
      jq -r '.[].name_value // empty' "$file" | normalize > "$file.clean" || true
      mv "$file.clean" "$file"
      record_tool crtsh completed "$(wc -l < "$file" | tr -d ' ')"; log "crt.sh completed"
    else
      : > "$file"; record_tool crtsh failed 0; log "crt.sh returned invalid JSON; see subs/raw/crtsh.jq"
      mv "$err.jq" "$OUT/subs/raw/crtsh.jq"
    fi
  else
    : > "$file"; record_tool crtsh failed 0; log "crt.sh failed; see subs/raw/crtsh.err"
  fi
}
log "Staged pipeline started for $TARGET"
stage 01-subdomains running "Preparing passive enumeration"
: > "$OUT/subs/tool-status.ndjson"
printf '%s\n' "$TARGET" > "$OUT/subs/raw/seed.txt"; record_tool seed completed 1
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then run_crtsh; else record_tool crtsh skipped 0; log "Skipping crt.sh: curl or jq unavailable"; fi
if command -v subfinder >/dev/null 2>&1; then run_text_tool subfinder subfinder -silent -d "$TARGET"; else record_tool subfinder skipped 0; log "Skipping subfinder: not installed"; fi
if command -v assetfinder >/dev/null 2>&1; then run_text_tool assetfinder assetfinder --subs-only "$TARGET"; else record_tool assetfinder skipped 0; log "Skipping assetfinder: not installed"; fi
{ cat "$OUT/subs/raw/"*.txt 2>/dev/null || true; printf '%s\n' "$TARGET"; } | normalize | sort -u > "$OUT/subs/all.txt"
TOTAL=$(wc -l < "$OUT/subs/all.txt" | tr -d ' ')
cat > "$OUT/subs/comparison.json" <<EOF
{"total_unique":$TOTAL,"tools":"subs/tool-status.ndjson"}
EOF
stage 01-subdomains completed "Passive enumeration complete: $TOTAL unique in-scope hosts"
for entry in '02-dns|Waiting for Phase 1 outputs' '03-alive|Waiting for DNS outputs' '04-ports|Waiting for alive hosts' '05-crawl|Waiting for alive URLs' '06-params|Waiting for crawled URLs' '07-tech|Waiting for alive URLs' '08-tls|Waiting for alive hosts' '09-api|Waiting for crawled URLs' '10-misconfig|Waiting for alive URLs' '11-injection|Waiting for parameterized URLs' '12-access-control|Waiting for URL candidates' '13-takeover|Waiting for DNS outputs' '14-secrets|Waiting for JavaScript and git outputs' '15-nuclei|Waiting for discovery outputs' '16-report|Waiting for completed stages'; do key="${entry%%|*}"; stage "$key" skipped "${entry#*|}"; done
cat > "$OUT/findings/findings.json" <<EOF
{"target":"$TARGET","generated":"$(date -Iseconds)","pipeline_status":"phase-1-complete","subdomains_total":$TOTAL,"findings":{}}
EOF
cat > "$OUT/report/report.md" <<EOF
# Recon Report

Target: $TARGET

Phase 1 passive subdomain enumeration completed.

Unique in-scope hosts: $TOTAL
EOF
log "Phase 1 completed"
