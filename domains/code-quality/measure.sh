#!/bin/bash
# SOSL Domain: Code Quality — Measurement script
# Counts ESLint errors+warnings, inverts for higher=better scoring

set -euo pipefail

TARGET_DIR="${1:-.}"

cd "$TARGET_DIR/frontend"

# Count total errors + warnings
ERROR_COUNT=$(npx eslint --format json . 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    total = sum(r.get('errorCount', 0) + r.get('warningCount', 0) for r in data)
    print(total)
except:
    print(9999)
")

# Invert: higher score = fewer errors (ceiling at 1000)
python3 - "$ERROR_COUNT" <<'PYEOF'
import sys
print(max(0, 1000 - int(sys.argv[1])))
PYEOF
