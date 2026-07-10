#!/bin/bash
# SOSL — Eval harness (robust measurement with median-of-N)

# Run measure.sh N times, return "median noise_floor"
# Usage: measure_robust /path/to/measure.sh /path/to/target 3
# Output: "63.0 0.7" on stdout. Progress/warnings go to stderr: callers capture
# stdout via command substitution, so anything else on stdout would corrupt the
# parsed score.
measure_robust() {
  local measure_script="$1"
  local target_dir="${2:-.}"
  local n_samples="${3:-3}"
  local values=()

  for ((i=1; i<=n_samples; i++)); do
    local score
    local exit_code=0
    local timeout_sec="${MEASURE_TIMEOUT:-120}"
    local t0=$SECONDS
    score=$(sosl_timeout "$timeout_sec" bash "$measure_script" "$target_dir" 2>/dev/null) || exit_code=$?
    hb_touch
    if [[ "$exit_code" -eq 124 ]]; then
      log_warn "Measurement $i/$n_samples timed out after ${timeout_sec}s" >&2
      continue
    fi
    if [[ -z "$score" ]]; then
      log_warn "Measurement $i/$n_samples failed (no output, exit $exit_code)" >&2
      continue
    fi
    # Score "0" from a non-zero exit = measurement failure, not a real score
    if [[ "$score" == "0" ]] && [[ "$exit_code" -ne 0 ]]; then
      log_warn "Measurement $i/$n_samples failed (exit $exit_code, score 0)" >&2
      continue
    fi
    log "  sample $i/$n_samples: $score ($((SECONDS - t0))s)" >&2
    values+=("$score")
  done

  if [[ ${#values[@]} -eq 0 ]]; then
    log_err "All measurements failed" >&2
    echo "0 0"
    return 1
  fi

  calculate_stats "${values[@]}"
}
