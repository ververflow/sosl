#!/bin/bash
# Baseline (score.txt still "42") measures fine, so the run gets a valid start;
# any CHANGE then makes the measurement fail on ALL samples — simulating a change
# that breaks the metric harness, or a transient DB/timeout failure mid-run.
# Proves B1: an in-loop all-samples-fail must REVERT and let the loop continue,
# never abort the whole run via `set -e`.
# On failure, print "0" and exit non-zero (see lib/eval.sh — a 0 score from a
# non-zero exit is counted as a failed sample, not a real measurement).
set -euo pipefail
TARGET_DIR="${1:-.}"
val="$(tr -cd '0-9' < "$TARGET_DIR/score.txt")"
if [[ "$val" == "42" ]]; then
  echo "$val"
else
  echo "measure-fail: metric harness broke on the change (all samples errored)" 1>&2
  echo "0"
  exit 1
fi
