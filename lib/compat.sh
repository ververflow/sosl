#!/bin/bash
# SOSL — Portability + process helpers, shared by sosl.sh and sosl-night.sh
#
# sosl_timeout gives the GNU-timeout contract (exit 124 on timeout) everywhere:
# macOS ships no `timeout` at all, and Git Bash ships a non-GNU timeout.exe with
# different semantics. Detection order: GNU timeout -> GNU gtimeout (brew
# coreutils) -> python3 fallback. The fallback kills the whole process group,
# so children spawned by measure.sh (node builds, test runners) die with it.

_sosl_detect_timeout() {
  if command -v timeout >/dev/null 2>&1 && timeout --version 2>/dev/null | grep -q GNU; then
    echo "timeout"
  elif command -v gtimeout >/dev/null 2>&1 && gtimeout --version 2>/dev/null | grep -q GNU; then
    echo "gtimeout"
  else
    echo "python"
  fi
}
SOSL_TIMEOUT_IMPL="${SOSL_TIMEOUT_IMPL:-$(_sosl_detect_timeout)}"

# Usage: sosl_timeout SECONDS CMD [ARGS...]     — exit 124 on timeout
sosl_timeout() {
  local secs="$1"; shift
  case "$SOSL_TIMEOUT_IMPL" in
    timeout|gtimeout)
      "$SOSL_TIMEOUT_IMPL" "$secs" "$@"
      ;;
    *)
      python3 - "$secs" "$@" <<'PYEOF'
import os, signal, subprocess, sys

secs = float(sys.argv[1])
cmd = sys.argv[2:]
p = subprocess.Popen(cmd, start_new_session=True)  # own process group
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    try:
        os.killpg(os.getpgid(p.pid), signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(p.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait()
    sys.exit(124)
PYEOF
      ;;
  esac
}

# Heartbeat: touched on every sign of life inside a run. The night
# orchestrator's stall watchdog keys off this file's mtime — without it, the
# longest legitimate silence (N samples x MEASURE_TIMEOUT) would blind any
# watchdog.
hb_touch() {
  if [[ -n "${SOSL_STATE_DIR:-}" ]]; then
    touch "$SOSL_STATE_DIR/heartbeat" 2>/dev/null || true
  fi
}

# Kill a process tree: TERM the whole tree, wait out a grace period, then KILL
# whatever is left. macOS-native (pgrep -P), no setsid needed.
# Usage: kill_tree PID [grace-seconds]
kill_tree() {
  local pid="$1" grace="${2:-10}"
  local pids
  pids="$(_collect_tree "$pid")"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
  fi
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [[ $waited -lt $grace ]]; do
    sleep 1
    waited=$((waited + 1))
  done
  pids="$(_collect_tree "$pid")"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null || true
  fi
}

_collect_tree() {
  local out="$1" queue="$1"
  while [[ -n "$queue" ]]; do
    local next="" p kids
    for p in $queue; do
      kids="$(pgrep -P "$p" 2>/dev/null || true)"
      if [[ -n "$kids" ]]; then
        out="$out $kids"
        next="$next $kids"
      fi
    done
    queue="$next"
  done
  echo "$out"
}
