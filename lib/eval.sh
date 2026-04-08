#!/bin/bash
# SOSL — Eval harness (robust measurement with median-of-N)

# Run measure.sh N times, return "median noise_floor"
# Usage: measure_robust /path/to/measure.sh /path/to/target 3
# Output: "63.0 0.7"
measure_robust() {
  local measure_script="$1"
  local target_dir="${2:-.}"
  local n_samples="${3:-3}"
  local values=()

  for ((i=1; i<=n_samples; i++)); do
    local score exit_code
    score=$(bash "$measure_script" "$target_dir" 2>/dev/null) || true
    exit_code=${PIPESTATUS[0]:-$?}
    # Score "0" from a failed measure is a measurement failure, not a real score
    if [[ -z "$score" ]]; then
      log_warn "Measurement $i/$n_samples failed (no output)"
      continue
    fi
    if [[ "$score" == "0" ]] && [[ "$exit_code" -ne 0 ]]; then
      log_warn "Measurement $i/$n_samples failed (exit $exit_code, score 0)"
      continue
    fi
    values+=("$score")
  done

  if [[ ${#values[@]} -eq 0 ]]; then
    log_err "All measurements failed"
    echo "0 0"
    return 1
  fi

  calculate_stats "${values[@]}"
}
