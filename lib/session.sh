#!/bin/bash
# SOSL — Living session document
# Tracks strategies tried, dead ends, and key wins across iterations.
# Enables Claude to learn from previous attempts within a single run.

# Initialize session document at run start
# Usage: session_init /target "code-quality" 983
session_init() {
  local target_dir="$1"
  local domain="$2"
  local baseline="$3"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$domain" "$baseline" <<'PYEOF'
import os, sys, datetime

py_dir, domain, baseline = sys.argv[1], sys.argv[2], sys.argv[3]
sosl_dir = os.path.join(py_dir, '.sosl')
os.makedirs(sosl_dir, exist_ok=True)

session_path = os.path.join(sosl_dir, 'session.md')

now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M UTC')

with open(session_path, 'w', encoding='utf-8') as f:
    f.write(f'# SOSL Session: {domain}\n')
    f.write(f'Started: {now}\n')
    f.write(f'Baseline: {baseline}\n\n')
    f.write('## Strategies Tried\n\n')
    f.write('## Dead Ends\n\n')
    f.write('## Key Wins\n\n')
PYEOF
}

# Update session document after each iteration
# Usage: session_update /target 1 "IMPROVE" "committed" 983 984 "Removed unused imports" ""
session_update() {
  local target_dir="$1"
  local iteration="$2"
  local mode="$3"         # DRAFT / DEBUG / IMPROVE
  local result="$4"       # committed / reverted / guard_fail / error
  local score_before="$5"
  local score_after="$6"
  local strategy_summary="$7"
  local guard_error="${8:-}"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" "$iteration" "$mode" "$result" "$score_before" "$score_after" "$strategy_summary" "$guard_error" <<'PYEOF'
import os, sys, re

py_dir = sys.argv[1]
iteration = int(sys.argv[2])
mode = sys.argv[3]
result = sys.argv[4]
score_before = sys.argv[5]
score_after = sys.argv[6]
strategy = sys.argv[7][:200]  # Cap length
guard_error = sys.argv[8][:200] if len(sys.argv) > 8 else ''

# Sanitize strategy text (comes from Claude's output — untrusted)
strategy = re.sub(r'[^\w\s\.\-\>\:\(\)\/,\'\"]', '', strategy)
guard_error = re.sub(r'[^\w\s\.\-\>\:\(\)\/,]', '', guard_error)

session_path = os.path.join(py_dir, '.sosl', 'session.md')
if not os.path.exists(session_path):
    sys.exit(0)

with open(session_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Build the strategy entry
score_str = f'{score_before} -> {score_after}' if score_after and score_after != 'null' else f'{score_before} -> ?'
result_tag = {
    'committed': 'COMMITTED',
    'reverted': 'REVERTED',
    'guard_fail': 'GUARD_FAIL',
    'error': 'ERROR'
}.get(result, result.upper())

entry = f'- [iter {iteration}, {mode}, {result_tag}] {strategy} ({score_str})\n'

# Insert into "Strategies Tried" section
strategies_marker = '## Strategies Tried\n'
if strategies_marker in content:
    idx = content.index(strategies_marker) + len(strategies_marker)
    # Find the next section or end
    next_section = content.find('\n## ', idx)
    if next_section == -1:
        next_section = len(content)
    # Insert before the next section (after existing entries)
    insert_at = next_section
    # Find last non-empty line before next section
    content = content[:insert_at].rstrip() + '\n' + entry + '\n' + content[insert_at:].lstrip('\n')

# Update Dead Ends section if guard_fail or repeated reverts
dead_ends_marker = '## Dead Ends\n'
if result == 'guard_fail' and guard_error and dead_ends_marker in content:
    dead_entry = f'- {strategy} -> {guard_error}\n'
    idx = content.index(dead_ends_marker) + len(dead_ends_marker)
    next_section = content.find('\n## ', idx)
    if next_section == -1:
        next_section = len(content)
    # Check if this dead end is already recorded (fuzzy: first 50 chars of strategy)
    existing_section = content[idx:next_section]
    if strategy[:50] not in existing_section:
        content = content[:next_section].rstrip() + '\n' + dead_entry + '\n' + content[next_section:].lstrip('\n')

# Update Key Wins section if committed
key_wins_marker = '## Key Wins\n'
if result == 'committed' and key_wins_marker in content:
    win_entry = f'- {strategy} ({score_str})\n'
    idx = content.index(key_wins_marker) + len(key_wins_marker)
    next_section = content.find('\n## ', idx)
    if next_section == -1:
        next_section = len(content)
    content = content[:next_section].rstrip() + '\n' + win_entry + '\n' + content[next_section:].lstrip('\n')

with open(session_path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF
}

# Get session context for prompt injection
# Returns a compact summary: recent strategies + dead ends + wins
# Usage: session_get /target → prints formatted context
session_get() {
  local target_dir="$1"
  local py_dir
  py_dir=$(to_py_path "$target_dir")

  python3 - "$py_dir" <<'PYEOF'
import os, sys

py_dir = sys.argv[1]
session_path = os.path.join(py_dir, '.sosl', 'session.md')

if not os.path.exists(session_path):
    print('No session history yet.')
    sys.exit(0)

with open(session_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Extract sections
def extract_section(content, header):
    marker = f'## {header}\n'
    if marker not in content:
        return ''
    start = content.index(marker) + len(marker)
    end = content.find('\n## ', start)
    if end == -1:
        end = len(content)
    section = content[start:end].strip()
    return section

strategies = extract_section(content, 'Strategies Tried')
dead_ends = extract_section(content, 'Dead Ends')
key_wins = extract_section(content, 'Key Wins')

output = []

# Last 5 strategies (most recent context)
if strategies:
    lines = [l for l in strategies.splitlines() if l.strip().startswith('-')]
    recent = lines[-5:] if len(lines) > 5 else lines
    output.append('Recent strategies:')
    for line in recent:
        output.append(line)

# All dead ends (critical — must not retry)
if dead_ends:
    lines = [l for l in dead_ends.splitlines() if l.strip().startswith('-')]
    if lines:
        output.append('')
        output.append('DEAD ENDS — do NOT retry these approaches:')
        for line in lines[-10:]:  # Cap at 10
            output.append(line)

# Last 3 wins (what works)
if key_wins:
    lines = [l for l in key_wins.splitlines() if l.strip().startswith('-')]
    if lines:
        recent_wins = lines[-3:] if len(lines) > 3 else lines
        output.append('')
        output.append('What has worked:')
        for line in recent_wins:
            output.append(line)

if output:
    print('\n'.join(output))
else:
    print('No session history yet.')
PYEOF
}
