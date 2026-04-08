#!/bin/bash
# SOSL — Shared utilities
# All JSON/math via python3 (no jq/bc dependency on Windows Git Bash)

set -eo pipefail
# Note: no -u (nounset) — this file is sourced into sosl.sh which needs
# unset vars in trap handlers. Domain scripts use -euo independently.

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ─────────────────────────────────────────────────────────────────
log()      { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] !${NC} $*"; }
log_err()  { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $*"; }
log_bold() { echo -e "${BOLD}[$(date +%H:%M:%S)]${NC} $*"; }

# Append to log file (ISO 8601 timestamps)
log_file() {
  local logfile="$1"; shift
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$logfile"
}

# ── Path conversion (Git Bash → Windows for Python) ────────────────────────
# Git Bash uses /c/Dev/... but Python on Windows needs C:\Dev\... or C:/Dev/...
to_py_path() {
  # cygpath converts Git Bash /c/Dev/... to C:/Dev/... which Python understands
  if command -v cygpath &>/dev/null; then
    cygpath -w "$1"
  else
    echo "$1"
  fi
}

# ── Sanitize output for logging (strip potential secrets) ──────────────────
# Removes lines containing common secret patterns before writing to experiment log
sanitize_for_log() {
  # Strip secrets, keep first line + error lines only, compact
  echo "$1" | grep -viE '(api_key|secret|token|password|auth|bearer|credential)' | \
    grep -E '(GUARD|error TS|Error:|FAIL|warning:)' | head -5 | \
    tr '\n' ' ' | sed 's/  */ /g'
}

# ── JSON parsing via python3 ───────────────────────────────────────────────
# Usage: echo '{"a":1}' | json_get "['a']"
json_get() {
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d$1)"
}

# ── Float math via python3 ─────────────────────────────────────────────────
# Usage: float_gt 3.5 2.1 → prints "1" or "0"
float_gt() {
  python3 - "$1" "$2" <<'PYEOF'
import sys; print('1' if float(sys.argv[1]) > float(sys.argv[2]) else '0')
PYEOF
}

# Usage: float_gte 3.5 2.1 → prints "1" or "0"
float_gte() {
  python3 - "$1" "$2" <<'PYEOF'
import sys; print('1' if float(sys.argv[1]) >= float(sys.argv[2]) else '0')
PYEOF
}

# Usage: float_add 3.5 2.1 → prints 5.6
float_add() {
  python3 - "$1" "$2" <<'PYEOF'
import sys; print(round(float(sys.argv[1]) + float(sys.argv[2]), 6))
PYEOF
}

# ── Health check ────────────────────────────────────────────────────────────
# Usage: check_url "http://localhost:3000" → exit 0 if reachable
check_url() {
  python3 - "$1" <<'PYEOF' 2>/dev/null
import urllib.request, urllib.error, sys
try:
    urllib.request.urlopen(sys.argv[1], timeout=5)
except urllib.error.HTTPError:
    pass  # Server responded (e.g., 503 auth gate) = it's running
except Exception:
    sys.exit(1)
PYEOF
}

# ── Git helpers ─────────────────────────────────────────────────────────────
git_has_changes() {
  [[ -n "$(git -C "$1" status --porcelain)" ]]
}

git_revert_changes() {
  local target="$1"
  git -C "$target" checkout -- .
  # Exclude .sosl/ from clean — it contains experiment log and checkpoints
  git -C "$target" clean -fd --exclude=.sosl > /dev/null 2>&1
}

git_commit_sosl() {
  local target="$1" domain="$2" old_score="$3" new_score="$4"
  git -C "$target" diff --name-only | xargs -r git -C "$target" add
  git -C "$target" commit -m "$(cat <<EOF
sosl($domain): $old_score → $new_score

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
}

# ── Prompt builder ──────────────────────────────────────────────────────────
# Reads directive.md and replaces placeholders with dynamic values
build_prompt() {
  local directive_file="$1"
  local current_score="$2"
  local iteration="$3"
  local max_iterations="$4"
  local recent_results="$5"
  local scope_guidance="${6:-}"
  local target_dir="$7"

  local directive
  directive=$(cat "$directive_file")

  # Replace placeholders
  directive="${directive//\{\{CURRENT_SCORE\}\}/$current_score}"
  directive="${directive//\{\{ITERATION\}\}/$iteration}"
  directive="${directive//\{\{MAX_ITERATIONS\}\}/$max_iterations}"
  directive="${directive//\{\{RECENT_RESULTS\}\}/$recent_results}"
  directive="${directive//\{\{SCOPE_GUIDANCE\}\}/$scope_guidance}"

  # Inject audit details if available (written by measure.sh)
  # Check both work dir and state dir (worktree setup splits these)
  local audit_details=""
  if [[ -f "$target_dir/.sosl/last-audit.txt" ]]; then
    audit_details=$(cat "$target_dir/.sosl/last-audit.txt")
  elif [[ -n "${SOSL_STATE_DIR:-}" ]] && [[ -f "$SOSL_STATE_DIR/last-audit.txt" ]]; then
    audit_details=$(cat "$SOSL_STATE_DIR/last-audit.txt")
  fi

  # Append working directory instruction
  cat <<EOF
$directive

## Working Directory
You are working in: $target_dir
Make changes there. Do NOT create files outside this directory.
${audit_details:+
## Audit Details
$audit_details
}
## Rules
- Make exactly ONE targeted change per iteration
- Do not make multiple unrelated changes
- Explain your reasoning briefly before making the change
EOF
}

# ── Elapsed time ────────────────────────────────────────────────────────────
elapsed_hours() {
  local start="$1"
  local now
  now=$(date +%s)
  python3 - "$now" "$start" <<'PYEOF'
import sys; print(round((int(sys.argv[1]) - int(sys.argv[2])) / 3600, 2))
PYEOF
}
