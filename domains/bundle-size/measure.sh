#!/bin/bash
# SOSL Domain: Bundle Size — Measurement script
# Builds Next.js, measures .next output size, inverts for higher=better

set -euo pipefail

TARGET_DIR="${1:-.}"

cd "$TARGET_DIR/frontend"

# Build production bundle
npm run build > /dev/null 2>&1 || {
  echo "0"
  exit 1
}

# Measure .next directory size in KB
SIZE_KB=$(du -sk .next/ 2>/dev/null | awk '{print $1}')

# Invert: smaller bundle = higher score (ceiling at 50000 KB)
python3 -c "print(max(0, 50000 - int($SIZE_KB)))"
