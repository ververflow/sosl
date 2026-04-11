#!/bin/bash
# SOSL Guard: Generic Lint Score
# Stack-agnostic: checks that the project still builds/passes basic checks
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# Auto-detect and run build/type check
if [[ -f "package.json" ]]; then
  # Node: TypeScript check if available
  if [[ -f "tsconfig.json" ]]; then
    npx tsc --noEmit 2>&1 || { echo "GUARD FAIL: TypeScript check failed"; exit 1; }
  fi
elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
  # Python: syntax check
  python -m py_compile $(find . -name "*.py" -not -path "./.venv/*" -not -path "./venv/*" | head -20) 2>&1 || {
    echo "GUARD FAIL: Python syntax error"; exit 1
  }
elif [[ -f "Cargo.toml" ]]; then
  cargo check 2>&1 || { echo "GUARD FAIL: cargo check failed"; exit 1; }
elif [[ -f "go.mod" ]]; then
  go build ./... 2>&1 || { echo "GUARD FAIL: go build failed"; exit 1; }
fi

echo "GUARD PASS"
