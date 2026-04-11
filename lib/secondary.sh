#!/bin/bash
# SOSL -- Secondary metrics: cross-domain tradeoff monitoring
# Runs other domain measure.sh scripts as secondary monitors.
# Secondary metrics are informational — they warn but don't block commits.

# Measure all secondary domains (1 sample each — tradeoff monitors, not commit decisions)
# Usage: measure_secondary /sosl-dir "bundle-size,code-quality" /worktree
# Output: JSON string: {"bundle-size": 47800, "code-quality": 985}
measure_secondary() {
  local script_dir="$1"
  local domains="$2"
  local target_dir="$3"

  python3 - "$script_dir" "$domains" "$target_dir" <<'PYEOF'
import json, subprocess, sys, os

script_dir, domains_str, target_dir = sys.argv[1], sys.argv[2], sys.argv[3]
domains = [d.strip() for d in domains_str.split(',') if d.strip()]

results = {}
for domain in domains:
    measure_script = os.path.join(script_dir, 'domains', domain, 'measure.sh')
    if not os.path.exists(measure_script):
        continue
    try:
        result = subprocess.run(
            ['bash', measure_script, target_dir],
            capture_output=True, text=True, timeout=120
        )
        if result.returncode == 0 and result.stdout.strip():
            score = float(result.stdout.strip().splitlines()[-1])
            results[domain] = score
    except (subprocess.TimeoutExpired, ValueError, IndexError):
        pass  # Skip failed secondary measures silently

print(json.dumps(results))
PYEOF
}

# Compare secondary metrics before/after, detect degradations
# Usage: compare_secondary '{"bundle-size":48500}' '{"bundle-size":47800}'
# Output: JSON with change info per metric
compare_secondary() {
  local before="$1"
  local after="$2"

  python3 - "$before" "$after" <<'PYEOF'
import json, sys

before = json.loads(sys.argv[1]) if sys.argv[1] else {}
after = json.loads(sys.argv[2]) if sys.argv[2] else {}

comparison = {}
for metric in set(list(before.keys()) + list(after.keys())):
    b = before.get(metric)
    a = after.get(metric)
    if b is None or a is None:
        continue
    change = a - b
    # Higher is better for all SOSL metrics (inverted where needed)
    # So a decrease = degradation
    degraded = change < -0.5  # Small threshold to avoid noise
    comparison[metric] = {
        "before": b,
        "after": a,
        "change": round(change, 2),
        "degraded": degraded
    }

print(json.dumps(comparison))
PYEOF
}

# Check if any secondary metric degraded
# Usage: has_warnings '{"bundle-size":{"degraded":true,...}}'
# Returns: exit 0 if warnings, exit 1 if clean
has_warnings() {
  local comparison="$1"

  python3 -c "
import json, sys
comp = json.loads(sys.argv[1]) if sys.argv[1] else {}
has_warn = any(v.get('degraded', False) for v in comp.values())
sys.exit(0 if has_warn else 1)
" "$comparison"
}

# Format secondary metrics for prompt injection
# Usage: format_secondary '{"bundle-size":{"before":48500,"after":47800,...}}'
# Output: human-readable text
format_secondary() {
  local comparison="$1"

  python3 -c "
import json, sys

comp = json.loads(sys.argv[1]) if sys.argv[1] else {}
if not comp:
    print('No secondary metrics measured.')
    sys.exit(0)

lines = []
for metric, data in sorted(comp.items()):
    b, a, change = data['before'], data['after'], data['change']
    if data.get('degraded'):
        status = 'DEGRADED'
    elif change > 0.5:
        status = 'improved'
    else:
        status = 'stable'
    lines.append(f'- {metric}: {b} -> {a} (change: {change:+.1f}, {status})')

print('\n'.join(lines))
" "$comparison"
}

# Format baseline secondary metrics for initial prompt context
# Usage: format_secondary_baseline '{"bundle-size":47800,"code-quality":985}'
# Output: human-readable text
format_secondary_baseline() {
  local scores="$1"

  python3 -c "
import json, sys

scores = json.loads(sys.argv[1]) if sys.argv[1] else {}
if not scores:
    sys.exit(0)

lines = ['Secondary metric baselines (tradeoff monitors):']
for metric, score in sorted(scores.items()):
    lines.append(f'- {metric}: {score}')

print('\n'.join(lines))
" "$scores"
}
