#!/bin/bash
# SOSL — Night orchestrator
#
# Runs a plan of SOSL domains SERIALLY (parallel builds race on shared
# node_modules/.next symlinks), inside a hard budget/time envelope, with a
# stall watchdog, and ALWAYS leaves a NIGHT_REPORT.md — a missing report is
# itself an incident signal. Never pushes, never pulls; fetch is opt-in.
#
# Usage: bash sosl-night.sh --plan /path/to/night.d [--force]
#
# The plan directory:
#   night.d/
#     night.conf         global envelope (NIGHT_* keys, TARGET_DIR)
#     10-<name>.conf     one run: a normal sosl.sh --config file
#     20-<name>.conf     (+ optional RUN_TIMEOUT_MIN per run)
#
# Config values are parsed with SOSL's safe parser (never sourced).
# State/reports: ~/.local/state/sosl-night/<date>/ (override: SOSL_NIGHT_STATE_DIR)
# and a copy under <target>/.sosl/night/<date>/.
#
# Gates (all exit 0 with a logged reason):
#   - NIGHT_ENABLED=false or an empty plan  -> skip (turn nights off without launchctl)
#   - already ran today (date stamp)        -> skip   (--force bypasses)
#   - outside the 00:00..NIGHT_END_BY window -> skip   (--force bypasses)
# This makes the launchd install-time kickstart a deliberate no-op by day.

set -uo pipefail   # deliberately no -e: every failure path must end in a report

SOSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOSL_DIR/lib/compat.sh"
source "$SOSL_DIR/lib/utils.sh"

# ── Args ────────────────────────────────────────────────────────────────────
PLAN_DIR=""
FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)  PLAN_DIR="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help)
      grep '^#' "$0" | head -30 | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
[[ -n "$PLAN_DIR" ]] || { echo "Missing --plan <dir>"; exit 1; }

STATE_ROOT="${SOSL_NIGHT_STATE_DIR:-$HOME/.local/state/sosl-night}"
TODAY="$(date +%Y-%m-%d)"
NIGHT_DIR="$STATE_ROOT/$TODAY"
mkdir -p "$NIGHT_DIR"
ROWS="$NIGHT_DIR/rows.tsv"
NOTES="$NIGHT_DIR/notes.txt"
: > "$NOTES"
[[ -f "$ROWS" ]] || : > "$ROWS"

note() { echo "$*" | tee -a "$NOTES"; }

# ── Night defaults, then night.conf ────────────────────────────────────────
NIGHT_ENABLED=true
NIGHT_TARGET=""
NIGHT_MAX_TOTAL_COST=5.00
NIGHT_END_BY="06:30"
NIGHT_STALL_MINUTES=30
NIGHT_RUN_TIMEOUT_MIN=150
NIGHT_MIN_BATTERY_PCT=20
NIGHT_REQUIRE_AC=false
NIGHT_FETCH=false
NIGHT_NOTIFY=true
NIGHT_BASE_REF="main"
NIGHT_AUTO_SYNC=false
NIGHT_WATCH_INTERVAL="${NIGHT_WATCH_INTERVAL:-30}"

