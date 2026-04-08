#!/bin/bash
# SOSL — Statistical confidence (median, MAD)
# All math via python3 statistics module

# Calculate median and MAD from a list of values
# Usage: calculate_stats 62.3 64.1 63.0
# Output: "63.0 0.7" (median MAD)
calculate_stats() {
  python3 -c "
import statistics, sys

vals = [float(x) for x in sys.argv[1:]]
if not vals:
    print('0 0')
    sys.exit(0)

med = statistics.median(vals)
if len(vals) < 2:
    mad = 0.0
else:
    mad = statistics.median([abs(x - med) for x in vals])

print(f'{round(med, 2)} {round(mad, 2)}')
" "$@"
}

# Check if improvement is statistically significant
# Improvement must exceed max(noise_floor * 1.5, 0.5)
# Usage: is_significant 62.3 65.1 0.7 → exit 0 if significant
is_significant() {
  local old="$1" new="$2" noise="$3"
  python3 -c "
old, new, noise = float($old), float($new), float($noise)
threshold = max(noise * 1.5, 0.5)
improvement = new - old
if improvement > threshold:
    exit(0)
else:
    exit(1)
"
}
