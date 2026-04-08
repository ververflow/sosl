#!/bin/bash
# SOSL — State persistence (checkpoint + resume)

# Save checkpoint
# Usage: save_checkpoint /target run-id 5 67.2 2.15 sosl/perf/20260408
save_checkpoint() {
  local target_dir="$1" run_id="$2" iteration="$3" baseline="$4" total_cost="$5" branch="$6"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 -c "
import json, datetime, os

sosl_dir = os.path.join(r'$py_dir', '.sosl')
os.makedirs(sosl_dir, exist_ok=True)

data = {
    'run_id': '$run_id',
    'iteration': int($iteration),
    'baseline': float($baseline),
    'total_cost_usd': float($total_cost),
    'branch': '$branch',
    'updated_at': datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
}

checkpoint_path = os.path.join(sosl_dir, 'checkpoint.json')
with open(checkpoint_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
"
}

# Load checkpoint for a domain
# Usage: load_checkpoint /target performance → prints JSON or empty
load_checkpoint() {
  local target_dir="$1" domain="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 -c "
import json, sys, os

checkpoint_path = os.path.join(r'$py_dir', '.sosl', 'checkpoint.json')
if not os.path.exists(checkpoint_path):
    sys.exit(0)

with open(checkpoint_path, encoding='utf-8') as f:
    d = json.load(f)

if '$domain' in d.get('run_id', ''):
    print(json.dumps(d))
" 2>/dev/null
}

# Clear checkpoint
# Usage: clear_checkpoint /target run-id
clear_checkpoint() {
  local target_dir="$1" run_id="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 -c "
import os
p = os.path.join(r'$py_dir', '.sosl', 'checkpoint.json')
if os.path.exists(p): os.remove(p)
" 2>/dev/null || true
}
