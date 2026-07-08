#!/bin/bash
# Suite fixture: a slow-but-legal measurement (90s < MEASURE_TIMEOUT=120).
# Used to prove the night orchestrator's wallclock watchdog, which must kill
# the whole run even though no single step violates its own timeout.
set -euo pipefail
TARGET_DIR="${1:-.}"
sleep 90
tr -cd '0-9' < "$TARGET_DIR/score.txt"
echo ""
