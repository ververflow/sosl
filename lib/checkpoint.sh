#!/bin/bash
# SOSL — State persistence (checkpoint + resume)

# Save checkpoint
# Usage: save_checkpoint /target run-id 5 67.2 2.15 sosl/perf/20260408 perf
save_checkpoint() {
  local target_dir="$1" run_id="$2" iteration="$3" baseline="$4" total_cost="$5" branch="$6" domain="${7:-}"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$run_id" "$iteration" "$baseline" "$total_cost" "$branch" "$domain" <<'PYEOF'
import json, datetime, os, sys

py_dir, run_id, iteration, baseline, total_cost, branch, domain = sys.argv[1:8]

def num(x, cast, default):
    # Tolerant: the EXIT trap can call this before a value exists (e.g. a
    # failed baseline measurement leaves BASELINE empty).
    try:
        return cast(x)
    except (TypeError, ValueError):
        return default

sosl_dir = os.path.join(py_dir, '.sosl')
os.makedirs(sosl_dir, exist_ok=True)

search_mode = os.environ.get('SOSL_SEARCH_MODE', 'linear')

data = {
    'run_id': run_id,
    'domain': domain,
    'iteration': num(iteration, int, 0),
    'baseline': num(baseline, float, 0.0),
    'total_cost_usd': num(total_cost, float, 0.0),
    'branch': branch,
    'search_mode': search_mode,
    'updated_at': datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
}

checkpoint_path = os.path.join(sosl_dir, 'checkpoint.json')
tmp_path = checkpoint_path + '.tmp'
with open(tmp_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
os.replace(tmp_path, checkpoint_path)
PYEOF
}

# Load checkpoint for a domain
# Usage: load_checkpoint /target performance → prints JSON or empty
load_checkpoint() {
  local target_dir="$1" domain="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$domain" <<'PYEOF' 2>/dev/null
import json, re, sys, os

py_dir, domain = sys.argv[1], sys.argv[2]

checkpoint_path = os.path.join(py_dir, '.sosl', 'checkpoint.json')
if not os.path.exists(checkpoint_path):
    sys.exit(0)

with open(checkpoint_path, encoding='utf-8') as f:
    d = json.load(f)

# Exact domain match; substring matching would let "code" resume a
# "code-quality" checkpoint. Legacy checkpoints lack the domain field —
# fall back to matching run_id as "<domain>-YYYYMMDD-HHMMSS".
if d.get('domain'):
    if d['domain'] == domain:
        print(json.dumps(d))
elif re.fullmatch(re.escape(domain) + r'-\d{8}-\d{6}', d.get('run_id', '')):
    print(json.dumps(d))
PYEOF
}

# Clear checkpoint
# Usage: clear_checkpoint /target run-id
clear_checkpoint() {
  local target_dir="$1" run_id="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" <<'PYEOF' 2>/dev/null || true
import os, sys
p = os.path.join(sys.argv[1], '.sosl', 'checkpoint.json')
if os.path.exists(p): os.remove(p)
PYEOF
}
