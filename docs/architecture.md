#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-}"
SCOPE_FILE=""; RESUME_DIR=""; DIFF_DIR=""; AGGRESSIVE=false
usage(){ echo "Usage: $0 <domain> [--scope FILE] [--resume DIR] [--diff DIR] [--aggressive]"; }
while [[ $# -gt 0 ]]; do case "$1" in --scope) SCOPE_FILE="${2:-}"; shift 2;; --resume) RESUME_DIR="${2:-}"; shift 2;; --diff) DIFF_DIR="${2:-}"; shift 2;; --aggressive) AGGRESSIVE=true; shift;; -h|--help) usage; exit 0;; *) [[ -z "$TARGET" ]] && { TARGET="$1"; shift; } || { echo "Unknown argument: $1"; exit 1; };; esac; done
[[ -n "$TARGET" ]] || { usage; exit 1; }
if [[ -n "$RESUME_DIR" ]]; then OUT="$RESUME_DIR"; else OUT="recon_${TARGET}_$(date +%Y%m%d_%H%M%S)"; fi
mkdir -p "$OUT"/{subs,dns,alive,urls,js,findings,logs,report}
log(){ echo "[$(date +%H:%M:%S)] $1" | tee -a "$OUT/logs/run.log"; }
log "Starting Elite Recon for $TARGET (safe_mode=$([[ "$AGGRESSIVE" == true ]] && echo false || echo true))"
printf '%s\n' "$TARGET" > "$OUT/subs/all.txt"; printf '%s\n' "$TARGET" > "$OUT/dns/resolved.txt"; printf 'https://%s\n' "$TARGET" > "$OUT/alive/alive_urls.txt"
: > "$OUT/urls/all_urls.txt"
: > "$OUT/js/js_urls.txt"
# Important: avoid ((count++)) under set -e. The first iteration returns 0 and can exit the script.
if [[ -s "$OUT/urls/all_urls.txt" ]]; then grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?' "$OUT/urls/all_urls.txt" | sed 's/[),;>]$//' | sort -u > "$OUT/js/js_urls.txt" || true; fi
count=0
while IFS= read -r url; do [[ -z "$url" ]] && continue; count=$((count + 1)); file_hash=$(printf '%s' "$url" | md5sum | awk '{print $1}'); curl -fsSL --max-time 20 "$url" -o "$OUT/js/${file_hash}.js" 2>/dev/null || true; done < "$OUT/js/js_urls.txt"
log "Downloaded $count JavaScript files"
if command -v jq >/dev/null 2>&1; then jq -n --arg target "$TARGET" --arg generated "$(date -Iseconds)" '{target:$target,generated:$generated,findings:{A01_broken_access_control:{git_exposure:[],idor_bola_candidates:[]},A02_crypto_failures:{note:"see tls/*.json"},A03_injection:{sqlmap_confirmed:[],nuclei:[]},A05_security_misconfiguration:{missing_headers:[],cors:[],subdomain_takeover:[]}}}' > "$OUT/findings/findings.json"; fi
printf '# Recon Report\n\nTarget: %s\n' "$TARGET" > "$OUT/report/report.md"
log "Recon complete. Output: $OUT"
