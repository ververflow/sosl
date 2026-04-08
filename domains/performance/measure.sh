#!/bin/bash
# SOSL Domain: Performance — Measurement script
# Runs Lighthouse CI against a target URL, outputs performance score (0-100)
#
# Usage: bash measure.sh /path/to/target
# Output: single number (0-100) to stdout

set -euo pipefail

TARGET_DIR="${1:-.}"
TARGET_URL="${TARGET_URL:-http://localhost:3000}"

# Create temp dir with Windows-compatible path for Python
WORK_DIR=$(python3 -c "import tempfile, os; d = tempfile.mkdtemp(prefix='sosl-lh-'); print(d.replace(os.sep, '/'))")

cd "$WORK_DIR"

npx @lhci/cli collect \
  --url="$TARGET_URL" \
  --numberOfRuns=1 \
  --chromeFlags="--headless --no-sandbox --disable-gpu" > /dev/null 2>&1

# Parse score from JSON report (WORK_DIR is Python-resolved, so glob works)
python3 -c "
import json, glob, sys, os, shutil

lhci_dir = os.path.join('$WORK_DIR', '.lighthouseci')
files = sorted(glob.glob(os.path.join(lhci_dir, 'lhr-*.json')))
if not files:
    shutil.rmtree('$WORK_DIR', ignore_errors=True)
    print('0')
    sys.exit(1)

with open(files[-1], encoding='utf-8') as f:
    report = json.load(f)

score = report.get('categories', {}).get('performance', {}).get('score', 0)
shutil.rmtree('$WORK_DIR', ignore_errors=True)
print(round(score * 100, 1))
"
