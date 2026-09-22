#!/usr/bin/env bash
set -Eeuo pipefail

# Best-effort tool bootstrap for the recon container. The scan runner remains
# safe-by-default and records unavailable tools as skipped.
export DEBIAN_FRONTEND=noninteractive
TOOLS_DIR=/opt/recon-tools
BIN_DIR=/usr/local/bin
mkdir -p "$TOOLS_DIR" "$BIN_DIR"

apt-get update
apt-get install -y --no-install-recommends \
  bash ca-certificates curl jq git wget unzip \
  build-essential golang-go python3 python3-pip python3-venv \
  nmap masscan whatweb wafw00f sqlmap pandoc \
  dnsutils libpcap-dev libpcap0.8-dev \
  chromium chromium-driver || true

install_go_tool() {
  local name="$1" package="$2"
  if command -v "$name" >/dev/null 2>&1; then return 0; fi
  echo "[tools] installing $name"
  if timeout 12m go install "$package"; then
    local built="$(go env GOPATH)/bin/$name"
    [[ -x "$built" ]] && ln -sf "$built" "$BIN_DIR/$name"
  else
    echo "[tools] skipped $name: Go installation failed" >&2
  fi
}

install_go_tool subfinder github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
install_go_tool assetfinder github.com/tomnomnom/assetfinder@latest
install_go_tool amass github.com/owasp-amass/amass/v4/cmd/amass@latest
install_go_tool dnsx github.com/projectdiscovery/dnsx/cmd/dnsx@latest
install_go_tool httpx github.com/projectdiscovery/httpx/cmd/httpx@latest
install_go_tool naabu github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
install_go_tool nuclei github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
install_go_tool katana github.com/projectdiscovery/katana/cmd/katana@latest
install_go_tool waybackurls github.com/tomnomnom/waybackurls@latest
install_go_tool gau github.com/lc/gau/v2/cmd/gau@latest
install_go_tool hakrawler github.com/hakluke/hakrawler@latest
install_go_tool dalfox github.com/hahwul/dalfox/v2@latest
install_go_tool subzy github.com/LukaSikic/subzy@latest
install_go_tool gowitness github.com/sensepost/gowitness@latest

# Python tools are isolated so pip does not modify the system interpreter.
python3 -m venv /opt/recon-venv || true
if [[ -x /opt/recon-venv/bin/pip ]]; then
  /opt/recon-venv/bin/pip install --no-cache-dir --upgrade pip || true
  /opt/recon-venv/bin/pip install --no-cache-dir arjun xsstrike ssrfmap || true
  for tool in arjun xsstrike ssrfmap; do
    [[ -x "/opt/recon-venv/bin/$tool" ]] && ln -sf "/opt/recon-venv/bin/$tool" "$BIN_DIR/$tool"
  done
fi

# Tools distributed as repositories/scripts.
clone_tool() {
  local name="$1" url="$2"
  if [[ -d "$TOOLS_DIR/$name/.git" ]]; then return 0; fi
  rm -rf "$TOOLS_DIR/$name"
  git clone --depth 1 "$url" "$TOOLS_DIR/$name" || echo "[tools] skipped $name: clone failed" >&2
}
clone_tool testssl.sh https://github.com/drwetter/testssl.sh.git
[[ -x "$TOOLS_DIR/testssl.sh/testssl.sh" ]] && ln -sf "$TOOLS_DIR/testssl.sh/testssl.sh" "$BIN_DIR/testssl.sh"
clone_tool Corsy https://github.com/s0md3v/Corsy.git
[[ -f "$TOOLS_DIR/Corsy/corsy.py" ]] && printf '#!/bin/sh\nexec python3 /opt/recon-tools/Corsy/corsy.py "$@"\n' > "$BIN_DIR/corsy" && chmod +x "$BIN_DIR/corsy"
clone_tool SecretFinder https://github.com/m4ll0k/SecretFinder.git
if [[ -f "$TOOLS_DIR/SecretFinder/SecretFinder.py" ]]; then
  printf '#!/bin/sh\nexec python3 /opt/recon-tools/SecretFinder/SecretFinder.py "$@"\n' > "$BIN_DIR/secretfinder"
  chmod +x "$BIN_DIR/secretfinder"
fi

# Feroxbuster is downloaded from its release when a package is unavailable.
if ! command -v feroxbuster >/dev/null 2>&1; then
  echo "[tools] feroxbuster is not available from the base package set; runner will mark it skipped"
fi

# Keep the image build successful even when an upstream tool changes its install path.
cat > /etc/profile.d/recon-tools.sh <<'EOF'
export PATH="/usr/local/bin:/opt/recon-venv/bin:$PATH"
EOF

echo '[tools] installed/best-effort inventory:'
for tool in subfinder assetfinder amass crt.sh waybackurls gau dnsx httpx gowitness masscan naabu nmap wafw00f katana hakrawler feroxbuster arjun whatweb testssl.sh sqlmap dalfox xsstrike ssrfmap corsy subzy nuclei trufflehog gitleaks pandoc jq; do
  if command -v "$tool" >/dev/null 2>&1; then echo "[tools] $tool: available"; else echo "[tools] $tool: unavailable"; fi
done
