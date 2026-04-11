#!/bin/bash
# SOSL — Stack-specific guards: Go

run_stack_guards() {
  local target_dir="$1"

  # ── Test file deletion (Go patterns) ─────────────────────────────────────
  local deleted_tests
  deleted_tests=$(git -C "$target_dir" diff --name-only --diff-filter=D | grep -E '_test\.go$' || true)
  if [[ -n "$deleted_tests" ]]; then
    echo "Test files deleted: $deleted_tests"
    return 1
  fi

  # ── No new //nolint comments ─────────────────────────────────────────────
  local suppression_added
  suppression_added=$(git -C "$target_dir" diff HEAD -- '*.go' 2>/dev/null | python3 -c "
import sys
added = removed = 0
for line in sys.stdin:
    line = line.rstrip()
    if '//nolint' in line:
        if line.startswith('+') and not line.startswith('+++'):
            added += 1
        elif line.startswith('-') and not line.startswith('---'):
            removed += 1
print(max(0, added - removed))
" 2>/dev/null || echo 0)
  if [[ "$suppression_added" -gt 0 ]]; then
    echo "New //nolint comments added ($suppression_added net new)"
    return 1
  fi

  # ── No new go.mod dependencies ───────────────────────────────────────────
  local new_deps
  new_deps=$(git -C "$target_dir" diff HEAD -- 'go.mod' 2>/dev/null | python3 -c "
import sys
added = 0
for line in sys.stdin:
    line = line.rstrip()
    if line.startswith('+') and not line.startswith('+++'):
        stripped = line[1:].strip()
        if stripped.startswith('require') or (stripped and '/' in stripped and not stripped.startswith('//')):
            added += 1
print(added)
" 2>/dev/null || echo 0)
  new_deps=$(echo "$new_deps" | tr -d '[:space:]')
  if [[ -n "$new_deps" ]] && [[ "$new_deps" -gt 0 ]]; then
    echo "New go.mod dependencies added ($new_deps new)"
    return 1
  fi

  return 0
}
