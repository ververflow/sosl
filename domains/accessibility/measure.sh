#!/bin/bash
# SOSL Domain: Accessibility — Measurement script
# Runs Lighthouse CI, outputs accessibility score (0-100)

set -euo pipefail

TARGET_DIR="${1:-.}"
TARGET_URL="${TARGET_URL:-http://localhost:3000}"
TEMP_DIR=$(mktemp -d)

npx @lhci/cli collect \
  --url="$TARGET_URL" \
  --numberOfRuns=1 \
  --chromeFlags="--headless --no-sandbox --disable-gpu" \
  --outputDir="$TEMP_DIR" 2>/dev/null

SCORE=$(python3 -c "
import json, glob, sys, os
files = sorted(glob.glob(os.path.join('$TEMP_DIR', 'lhr-*.json')))
if not files:
    print('0'); sys.exit(1)
with open(files[-1]) as f:
    report = json.load(f)
score = report.get('categories', {}).get('accessibility', {}).get('score', 0)
print(round(score * 100, 1))
")

python3 -c "import shutil; shutil.rmtree('$TEMP_DIR', ignore_errors=True)"
echo "$SCORE"
