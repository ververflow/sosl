#!/bin/bash
# SOSL — Guard rail framework
# Three layers: universal (any stack) → stack-specific (auto-detected) → domain-specific
# Any failure = immediate revert, no measurement needed

# ── Stack detection ────────────────────────────────────────────────────────
# Detect ALL of the project's stacks from marker files (monorepo-aware, one
# directory level deep). Returns a comma-separated list: "node,python".
# An explicit STACK env/config override wins, as escape hatch to narrow or
# force the list. Every detected stack's guards run — first-match-only would
# leave e.g. a python backend unguarded behind a frontend/package.json.
detect_stack() {
  local dir="$1"
  if [[ -n "${STACK:-}" ]]; then
    echo "$STACK"
    return
  fi
  local found=()
  if [[ -f "$dir/package.json" ]] || compgen -G "$dir/*/package.json" >/dev/null; then
    found+=("node")
  fi
  if [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]] || [[ -f "$dir/requirements.txt" ]] \
     || compgen -G "$dir/*/pyproject.toml" >/dev/null; then
    found+=("python")
  fi
  [[ -f "$dir/Cargo.toml" ]] && found+=("rust")
  [[ -f "$dir/go.mod" ]] && found+=("go")
  if [[ ${#found[@]} -eq 0 ]]; then
    echo "unknown"
  else
    (IFS=','; echo "${found[*]}")
  fi
}

# Run all guard layers in order
# Usage: run_guards /path/to/guard.sh /path/to/target
# Exit 0 = all pass, exit 1 = guard violation (reason on stdout)
run_guards() {
  local guard_script="$1"
  local target_dir="$2"

  # Make untracked files visible (with content) to every diff-based check
  # below: file count, scope, deletions, suppressions, deps. Reverted by the
  # `git reset` in git_revert_changes; committed via `git add -A`.
  # SOSL_WT_LINKS: infra symlinks SOSL planted in the worktree (node_modules,
  # .venv) — trailing-slash gitignore patterns don't match symlinks, so they
  # must be excluded here or the scope guard trips over SOSL's own plumbing.
  local _add_args=('.' ':(exclude).sosl' ':(exclude).sosl-worktrees')
  local _l
  for _l in ${SOSL_WT_LINKS:-}; do _add_args+=(":(exclude)$_l"); done
  git -C "$target_dir" add -N -- "${_add_args[@]}" 2>/dev/null || true

  # ══ Layer 1: Universal guards (any stack) ════════════════════════════════

  # 1. File count limit
  local changed_count
  changed_count=$(git -C "$target_dir" diff --name-only | wc -l | tr -d '[:space:]')
  if [[ "$changed_count" -gt 50 ]]; then
    echo "Too many files changed ($changed_count > 50)"
    return 1
  fi

  # 2. Scope enforcement — changes must be within ALLOWED_PATHS
  if [[ -n "${ALLOWED_PATHS:-}" ]]; then
    local changed_files
    changed_files=$(git -C "$target_dir" diff --name-only 2>/dev/null)
    local out_of_scope
    out_of_scope=$(SOSL_CHANGED="$changed_files" SOSL_ALLOWED="$ALLOWED_PATHS" python3 -c "
import os, fnmatch

changed = os.environ.get('SOSL_CHANGED', '').strip().splitlines()
allowed = [p.strip() for p in os.environ.get('SOSL_ALLOWED', '').split(',')]
violations = []
for path in changed:
    path = path.strip()
    if not path:
        continue
    matched = False
    for pattern in allowed:
        prefix = pattern.rstrip('*').rstrip('/')
        if fnmatch.fnmatch(path, pattern) or path.startswith(prefix + '/'):
            matched = True
            break
    if not matched:
        violations.append(path)
for v in violations[:10]:
    print(v)
" 2>/dev/null)
    if [[ -n "$out_of_scope" ]]; then
      echo "Files changed outside allowed scope ($ALLOWED_PATHS):"
      echo "$out_of_scope"
      return 1
    fi
  fi

  # 3. Deletion limit — prevent mass deletions
  local max_deletions="${MAX_NET_DELETIONS:-100}"
  local net_deletions
  net_deletions=$(git -C "$target_dir" diff --shortstat 2>/dev/null | python3 -c "
import sys, re
line = sys.stdin.read().strip()
ins = re.search(r'(\d+) insertion', line)
dels = re.search(r'(\d+) deletion', line)
insertions = int(ins.group(1)) if ins else 0
deletions = int(dels.group(1)) if dels else 0
print(max(0, deletions - insertions))
" 2>/dev/null || echo 0)
  net_deletions=$(echo "$net_deletions" | tr -d '[:space:]')
  if [[ -n "$net_deletions" ]] && [[ "$net_deletions" -gt "$max_deletions" ]]; then
    echo "Too many net deletions ($net_deletions lines > max $max_deletions)"
    return 1
  fi

  # ══ Layer 2: Stack-specific guards (auto-detected) ══════════════════════

  local detected_stacks
  detected_stacks=$(detect_stack "$target_dir")
  local guard_dir
  guard_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guards"

  local _stack _stack_list stack_output stack_exit
  IFS=',' read -ra _stack_list <<< "$detected_stacks"
  for _stack in "${_stack_list[@]}"; do
    [[ -f "$guard_dir/${_stack}.sh" ]] || continue
    # Subshell: every guards file defines run_stack_guards; isolate so the
    # same-named functions don't overwrite each other across stacks.
    stack_output=$(
      # shellcheck source=/dev/null
      source "$guard_dir/${_stack}.sh"
      run_stack_guards "$target_dir" 2>&1
    )
    stack_exit=$?
    if [[ $stack_exit -ne 0 ]]; then
      echo "[$_stack] $stack_output"
      return 1
    fi
  done

  # ══ Layer 3: Domain-specific guard (heavier: tsc, build, tests) ═════════
  # Security: run guards with a clean PATH that excludes the target's
  # node_modules/.bin to prevent a hostile repo from overriding tsc/eslint/etc.
  if [[ -f "$guard_script" ]]; then
    local clean_path
    clean_path=$(echo "$PATH" | tr ':' '\n' | grep -v "$target_dir" | grep -v "node_modules/.bin" | tr '\n' ':')
    local npm_global_bin
    npm_global_bin=$(npm root -g 2>/dev/null | sed 's|/lib/node_modules||' || true)
    [[ -n "$npm_global_bin" ]] && clean_path="$npm_global_bin/bin:$npm_global_bin:$clean_path"

    local guard_output
    guard_output=$(PATH="$clean_path" bash "$guard_script" "$target_dir" 2>&1)
    local guard_exit=$?
    if [[ $guard_exit -ne 0 ]]; then
      echo "$guard_output"
      return 1
    fi
  fi

  return 0
}
