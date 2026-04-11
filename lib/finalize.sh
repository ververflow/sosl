#!/bin/bash
# SOSL -- Branch finalization: group commits into independent cherry-pickable changesets
# Inspired by pi-autoresearch's autoresearch-finalize skill.
# Commits sharing files are grouped together (union-find). Each group gets its own branch.

# Finalize a SOSL branch into independent changesets
# Usage: finalize_branch /target "sosl/perf/20260411" /worktree
# Creates: sosl/perf/20260411/final-1, final-2, ... branches
# Writes: .sosl/FINALIZED.md report
finalize_branch() {
  local target_dir="$1"
  local branch="$2"
  local work_dir="$3"
  local py_dir
  py_dir=$(to_py_path "$target_dir")
  local py_work
  py_work=$(to_py_path "$work_dir")

  # Get commits on the SOSL branch (not on main), oldest first
  local commits
  commits=$(git -C "$work_dir" log main.."$branch" --pretty=format:"%H" --reverse 2>/dev/null)

  if [[ -z "$commits" ]]; then
    log_warn "No commits to finalize on $branch"
    return 0
  fi

  local commit_count
  commit_count=$(echo "$commits" | wc -l | tr -d '[:space:]')
  log "Finalizing $commit_count commits on $branch..."

  # Group commits by shared files using union-find (Python does all git calls)
  local groups_json
  groups_json=$(python3 - "$py_work" "$branch" <<'PYEOF'
import subprocess, sys, json
from collections import defaultdict

work_dir, branch = sys.argv[1], sys.argv[2]

# Get commit hashes (oldest first)
result = subprocess.run(
    ['git', '-C', work_dir, 'log', f'main..{branch}', '--pretty=format:%H', '--reverse'],
    capture_output=True, text=True)
hashes = [h.strip() for h in result.stdout.strip().splitlines() if h.strip()]

if not hashes:
    print('[]')
    sys.exit(0)

# For each commit, get message and files
commits = []
for h in hashes:
    msg = subprocess.run(
        ['git', '-C', work_dir, 'log', '-1', '--pretty=format:%s', h],
        capture_output=True, text=True).stdout.strip()
    files_out = subprocess.run(
        ['git', '-C', work_dir, 'diff-tree', '--no-commit-id', '--name-only', '-r', h],
        capture_output=True, text=True).stdout.strip()
    files = [f for f in files_out.splitlines() if f.strip()]
    commits.append({'hash': h, 'message': msg, 'files': files})

# Union-Find
parent = {c['hash']: c['hash'] for c in commits}

def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x

def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb:
        parent[ra] = rb

# Group commits that share files
file_owner = {}
for c in commits:
    for f in c['files']:
        if f in file_owner:
            union(c['hash'], file_owner[f])
        else:
            file_owner[f] = c['hash']

# Collect groups (preserve commit order)
groups = defaultdict(list)
for c in commits:
    groups[find(c['hash'])].append(c)

result = []
for group_commits in groups.values():
    all_files = set()
    for c in group_commits:
        all_files.update(c['files'])
    result.append({
        'commits': [{'hash': c['hash'], 'message': c['message']} for c in group_commits],
        'files': sorted(all_files)
    })

print(json.dumps(result))
PYEOF
)

  if [[ -z "$groups_json" ]] || [[ "$groups_json" == "[]" ]]; then
    log_warn "Could not group commits"
    return 0
  fi

  local group_count
  group_count=$(echo "$groups_json" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))")

  if [[ "$group_count" -eq 1 ]]; then
    log "All commits share files -- single changeset (no split needed)"
  else
    log_ok "Grouped into $group_count independent changesets"
  fi

  # Save groups to temp file for the next Python script
  local groups_file
  groups_file=$(mktemp)
  echo "$groups_json" > "$groups_file"

  # Create finalized branches
  local finalized_branches
  finalized_branches=$(python3 - "$py_work" "$branch" "$groups_file" <<'PYEOF'
import json, sys, subprocess, os

work_dir = sys.argv[1]
branch = sys.argv[2]
groups_file = sys.argv[3]

with open(groups_file) as f:
    groups = json.load(f)

results = []
for i, group in enumerate(groups, 1):
    final_branch = f'{branch}-final-{i}'
    hashes = [c['hash'] for c in group['commits']]

    # Create branch from main
    subprocess.run(['git', '-C', work_dir, 'branch', '-D', final_branch],
                   capture_output=True)
    subprocess.run(['git', '-C', work_dir, 'branch', final_branch, 'main'],
                   capture_output=True, check=True)

    # Cherry-pick commits onto the branch
    original_branch = subprocess.run(
        ['git', '-C', work_dir, 'branch', '--show-current'],
        capture_output=True, text=True).stdout.strip()

    subprocess.run(['git', '-C', work_dir, 'checkout', final_branch],
                   capture_output=True, check=True)

    success = True
    for h in hashes:
        r = subprocess.run(['git', '-C', work_dir, 'cherry-pick', h],
                           capture_output=True, text=True)
        if r.returncode != 0:
            subprocess.run(['git', '-C', work_dir, 'cherry-pick', '--abort'],
                           capture_output=True)
            success = False
            break

    # Return to original branch
    subprocess.run(['git', '-C', work_dir, 'checkout', original_branch],
                   capture_output=True)

    results.append({
        'group': i,
        'branch': final_branch,
        'commits': group['commits'],
        'files': group['files'],
        'success': success
    })

print(json.dumps(results))
PYEOF
)
  rm -f "$groups_file"

  # Save results to temp for report generation
  local results_file
  results_file=$(mktemp)
  echo "$finalized_branches" > "$results_file"

  # Also write JSON for programmatic access
  cp "$results_file" "$target_dir/.sosl/finalization.json"

  # Write report
  local report_path="$target_dir/.sosl/FINALIZED.md"
  PYTHONIOENCODING=utf-8 python3 - "$branch" "$results_file" <<'PYEOF' > "$report_path"
import json, sys

branch = sys.argv[1]
with open(sys.argv[2]) as f:
    results = json.load(f)

lines = [f'# Branch Finalization Report\n']
lines.append(f'Original branch: {branch}')
lines.append(f'Independent changesets: {len(results)}\n')

for r in results:
    status = 'OK' if r['success'] else 'CONFLICT (cherry-pick failed)'
    lines.append(f'## Changeset {r["group"]}: {r["branch"]}')
    lines.append(f'Status: {status}')
    lines.append(f'Commits: {len(r["commits"])}')
    lines.append(f'Files: {", ".join(r["files"])}')
    lines.append('')
    for c in r['commits']:
        lines.append(f'- `{c["hash"][:7]}` {c["message"]}')
    lines.append('')
    if r['success']:
        lines.append(f'```bash')
        lines.append(f'git merge {r["branch"]}')
        lines.append(f'```')
    lines.append('')

print('\n'.join(lines))
PYEOF

  log_ok "Finalization report: $report_path"

  # Log each group
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for r in json.load(f):
        status = 'ok' if r['success'] else 'CONFLICT'
        print(f'  final-{r[\"group\"]}: {len(r[\"commits\"])} commits, {len(r[\"files\"])} files [{status}]')
" "$results_file" 2>/dev/null

  rm -f "$results_file"
}
