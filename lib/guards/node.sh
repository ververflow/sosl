#!/bin/bash
# SOSL — Stack-specific guards: Node.js / TypeScript / JavaScript
# Extracted from the original universal guards in lib/guard.sh.

run_stack_guards() {
  local target_dir="$1"

  # ── Test file deletion (JS/TS patterns) ──────────────────────────────────
  local deleted_tests
  deleted_tests=$(git -C "$target_dir" diff --name-only --diff-filter=D | grep -E '(test_|\.test\.|\.spec\.|e2e/)' || true)
  if [[ -n "$deleted_tests" ]]; then
    echo "Test files deleted: $deleted_tests"
    return 1
  fi

  # ── No new eslint-disable / ts-ignore / ts-expect-error comments ─────────
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

  # ── No new dependencies added to package.json ────────────────────────────
  local new_pkgs
  new_pkgs=$(git -C "$target_dir" diff HEAD -- '*/package.json' 'package.json' 2>/dev/null | python3 -c "
import sys, re
added = 0
in_deps = False
for line in sys.stdin:
    if re.match(r'^\+\s+\"(dependencies|devDependencies|peerDependencies)\"', line):
        in_deps = True
    elif line.startswith('+') and in_deps and re.match(r'^\+\s+\"[^\"]+\"\s*:', line):
        added += 1
    elif line.startswith('+') and ('}' in line):
        in_deps = False
print(added)
" 2>/dev/null || echo 0)
  new_pkgs=$(echo "$new_pkgs" | tr -d '[:space:]')
  if [[ -n "$new_pkgs" ]] && [[ "$new_pkgs" -gt 0 ]]; then
    echo "New packages added to package.json ($new_pkgs new dependencies)"
    return 1
  fi

  # ── Dangling import check — all @/ imports must resolve to files ─────────
  local frontend_src=""
  [[ -d "$target_dir/frontend/src" ]] && frontend_src="$target_dir/frontend/src"
  [[ -d "$target_dir/src" ]] && frontend_src="$target_dir/src"

  if [[ -n "$frontend_src" ]]; then
    local broken_imports
    broken_imports=$(python3 - "$frontend_src" <<'PYEOF' 2>/dev/null
import re, os, glob, sys

src_dir = sys.argv[1]
alias_base = src_dir

broken = []
for ext in ('*.ts', '*.tsx'):
    for fpath in glob.glob(os.path.join(src_dir, '**', ext), recursive=True):
        try:
            with open(fpath, encoding='utf-8') as f:
                content = f.read()
        except:
            continue
        for m in re.finditer(r'from\s+["\']@/([^"\'\s]+)["\']', content):
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
PYEOF
)

    if [[ -n "$broken_imports" ]]; then
      echo "Dangling imports -- files referenced but don't exist:"
      echo "$broken_imports"
      return 1
    fi
  fi

  return 0
}
