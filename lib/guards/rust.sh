#!/bin/bash
# SOSL — Stack-specific guards: Rust

run_stack_guards() {
  local target_dir="$1"

  # ── Test file deletion (Rust patterns) ───────────────────────────────────
  local deleted_tests
  deleted_tests=$(git -C "$target_dir" diff --name-only --diff-filter=D | grep -E '(tests/|_test\.rs)' || true)
  if [[ -n "$deleted_tests" ]]; then
    echo "Test files deleted: $deleted_tests"
    return 1
  fi

  # ── No new #[allow(...)] attributes ──────────────────────────────────────
  local suppression_added
  suppression_added=$(git -C "$target_dir" diff HEAD -- '*.rs' 2>/dev/null | python3 -c "
import sys, re
added = removed = 0
for line in sys.stdin:
    line = line.rstrip()
    if re.search(r'#\[allow\(', line):
        if line.startswith('+') and not line.startswith('+++'):
            added += 1
        elif line.startswith('-') and not line.startswith('---'):
            removed += 1
print(max(0, added - removed))
" 2>/dev/null || echo 0)
  if [[ "$suppression_added" -gt 0 ]]; then
    echo "New #[allow(...)] attributes added ($suppression_added net new)"
    return 1
  fi

  # ── No new Cargo.toml dependencies ───────────────────────────────────────
  local new_deps
  new_deps=$(git -C "$target_dir" diff HEAD -- 'Cargo.toml' '*/Cargo.toml' 2>/dev/null | python3 -c "
import sys, re
added = 0
in_deps = False
for line in sys.stdin:
    line = line.rstrip()
    if re.match(r'^\+\s*\[(.*dependencies)', line):
        in_deps = True
    elif line.startswith('+') and in_deps:
        stripped = line[1:].strip()
        if stripped and not stripped.startswith('[') and not stripped.startswith('#'):
            added += 1
    elif line.startswith('+') and line[1:].strip().startswith('['):
        in_deps = False
print(added)
" 2>/dev/null || echo 0)
  new_deps=$(echo "$new_deps" | tr -d '[:space:]')
  if [[ -n "$new_deps" ]] && [[ "$new_deps" -gt 0 ]]; then
    echo "New Cargo dependencies added ($new_deps new)"
    return 1
  fi

  return 0
}
