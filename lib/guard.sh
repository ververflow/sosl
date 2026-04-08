#!/bin/bash
# SOSL — Guard rail framework

# Run domain-specific guard + universal guards
# Usage: run_guards /path/to/guard.sh /path/to/target
# Exit 0 = all pass, exit 1 = guard violation (reason on stdout)
run_guards() {
  local guard_script="$1"
  local target_dir="$2"

  # ── Universal guards ──────────────────────────────────────────────────────

  # 1. Changed files count check (prevent mass rewrites)
  local changed_count
  changed_count=$(git -C "$target_dir" diff --name-only | wc -l | tr -d '[:space:]')
  if [[ "$changed_count" -gt 50 ]]; then
    echo "Too many files changed ($changed_count > 50)"
    return 1
  fi

  # 2. No deleted test files
  local deleted_tests
  deleted_tests=$(git -C "$target_dir" diff --name-only --diff-filter=D | grep -E '(test_|\.test\.|\.spec\.|e2e/)' || true)
  if [[ -n "$deleted_tests" ]]; then
    echo "Test files deleted: $deleted_tests"
    return 1
  fi

  # 3. No new eslint-disable comments (use python for reliable counting)
  local disable_added
  disable_added=$(git -C "$target_dir" diff HEAD -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null | python3 -c "
import sys
added = removed = 0
for line in sys.stdin:
    line = line.rstrip()
    if line.startswith('+') and 'eslint-disable' in line:
        added += 1
    elif line.startswith('-') and 'eslint-disable' in line:
        removed += 1
print(max(0, added - removed))
" 2>/dev/null || echo 0)
  if [[ "$disable_added" -gt 0 ]]; then
    echo "New eslint-disable comments added ($disable_added net new)"
    return 1
  fi

  # ── Domain-specific guard ─────────────────────────────────────────────────
  if [[ -f "$guard_script" ]]; then
    local guard_output
    guard_output=$(bash "$guard_script" "$target_dir" 2>&1)
    local guard_exit=$?
    if [[ $guard_exit -ne 0 ]]; then
      echo "$guard_output"
      return 1
    fi
  fi

  return 0
}
