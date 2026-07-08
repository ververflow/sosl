#!/bin/bash
# Suite fixture guard: score.txt must contain a bare integer, nothing else.
set -euo pipefail
TARGET_DIR="${1:-.}"
content="$(cat "$TARGET_DIR/score.txt")"
if [[ ! "$content" =~ ^[0-9]+[[:space:]]*$ ]]; then
  echo "GUARD FAIL: score.txt is not a bare integer"
  exit 1
fi
echo "GUARD PASS"
exit 0
