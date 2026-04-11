#!/bin/bash
# SOSL Example Domain: Python Test Coverage
# Metric: pytest coverage percentage (higher = better)
# Works with any Python project using pytest + pytest-cov
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# Run pytest with coverage, capture the total percentage
# Output format of pytest-cov: "TOTAL    500    50    90%"
coverage_output=$(python -m pytest --cov --cov-report=term --tb=no -q 2>&1 || true)

# Extract the total coverage percentage
score=$(echo "$coverage_output" | python3 -c "
import sys, re
for line in sys.stdin:
    m = re.search(r'TOTAL\s+\d+\s+\d+\s+(\d+)%', line)
    if m:
        print(m.group(1))
        sys.exit(0)
# Fallback: try pytest-cov summary line format
print(0)
")

echo "$score"
