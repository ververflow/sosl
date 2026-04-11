#!/bin/bash
# SOSL — Guard rail framework
# Three layers: universal (any stack) → stack-specific (auto-detected) → domain-specific
# Any failure = immediate revert, no measurement needed

# ── Stack detection ────────────────────────────────────────────────────────
# Auto-detect the project's tech stack from marker files.
# Usage: detect_stack /path/to/project → prints "node", "python", "rust", "go", or "unknown"
detect_stack() {
  local dir="$1"
  # Check subdirectories too (monorepo: frontend/package.json)
  [[ -f "$dir/package.json" ]] || [[ -f "$dir/frontend/package.json" ]] && echo "node" && return
  [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]] || [[ -f "$dir/requirements.txt" ]] && echo "python" && return
  [[ -f "$dir/Cargo.toml" ]] && echo "rust" && return
  [[ -f "$dir/go.mod" ]] && echo "go" && return
  echo "unknown"
}

# Run all guard layers in order
# Usage: run_guards /path/to/guard.sh /path/to/target
# Exit 0 = all pass, exit 1 = guard violation (reason on stdout)
run_guards() {
  local guard_script="$1"
  local target_dir="$2"

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

  local detected_stack
  detected_stack=$(detect_stack "$target_dir")
  local guard_dir
  guard_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guards"

  if [[ -f "$guard_dir/${detected_stack}.sh" ]]; then
    source "$guard_dir/${detected_stack}.sh"
    local stack_output
    stack_output=$(run_stack_guards "$target_dir" 2>&1)
    local stack_exit=$?
    if [[ $stack_exit -ne 0 ]]; then
      echo "$stack_output"
      return 1
    fi
  fi

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
