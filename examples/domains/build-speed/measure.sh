#!/bin/bash
# SOSL Example Domain: Build Speed
# Metric: max(0, 300 - build_seconds) -- higher = faster build
# Auto-detects build command from project type
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# Auto-detect build command
BUILD_CMD=""
if [[ -f "package.json" ]]; then
  BUILD_CMD="npm run build"
elif [[ -f "Cargo.toml" ]]; then
  BUILD_CMD="cargo build --release"
elif [[ -f "go.mod" ]]; then
  BUILD_CMD="go build ./..."
elif [[ -f "Makefile" ]]; then
  BUILD_CMD="make"
elif [[ -f "pyproject.toml" ]]; then
  BUILD_CMD="python -m build"
fi

if [[ -z "$BUILD_CMD" ]]; then
  echo "0"
  exit 1
fi

# Time the build
start=$(python3 -c "import time; print(time.time())")
eval "$BUILD_CMD" > /dev/null 2>&1
end=$(python3 -c "import time; print(time.time())")

# Calculate build time in seconds, invert (faster = higher score)
python3 -c "
start, end = $start, $end
seconds = end - start
# Invert: 300 - seconds (cap at 0). Faster builds = higher score
score = max(0, 300 - seconds)
print(round(score, 1))
"
