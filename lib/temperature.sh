#!/bin/bash
# SOSL — Scope temperature (exploration → refinement → polishing)

# Get scope guidance text for the current iteration phase
# Usage: get_scope_guidance 3 30 → prints scope instruction text
get_scope_guidance() {
  local iter="$1"
  local max_iter="$2"

  python3 -c "
iter, max_iter = int($iter), int($max_iter)
progress = iter / max_iter if max_iter > 0 else 1.0

if progress < 0.33:
    phase = 'EXPLORATION'
    guidance = '''Phase: EXPLORATION (iterations 1-33%)
You may make larger architectural changes: restructuring imports, adding code splitting
boundaries, reorganizing component structure, introducing new optimization patterns.
Bold changes are welcome — this is the time for high-impact improvements.'''
elif progress < 0.66:
    phase = 'REFINEMENT'
    guidance = '''Phase: REFINEMENT (iterations 33-66%)
Make moderate, targeted changes. Focus on specific bottlenecks identified in earlier
iterations. No large restructuring — build on what already works. Target the weakest
remaining audit items.'''
else:
    phase = 'POLISHING'
    guidance = '''Phase: POLISHING (iterations 66-100%)
Only small, safe micro-optimizations. Attribute-level changes, minor CSS tweaks,
configuration tuning, preload hints, defer attributes. Do not restructure code.
Focus on squeezing the last few points from known bottlenecks.'''

print(guidance)
"
}
