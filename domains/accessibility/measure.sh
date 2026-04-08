#!/bin/bash
# SOSL Domain: Accessibility — Measurement script
# Runs Lighthouse CI, outputs accessibility score (0-100)

set -euo pipefail

TARGET_DIR="${1:-.}"
TARGET_URL="${TARGET_URL:-http://localhost:3000}"
URLS="${URLS:-/}"

LOWEST_SCORE=100
IFS=',' read -ra URL_LIST <<< "$URLS"

for url_path in "${URL_LIST[@]}"; do
  LH_DIR=$(python3 -c "import tempfile, os; d = tempfile.mkdtemp(prefix='sosl-lhrun-'); print(d.replace(os.sep, '/'))")
  cd "$LH_DIR"

  npx @lhci/cli collect \
    --url="${TARGET_URL}${url_path}" \
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

score = report.get('categories', {}).get('accessibility', {}).get('score', 0)
print(round(score * 100, 1))

# Write top failing audits to .sosl/last-audit.txt for prompt injection
try:
    audits = report.get('audits', {})
    a11y_refs = report.get('categories', {}).get('accessibility', {}).get('auditRefs', [])
    failures = []
    for ref in a11y_refs:
        audit = audits.get(ref.get('id', ''), {})
        audit_score = audit.get('score')
        if audit_score is not None and audit_score < 1.0 and ref.get('weight', 0) > 0:
            title = audit.get('title', ref['id'])
            display = audit.get('displayValue', '')
            failures.append((ref.get('weight', 0), title, display, audit_score))
    failures.sort(key=lambda x: -x[0])

    sosl_dir = os.environ.get('SOSL_STATE_DIR') or os.path.join(target_dir, '.sosl')
    os.makedirs(sosl_dir, exist_ok=True)
    with open(os.path.join(sosl_dir, 'last-audit.txt'), 'w', encoding='utf-8') as f:
        f.write('Top failing Lighthouse accessibility audits:\n')
        for weight, title, display, ascore in failures[:8]:
            f.write(f'  [{int(ascore*100)}/100] {title}')
            if display:
                f.write(f' ({display})')
            f.write(f' [weight: {weight}]\n')
except Exception:
    pass

shutil.rmtree(lh_dir, ignore_errors=True)
PYEOF
)

  if python3 -c "exit(0 if float($SCORE) < float($LOWEST_SCORE) else 1)" 2>/dev/null; then
    LOWEST_SCORE="$SCORE"
  fi
done

echo "$LOWEST_SCORE"