if [[ -f "$PLAN_DIR/night.conf" ]]; then
  night_cfg=$(parse_config "$PLAN_DIR/night.conf") || { note "night.conf parse error"; exit 1; }
  _ncfg() { echo "$night_cfg" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get(sys.argv[1],''))" "$1"; }
  _v=$(_ncfg NIGHT_ENABLED);         [[ -n "$_v" ]] && NIGHT_ENABLED="$_v"
  _v=$(_ncfg TARGET_DIR);            [[ -n "$_v" ]] && NIGHT_TARGET="$_v"
  _v=$(_ncfg NIGHT_MAX_TOTAL_COST);  [[ -n "$_v" ]] && NIGHT_MAX_TOTAL_COST="$_v"
  _v=$(_ncfg NIGHT_END_BY);          [[ -n "$_v" ]] && NIGHT_END_BY="$_v"
  _v=$(_ncfg NIGHT_STALL_MINUTES);   [[ -n "$_v" ]] && NIGHT_STALL_MINUTES="$_v"
  _v=$(_ncfg NIGHT_RUN_TIMEOUT_MIN); [[ -n "$_v" ]] && NIGHT_RUN_TIMEOUT_MIN="$_v"
  _v=$(_ncfg NIGHT_MIN_BATTERY_PCT); [[ -n "$_v" ]] && NIGHT_MIN_BATTERY_PCT="$_v"
  _v=$(_ncfg NIGHT_REQUIRE_AC);      [[ -n "$_v" ]] && NIGHT_REQUIRE_AC="$_v"
  _v=$(_ncfg NIGHT_FETCH);           [[ -n "$_v" ]] && NIGHT_FETCH="$_v"
  _v=$(_ncfg NIGHT_NOTIFY);          [[ -n "$_v" ]] && NIGHT_NOTIFY="$_v"
  _v=$(_ncfg NIGHT_BASE_REF);        [[ -n "$_v" ]] && NIGHT_BASE_REF="$_v"
  _v=$(_ncfg NIGHT_AUTO_SYNC);       [[ -n "$_v" ]] && NIGHT_AUTO_SYNC="$_v"
  _v=$(_ncfg NIGHT_WATCH_INTERVAL);  [[ -n "$_v" ]] && NIGHT_WATCH_INTERVAL="$_v"
else
  note "no night.conf in $PLAN_DIR"
  exit 0
fi

SPENT=0.00
REPORT_WRITTEN=false
BASE_SHA="(unknown)"

