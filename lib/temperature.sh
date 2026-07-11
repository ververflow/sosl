#!/bin/bash
# SOSL — Scope temperature (exploration → refinement → polishing)

# Get scope guidance text for the current iteration phase
# Usage: get_scope_guidance 3 30 → prints scope instruction text
get_scope_guidance() {
  local iter="$1"
  local max_iter="$2"

  python3 - "$iter" "$max_iter" <<'PYEOF'
import sys
iter, max_iter = int(sys.argv[1]), int(sys.argv[2])
progress = iter / max_iter if max_iter > 0 else 1.0

if progress < 0.33:
    guidance = '''Phase: EXPLORATION (iterations 1-33%)
Bold, high-impact changes are welcome now. You may attempt larger or structural
changes and try genuinely different approaches to move the metric. Favor the change
with the highest expected payoff, always within the directive's allowed scope.'''
elif progress < 0.66:
    guidance = '''Phase: REFINEMENT (iterations 33-66%)
Make moderate, targeted changes. Build on what already works (see session history)
and address the weakest remaining areas. Avoid large restructuring.'''
else:
    guidance = '''Phase: POLISHING (iterations 66-100%)
Only small, safe, low-risk changes now. Tighten and tune what already works; do not
restructure. Focus on squeezing the last gains from known weak spots.'''

print(guidance)
PYEOF
}
