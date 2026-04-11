#!/bin/bash
# SOSL Guard: Build Speed
# Ensures the build still succeeds and tests pass
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# Build must succeed (same auto-detection as measure.sh)
if [[ -f "package.json" ]]; then
  npm run build 2>&1 || { echo "GUARD FAIL: npm build failed"; exit 1; }
  # Run tests if available
  if grep -q '"test"' package.json 2>/dev/null; then
    npm test 2>&1 || { echo "GUARD FAIL: npm test failed"; exit 1; }
  fi
elif [[ -f "Cargo.toml" ]]; then
  cargo build --release 2>&1 || { echo "GUARD FAIL: cargo build failed"; exit 1; }
  cargo test 2>&1 || { echo "GUARD FAIL: cargo test failed"; exit 1; }
elif [[ -f "go.mod" ]]; then
  go build ./... 2>&1 || { echo "GUARD FAIL: go build failed"; exit 1; }
  go test ./... 2>&1 || { echo "GUARD FAIL: go test failed"; exit 1; }
elif [[ -f "Makefile" ]]; then
  make 2>&1 || { echo "GUARD FAIL: make failed"; exit 1; }
fi

echo "GUARD PASS"