# ── Helpers ─────────────────────────────────────────────────────────────────
minutes_until_end() { # prints whole minutes until NIGHT_END_BY today (>= 0)
  python3 - "$NIGHT_END_BY" <<'PYEOF'
import datetime, sys
try:
    h, m = (int(x) for x in sys.argv[1].split(':'))
except ValueError:
    print(0); raise SystemExit
now = datetime.datetime.now()
end = now.replace(hour=h, minute=m, second=0, microsecond=0)
print(max(0, int((end - now).total_seconds() // 60)))
PYEOF
}

within_window() { # 00:00 .. NIGHT_END_BY
  [[ "$(minutes_until_end)" -gt 0 ]]
}

battery_state() { # [pmset-output override for tests] -> "ac" | "batt <pct>"
  local out="${1:-$(pmset -g batt 2>/dev/null)}"
  if echo "$out" | grep -q "AC Power"; then
    echo "ac"
    return
  fi
  local pct
  pct=$(echo "$out" | grep -o '[0-9]\{1,3\}%' | head -1 | tr -d '%')
  echo "batt ${pct:-100}"
}

battery_ok() { # exit 0 if we may run/continue
  local state pct
  state=$(battery_state "${1:-}")
  if [[ "$state" == "ac" ]]; then
    return 0
  fi
  [[ "$NIGHT_REQUIRE_AC" == "true" ]] && return 1
  pct="${state#batt }"
  [[ "$pct" -ge "$NIGHT_MIN_BATTERY_PCT" ]]
}

newest_mtime() { # epoch of the newest existing path in args, or 0
  python3 - "$@" <<'PYEOF'
import os, sys
ts = [os.path.getmtime(p) for p in sys.argv[1:] if os.path.exists(p)]
print(int(max(ts)) if ts else 0)
PYEOF
}

add_row() { # name status score0 score1 iters cost verdict branch
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$ROWS"
}

notify() { # title message
  [[ "$NIGHT_NOTIFY" == "true" ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  local t m
  t=$(echo "$1" | tr -d '"\\'); m=$(echo "$2" | tr -d '"\\')
  osascript -e "display notification \"$m\" with title \"$t\" sound name \"Glass\"" 2>/dev/null || true
}

# ── Report (EXIT trap: runs on every path, crash included) ─────────────────
write_report() {
  $REPORT_WRITTEN && return 0
  REPORT_WRITTEN=true
  local report="$NIGHT_DIR/NIGHT_REPORT.md"
  {
    echo "# SOSL Night Report — $TODAY"
    echo ""
    echo "- Plan: $PLAN_DIR"
    echo "- Target: ${NIGHT_TARGET:-'(none)'}"
    echo "- Base: $NIGHT_BASE_REF @ $BASE_SHA"
    echo "- Envelope: \$$NIGHT_MAX_TOTAL_COST, end by $NIGHT_END_BY"
    echo "- Spent: \$$SPENT"
    echo ""
    echo "## Pre-flight"
    sed 's/^/- /' "$NOTES" 2>/dev/null || true
    echo ""
    echo "## Runs"
    echo ""
    echo "| run | status | score | iters | cost | judge | branch |"
    echo "|---|---|---|---|---|---|---|"
    if [[ -s "$ROWS" ]]; then
      while IFS=$'\t' read -r name status s0 s1 iters cost verdict branch; do
        echo "| $name | $status | $s0 -> $s1 | $iters | \$$cost | $verdict | $branch |"
      done < "$ROWS"
    else
      echo "| (none) | | | | | | |"
    fi
    echo ""
    echo "## Morning checklist"
    echo ""
    if [[ -s "$ROWS" ]]; then
      while IFS=$'\t' read -r name status s0 s1 iters cost verdict branch; do
        if [[ -n "$branch" && "$branch" != "-" ]]; then
          echo "- \`git -C $NIGHT_TARGET log --oneline $NIGHT_BASE_REF..$branch\`"
          echo "- merge: \`git -C $NIGHT_TARGET merge $branch\` (only after reading the judge verdict)"
        fi
      done < "$ROWS"
    fi
    if [[ -n "${UNMERGED_INVENTORY:-}" ]]; then
      echo ""
      echo "## Unmerged sosl branches (kept, never auto-deleted)"
      echo ""
      echo "$UNMERGED_INVENTORY"
    fi
  } > "$report"
  # Copy next to the target so the code cockpit sees it too
  if [[ -n "$NIGHT_TARGET" && -d "$NIGHT_TARGET/.sosl" ]]; then
    mkdir -p "$NIGHT_TARGET/.sosl/night/$TODAY" 2>/dev/null || true
    cp "$report" "$NIGHT_TARGET/.sosl/night/$TODAY/" 2>/dev/null || true
  fi
  echo "report: $report"
}
on_exit() {
  local rc=$?
  write_report
  rm -rf "$STATE_ROOT/lock.d" 2>/dev/null || true
  if [[ $rc -ne 0 ]]; then
    notify "SOSL night: FAILED" "rc=$rc — read the night report"
  fi
}
trap on_exit EXIT

# ── Gates ───────────────────────────────────────────────────────────────────
if [[ "$NIGHT_ENABLED" != "true" ]]; then
  note "night disabled (NIGHT_ENABLED=false), skip"
  exit 0
fi

shopt -s nullglob
RUN_CONFS=("$PLAN_DIR"/[0-9]*.conf)
shopt -u nullglob
if [[ ${#RUN_CONFS[@]} -eq 0 ]]; then
  note "no run configs (NN-*.conf) in plan, skip"
  exit 0
fi

STAMP="$STATE_ROOT/last-night-date"
if [[ "$FORCE" != "true" ]]; then
  if [[ -f "$STAMP" ]] && [[ "$(cat "$STAMP" 2>/dev/null)" == "$TODAY" ]]; then
    note "already ran today ($TODAY), skip (use --force to override)"
    exit 0
  fi
  if ! within_window; then
    note "outside the 00:00..$NIGHT_END_BY window, skip (use --force for a day test)"
    exit 0
  fi
fi

# Lock (overlap between a scheduled and a manual run)
if ! mkdir "$STATE_ROOT/lock.d" 2>/dev/null; then
  other_pid="$(cat "$STATE_ROOT/lock.d/pid" 2>/dev/null || echo '')"
  if [[ -n "$other_pid" ]] && kill -0 "$other_pid" 2>/dev/null; then
    note "another sosl-night instance is running (pid $other_pid), skip"
    trap - EXIT   # do not clobber the other instance's lock or report
    exit 0
  fi
  note "stale lock found, taking over"
  rm -rf "$STATE_ROOT/lock.d"
  mkdir "$STATE_ROOT/lock.d" || exit 1
fi
echo $$ > "$STATE_ROOT/lock.d/pid"
echo "$TODAY" > "$STAMP"

# ── Pre-flight ──────────────────────────────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  note "PRE-FLIGHT FAIL: claude CLI not found on PATH"
  notify "SOSL night: not started" "claude CLI not found"
  exit 1
fi

if [[ -z "$NIGHT_TARGET" || ! -d "$NIGHT_TARGET/.git" ]]; then
  note "PRE-FLIGHT FAIL: TARGET_DIR is not a git repo: '$NIGHT_TARGET'"
  notify "SOSL night: not started" "target repo missing"
  exit 1
fi

if ! battery_ok; then
  note "PRE-FLIGHT: on battery below ${NIGHT_MIN_BATTERY_PCT}% (or AC required), skip"
  notify "SOSL night: skipped" "battery too low"
  exit 0
fi

if [[ "$NIGHT_FETCH" == "true" ]]; then
  if git -C "$NIGHT_TARGET" fetch origin 2>>"$NOTES"; then
    note "fetched origin"
  else
    note "WARN: fetch failed, continuing on local refs"
  fi
fi

if ! git -C "$NIGHT_TARGET" rev-parse --verify -q "${NIGHT_BASE_REF}^{commit}" >/dev/null; then
  note "PRE-FLIGHT FAIL: base ref '$NIGHT_BASE_REF' not found in target"
  notify "SOSL night: not started" "base ref missing"
  exit 1
fi
BASE_SHA="$(git -C "$NIGHT_TARGET" rev-parse --short "$NIGHT_BASE_REF")"
note "base: $NIGHT_BASE_REF @ $BASE_SHA"

# Auth ping: catches logged-out / rate-limited CLI before burning the night
ping_out=$(cd "$NIGHT_TARGET" && sosl_timeout 120 claude -p "Reply with exactly: OK" \
  --output-format json --model claude-haiku-4-5 --max-turns 1 \
  --max-budget-usd 0.05 2>>"$NOTES" || echo '{"is_error": true}')
ping_err=$(echo "$ping_out" | python3 -c "import json,sys
try: print('true' if json.loads(sys.stdin.read()).get('is_error') else 'false')
except Exception: print('true')" 2>/dev/null || echo true)
if [[ "$ping_err" == "true" ]]; then
  note "PRE-FLIGHT FAIL: claude auth ping failed (logged out? rate limited?)"
  notify "SOSL night: not started" "claude auth ping failed"
  exit 1
fi
note "claude auth ping OK"

# Disk space (warn only)
free_gb=$(df -g "$NIGHT_TARGET" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n "${free_gb:-}" && "$free_gb" -lt 15 ]]; then
  note "WARN: low disk space (${free_gb}G free)"
fi

# Lockfile drift: builds against a stale node_modules/.venv give false signals
sync_warn() { note "WARN: $1 is newer than its install dir — run '$2' before trusting results"; }
for fe in "$NIGHT_TARGET" "$NIGHT_TARGET/frontend"; do
  if [[ -f "$fe/package-lock.json" && -d "$fe/node_modules" ]] \
     && [[ "$fe/package-lock.json" -nt "$fe/node_modules" ]]; then
    if [[ "$NIGHT_AUTO_SYNC" == "true" ]]; then
      note "lockfile drift: running npm ci in $fe"
      (cd "$fe" && sosl_timeout 900 npm ci >>"$NOTES" 2>&1) || note "WARN: npm ci failed"
    else
      sync_warn "$fe/package-lock.json" "npm ci"
    fi
  fi
done
for be in "$NIGHT_TARGET" "$NIGHT_TARGET/backend"; do
  if [[ -f "$be/uv.lock" && -d "$be/.venv" ]] && [[ "$be/uv.lock" -nt "$be/.venv" ]]; then
    if [[ "$NIGHT_AUTO_SYNC" == "true" ]]; then
      note "lockfile drift: running uv sync in $be"
      (cd "$be" && sosl_timeout 600 uv sync >>"$NOTES" 2>&1) || note "WARN: uv sync failed"
    else
      sync_warn "$be/uv.lock" "uv sync"
    fi
  fi
done

# ── Serial run loop ─────────────────────────────────────────────────────────
for conf in "${RUN_CONFS[@]}"; do
  run_name="$(basename "$conf" .conf)"
  run_name="${run_name#[0-9][0-9]-}"

  # Envelope: time
  mins_left=$(minutes_until_end)
  if [[ "$FORCE" != "true" && "$mins_left" -lt 15 ]]; then
    note "SKIP $run_name: only ${mins_left}m left before $NIGHT_END_BY"
    add_row "$run_name" "SKIPPED" "-" "-" "-" "0" "-" "-"
    continue
  fi

  # Envelope: budget
  remaining=$(python3 -c "print(round($NIGHT_MAX_TOTAL_COST - $SPENT, 2))")
  if python3 -c "exit(0 if $remaining < 0.50 else 1)"; then
    note "SKIP $run_name: only \$$remaining left of \$$NIGHT_MAX_TOTAL_COST envelope"
    add_row "$run_name" "SKIPPED" "-" "-" "-" "0" "-" "-"
    continue
  fi

  # Battery re-check between runs
  if ! battery_ok; then
    note "BATTERY_ABORT before $run_name: battery below limit"
    add_row "$run_name" "BATTERY_ABORT" "-" "-" "-" "0" "-" "-"
    break
  fi

  # Per-run config values the orchestrator needs
  run_cfg=$(parse_config "$conf") || { add_row "$run_name" "CONF_ERROR" "-" "-" "-" "0" "-" "-"; continue; }
  _rcfg() { echo "$run_cfg" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get(sys.argv[1],''))" "$1"; }
  run_target="$(_rcfg TARGET_DIR)"; [[ -n "$run_target" ]] || run_target="$NIGHT_TARGET"
  run_base="$(_rcfg BASE_REF)";     [[ -n "$run_base" ]] || run_base="$NIGHT_BASE_REF"
  run_cost_cap="$(_rcfg MAX_COST_USD)"; [[ -n "$run_cost_cap" ]] || run_cost_cap="2.00"
  run_timeout_min="$(_rcfg RUN_TIMEOUT_MIN)"; [[ -n "$run_timeout_min" ]] || run_timeout_min="$NIGHT_RUN_TIMEOUT_MIN"

  eff_cost=$(python3 -c "print(round(min($run_cost_cap, $remaining), 2))")
  # Hard wallclock cap: run timeout, but never past NIGHT_END_BY (unless --force day test)
  if [[ "$FORCE" == "true" ]]; then
    cap_min="$run_timeout_min"
  else
    cap_min=$(python3 -c "print(min(int($run_timeout_min), $mins_left))")
  fi
  cap_sec=$((cap_min * 60))

  run_log="$NIGHT_DIR/$run_name.log"
  hb_file="$run_target/.sosl/heartbeat"
  note "RUN $run_name: cap \$$eff_cost, ${cap_min}m (log: $run_log)"

  bash "$SOSL_DIR/sosl.sh" --config "$conf" \
    --target "$run_target" --base "$run_base" --max-cost "$eff_cost" \
    >"$run_log" 2>&1 &
  run_pid=$!
  run_status=""
  run_start=$SECONDS

  # Watchdog: wallclock cap + stall (no log/heartbeat movement) + battery
  while kill -0 "$run_pid" 2>/dev/null; do
    sleep "$NIGHT_WATCH_INTERVAL"
    kill -0 "$run_pid" 2>/dev/null || break
    elapsed=$((SECONDS - run_start))
    if [[ $elapsed -ge $cap_sec ]]; then
      note "TIMEOUT $run_name after ${cap_min}m — killing process tree"
      kill_tree "$run_pid" 60
      run_status="TIMEOUT"
      break
    fi
    last_alive=$(newest_mtime "$run_log" "$hb_file")
    now_epoch=$(date +%s)
    if [[ "$last_alive" -gt 0 ]] && (( now_epoch - last_alive > NIGHT_STALL_MINUTES * 60 )); then
      note "STALLED $run_name: no output/heartbeat for ${NIGHT_STALL_MINUTES}m — killing"
      kill_tree "$run_pid" 60
      run_status="STALLED"
      break
    fi
    if ! battery_ok; then
      note "BATTERY_ABORT during $run_name"
      kill_tree "$run_pid" 60
      run_status="BATTERY_ABORT"
      break
    fi
  done
  wait "$run_pid" 2>/dev/null
  run_rc=$?

  # Collect from the manifest (written by sosl.sh's EXIT trap, kill included)
  manifest="$run_target/.sosl/last-run.json"
  read -r m_cost m_impr m_iters m_b0 m_b1 m_verdict m_branch <<< "$(python3 - "$manifest" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('total_cost_usd', 0), d.get('improvements', 0), d.get('iterations', 0),
          d.get('baseline_initial', '-'), d.get('baseline_final', '-'),
          str(d.get('judge_verdict', '-')).replace(' ', '_'), d.get('branch') or '-')
except Exception:
    print('0 0 0 - - - -')
PYEOF
)"
  SPENT=$(float_add "$SPENT" "${m_cost:-0}")

  if [[ -z "$run_status" ]]; then
    if [[ $run_rc -eq 0 ]]; then
      if [[ "${m_impr:-0}" -gt 0 ]]; then run_status="OK"; else run_status="DRY"; fi
    else
      run_status="FAILED"
    fi
  fi
  note "DONE $run_name: $run_status (${m_impr:-0} improvements, \$${m_cost:-0})"
  add_row "$run_name" "$run_status" "${m_b0:--}" "${m_b1:--}" "${m_iters:-0}" "${m_cost:-0}" "${m_verdict:--}" "${m_branch:--}"

  # Keep run artifacts with the night
  for art in SUMMARY.md JUDGE_REPORT.md last-run.json; do
    [[ -f "$run_target/.sosl/$art" ]] && cp "$run_target/.sosl/$art" "$NIGHT_DIR/$run_name-$art" 2>/dev/null
  done
done

# ── Housekeeping: only branches fully merged into the base ref ──────────────
merged=$(git -C "$NIGHT_TARGET" branch --merged "$NIGHT_BASE_REF" --format='%(refname:short)' 2>/dev/null | grep '^sosl/' || true)
for b in $merged; do
  wt=$(git -C "$NIGHT_TARGET" worktree list --porcelain 2>/dev/null | grep -B2 "branch refs/heads/$b" | awk '/^worktree /{print $2}' | head -1)
  [[ -n "$wt" ]] && git -C "$NIGHT_TARGET" worktree remove --force "$wt" 2>/dev/null
  git -C "$NIGHT_TARGET" branch -d "$b" 2>/dev/null && note "cleaned merged branch $b"
done
git -C "$NIGHT_TARGET" worktree prune 2>/dev/null || true

UNMERGED_INVENTORY=$(git -C "$NIGHT_TARGET" for-each-ref 'refs/heads/sosl/**' \
  --format='- %(refname:short) (%(committerdate:relative)) %(contents:subject)' 2>/dev/null | head -20)

# ── Wrap up ─────────────────────────────────────────────────────────────────
ok_count=$(cut -f2 "$ROWS" | grep -c "OK" || true)
write_report
notify "SOSL night: done" "$ok_count run(s) with improvements, spent \$$SPENT — read the report"
exit 0
