#!/bin/bash
# SOSL — State persistence (checkpoint + resume)

# Save checkpoint
# Usage: save_checkpoint /target run-id 5 67.2 2.15 sosl/perf/20260408
save_checkpoint() {
  local target_dir="$1" run_id="$2" iteration="$3" baseline="$4" total_cost="$5" branch="$6"
  local checkpoint_dir="$target_dir/.sosl"
  mkdir -p "$checkpoint_dir"

  python3 -c "
import json
data = {
    'run_id': '$run_id',
    'iteration': int($iteration),
    'baseline': float($baseline),
    'total_cost_usd': float($total_cost),
    'branch': '$branch',
    'updated_at': __import__('datetime').datetime.utcnow().isoformat() + 'Z'
}
with open('$checkpoint_dir/checkpoint.json', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Load checkpoint for a domain
# Usage: load_checkpoint /target performance → prints JSON or empty
load_checkpoint() {
  local target_dir="$1" domain="$2"
  local checkpoint_file="$target_dir/.sosl/checkpoint.json"

  if [[ ! -f "$checkpoint_file" ]]; then
    echo ""
    return
  fi

  # Check if checkpoint matches this domain
  local matches
  matches=$(python3 -c "
import json
with open('$checkpoint_file') as f:
    d = json.load(f)
print('yes' if '$domain' in d.get('run_id', '') else 'no')
" 2>/dev/null || echo "no")

  if [[ "$matches" == "yes" ]]; then
    cat "$checkpoint_file"
  else
    echo ""
  fi
}

# Clear checkpoint
# Usage: clear_checkpoint /target run-id
clear_checkpoint() {
  local target_dir="$1" run_id="$2"
  local checkpoint_file="$target_dir/.sosl/checkpoint.json"
  if [[ -f "$checkpoint_file" ]]; then
    rm "$checkpoint_file"
  fi
}
