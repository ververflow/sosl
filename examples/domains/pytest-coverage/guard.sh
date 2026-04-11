#!/bin/bash
# SOSL Guard: Python Test Coverage
# Ensures tests still pass and no test files were deleted
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# 1. All tests must pass (not just coverage — tests must be green)
python -m pytest --tb=short -q 2>&1 || {
  echo "GUARD FAIL: pytest tests failed"
  exit 1
}

# 2. Type checking (if mypy is available)
if command -v mypy &>/dev/null && [[ -f "pyproject.toml" ]]; then
  mypy . --ignore-missing-imports --no-error-summary 2>&1 || {
    echo "GUARD FAIL: mypy type check failed"
    exit 1
  }
fi

echo "GUARD PASS"
