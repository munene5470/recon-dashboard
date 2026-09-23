#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="/usr/local/go/bin:/usr/local/bin:/root/go/bin:${PATH:-}"
export GOBIN=/usr/local/bin
export GOPATH=/root/go
# Allow Go to select/download a newer toolchain when a @latest dependency
# requires one newer than the base image toolchain.
export GOTOOLCHAIN=auto

install_go_tool() {
  local name="$1"
  local module="$2"

  echo "[tools] installing ${name} (${module})"
  go install "$module"

  if [[ ! -x "${GOBIN}/${name}" ]]; then
    echo "[tools] failed to install ${name}: ${GOBIN}/${name} was not created" >&2
    exit 1
  fi

  echo "[tools] installed ${name} -> ${GOBIN}/${name}"
}

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || {
    echo "[tools] required command is missing: ${name}" >&2
    exit 1
  }
}

echo "[tools] $(go version)"

# Passive discovery and DNS.
install_go_tool subfinder github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
install_go_tool assetfinder github.com/tomnomnom/assetfinder@latest
install_go_tool amass github.com/owasp-amass/amass/v4/cmd/amass@latest
install_go_tool dnsx github.com/projectdiscovery/dnsx/cmd/dnsx@latest
install_go_tool alterx github.com/projectdiscovery/alterx/cmd/alterx@latest

# HTTP discovery, crawling, fingerprinting, and templates.
install_go_tool httpx github.com/projectdiscovery/httpx/cmd/httpx@latest
install_go_tool katana github.com/projectdiscovery/katana/cmd/katana@latest
install_go_tool nuclei github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
install_go_tool tlsx github.com/projectdiscovery/tlsx/cmd/tlsx@latest
install_go_tool uncover github.com/projectdiscovery/uncover/cmd/uncover@latest

# Port scanning and content discovery.
install_go_tool naabu github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
install_go_tool ffuf github.com/ffuf/ffuf/v2@latest
install_go_tool gau github.com/lc/gau/v2/cmd/gau@latest
install_go_tool waybackurls github.com/tomnomnom/waybackurls@latest
install_go_tool hakrawler github.com/hakluke/hakrawler@latest

# Common Go-based enumeration utilities.
install_go_tool gobuster github.com/OJ/gobuster/v3@latest

# These commands are supplied by apt in the runtime image.
for tool in bash curl jq git wget unzip dig nmap whois whatweb; do
  require_command "$tool"
done

# crt.sh is accessed through curl and parsed with jq by the runner.
echo '[tools] installed tool inventory:'
for tool in \
  subfinder assetfinder amass dnsx alterx httpx katana nuclei tlsx uncover \
  naabu ffuf gau waybackurls hakrawler gobuster curl jq dig nmap whois whatweb; do
  printf '  %-14s %s\n' "$tool" "$(command -v "$tool")"
done
