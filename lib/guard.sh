#!/bin/bash
# SOSL — Guard rail framework
# Guards run in order: universal (fast, cheap) → domain-specific (slower, heavier)
# Any failure = immediate revert, no measurement needed

# Run domain-specific guard + universal guards
# Usage: run_guards /path/to/guard.sh /path/to/target
# Exit 0 = all pass, exit 1 = guard violation (reason on stdout)
run_guards() {
  local guard_script="$1"
  local target_dir="$2"

  # ── Universal guards (fast, no build tools) ───────────────────────────────

  # 1. Must have actual changes (not just whitespace)
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

  # 3. No new eslint-disable / ts-ignore / ts-expect-error comments
  local suppression_added
  suppression_added=$(git -C "$target_dir" diff HEAD -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null | python3 -c "
import sys
patterns = ['eslint-disable', '@ts-ignore', '@ts-expect-error']
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
    echo "New suppression comments added ($suppression_added net new: eslint-disable, ts-ignore, ts-expect-error)"
    return 1
  fi

  # 4. No new dependencies added to package.json
  local new_pkgs
  new_pkgs=$(git -C "$target_dir" diff HEAD -- '*/package.json' 'package.json' 2>/dev/null | grep -cE '^\+\s+"[^"]+"\s*:\s*"[\^~]' || true)
  new_pkgs=$(echo "$new_pkgs" | tr -d '[:space:]')
  if [[ -n "$new_pkgs" ]] && [[ "$new_pkgs" -gt 0 ]]; then
    echo "New packages added to package.json ($new_pkgs new dependencies)"
    return 1
  fi

  # 5. Dangling import check — all @/ imports must resolve to files
  # This catches Claude's most common failure mode: referencing files it never created
  local frontend_src=""
  [[ -d "$target_dir/frontend/src" ]] && frontend_src="$target_dir/frontend/src"
  [[ -d "$target_dir/src" ]] && frontend_src="$target_dir/src"

  if [[ -n "$frontend_src" ]]; then
    local broken_imports
    broken_imports=$(python3 -c "
import re, os, glob

src_dir = '$frontend_src'
# Determine alias base: @/ maps to src/ (inside frontend/) or src/ (root)
alias_base = src_dir

broken = []
for ext in ('*.ts', '*.tsx'):
    for fpath in glob.glob(os.path.join(src_dir, '**', ext), recursive=True):
        try:
            with open(fpath, encoding='utf-8') as f:
                content = f.read()
        except:
            continue
        for m in re.finditer(r'from\s+[\"\\']@/([^\"\\'\s]+)[\"\\']', content):
            import_path = m.group(1)
            resolved = os.path.join(alias_base, import_path)
            candidates = [
                resolved + '.ts', resolved + '.tsx',
                resolved + '.js', resolved + '.jsx',
                os.path.join(resolved, 'index.ts'),
                os.path.join(resolved, 'index.tsx'),
                resolved
            ]
            if not any(os.path.exists(c) for c in candidates):
                broken.append(f'{os.path.relpath(fpath, src_dir)}: @/{import_path}')

if broken:
    for b in broken[:10]:
        print(b)
" 2>/dev/null)

    if [[ -n "$broken_imports" ]]; then
      echo "Dangling imports — files referenced but don't exist:"
      echo "$broken_imports"
      return 1
    fi
  fi

  # ── Domain-specific guard (heavier: tsc, build, tests) ────────────────────
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
