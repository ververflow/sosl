#!/bin/bash
# Suite fixture (monorepo variant): metric is the number in score.txt.
set -euo pipefail
TARGET_DIR="${1:-.}"
val="$(tr -cd '0-9' < "$TARGET_DIR/score.txt")"
[[ -n "$val" ]] || { echo "0"; exit 1; }
echo "$val"
