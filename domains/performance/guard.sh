#!/bin/bash
# SOSL Domain: Performance — Guard script
# Heavy checks: tsc + build. Universal guards (imports, deletions) run first in lib/guard.sh
#
# Usage: bash guard.sh /path/to/target
# Exit 0 = pass, exit 1 = fail (reason on stdout)

set -euo pipefail

TARGET_DIR="${1:-.}"
FRONTEND_DIR="$TARGET_DIR/frontend"

# ── 1. Clear tsc incremental cache only (NOT .next — that kills the dev server)
if [[ -d "$FRONTEND_DIR" ]]; then
  python3 - "$FRONTEND_DIR" <<'PYEOF' 2>/dev/null || true
import os, sys
frontend = os.path.normpath(sys.argv[1])
for f in ['tsconfig.tsbuildinfo', '.tsbuildinfo']:
    p = os.path.join(frontend, f)
    if os.path.exists(p): os.remove(p)
PYEOF
fi

# ── 2. TypeScript must compile (fresh incremental check) ─────────────────────
if [[ -f "$FRONTEND_DIR/tsconfig.json" ]]; then
  cd "$FRONTEND_DIR"
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1) || {
    echo "GUARD FAIL: TypeScript compilation errors"
    echo "$TSC_OUTPUT" | head -15
    exit 1
  }
fi

# ── 3. No pages deleted (feature protection) ────────────────────────────────
if [[ -d "$FRONTEND_DIR/src/app" ]]; then
  PAGE_COUNT=$(find "$FRONTEND_DIR/src/app" -name "page.tsx" | wc -l | tr -d '[:space:]')
  if [[ "$PAGE_COUNT" -lt 2 ]]; then
    echo "GUARD FAIL: Too few pages remaining ($PAGE_COUNT). Possible feature deletion."
    exit 1
  fi
fi

# ── 4. Build must succeed ────────────────────────────────────────────────────
if [[ -f "$FRONTEND_DIR/package.json" ]]; then
  cd "$FRONTEND_DIR"
  BUILD_OUTPUT=$(npm run build 2>&1) || {
    echo "GUARD FAIL: Build failed"
    echo "$BUILD_OUTPUT" | tail -10
    exit 1
  }
fi

echo "GUARD PASS"
exit 0
