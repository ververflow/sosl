#!/bin/bash
# SOSL — Stack-specific guards: Python

run_stack_guards() {
  local target_dir="$1"

  # ── Test file deletion (Python patterns) ─────────────────────────────────
  local deleted_tests
  deleted_tests=$(git -C "$target_dir" diff --name-only --diff-filter=D | grep -E '(test_.*\.py|_test\.py|tests/)' || true)
  if [[ -n "$deleted_tests" ]]; then
    echo "Test files deleted: $deleted_tests"
    return 1
  fi

  # ── No new suppression comments (# noqa, # type: ignore) ────────────────
  local suppression_added
  suppression_added=$(git -C "$target_dir" diff HEAD -- '*.py' 2>/dev/null | python3 -c "
import sys
patterns = ['# noqa', '# type: ignore', '# type:ignore']
added = removed = 0
for line in sys.stdin:
    line = line.rstrip()
    if any(p in line for p in patterns):
        if line.startswith('+') and not line.startswith('+++'):
            added += 1
        elif line.startswith('-') and not line.startswith('---'):
            removed += 1
print(max(0, added - removed))
" 2>/dev/null || echo 0)
  if [[ "$suppression_added" -gt 0 ]]; then
    echo "New suppression comments added ($suppression_added net new: noqa, type: ignore)"
    return 1
  fi

  # ── No new dependencies in pyproject.toml or requirements.txt ────────────
  local new_deps
  new_deps=$(git -C "$target_dir" diff HEAD -- 'pyproject.toml' 'requirements*.txt' 'setup.py' 'setup.cfg' 2>/dev/null | python3 -c "
import sys, re
added = 0
in_deps = False
for line in sys.stdin:
    line = line.rstrip()
    # pyproject.toml [project.dependencies] or [tool.poetry.dependencies]
    if re.match(r'^\+\s*\[.*dependencies', line, re.IGNORECASE):
        in_deps = True
    elif line.startswith('+') and in_deps:
        # New dependency line (not empty, not section header)
        stripped = line[1:].strip()
        if stripped and not stripped.startswith('[') and not stripped.startswith('#'):
            added += 1
    elif line.startswith('+') and line[1:].strip().startswith('['):
        in_deps = False
    # requirements.txt: any added non-comment line
    if line.startswith('+') and not line.startswith('+++'):
        stripped = line[1:].strip()
        if stripped and not stripped.startswith('#') and '==' in stripped or '>=' in stripped:
            added += 1
print(added)
" 2>/dev/null || echo 0)
  new_deps=$(echo "$new_deps" | tr -d '[:space:]')
  if [[ -n "$new_deps" ]] && [[ "$new_deps" -gt 0 ]]; then
    echo "New dependencies added ($new_deps new in pyproject.toml/requirements.txt)"
    return 1
  fi

  return 0
}
