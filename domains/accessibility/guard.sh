#!/bin/bash
# SOSL Domain: Accessibility — Guard script
set -euo pipefail
TARGET_DIR="${1:-.}"

# TypeScript must compile
if [[ -f "$TARGET_DIR/frontend/tsconfig.json" ]]; then
  cd "$TARGET_DIR/frontend"
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1) || {
    echo "GUARD FAIL: TypeScript errors"
    echo "$TSC_OUTPUT" | head -10
    exit 1
  }
fi

echo "GUARD PASS"
exit 0
