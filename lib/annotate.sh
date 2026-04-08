#!/bin/bash
# SOSL — Experiment log (JSONL) + summary generation

# Append one experiment entry to the JSONL log
# Usage: append_experiment /target 0 "performance" 62.3 65.1 true 0.42 "Dynamic import"
append_experiment() {
  local target_dir="$1"
  local iteration="$2"
  local domain="$3"
  local score_before="$4"
  local score_after="${5:-null}"
  local improved="$6"
  local cost="$7"
  local summary="$8"

  # Convert Git Bash path to Windows path for Python
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  local _improved
  [[ "$improved" == "true" ]] && _improved="True" || _improved="False"

  SOSL_SUMMARY="$summary" python3 -c "
import json, datetime, os

sosl_dir = os.path.join(r'$py_dir', '.sosl')
os.makedirs(sosl_dir, exist_ok=True)

entry = {
    'ts': datetime.datetime.now(datetime.UTC).isoformat().replace('+00:00', 'Z'),
    'iter': int($iteration),
    'domain': '$domain',
    'score_before': float($score_before) if '$score_before' else None,
    'score_after': float($score_after) if '$score_after' and '$score_after' != 'null' else None,
    'improved': $_improved,
    'cost_usd': float($cost),
    'summary': os.environ.get('SOSL_SUMMARY', '')
}

jsonl_path = os.path.join(sosl_dir, 'experiments.jsonl')
with open(jsonl_path, 'a', encoding='utf-8') as f:
    f.write(json.dumps(entry) + '\n')
"
}

# Get last N experiments as formatted text (for prompt injection)
# Usage: get_recent /target 3
get_recent() {
  local target_dir="$1"
  local n="${2:-3}"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 -c "
import json, sys, os

jsonl_path = os.path.join(r'$py_dir', '.sosl', 'experiments.jsonl')
if not os.path.exists(jsonl_path):
    print('No previous experiments.')
    sys.exit(0)

with open(jsonl_path, encoding='utf-8') as f:
    lines = f.readlines()

lines = lines[-$n:]
if not lines:
    print('No previous experiments.')
else:
    for line in lines:
        e = json.loads(line.strip())
        status = 'IMPROVED' if e['improved'] else 'REVERTED'
        score_after = e['score_after'] if e['score_after'] is not None else '?'
        print(f'  [{status}] iter {e[\"iter\"]}: {e[\"score_before\"]} -> {score_after} -- {e[\"summary\"]}')
"
}

# Generate summary markdown from JSONL
# Usage: write_summary /target performance
write_summary() {
  local target_dir="$1"
  local domain="$2"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 -c "
import json, os

jsonl_path = os.path.join(r'$py_dir', '.sosl', 'experiments.jsonl')
summary_path = os.path.join(r'$py_dir', '.sosl', 'SUMMARY.md')

if not os.path.exists(jsonl_path):
    exit(0)

entries = []
with open(jsonl_path, encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line:
            entries.append(json.loads(line))

domain_entries = [e for e in entries if e['domain'] == '$domain']
improved = [e for e in domain_entries if e['improved']]
total_cost = sum(e['cost_usd'] for e in domain_entries)

with open(summary_path, 'w', encoding='utf-8') as f:
    f.write('# SOSL Run Summary: $domain\n\n')
    f.write(f'Total iterations: {len(domain_entries)}\n')
    f.write(f'Improvements: {len(improved)}\n')
    f.write(f'Total cost: \${total_cost:.2f}\n\n')
    if domain_entries:
        first = domain_entries[0]['score_before']
        last_improved = improved[-1]['score_after'] if improved else first
        f.write(f'Score: {first} -> {last_improved}\n\n')
    f.write('## Experiment Log\n\n')
    f.write('| Iter | Before | After | Result | Cost | Summary |\n')
    f.write('|------|--------|-------|--------|------|---------|\n')
    for e in domain_entries:
        status = 'OK' if e['improved'] else 'X'
        after = e['score_after'] if e['score_after'] is not None else '-'
        f.write(f'| {e[\"iter\"]} | {e[\"score_before\"]} | {after} | {status} | \${e[\"cost_usd\"]:.2f} | {e[\"summary\"]} |\n')
"
}
