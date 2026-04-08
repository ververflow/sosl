#!/bin/bash
# SOSL Domain: Performance — Guard script
# Ensures optimization changes don't break functionality
#
# Usage: bash guard.sh /path/to/target
# Exit 0 = pass, exit 1 = fail (reason on stdout)

set -euo pipefail

TARGET_DIR="${1:-.}"

# ── 1. TypeScript must compile ───────────────────────────────────────────────
if [[ -f "$TARGET_DIR/frontend/tsconfig.json" ]]; then
  cd "$TARGET_DIR/frontend"
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1) || {
    echo "GUARD FAIL: TypeScript compilation errors"
    echo "$TSC_OUTPUT" | head -10
    exit 1
  }
fi

# ── 2. No pages deleted (feature protection) ────────────────────────────────
if [[ -d "$TARGET_DIR/frontend/src/app" ]]; then
  PAGE_COUNT=$(find "$TARGET_DIR/frontend/src/app" -name "page.tsx" | wc -l | tr -d '[:space:]')
  if [[ "$PAGE_COUNT" -lt 2 ]]; then
    echo "GUARD FAIL: Too few pages remaining ($PAGE_COUNT). Possible feature deletion."
    exit 1
  fi
fi

# ── 3. Build must succeed ────────────────────────────────────────────────────
if [[ -f "$TARGET_DIR/frontend/package.json" ]]; then
  cd "$TARGET_DIR/frontend"
  BUILD_OUTPUT=$(npm run build 2>&1) || {
    echo "GUARD FAIL: Build failed"
    echo "$BUILD_OUTPUT" | tail -10
    exit 1
  }
fi

echo "GUARD PASS"
exit 0
