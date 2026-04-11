#!/bin/bash
# SOSL — Tree search data structure and operations
# Enables greedy best-first search over the solution space.
# Each successful commit becomes a node; the frontier is all expandable leaves.
# Inspired by AIDE's tree search algorithm (arXiv 2502.13138).

# ── Tree initialization ───────────────────────────────────────────────────────
# Creates tree.json with a root node from the baseline measurement.
# Usage: tree_init /target "sosl/perf/20260411" 62.3 0.7
tree_init() {
  local target_dir="$1"
  local root_branch="$2"
  local baseline="$3"
  local noise_floor="$4"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$root_branch" "$baseline" "$noise_floor" <<'PYEOF'
import json, os, sys, datetime, tempfile

py_dir, root_branch = sys.argv[1], sys.argv[2]
baseline, noise_floor = float(sys.argv[3]), float(sys.argv[4])

sosl_dir = os.path.join(py_dir, '.sosl')
os.makedirs(sosl_dir, exist_ok=True)

tree = {
    "version": 1,
    "root_branch": root_branch,
    "global_iteration": 0,
    "total_cost_usd": 0.0,
    "nodes": {
        "root": {
            "id": "root",
            "parent_id": None,
            "branch": root_branch,
            "score": baseline,
            "noise_floor": noise_floor,
            "depth": 0,
            "children": [],
            "visits": 0,
            "status": "leaf",
            "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
        }
    },
    "failed_attempts": []
}

# Atomic write: write to temp file, then rename
tree_path = os.path.join(sosl_dir, 'tree.json')
fd, tmp_path = tempfile.mkstemp(dir=sosl_dir, suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(tree, f, indent=2)
    os.replace(tmp_path, tree_path)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF
}

# ── Atomic save ───────────────────────────────────────────────────────────────
# Writes tree JSON from stdin to tree.json atomically.
# Usage: echo "$tree_json" | tree_save /target
tree_save() {
  local target_dir="$1"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" <<'PYEOF'
import json, os, sys, tempfile

py_dir = sys.argv[1]
sosl_dir = os.path.join(py_dir, '.sosl')
tree_path = os.path.join(sosl_dir, 'tree.json')

data = json.loads(sys.stdin.read())

fd, tmp_path = tempfile.mkstemp(dir=sosl_dir, suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
    os.replace(tmp_path, tree_path)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF
}

# ── Load tree ─────────────────────────────────────────────────────────────────
# Outputs tree.json contents to stdout.
# Usage: tree_json=$(tree_load /target)
tree_load() {
  local target_dir="$1"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 -c "
import json, sys, os
tree_path = os.path.join(sys.argv[1], '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    print(f.read())
" "$py_dir"
}

# ── Generate node ID ──────────────────────────────────────────────────────────
# Short random ID: "n" + 4 hex chars (e.g., "na3f1").
# Usage: new_id=$(tree_generate_id)
tree_generate_id() {
  python3 -c "import secrets; print('n' + secrets.token_hex(2))"
}

# ── Select best node ──────────────────────────────────────────────────────────
# Greedy best-first: pick highest-scoring expandable node.
# Outputs JSON of selected node, or empty string if frontier is exhausted.
# Usage: node_json=$(tree_select_node /target 3 5)
tree_select_node() {
  local target_dir="$1"
  local max_children="${2:-3}"
  local max_depth="${3:-5}"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$max_children" "$max_depth" <<'PYEOF'
import json, sys, os

py_dir = sys.argv[1]
max_children, max_depth = int(sys.argv[2]), int(sys.argv[3])

tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

candidates = []
for node in tree["nodes"].values():
    if node["depth"] >= max_depth:
        continue
    if node["visits"] >= max_children:
        continue
    if node["status"] == "exhausted":
        continue
    candidates.append(node)

if not candidates:
    sys.exit(0)  # Empty output = no nodes available

# Sort: highest score first, break ties by shallowest depth
candidates.sort(key=lambda n: (-n["score"], n["depth"]))
print(json.dumps(candidates[0]))
PYEOF
}

# ── Add child node (successful improvement) ───────────────────────────────────
# Creates a new node in the tree after a successful commit.
# Usage: tree_add_node /target "na3f1" "root" "sosl/perf/ts/na3f1" 65.1 0.8 "IMPROVE" "Removed imports" 0.42
tree_add_node() {
  local target_dir="$1"
  local node_id="$2"
  local parent_id="$3"
  local branch="$4"
  local score="$5"
  local noise_floor="$6"
  local mode="$7"
  local strategy="$8"
  local cost="$9"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$node_id" "$parent_id" "$branch" "$score" "$noise_floor" "$mode" "$strategy" "$cost" <<'PYEOF'
import json, sys, os, re, datetime, tempfile

py_dir = sys.argv[1]
node_id, parent_id, branch = sys.argv[2], sys.argv[3], sys.argv[4]
score, noise_floor = float(sys.argv[5]), float(sys.argv[6])
mode, strategy, cost = sys.argv[7], sys.argv[8], float(sys.argv[9])

# Sanitize strategy (from Claude output)
strategy = re.sub(r'[^\w\s\.\-\>\:\(\)\/,\'\"]', '', strategy)[:200]

tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

# Add child node
tree["nodes"][node_id] = {
    "id": node_id,
    "parent_id": parent_id,
    "branch": branch,
    "score": score,
    "noise_floor": noise_floor,
    "depth": tree["nodes"][parent_id]["depth"] + 1,
    "children": [],
    "visits": 0,
    "status": "leaf",
    "mode": mode,
    "strategy": strategy,
    "cost_usd": cost,
    "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
}

# Update parent
tree["nodes"][parent_id]["children"].append(node_id)
tree["nodes"][parent_id]["visits"] += 1
if tree["nodes"][parent_id]["status"] == "leaf":
    tree["nodes"][parent_id]["status"] = "expanded"

# Update global cost
tree["total_cost_usd"] = round(tree["total_cost_usd"] + cost, 6)

# Atomic write
sosl_dir = os.path.join(py_dir, '.sosl')
fd, tmp_path = tempfile.mkstemp(dir=sosl_dir, suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(tree, f, indent=2)
    os.replace(tmp_path, tree_path)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF
}

# ── Record failed attempt ─────────────────────────────────────────────────────
# Records a failed expansion (guard fail, no improvement, error) without creating a node.
# Usage: tree_record_failure /target "root" "IMPROVE" "Minify CSS" "guard_fail" 0.30 5
tree_record_failure() {
  local target_dir="$1"
  local parent_id="$2"
  local mode="$3"
  local strategy="$4"
  local reason="$5"
  local cost="$6"
  local iteration="$7"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$parent_id" "$mode" "$strategy" "$reason" "$cost" "$iteration" <<'PYEOF'
import json, sys, os, re, tempfile

py_dir = sys.argv[1]
parent_id, mode = sys.argv[2], sys.argv[3]
strategy = re.sub(r'[^\w\s\.\-\>\:\(\)\/,\'\"]', '', sys.argv[4])[:200]
reason, cost, iteration = sys.argv[5], float(sys.argv[6]), int(sys.argv[7])

tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

# Record failure
tree["failed_attempts"].append({
    "parent_id": parent_id,
    "mode": mode,
    "strategy": strategy,
    "reason": reason,
    "cost_usd": cost,
    "iteration": iteration
})

# Increment visits on parent
tree["nodes"][parent_id]["visits"] += 1
tree["total_cost_usd"] = round(tree["total_cost_usd"] + cost, 6)

# Atomic write
sosl_dir = os.path.join(py_dir, '.sosl')
fd, tmp_path = tempfile.mkstemp(dir=sosl_dir, suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(tree, f, indent=2)
    os.replace(tmp_path, tree_path)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF
}

# ── Switch worktree to a node's branch ────────────────────────────────────────
# Checks out the target branch in the worktree. Safe: all changes must be
# committed or reverted before calling this.
# Usage: tree_switch_to_node /worktree "sosl/perf/ts/na3f1"
tree_switch_to_node() {
  local work_dir="$1"
  local target_branch="$2"

  # Clean any leftover state (should already be clean, but safety first)
  git -C "$work_dir" checkout -- . 2>/dev/null
  git -C "$work_dir" clean -fd --exclude=.sosl > /dev/null 2>&1
  git -C "$work_dir" checkout "$target_branch" 2>/dev/null
}

# ── Ancestor-scoped session context ───────────────────────────────────────────
# Returns session context scoped to a node's ancestry (root → ... → node).
# Includes: ancestor strategies, sibling failures, dead ends on this path.
# Usage: ctx=$(tree_session_get /target "na3f1")
tree_session_get() {
  local target_dir="$1"
  local node_id="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$node_id" <<'PYEOF'
import json, sys, os

py_dir, node_id = sys.argv[1], sys.argv[2]

tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

nodes = tree["nodes"]
failed = tree["failed_attempts"]

# Walk up from node to root to get ancestor path
path = []
current = node_id
while current is not None:
    if current not in nodes:
        break
    path.append(current)
    current = nodes[current].get("parent_id")
path.reverse()  # root → ... → node

output = []

# Ancestor wins (successful nodes on this path)
wins = [nodes[nid] for nid in path if nid != "root" and nodes[nid].get("strategy")]
if wins:
    output.append("Path to current node (what worked):")
    for w in wins:
        output.append(f'- [{w.get("mode", "?")}] {w["strategy"]} ({nodes.get(w["parent_id"], {}).get("score", "?")} -> {w["score"]})')

# Failed attempts on ancestors (dead ends on this path)
ancestor_ids = set(path)
path_failures = [f for f in failed if f["parent_id"] in ancestor_ids]
if path_failures:
    output.append('')
    output.append("DEAD ENDS on this path -- do NOT retry:")
    for f in path_failures[-8:]:  # Cap at 8
        output.append(f'- {f["strategy"]} -> {f["reason"]}')

# Sibling context (what other children of this node's parent tried)
parent_id = nodes[node_id]["parent_id"] if node_id in nodes else None
if parent_id and parent_id in nodes:
    siblings = [nodes[cid] for cid in nodes[parent_id].get("children", [])
                if cid != node_id and cid in nodes and nodes[cid].get("strategy")]
    if siblings:
        output.append('')
        output.append("Sibling approaches (try something DIFFERENT):")
        for s in siblings[:5]:
            status = "worked" if s["score"] > nodes[parent_id]["score"] else "didn't help"
            output.append(f'- {s["strategy"]} ({status}, score: {s["score"]})')

# Failures directly on this node (previous attempts to expand it)
node_failures = [f for f in failed if f["parent_id"] == node_id]
if node_failures:
    output.append('')
    output.append("Previous attempts from THIS node that failed:")
    for f in node_failures:
        output.append(f'- {f["strategy"]} -> {f["reason"]}')

if output:
    print('\n'.join(output))
else:
    print('No session history for this node yet.')
PYEOF
}

# ── Tree-scoped mode detection ────────────────────────────────────────────────
# Like detect_mode but scoped to a specific node's context.
# Usage: mode=$(tree_detect_mode /target "na3f1")
tree_detect_mode() {
  local target_dir="$1"
  local node_id="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$node_id" <<'PYEOF'
import json, sys, os

py_dir, node_id = sys.argv[1], sys.argv[2]

tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

nodes = tree["nodes"]
failed = tree["failed_attempts"]

# Get failures on this specific node
node_failures = [f for f in failed if f["parent_id"] == node_id]

# Rule 1: If this node has 2+ failures, need a fresh approach
if len(node_failures) >= 2:
    print('DRAFT')
    sys.exit(0)

# Rule 2: If last failure on this node was a guard fail, try DEBUG
if node_failures and node_failures[-1]["reason"] == "guard_fail":
    print('DEBUG')
    sys.exit(0)

# Rule 3: If this node is root and has no children yet, first attempt = IMPROVE
# Rule 4: Default = IMPROVE
print('IMPROVE')
PYEOF
}

# ── Get last guard error for a node ───────────────────────────────────────────
# Usage: error=$(tree_get_last_guard_error /target "root")
tree_get_last_guard_error() {
  local target_dir="$1"
  local node_id="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$node_id" <<'PYEOF'
import json, sys, os

py_dir, node_id = sys.argv[1], sys.argv[2]

tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

failures = [f for f in tree["failed_attempts"]
            if f["parent_id"] == node_id and f["reason"] == "guard_fail"]
if failures:
    print(failures[-1].get("strategy", "Unknown guard error")[:300])
PYEOF
}

# ── Best path from root to highest-scoring node ──────────────────────────────
# Outputs: "root (62.3) → n1 (65.1) → n3 (67.2)"
# Usage: tree_get_best_path /target
tree_get_best_path() {
  local target_dir="$1"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" <<'PYEOF'
import json, sys, os

py_dir = sys.argv[1]

tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

nodes = tree["nodes"]

# Find best-scoring node
best_id = max(nodes, key=lambda nid: nodes[nid]["score"])
best = nodes[best_id]

# Walk up to root
path = []
current = best_id
while current is not None:
    if current not in nodes:
        break
    path.append(current)
    current = nodes[current].get("parent_id")
path.reverse()

parts = []
for nid in path:
    n = nodes[nid]
    strategy = n.get("strategy", "baseline")[:40]
    parts.append(f'{nid} ({n["score"]}, "{strategy}")')

print(' -> '.join(parts))
PYEOF
}

# ── Get best score and branch across all nodes ────────────────────────────────
# Outputs: "67.2 sosl/perf/ts/n3"
# Usage: read best_score best_branch <<< $(tree_get_best /target)
tree_get_best() {
  local target_dir="$1"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" <<'PYEOF'
import json, sys, os

py_dir = sys.argv[1]
tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

nodes = tree["nodes"]
best_id = max(nodes, key=lambda nid: nodes[nid]["score"])
best = nodes[best_id]
print(f'{best["score"]} {best["branch"]}')
PYEOF
}

# ── Update global iteration counter ──────────────────────────────────────────
# Usage: tree_update_iteration /target 12
tree_update_iteration() {
  local target_dir="$1"
  local iteration="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$iteration" <<'PYEOF'
import json, sys, os, tempfile

py_dir, iteration = sys.argv[1], int(sys.argv[2])
tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

tree["global_iteration"] = iteration

sosl_dir = os.path.join(py_dir, '.sosl')
fd, tmp_path = tempfile.mkstemp(dir=sosl_dir, suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(tree, f, indent=2)
    os.replace(tmp_path, tree_path)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF
}

# ── Human-readable tree visualization ─────────────────────────────────────────
# Outputs ASCII tree for summary/review.
# Usage: tree_summary /target
tree_summary() {
  local target_dir="$1"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  PYTHONIOENCODING=utf-8 python3 - "$py_dir" <<'PYEOF'
import json, sys, os

py_dir = sys.argv[1]
tree_path = os.path.join(py_dir, '.sosl', 'tree.json')
with open(tree_path, encoding='utf-8') as f:
    tree = json.load(f)

nodes = tree["nodes"]
failed = tree["failed_attempts"]

# Find best node for marking
best_id = max(nodes, key=lambda nid: nodes[nid]["score"])

# Walk up from best to root for best-path marking
best_path = set()
current = best_id
while current is not None:
    best_path.add(current)
    current = nodes.get(current, {}).get("parent_id")

total_nodes = len(nodes)
total_failed = len(failed)
total_cost = tree.get("total_cost_usd", 0)
best_score = nodes[best_id]["score"]

print(f'Nodes explored: {total_nodes}')
print(f'Failed attempts: {total_failed}')
print(f'Total cost: ${total_cost:.2f}')
print(f'Best score: {best_score} (node {best_id})')
print()

# ASCII-safe tree drawing (no Unicode box chars — Windows cp1252 compat)
def render_node(nid, prefix="", is_last=True):
    if nid not in nodes:
        return
    n = nodes[nid]
    connector = "`-- " if is_last else "|-- "
    star = " *" if nid in best_path else ""
    strategy = n.get("strategy", "baseline")[:30]
    fails_on_node = sum(1 for f in failed if f["parent_id"] == nid)
    status_str = ""
    if n["status"] == "exhausted":
        status_str = " (exhausted)"
    elif fails_on_node > 0:
        status_str = f" ({fails_on_node} failed)"

    print(f'{prefix}{connector}{nid} [{n["score"]}] "{strategy}"{status_str}{star}')

    children = n.get("children", [])
    child_prefix = prefix + ("    " if is_last else "|   ")
    for i, cid in enumerate(children):
        render_node(cid, child_prefix, i == len(children) - 1)

# Render root
root = nodes["root"]
star = " *" if "root" in best_path else ""
fails_on_root = sum(1 for f in failed if f["parent_id"] == "root")
status_str = f" ({fails_on_root} failed)" if fails_on_root else ""
print(f'root [{root["score"]}] "baseline"{status_str}{star}')

children = root.get("children", [])
for i, cid in enumerate(children):
    render_node(cid, "", i == len(children) - 1)

print()
print(f'* = best path')
PYEOF
}
