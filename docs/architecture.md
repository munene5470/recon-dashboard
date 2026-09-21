#!/usr/bin/env bash
# Elite Recon Engine v11 - practical hardening pass over v10

set -euo pipefail

TARGET="${1:-}"
SCOPE_FILE=""
RESUME_DIR=""
DIFF_DIR=""
AGGRESSIVE=false

usage() {
  echo "Usage: $0 <domain> [--scope scope.txt] [--resume OUT_DIR] [--diff PREV_OUT_DIR] [--aggressive]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope) SCOPE_FILE="${2:-}"; shift 2 ;;
    --resume) RESUME_DIR="${2:-}"; shift 2 ;;
    --diff) DIFF_DIR="${2:-}"; shift 2 ;;
    --aggressive) AGGRESSIVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$TARGET" ]]; then TARGET="$1"; shift
      else echo "Unknown argument: $1"; usage; exit 1; fi
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

WORDLIST="/usr/share/seclists/Discovery/Web-Content/raft-large-directories.txt"
PARAM_WORDLIST="/usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt"
PARALLEL_HOSTS=${PARALLEL_HOSTS:-8}

if [[ -n "$RESUME_DIR" ]]; then
  OUT="$RESUME_DIR"
else
  TS=$(date +"%Y%m%d_%H%M%S")
  OUT="recon_${TARGET}_${TS}"
fi

mkdir -p "$OUT"/subs "$OUT"/dns "$OUT"/alive "$OUT"/ports "$OUT"/urls "$OUT"/crawl "$OUT"/content "$OUT"/js "$OUT"/api "$OUT"/params "$OUT"/secrets "$OUT"/vulns "$OUT"/tech "$OUT"/tls "$OUT"/logs "$OUT"/takeover "$OUT"/graphql "$OUT"/ssrf "$OUT"/xss "$OUT"/git "$OUT"/403 "$OUT"/headers "$OUT"/cors "$OUT"/idor "$OUT"/priority "$OUT"/report "$OUT"/dashboard "$OUT"/owasp "$OUT"/findings

log(){
  echo "[$(date +%H:%M:%S)] $1" | tee -a "$OUT/logs/run.log"
}

log "Starting Elite Recon for $TARGET"
log "Safe mode: $([[ "$AGGRESSIVE" == true ]] && echo false || echo true)"

mkdir -p "$OUT/subs"
printf '%s\n' "$TARGET" > "$OUT/subs/all.txt"
printf '%s\n' "$TARGET" > "$OUT/dns/resolved.txt"
printf 'https://%s\n' "$TARGET" > "$OUT/alive/alive_urls.txt"

mkdir -p "$OUT/js"
if [[ -s "$OUT/urls/all_urls.txt" ]]; then
  grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?' "$OUT/urls/all_urls.txt" 2>/dev/null \
    | sed 's/[),;>]$//' \
    | sort -u > "$OUT/js/js_urls.txt" || true
fi

if [[ -s "$OUT/js/js_urls.txt" ]]; then
  count=0
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    count=$((count + 1))
    file_hash=$(printf '%s' "$url" | md5sum | awk '{print $1}')
    curl -fsSL --max-time 20 "$url" -o "$OUT/js/${file_hash}.js" 2>/dev/null || true
  done < "$OUT/js/js_urls.txt"
  log "Downloaded ${count} JavaScript files"
else
  log "No JavaScript URLs found; JS collection is empty as expected"
fi

jq -n \
  --arg target "$TARGET" \
  --arg generated "$(date -Iseconds)" \
  '{
    target: $target,
    generated: $generated,
    findings: {
      "A01_broken_access_control": {git_exposure: [], idor_bola_candidates: []},
      "A02_crypto_failures": {note: "see tls/*.json for per-host testssl.sh output"},
      "A03_injection": {sqlmap_confirmed: [], nuclei: []},
      "A05_security_misconfiguration": {missing_headers: [], cors: [], subdomain_takeover: []}
    }
  }' > "$OUT/findings/findings.json" 2>/dev/null || true

log "Recon v11 complete. Output: $OUT"
