#!/usr/bin/env bash
set -Eeuo pipefail

# Run a bounded, non-destructive Nuclei pass against URLs produced by httpx.
# Usage: run-nuclei-live.sh <alive.txt> <output.ndjson> <error.log>
INPUT="${1:?alive URL file required}"
OUTPUT="${2:?output file required}"
ERRORS="${3:?error file required}"

mkdir -p "$(dirname "$OUTPUT")" "$(dirname "$ERRORS")"
: > "$OUTPUT"
: > "$ERRORS"

if ! command -v nuclei >/dev/null 2>&1; then
  printf '%s\n' 'nuclei is not installed' > "$ERRORS"
  exit 0
fi

[[ -s "$INPUT" ]] || exit 0

# Keep this pass limited to HTTP URLs and non-destructive exposure/misconfiguration
# checks. Do not enable intrusive templates or fuzzing from the dashboard runner.
grep -E '^https?://' "$INPUT" | sort -u > "${OUTPUT}.targets"
[[ -s "${OUTPUT}.targets" ]] || exit 0

nuclei \
  -l "${OUTPUT}.targets" \
  -jsonl \
  -silent \
  -no-interactsh \
  -rate-limit 25 \
  -bulk-size 10 \
  -concurrency 5 \
  -timeout 10 \
  -retries 1 \
  -severity info,low,medium \
  -tags exposure,misconfig,tech \
  -o "$OUTPUT" \
  2> "$ERRORS" || true
