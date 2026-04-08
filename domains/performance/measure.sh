#!/bin/bash
# SOSL Domain: Performance — Measurement script
# Runs Lighthouse CI against a running dev/prod server, outputs performance score (0-100)
#
# Usage: bash measure.sh /path/to/target
# Output: single number (0-100) to stdout
# Env: TARGET_URL (default: http://localhost:3000)
#      URLS (comma-separated paths, default: /)

set -euo pipefail

TARGET_DIR="${1:-.}"
TARGET_URL="${TARGET_URL:-http://localhost:3000}"
URLS="${URLS:-/}"

# ── Measure Lighthouse on each URL, take lowest score ────────────────────────
LOWEST_SCORE=100
IFS=',' read -ra URL_LIST <<< "$URLS"

for url_path in "${URL_LIST[@]}"; do
  FULL_URL="${TARGET_URL}${url_path}"

  LH_DIR=$(python3 -c "import tempfile, os; d = tempfile.mkdtemp(prefix='sosl-lhrun-'); print(d.replace(os.sep, '/'))")
  cd "$LH_DIR"

  npx @lhci/cli collect \
    --url="$FULL_URL" \
    --numberOfRuns=1 \
    --chromeFlags="--headless --no-sandbox --disable-gpu" > /dev/null 2>&1 || true

  SCORE=$(python3 -c "
import json, glob, sys, os, shutil

lhci_dir = os.path.join('$LH_DIR', '.lighthouseci')
files = sorted(glob.glob(os.path.join(lhci_dir, 'lhr-*.json')))
if not files:
    print('0')
else:
    with open(files[-1], encoding='utf-8') as f:
        report = json.load(f)
    score = report.get('categories', {}).get('performance', {}).get('score', 0)
    print(round(score * 100, 1))

shutil.rmtree('$LH_DIR', ignore_errors=True)
" 2>/dev/null || echo "0")

  if python3 -c "exit(0 if float($SCORE) < float($LOWEST_SCORE) else 1)" 2>/dev/null; then
    LOWEST_SCORE="$SCORE"
  fi
done

echo "$LOWEST_SCORE"
