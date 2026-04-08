#!/bin/bash
# SOSL Domain: Code Quality — Guard script
set -euo pipefail
TARGET_DIR="${1:-.}"

# TypeScript must still compile
if [[ -f "$TARGET_DIR/frontend/tsconfig.json" ]]; then
  cd "$TARGET_DIR/frontend"
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1) || {
    echo "GUARD FAIL: TypeScript errors introduced"
    echo "$TSC_OUTPUT" | head -10
    exit 1
  }
fi

# Unit tests must still pass
if [[ -f "$TARGET_DIR/frontend/vitest.config.ts" ]] || [[ -f "$TARGET_DIR/frontend/vitest.config.mts" ]]; then
  cd "$TARGET_DIR/frontend"
  TEST_OUTPUT=$(npx vitest run --reporter=verbose 2>&1) || {
    echo "GUARD FAIL: Unit tests failed"
    echo "$TEST_OUTPUT" | tail -10
    exit 1
  }
fi

echo "GUARD PASS"
exit 0
