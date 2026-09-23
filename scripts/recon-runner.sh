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

mkdir -p "$OUT"/{logs,findings,report,subs/raw,dns,alive,ports,crawl,params,tech,tls,api,graphql,headers,cors,vulns,403,idor,takeover,secrets,js/downloads}

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/logs/run.log"; }
stage() { echo "STAGE_EVENT|$1|$2|$3"; }
count_lines() { [[ -f "$1" ]] && wc -l < "$1" | tr -d ' ' || echo 0; }

normalize_hostnames() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#^https?://##I; s#^[*.]+##; s#/.*##' \
    | tr '[:upper:]' '[:lower:]' \
    | grep -E "(^|\.)${TARGET//./\\.}$" || true
}

record_tool() {
  printf '{"tool":"%s","status":"%s","count":%s}\n' "$1" "$2" "${3:-0}" >> "$OUT/subs/tool-status.ndjson"
}

run_subdomain_tool() {
  local name="$1"; shift
  local output="$OUT/subs/raw/$name.txt"
  log "Running $name"
  if "$@" > "$output" 2> "$OUT/subs/raw/$name.err"; then
    normalize_hostnames < "$output" | sort -u > "$output.clean" || true
    mv "$output.clean" "$output"
    record_tool "$name" completed "$(count_lines "$output")"
  else
    : > "$output"
    record_tool "$name" failed 0
    log "$name failed; see $OUT/subs/raw/$name.err"
  fi
}

run_stage() {
  local key="$1"; local description="$2"; local command="$3"
  stage "$key" running "$description"
  log "$description"
  if eval "$command"; then
    stage "$key" completed "$description completed"
  else
    log "$description failed; continuing safely"
    stage "$key" failed "$description failed"
  fi
}

log "Pipeline started for $TARGET"
: > "$OUT/subs/tool-status.ndjson"
printf '%s\n' "$TARGET" > "$OUT/subs/raw/seed.txt"
record_tool seed completed 1

stage 01-subdomains running "Running passive subdomain enumeration"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  log "Running crt.sh"
  if curl -fsSL --retry 2 --connect-timeout 8 --max-time 30 "https://crt.sh/?q=%25.${TARGET}&output=json" > "$OUT/subs/raw/crtsh.json" 2> "$OUT/subs/raw/crtsh.err"; then
    jq -r '.[].name_value // empty' "$OUT/subs/raw/crtsh.json" 2> "$OUT/subs/raw/crtsh.jq.err" | normalize_hostnames | sort -u > "$OUT/subs/raw/crtsh.txt" || true
    record_tool crtsh completed "$(count_lines "$OUT/subs/raw/crtsh.txt")"
  else
    : > "$OUT/subs/raw/crtsh.txt"
    record_tool crtsh failed 0
  fi
else
  record_tool crtsh skipped 0
fi

if command -v subfinder >/dev/null 2>&1; then run_subdomain_tool subfinder subfinder -silent -d "$TARGET"; else record_tool subfinder skipped 0; fi
if command -v assetfinder >/dev/null 2>&1; then run_subdomain_tool assetfinder assetfinder --subs-only "$TARGET"; else record_tool assetfinder skipped 0; fi

{ cat "$OUT/subs/raw/"*.txt 2>/dev/null || true; printf '%s\n' "$TARGET"; } | normalize_hostnames | sort -u > "$OUT/subs/all.txt"
TOTAL_SUBS=$(count_lines "$OUT/subs/all.txt")
printf '{"total_unique":%s,"tools":"subs/tool-status.ndjson"}\n' "$TOTAL_SUBS" > "$OUT/subs/comparison.json"
stage 01-subdomains completed "Passive enumeration complete: $TOTAL_SUBS unique in-scope hosts"

run_stage 02-dns "Resolving discovered hosts" '
  if command -v dnsx >/dev/null 2>&1; then
    dnsx -silent -l "$OUT/subs/all.txt" -o "$OUT/dns/resolved.txt" 2> "$OUT/dns/dnsx.err" || true
  else
    cp "$OUT/subs/all.txt" "$OUT/dns/resolved.txt"
  fi
  [[ -s "$OUT/dns/resolved.txt" ]] || cp "$OUT/subs/all.txt" "$OUT/dns/resolved.txt"
  printf "{\"resolved_hosts\":%s}\n" "$(count_lines "$OUT/dns/resolved.txt")" > "$OUT/dns/summary.json"
'

run_stage 03-alive "Discovering live HTTP services" '
  if command -v httpx >/dev/null 2>&1; then
    httpx -silent -l "$OUT/dns/resolved.txt" -o "$OUT/alive/alive.txt" 2> "$OUT/alive/httpx.err" || true
  else
    sed "s#^#https://#" "$OUT/dns/resolved.txt" > "$OUT/alive/alive.txt"
  fi
  [[ -s "$OUT/alive/alive.txt" ]] || printf "https://%s\n" "$TARGET" > "$OUT/alive/alive.txt"
  printf "{\"alive_urls\":%s}\n" "$(count_lines "$OUT/alive/alive.txt")" > "$OUT/alive/summary.json"
