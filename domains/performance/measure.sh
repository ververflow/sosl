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

  SCORE=$(python3 - "$LH_DIR" "$TARGET_DIR" <<'PYEOF' 2>/dev/null || echo "0"
import json, glob, sys, os, shutil

lh_dir, target_dir = sys.argv[1], sys.argv[2]
lhci_dir = os.path.join(lh_dir, '.lighthouseci')
files = sorted(glob.glob(os.path.join(lhci_dir, 'lhr-*.json')))
if not files:
    print('0')
    sys.exit(0)

with open(files[-1], encoding='utf-8') as f:
    report = json.load(f)

score = report.get('categories', {}).get('performance', {}).get('score', 0)
print(round(score * 100, 1))

# Write top failing audits to .sosl/last-audit.txt for prompt injection
try:
    audits = report.get('audits', {})
    perf_refs = report.get('categories', {}).get('performance', {}).get('auditRefs', [])
    failures = []
    for ref in perf_refs:
        audit = audits.get(ref.get('id', ''), {})
        audit_score = audit.get('score')
        if audit_score is not None and audit_score < 0.9 and ref.get('weight', 0) > 0:
            title = audit.get('title', ref['id'])
            display = audit.get('displayValue', '')
            failures.append((ref.get('weight', 0), title, display, audit_score))
    failures.sort(key=lambda x: -x[0])

    sosl_dir = os.path.join(target_dir, '.sosl')
    os.makedirs(sosl_dir, exist_ok=True)
    with open(os.path.join(sosl_dir, 'last-audit.txt'), 'w', encoding='utf-8') as f:
        f.write('Top failing Lighthouse performance audits:\n')
        for weight, title, display, ascore in failures[:8]:
            f.write(f'  [{int(ascore*100)}/100] {title}')
            if display:
                f.write(f' ({display})')
            f.write(f' [weight: {weight}]\n')
except:
    pass

shutil.rmtree(lh_dir, ignore_errors=True)
PYEOF
)

  if python3 -c "exit(0 if float($SCORE) < float($LOWEST_SCORE) else 1)" 2>/dev/null; then
    LOWEST_SCORE="$SCORE"
  fi
done

echo "$LOWEST_SCORE"
