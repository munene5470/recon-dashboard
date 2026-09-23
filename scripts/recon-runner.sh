#!/usr/bin/env bash
set -Eeuo pipefail

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

mkdir -p "$OUT"/{logs,findings,report,subs/raw,dns,alive,ports,crawl,params,tech,tls,api,graphql,vulns,js/downloads}
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/logs/run.log"; }
stage(){ echo "STAGE_EVENT|$1|$2|$3"; }
count_lines(){ [[ -f "$1" ]] && wc -l < "$1" | tr -d ' ' || echo 0; }
normalize(){ sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#^https?://##I; s#^[*.]+##; s#/.*##' | tr '[:upper:]' '[:lower:]' | grep -E "(^|\.)${TARGET//./\\.}$" || true; }

run_stage(){
  local key="$1" description="$2"; shift 2
  stage "$key" running "$description"; log "$description"
  if "$@"; then stage "$key" completed "$description completed"; else stage "$key" failed "$description failed"; fi
}

# Phase 1: passive subdomain discovery.
: > "$OUT/subs/tool-status.ndjson"
printf '%s\n' "$TARGET" > "$OUT/subs/raw/seed.txt"
printf '{"tool":"seed","status":"completed","count":1}\n' >> "$OUT/subs/tool-status.ndjson"
stage 01-subdomains running "Running passive subdomain enumeration"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  if curl -fsSL --retry 2 --connect-timeout 8 --max-time 30 "https://crt.sh/?q=%25.${TARGET}&output=json" > "$OUT/subs/raw/crtsh.json" 2> "$OUT/subs/raw/crtsh.err"; then
    jq -r '.[].name_value // empty' "$OUT/subs/raw/crtsh.json" | normalize | sort -u > "$OUT/subs/raw/crtsh.txt" || true
    printf '{"tool":"crtsh","status":"completed","count":%s}\n' "$(count_lines "$OUT/subs/raw/crtsh.txt")" >> "$OUT/subs/tool-status.ndjson"
  else
    : > "$OUT/subs/raw/crtsh.txt"; printf '%s\n' '{"tool":"crtsh","status":"failed","count":0}' >> "$OUT/subs/tool-status.ndjson"
  fi
else
  printf '%s\n' '{"tool":"crtsh","status":"skipped","count":0}' >> "$OUT/subs/tool-status.ndjson"
fi
for tool in subfinder assetfinder; do
  file="$OUT/subs/raw/$tool.txt"
  if command -v "$tool" >/dev/null 2>&1; then
    if [[ "$tool" == subfinder ]]; then "$tool" -silent -d "$TARGET" > "$file" 2> "$file.err" || true; else "$tool" --subs-only "$TARGET" > "$file" 2> "$file.err" || true; fi
    normalize < "$file" | sort -u > "$file.clean" || true; mv "$file.clean" "$file"
    printf '{"tool":"%s","status":"completed","count":%s}\n' "$tool" "$(count_lines "$file")" >> "$OUT/subs/tool-status.ndjson"
  else
    : > "$file"; printf '{"tool":"%s","status":"skipped","count":0}\n' "$tool" >> "$OUT/subs/tool-status.ndjson"
  fi
done
{ cat "$OUT/subs/raw/"*.txt 2>/dev/null || true; printf '%s\n' "$TARGET"; } | normalize | sort -u > "$OUT/subs/all.txt"
TOTAL_SUBS=$(count_lines "$OUT/subs/all.txt")
printf '{"total_unique":%s,"tools":"subs/tool-status.ndjson"}\n' "$TOTAL_SUBS" > "$OUT/subs/comparison.json"
stage 01-subdomains completed "Passive enumeration complete: $TOTAL_SUBS unique in-scope hosts"

phase_dns(){
  if command -v dnsx >/dev/null 2>&1; then dnsx -silent -l "$OUT/subs/all.txt" -o "$OUT/dns/resolved.txt" 2> "$OUT/dns/dnsx.err" || true; else cp "$OUT/subs/all.txt" "$OUT/dns/resolved.txt"; fi
  [[ -s "$OUT/dns/resolved.txt" ]] || cp "$OUT/subs/all.txt" "$OUT/dns/resolved.txt"
  printf '{"resolved_hosts":%s}\n' "$(count_lines "$OUT/dns/resolved.txt")" > "$OUT/dns/summary.json"
}
run_stage 02-dns "Resolving discovered hosts" phase_dns

phase_alive(){
  if command -v httpx >/dev/null 2>&1; then httpx -silent -l "$OUT/dns/resolved.txt" -o "$OUT/alive/alive.txt" 2> "$OUT/alive/httpx.err" || true; else sed 's#^#https://#' "$OUT/dns/resolved.txt" > "$OUT/alive/alive.txt"; fi
  [[ -s "$OUT/alive/alive.txt" ]] || printf 'https://%s\n' "$TARGET" > "$OUT/alive/alive.txt"
  printf '{"alive_urls":%s}\n' "$(count_lines "$OUT/alive/alive.txt")" > "$OUT/alive/summary.json"
}
run_stage 03-alive "Discovering live HTTP services" phase_alive

NUCLEI_PID=""
if command -v nuclei >/dev/null 2>&1 && [[ -s "$OUT/alive/alive.txt" ]] && [[ -x /app/scripts/run-nuclei-live.sh ]]; then
  stage 15-nuclei running "Scanning alive URLs with Nuclei"
  bash /app/scripts/run-nuclei-live.sh "$OUT/alive/alive.txt" "$OUT/vulns/nuclei.jsonl" "$OUT/vulns/nuclei.err" & NUCLEI_PID=$!
else
  printf '%s\n' 'Nuclei helper unavailable or alive.txt is empty' > "$OUT/vulns/nuclei.err"
  stage 15-nuclei skipped "Nuclei helper unavailable or alive.txt is empty"
fi

phase_nmap(){
  : > "$OUT/ports/nmap-hosts.txt"
  awk '{ gsub(/\r/,""); sub(/^[[:space:]]+/,""); sub(/[[:space:]]+$/,""); sub(/^https?:\/\//,""); sub(/\/.*$/,""); sub(/:[0-9]+$/,""); if ($0 ~ /^[A-Za-z0-9.-]+$/) print tolower($0) }' "$OUT/alive/alive.txt" | sort -u > "$OUT/ports/nmap-hosts.txt"
  [[ -s "$OUT/ports/nmap-hosts.txt" ]] || cp "$OUT/dns/resolved.txt" "$OUT/ports/nmap-hosts.txt"
  : > "$OUT/ports/nmap-services.nmap"
  : > "$OUT/ports/nmap-services.xml"
  : > "$OUT/ports/nmap-os.txt"
  if command -v nmap >/dev/null 2>&1; then
    nmap -Pn -sV --version-light -T3 --max-retries 1 --host-timeout 2m -iL "$OUT/ports/nmap-hosts.txt" -p 80,443,8080,8443 -oA "$OUT/ports/nmap-services" 2> "$OUT/ports/nmap-services.err" || true
    nmap -Pn -O --osscan-limit -T3 --max-retries 1 --host-timeout 2m -iL "$OUT/ports/nmap-hosts.txt" -p 80,443,8080,8443 -oN "$OUT/ports/nmap-os.txt" 2> "$OUT/ports/nmap-os.err" || true
    if [[ "${RUN_NMAP_VULN:-false}" == true ]]; then
      nmap -Pn -sV --script vuln -T3 --max-retries 1 --host-timeout 3m -iL "$OUT/ports/nmap-hosts.txt" -p 80,443,8080,8443 -oN "$OUT/ports/nmap-vuln.txt" 2> "$OUT/ports/nmap-vuln.err" || true
    else
      printf '%s\n' 'Nmap vulnerability scripts disabled. Set RUN_NMAP_VULN=true only for authorized targets.' > "$OUT/ports/nmap-vuln.txt"
    fi
  else
    printf '%s\n' 'nmap is not installed' > "$OUT/ports/nmap-services.err"
  fi
  grep -E '^[0-9]+/(tcp|udp)[[:space:]]+open' "$OUT/ports/nmap-services.nmap" 2>/dev/null | awk '{print $1}' | sort -u > "$OUT/ports/open-ports.txt" || true
  printf '{"hosts":%s,"open_ports":%s,"nmap_vuln":%s}\n' "$(count_lines "$OUT/ports/nmap-hosts.txt")" "$(count_lines "$OUT/ports/open-ports.txt")" "${RUN_NMAP_VULN:-false}" > "$OUT/ports/summary.json"
}
run_stage 04-ports "Nmap service, port, and OS enumeration" phase_nmap

phase_crawl(){
  : > "$OUT/crawl/all_urls.txt"
  if command -v katana >/dev/null 2>&1; then
    while IFS= read -r url; do [[ -n "$url" ]] || continue; katana -silent -u "$url" -d 2 -jc -o "$OUT/crawl/$(printf '%s' "$url" | md5sum | cut -d' ' -f1).txt" 2>> "$OUT/crawl/katana.err" || true; done < "$OUT/alive/alive.txt"
    cat "$OUT/crawl"/*.txt 2>/dev/null | sort -u > "$OUT/crawl/all_urls.clean" || true
    [[ -f "$OUT/crawl/all_urls.clean" ]] && mv "$OUT/crawl/all_urls.clean" "$OUT/crawl/all_urls.txt"
  fi
  [[ -s "$OUT/crawl/all_urls.txt" ]] || cp "$OUT/alive/alive.txt" "$OUT/crawl/all_urls.txt"
  printf '{"crawl_urls":%s}\n' "$(count_lines "$OUT/crawl/all_urls.txt")" > "$OUT/crawl/summary.json"
}
run_stage 05-crawl "Crawling live HTTP services" phase_crawl

phase_params(){
  grep -Eo 'https?://[^[:space:]]+' "$OUT/crawl/all_urls.txt" | sort -u > "$OUT/params/urls.txt" || true
  grep -Eo '[?&][A-Za-z0-9_-]+=[^&[:space:]]*' "$OUT/params/urls.txt" | sort -u > "$OUT/params/params.txt" || true
  printf '{"params":%s}\n' "$(count_lines "$OUT/params/params.txt")" > "$OUT/params/summary.json"
}
run_stage 06-params "Extracting parameters and endpoints" phase_params

phase_js(){
  grep -Eo 'https?://[^"[:space:]]+\.js([?#[^"[:space:]]*)?' "$OUT/crawl/all_urls.txt" "$OUT/alive/alive.txt" 2>/dev/null | sed 's/^[^:]*://' | sed 's/[),;>]$//' | sort -u > "$OUT/js/js_urls.txt" || true
  while IFS= read -r url; do [[ -n "$url" ]] || continue; hash=$(printf '%s' "$url" | md5sum | cut -d' ' -f1); curl -fsSL --retry 1 --connect-timeout 8 --max-time 30 "$url" -o "$OUT/js/downloads/$hash.js" 2>> "$OUT/js/download.err" || true; done < "$OUT/js/js_urls.txt"
  find "$OUT/js/downloads" -type f -name '*.js' -print -quit | grep -q . && zip -qr "$OUT/js/js-files.zip" "$OUT/js/downloads" || true
  printf '{"js_urls":%s}\n' "$(count_lines "$OUT/js/js_urls.txt")" > "$OUT/tech/summary.json"
}
run_stage 07-tech "Extracting JavaScript URLs" phase_js

if [[ -n "$NUCLEI_PID" ]]; then
  if wait "$NUCLEI_PID"; then stage 15-nuclei completed "Nuclei scan completed: $(count_lines "$OUT/vulns/nuclei.jsonl") findings"; else stage 15-nuclei failed "Nuclei exited with an error"; fi
fi

for key in 08-tls 09-api 10-misconfig 11-injection 12-access-control 13-takeover 14-secrets; do stage "$key" skipped "Not enabled in safe discovery mode"; done
cat > "$OUT/findings/findings.json" <<EOF
{"target":"$TARGET","generated":"$(date -Iseconds)","pipeline_status":"completed","summary":{"subdomains":$TOTAL_SUBS,"resolved_hosts":$(count_lines "$OUT/dns/resolved.txt"),"alive_urls":$(count_lines "$OUT/alive/alive.txt"),"open_ports":$(count_lines "$OUT/ports/open-ports.txt"),"crawl_urls":$(count_lines "$OUT/crawl/all_urls.txt"),"js_urls":$(count_lines "$OUT/js/js_urls.txt"),"nuclei_findings":$(count_lines "$OUT/vulns/nuclei.jsonl")}}
EOF
cat > "$OUT/report/report.md" <<EOF
# Recon Report

Target: $TARGET
Generated: $(date -Iseconds)

- Subdomains: $TOTAL_SUBS
- Resolved hosts: $(count_lines "$OUT/dns/resolved.txt")
- Alive URLs: $(count_lines "$OUT/alive/alive.txt")
- Open ports: $(count_lines "$OUT/ports/open-ports.txt")
- Crawled URLs: $(count_lines "$OUT/crawl/all_urls.txt")
- JavaScript URLs: $(count_lines "$OUT/js/js_urls.txt")
- Nuclei findings: $(count_lines "$OUT/vulns/nuclei.jsonl")

Artifacts:
- ports/nmap-services.nmap
- ports/nmap-services.xml
- ports/nmap-os.txt
- ports/nmap-vuln.txt
- vulns/nuclei.jsonl
EOF
stage 16-report completed "Report generated successfully"
log "Pipeline completed for $TARGET"
