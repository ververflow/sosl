#!/bin/bash
# SOSL — Strategy mode detection (DRAFT / DEBUG / IMPROVE)
# Inspired by AIDE's three-mode operator: different situations need different prompts.
#
# DRAFT:   Start fresh with a new approach (stagnation, or multiple guard fails)
# DEBUG:   Fix a specific guard failure from the previous iteration
# IMPROVE: Incremental refinement of working code (normal case)

# Detect which mode to use for the next iteration
# Reads recent experiments from JSONL to decide
# Usage: detect_mode /target 3 → prints "IMPROVE" (or "DEBUG" or "DRAFT")
detect_mode() {
  local target_dir="$1"
  local stagnation_count="${2:-0}"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$stagnation_count" <<'PYEOF'
import json, os, sys

py_dir = sys.argv[1]
stagnation = int(sys.argv[2])

jsonl_path = os.path.join(py_dir, '.sosl', 'experiments.jsonl')

# Default: IMPROVE (normal incremental optimization)
if not os.path.exists(jsonl_path):
    print('IMPROVE')
    sys.exit(0)

with open(jsonl_path, encoding='utf-8') as f:
    entries = [json.loads(line.strip()) for line in f if line.strip()]

if not entries:
    print('IMPROVE')
    sys.exit(0)

last = entries[-1]
recent_3 = entries[-3:] if len(entries) >= 3 else entries

# Rule 1: High stagnation overrides everything → DRAFT
# (We've been stuck too long, need a fundamentally different approach)
if stagnation >= 4:
    print('DRAFT')
    sys.exit(0)

# Rule 2: If last iteration was a guard failure → DEBUG
# (Try to fix the approach rather than abandoning it)
if 'Guard fail' in last.get('summary', ''):
    # But if last 3 were ALL guard fails → DRAFT (approach is broken, try something new)
    guard_fails = sum(1 for e in recent_3 if 'Guard fail' in e.get('summary', ''))
    if guard_fails >= 3:
        print('DRAFT')
    else:
        print('DEBUG')
    sys.exit(0)

# Rule 3: If last iteration was a Claude error → IMPROVE (just retry normally)
if 'Claude error' in last.get('summary', ''):
    print('IMPROVE')
    sys.exit(0)

# Rule 4: If last iteration had no changes → DRAFT
# (Claude couldn't find anything to improve with current approach)
if 'No changes' in last.get('summary', ''):
    # If 2+ consecutive "No changes" → DRAFT
    no_change_count = sum(1 for e in recent_3 if 'No changes' in e.get('summary', ''))
    if no_change_count >= 2:
        print('DRAFT')
    else:
        print('IMPROVE')
    sys.exit(0)

# Default: IMPROVE
print('IMPROVE')
PYEOF
}

# Get the last guard error message (for DEBUG mode prompting)
# Usage: get_last_guard_error /target → prints the error or empty string
get_last_guard_error() {
  local target_dir="$1"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" <<'PYEOF'
import json, os, sys

py_dir = sys.argv[1]
jsonl_path = os.path.join(py_dir, '.sosl', 'experiments.jsonl')

if not os.path.exists(jsonl_path):
    sys.exit(0)

with open(jsonl_path, encoding='utf-8') as f:
    entries = [json.loads(line.strip()) for line in f if line.strip()]

# Find the last guard failure
for entry in reversed(entries):
    summary = entry.get('summary', '')
    if summary.startswith('Guard fail:'):
        # Strip the prefix, return the error
        print(summary[len('Guard fail:'):].strip()[:300])
        break
PYEOF
}

# Generate mode-specific prompt guidance
# Usage: get_mode_guidance "DEBUG" "tsc error in Button.tsx" → prints guidance text
get_mode_guidance() {
  local mode="$1"
  local guard_error="${2:-}"

  case "$mode" in
    DRAFT)
      cat <<'EOF'
## Strategy Mode: DRAFT (Fresh Approach)
Previous approaches have stalled or repeatedly failed. You must try a COMPLETELY
DIFFERENT strategy than what was attempted before. Review the session history below
to understand what has been tried and what failed — then take a new direction.

Rules for DRAFT mode:
- Do NOT retry any approach listed under "Dead Ends"
- Do NOT make the same type of change as recent reverted attempts
- Think about what CATEGORY of optimization hasn't been tried yet
- A fresh approach means a different file, different technique, or different target
EOF
      ;;
    DEBUG)
      cat <<EOF
## Strategy Mode: DEBUG (Fix Previous Failure)
The previous iteration's change was reverted because a guard check failed.
Your job is to fix the SPECIFIC issue that caused the failure, not to try
something entirely different.

The guard failure was:
> ${guard_error:-Unknown guard error}

Rules for DEBUG mode:
- Understand WHY the guard failed before making changes
- Make the MINIMAL fix needed to pass the guard
- Keep the optimization intent from the previous attempt
- If the guard error mentions missing imports/references, add them
- If the guard error mentions type errors, fix the types
EOF
      ;;
    IMPROVE|*)
      cat <<'EOF'
## Strategy Mode: IMPROVE (Incremental Refinement)
Make one targeted improvement to the codebase. Build on what has worked before
(see session history). Focus on the highest-impact change available.

Rules for IMPROVE mode:
- Make exactly ONE targeted change
- Prefer approaches similar to what has worked (see "Key Wins")
- Avoid approaches that have failed (see "Dead Ends")
EOF
      ;;
  esac
}
