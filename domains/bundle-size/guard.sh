#!/bin/bash
# SOSL Domain: Bundle Size — Guard script
set -euo pipefail
TARGET_DIR="${1:-.}"

# Build must succeed
cd "$TARGET_DIR/frontend"
BUILD_OUTPUT=$(npm run build 2>&1) || {
  echo "GUARD FAIL: Build failed"
  echo "$BUILD_OUTPUT" | tail -10
  exit 1
}

# No pages deleted
if [[ -d "$TARGET_DIR/frontend/src/app" ]]; then
  PAGE_COUNT=$(find "$TARGET_DIR/frontend/src/app" -name "page.tsx" | wc -l)
  if [[ "$PAGE_COUNT" -lt 2 ]]; then
    echo "GUARD FAIL: Pages deleted ($PAGE_COUNT remaining)"
    exit 1
  fi
fi

echo "GUARD PASS"
exit 0
