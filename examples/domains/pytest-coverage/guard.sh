#!/bin/bash
# SOSL Guard: Python Test Coverage
# Ensures tests still pass, no test files were deleted, and new tests actually
# assert behaviour (coverage rewards executed lines — hollow tests game it).
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# 1. All tests must pass (not just coverage — tests must be green)
python -m pytest --tb=short -q 2>&1 || {
  echo "GUARD FAIL: pytest tests failed"
  exit 1
}

# 1b. Test quality: reject assertionless/import-farming/xfail/suppress tests that
# raise coverage without testing anything. Uses the framework helper located via
# SOSL_HOME (exported by sosl.sh); skipped only if the helper can't be found.
_tq="${SOSL_HOME:-}/lib/guards/py_test_quality.py"
if [[ -n "${SOSL_HOME:-}" ]] && [[ -f "$_tq" ]]; then
  python3 "$_tq" "$TARGET_DIR" || exit 1
fi

# 2. Type checking (if mypy is available)
if command -v mypy &>/dev/null && [[ -f "pyproject.toml" ]]; then
  mypy . --ignore-missing-imports --no-error-summary 2>&1 || {
    echo "GUARD FAIL: mypy type check failed"
    exit 1
  }
fi

echo "GUARD PASS"
