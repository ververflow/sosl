#!/bin/bash
# SOSL Domain: Performance — Measurement script
# Runs Lighthouse CI against a target URL, outputs performance score (0-100)
#
# Usage: bash measure.sh /path/to/target
# Output: single number (0-100) to stdout

set -euo pipefail

TARGET_DIR="${1:-.}"
TARGET_URL="${TARGET_URL:-http://localhost:3000}"
TEMP_DIR=$(mktemp -d)

# Run Lighthouse headless (single run — median handled by eval.sh)
npx @lhci/cli collect \
  --url="$TARGET_URL" \
  --numberOfRuns=1 \
  --chromeFlags="--headless --no-sandbox --disable-gpu" \
  --outputDir="$TEMP_DIR" 2>/dev/null

# Parse score from JSON report
SCORE=$(python3 -c "
import json, glob, sys, os

files = sorted(glob.glob(os.path.join('$TEMP_DIR', 'lhr-*.json')))
if not files:
    print('0')
    sys.exit(1)

with open(files[-1]) as f:
    report = json.load(f)

score = report.get('categories', {}).get('performance', {}).get('score', 0)
print(round(score * 100, 1))
")

# Cleanup
rm -rf "$TEMP_DIR"

echo "$SCORE"