'

run_stage 04-ports "Enumerating ports and services" '
  : > "$OUT/ports/naabu-hosts.txt"
  awk "
  {
    gsub(/\r/, "")
    sub(/^[[:space:]]+/, "")
    sub(/[[:space:]]+$/, "")
    sub(/^https?:\\/\\//, "")
    sub(/\\/.*$/, "")
    sub(/:[0-9]+$/, "")
    if (\$0 ~ /^[A-Za-z0-9.-]+$/) print tolower(\$0)
  }
  " "$OUT/alive/alive.txt" | sort -u > "$OUT/ports/naabu-hosts.txt"
  [[ -s "$OUT/ports/naabu-hosts.txt" ]] || cp "$OUT/dns/resolved.txt" "$OUT/ports/naabu-hosts.txt"

  : > "$OUT/ports/open-ports.txt"
  if command -v naabu >/dev/null 2>&1; then
    naabu -silent -list "$OUT/ports/naabu-hosts.txt" -p 80,443,8080,8443 -c 10 -rate 50 -timeout 5 -retries 1 -o "$OUT/ports/open-ports.txt" 2> "$OUT/ports/naabu.err" || true
  fi

  : > "$OUT/ports/masscan.list"
  if command -s masscan >/dev/null 2>&1 && [[ -s "$OUT/ports/naabu-hosts.txt" ]]; then
    masscan -iL "$OUT/ports/naabu-hosts.txt" -p80,443,8080,8443 --rate 100 --wait 5 --open-only -oL "$OUT/ports/masscan.list" 2> "$OUT/ports/masscan.err" || true
  fi

  PORTS=$(awk -F/ '/open/ {print $1}' "$OUT/ports/open-ports.txt" "$OUT/ports/masscan.list" 2>/dev/null | sort -n -u | paste -sd, -)
  [[ -n "$PORTS" ]] || PORTS="80,443,8080,8443"
  printf "%s\n" "$PORTS" > "$OUT/ports/ports.txt"

  : > "$OUT/ports/nmap-services.nmap"
  : > "$OUT/ports/nmap-services.xml"
  if command -v nmap >/dev/null 2>&1 && [[ -s "$OUT/ports/naabu-hosts.txt" ]]; then
    nmap -Pn -sV --version-light -T3 --max-retries 1 --host-timeout 2m -iL "$OUT/ports/naabu-hosts.txt" -p "$PORTS" -oA "$OUT/ports/nmap-services" 2> "$OUT/ports/nmap-services.err" || true
    nmap -Pn -O --osscan-limit -T3 --max-retries 1 --host-timeout 2m -iL "$OUT/ports/naabu-hosts.txt" -p "$PORTS" -oN "$OUT/ports/nmap-os.txt" 2> "$OUT/ports/nmap-os.err" || true
    if [[ "${RUN_NMAP_VULN:-false}" == "true" ]]; then
      nmap -Pn -sV --script vuln -T3 --max-retries 1 --host-timeout 3m -iL "$OUT/ports/naabu-hosts.txt" -p "$PORTS" -oN "$OUT/ports/nmap-vuln.txt" 2> "$OUT/ports/nmap-vuln.err" || true
    else
      printf '%s\n' "Nmap vulnerability scripts disabled. Set RUN_NMAP_VULN=true only for authorized targets." > "$OUT/ports/nmap-vuln.txt"
    fi
  fi
  printf "{\"naabu\":%s,\"masscan_lines\":%s,\"nmap_ports\":\"%s\",\"nmap_vuln\":%s}\n" "$(count_lines "$OUT/ports/open-ports.txt")" "$(count_lines "$OUT/ports/masscan.list")" "$PORTS" "${RUN_NMAP_VULN:-false}" > "$OUT/ports/summary.json"
'

run_stage 05-crawl "Crawling live HTTP services" '
  : > "$OUT/crawl/all_urls.txt"
  if command -v katana >/dev/null 2>&1; then
    while IFS= read -r url; do
      [[ -n "$url" ]] || continue
      katana -silent -u "$url" -d 2 -jc -o "$OUT/crawl/$(printf "%s" "$url" | md5sum | cut -d" " -f1).txt" 2> "$OUT/crawl/katana.err" || true
    done < "$OUT/alive/alive.txt"
    cat "$OUT/crawl"/*.txt 2>/dev/null | sort -u > "$OUT/crawl/all_urls.clean" || true
    [[ -f "$OUT/crawl/all_urls.clean" ]] && mv "$OUT/crawl/all_urls.clean" "$OUT/crawl/all_urls.txt"
  fi
  [[ -s "$OUT/crawl/all_urls.txt" ]] || cp "$OUT/alive/alive.txt" "$OUT/crawl/all_urls.txt"
  printf "{\"crawl_urls\":%s}\n" "$(count_lines "$OUT/crawl/all_urls.txt")" > "$OUT/crawl/summary.json"
'

run_stage 06-params "Extracting parameters and endpoints" '
  grep -Eo "https?://[^[:space:]]+" "$OUT/crawl/all_urls.txt" | sort -u > "$OUT/params/urls.txt" || true
  grep -Eo "[?&][A-Za-z0-9_-]+=[^&[:space:]]*" "$OUT/params/urls.txt" | sort -u > "$OUT/params/params.txt" || true
  printf "{\"params\":%s}\n" "$(count_lines "$OUT/params/params.txt")" > "$OUT/params/summary.json"
'

run_stage 07-tech "Extracting JavaScript URLs" '
  grep -Eo "https?://[^\"[:space:]]+\.js([?#[^\"[:space:]]*)?" "$OUT/crawl/all_urls.txt" "$OUT/alive/alive.txt" 2>/dev/null | sed "s/^[^:]*://" | sed "s/[),;>]$//" | sort -u > "$OUT/js/js_urls.txt" || true
  while IFS= read -r js_url; do
    [[ -n "$js_url" ]] || continue
    hash=$(printf "%s" "$js_url" | md5sum | cut -d" " -f1)
    curl -fsSL --retry 1 --connect-timeout 8 --max-time 30 "$js_url" -o "$OUT/js/downloads/$hash.js" 2>> "$OUT/js/download.err" || true
  done < "$OUT/js/js_urls.txt"
  if find "$OUT/js/downloads" -type f -name "*.js" -print -quit | grep -q .; then zip -qr "$OUT/js/js-files.zip" "$OUT/js/downloads"; fi
  printf "{\"js_urls\":%s}\n" "$(count_lines "$OUT/js/js_urls.txt")" > "$OUT/tech/summary.json"
'

run_stage 08-tls "Collecting TLS observations" '
  : > "$OUT/tls/observations.txt"
  while IFS= read -r url; do [[ "$url" == https://* ]] && printf "%s\n" "$url" >> "$OUT/tls/observations.txt"; done < "$OUT/alive/alive.txt"
'

run_stage 09-api "Discovering API and GraphQL endpoints" '
  grep -Eio "https?://[^[:space:]]+/(api|graphql|v[0-9]+)[^[:space:]]*" "$OUT/crawl/all_urls.txt" "$OUT/js/js_urls.txt" 2>/dev/null | sort -u > "$OUT/api/api_endpoints.txt" || true
  grep -Ei "graphql|/graphql" "$OUT/crawl/all_urls.txt" "$OUT/js/js_urls.txt" 2>/dev/null | sort -u > "$OUT/graphql/graphql_endpoints.txt" || true
  printf "{\"api\":%s,\"graphql\":%s}\n" "$(count_lines "$OUT/api/api_endpoints.txt")" "$(count_lines "$OUT/graphql/graphql_endpoints.txt")" > "$OUT/api/summary.json"
'

for key in 10-misconfig 11-injection 12-access-control 13-takeover 14-secrets 15-nuclei; do stage "$key" skipped "Not enabled in safe discovery mode"; done

cat > "$OUT/findings/findings.json" <<EOF
{"target":"$TARGET","generated":"$(date -Iseconds)","pipeline_status":"completed","summary":{"subdomains":$TOTAL_SUBS,"resolved_hosts":$(count_lines "$OUT/dns/resolved.txt"),"alive_urls":$(count_lines "$OUT/alive/alive.txt"),"crawl_urls":$(count_lines "$OUT/crawl/all_urls.txt"),"js_urls":$(count_lines "$OUT/js/js_urls.txt"),"api_endpoints":$(count_lines "$OUT/api/api_endpoints.txt"),"graphql_endpoints":$(count_lines "$OUT/graphql/graphql_endpoints.txt"),"open_ports":$(count_lines "$OUT/ports/open-ports.txt")}}
EOF

cat > "$OUT/report/report.md" <<EOF
# Recon Report

Target: $TARGET
Generated: $(date -Iseconds)

## Discovery summary
- Subdomains: $TOTAL_SUBS
- Resolved hosts: $(count_lines "$OUT/dns/resolved.txt")
- Alive URLs: $(count_lines "$OUT/alive/alive.txt")
- Crawled URLs: $(count_lines "$OUT/crawl/all_urls.txt")
- JavaScript URLs: $(count_lines "$OUT/js/js_urls.txt")
- Open ports: $(count_lines "$OUT/ports/open-ports.txt")
- API endpoints: $(count_lines "$OUT/api/api_endpoints.txt")
- GraphQL endpoints: $(count_lines "$OUT/graphql/graphql_endpoints.txt")

## Port and service artifacts
- Naabu: ports/open-ports.txt
- Masscan: ports/masscan.list
- Nmap service/version scan: ports/nmap-services.nmap
- Nmap OS scan: ports/nmap-os.txt
- Nmap NSE vulnerability scan: ports/nmap-vuln.txt
EOF

stage 16-report completed "Report generated successfully"
log "Pipeline completed for $TARGET"
