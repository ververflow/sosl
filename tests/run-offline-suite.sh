#!/bin/bash
# SOSL offline test suite: exercises the full loop (measure -> change -> guards ->
# re-measure -> commit/revert -> judge) plus the night orchestrator, with zero real
# Claude calls and zero cost, against disposable dummy repos.
#
# Usage: bash tests/run-offline-suite.sh [scenario ...]     (default: all)
#   e.g. bash tests/run-offline-suite.sh s02 s05
#
# The fake `claude` in tests/fake-claude is prepended to PATH; see that stub for
# the SOSL_FAKE_MODE knobs each scenario uses.
set -uo pipefail

SOSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$SOSL_DIR/tests"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/sosl-suite.XXXXXX")"
export PATH="$TESTS_DIR/fake-claude:$TESTS_DIR/fake-gh:$PATH"

PASS=0; FAIL=0; RUN_N=0
ok()  { PASS=$((PASS+1)); echo "    ok: $1"; }
bad() { FAIL=$((FAIL+1)); echo "    FAIL: $1"; }
hdr() { echo ""; echo "== $1 =="; }

new_target() { # new_target <name> [--monorepo]; sets TARGET
  TARGET="$BASE/$1"
  bash "$TESTS_DIR/create-dummy-target.sh" "$TARGET" "${2:-}" >/dev/null
}

run_sosl() { # run_sosl <domain-dir> [extra sosl args...]; sets LOG, RC; uses $TARGET
  local domain="$1"; shift
  RUN_N=$((RUN_N+1)); LOG="$BASE/run-$RUN_N.log"
  bash "$SOSL_DIR/sosl.sh" --domain "$domain" --target "$TARGET" --samples 1 "$@" >"$LOG" 2>&1
  RC=$?
}

sosl_branch() { # sosl_branch <domain-name>
  git -C "$TARGET" for-each-ref --format='%(refname:short)' "refs/heads/sosl/$1/*" | head -1
}

jsonl_count() {
  if [[ -f "$TARGET/.sosl/experiments.jsonl" ]]; then
    wc -l < "$TARGET/.sosl/experiments.jsonl" | tr -d ' '
  else
    echo 0
  fi
}

s01() {
  hdr "s01 hang measurement dies fast (timeout shim + MEASURE_TIMEOUT export)"
  new_target t01
  local t0=$SECONDS
  run_sosl "$TESTS_DIR/fixture-domain-hang" --max-iterations 1
  local dt=$((SECONDS - t0))
  [[ $RC -ne 0 ]] && ok "non-zero exit ($RC)" || bad "expected failure, got rc=0"
  grep -q "All measurements failed\|timed out" "$LOG" && ok "measurement failure reported" || bad "no failure message in log"
  [[ $dt -lt 40 ]] && ok "died fast (${dt}s < 40s)" || bad "took ${dt}s (MEASURE_TIMEOUT=5 not honored)"
}

s02() {
  hdr "s02 two improvements commit, judge approves, manifest written"
  new_target t02
  run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 2
  [[ $RC -eq 0 ]] && ok "clean exit" || bad "rc=$RC (see $LOG)"
  local br; br="$(sosl_branch fixture-domain)"
  [[ -n "$br" ]] && ok "branch created ($br)" || bad "no sosl branch"
  local n=0
  [[ -n "$br" ]] && n=$(git -C "$TARGET" log --oneline "$br" 2>/dev/null | grep -c "sosl(fixture-domain)")
  [[ "$n" == "2" ]] && ok "2 sosl commits" || bad "expected 2 commits, got $n"
  local score=""
  [[ -n "$br" ]] && score="$(git -C "$TARGET" show "$br:score.txt" 2>/dev/null | tr -d '[:space:]')"
  [[ "$score" == "44" ]] && ok "score 42 -> 44 on branch" || bad "branch score = '$score'"
  grep -q '"improved": true' "$TARGET/.sosl/experiments.jsonl" 2>/dev/null && ok "improvements logged" || bad "no improved entries"
  grep -q "APPROVE" "$TARGET/.sosl/JUDGE_REPORT.md" 2>/dev/null && ok "judge report APPROVE" || bad "no judge report / no approve"
  python3 - "$TARGET/.sosl/last-run.json" <<'PYEOF' && ok "last-run.json manifest correct" || bad "manifest missing/wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["improvements"] == 2, d
assert d["status"] == "completed", d
assert d["domain"] == "fixture-domain", d
PYEOF
}

s03() {
  hdr "s03 new file inside scope is committed along (add -N / add -A)"
  new_target t03
  SOSL_FAKE_NEWFILE=1 run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1
  local br; br="$(sosl_branch fixture-domain)"
  [[ -n "$br" ]] || { bad "no sosl branch"; return; }
  git -C "$TARGET" show --name-only --format= "$br" 2>/dev/null | grep -q "notes.md" \
    && ok "notes.md included in the commit" || bad "notes.md missing from commit"
}

s04() {
  hdr "s04 new file outside scope hits the scope guard, clean revert"
  new_target t04
  SOSL_FAKE_NEWFILE=1 SOSL_FAKE_NEWFILE_PATH=evil.txt run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1
  grep -q "outside allowed scope" "$LOG" && ok "scope guard fired" || bad "scope guard did not fire"
  local br; br="$(sosl_branch fixture-domain)"
  local n=0
  [[ -n "$br" ]] && n=$(git -C "$TARGET" log --oneline "$br" | grep -c "sosl(") || true
  [[ "$n" == "0" ]] && ok "no commit made" || bad "unexpected commit"
  local wt="$TARGET/.sosl-worktrees/fixture-domain"
  [[ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]] && ok "worktree clean after revert" \
    || bad "worktree dirty: $(git -C "$wt" status --porcelain | head -3 | tr '\n' ' ')"
}

s05() {
  hdr "s05 abort after 3 consecutive Claude errors"
  new_target t05
  SOSL_FAKE_MODE=error run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 10
  grep -q "consecutive Claude errors" "$LOG" && ok "abort message present" || bad "no abort message"
  local n; n=$(jsonl_count)
  [[ "$n" == "3" ]] && ok "exactly 3 experiments" || bad "expected 3 experiments, got $n"
}

s06() {
  hdr "s06 tree mode stagnation breaker"
  new_target t06
  local cfg="$BASE/t06.conf"
  printf 'STAGNATION_THRESHOLD=3\n' > "$cfg"
  SOSL_FAKE_MODE=noop run_sosl "$TESTS_DIR/fixture-domain" --search tree --max-iterations 10 --max-children 5 --config "$cfg"
  grep -qi "stagnation" "$LOG" && ok "stagnation breaker fired" || bad "no stagnation stop in log"
  local n; n=$(jsonl_count)
  [[ "$n" == "3" ]] && ok "stopped after 3 iterations" || bad "got $n iterations"
}

s07() {
  hdr "s07 monorepo: python stack guard fires; STACK override narrows"
  new_target t07 --monorepo
  SOSL_FAKE_MODE=noqa run_sosl "$TESTS_DIR/fixture-domain-mono" --max-iterations 1
  if grep -q "\[python\]" "$LOG" && grep -qi "suppression" "$LOG"; then
    ok "python guard caught the # noqa"
  else
    bad "python guard did not fire (monorepo bug)"
  fi
  new_target t07b --monorepo
  local dom="$BASE/dom-nodeonly"
  rm -rf "$dom"; cp -R "$TESTS_DIR/fixture-domain-mono" "$dom"
  printf 'STACK="node"\n' >> "$dom/config.sh"
  SOSL_FAKE_MODE=noqa run_sosl "$dom" --max-iterations 1
  if grep -q "\[python\]" "$LOG"; then
    bad "python guard fired despite STACK=node"
  else
    ok "STACK=node narrowed layer 2 (no python guard)"
  fi
  grep -q "No significant improvement" "$LOG" && ok "edit measured + reverted (below noise)" || bad "expected below-noise revert"
}

s08() {
  hdr "s08 --base main bases the worktree off main, not the feature HEAD"
  new_target t08
  run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1 --base main
  local wt="$TARGET/.sosl-worktrees/fixture-domain"
  [[ ! -f "$wt/ruis.txt" ]] && ok "no feature-branch noise in worktree" || bad "ruis.txt present (based on HEAD)"
  new_target t08b
  run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1
  [[ -f "$TARGET/.sosl-worktrees/fixture-domain/ruis.txt" ]] && ok "default still bases on HEAD" || bad "default base changed"
}

s09() {
  hdr "s09 checkpoint domain match is exact"
  new_target t09
  (
    source "$SOSL_DIR/lib/utils.sh" 2>/dev/null
    source "$SOSL_DIR/lib/checkpoint.sh"
    mkdir -p "$TARGET/.sosl"
    save_checkpoint "$TARGET" "code-quality-20260101-000000" 3 100 1.50 "sosl/code-quality/x" "code-quality"
    a="$(load_checkpoint "$TARGET" "code")"
    b="$(load_checkpoint "$TARGET" "code-quality")"
    [[ -z "$a" && -n "$b" ]]
  ) && ok "substring no longer matches; exact domain does" || bad "checkpoint matching wrong"
}

s10() {
  hdr "s10 night orchestrator: report always, timeout row, gates"
  new_target t10
  local plan="$BASE/night.d"
  local state="$BASE/night-state"
  mkdir -p "$plan"
  cat > "$plan/night.conf" <<EOF
NIGHT_ENABLED=true
TARGET_DIR="$TARGET"
NIGHT_MAX_TOTAL_COST=5.00
NIGHT_END_BY="23:59"
NIGHT_STALL_MINUTES=2
NIGHT_RUN_TIMEOUT_MIN=1
NIGHT_NOTIFY=false
NIGHT_BASE_REF="main"
EOF
  printf 'DOMAIN_DIR="%s"\nMAX_ITERATIONS=2\nMAX_COST_USD=1.00\n' "$TESTS_DIR/fixture-domain" > "$plan/10-improve.conf"
  printf 'DOMAIN_DIR="%s"\nMAX_ITERATIONS=1\nMAX_COST_USD=1.00\nRUN_TIMEOUT_MIN=1\n' "$TESTS_DIR/fixture-domain-slow" > "$plan/20-slow.conf"

  SOSL_NIGHT_STATE_DIR="$state" NIGHT_WATCH_INTERVAL=5 SOSL_FAKE_PMSET="Now drawing from 'AC Power'" \
    bash "$SOSL_DIR/sosl-night.sh" --plan "$plan" --force > "$BASE/night1.log" 2>&1
  local rep; rep="$(find "$state" -name NIGHT_REPORT.md 2>/dev/null | head -1)"
  [[ -n "$rep" ]] || { bad "no night report written"; return; }
  ok "night report written"
  grep -q "fixture-domain" "$rep" && grep -q "OK" "$rep" && ok "improve run row: OK" || bad "improve row missing/wrong"
  grep -qE "TIMEOUT|STALLED" "$rep" && ok "slow run capped by watchdog" || bad "no TIMEOUT/STALLED row"
  grep -q "merge" "$rep" && ok "merge command in report" || bad "no merge command in report"

  SOSL_NIGHT_STATE_DIR="$state" SOSL_FAKE_PMSET="Now drawing from 'AC Power'" \
    bash "$SOSL_DIR/sosl-night.sh" --plan "$plan" > "$BASE/night2.log" 2>&1
  grep -qi "already ran" "$BASE/night2.log" && ok "date-stamp gate skips second run" || bad "no skip on second run"

  cat > "$plan/night.conf" <<EOF
NIGHT_ENABLED=false
TARGET_DIR="$TARGET"
EOF
  SOSL_NIGHT_STATE_DIR="$state" SOSL_FAKE_PMSET="Now drawing from 'AC Power'" \
    bash "$SOSL_DIR/sosl-night.sh" --plan "$plan" --force > "$BASE/night3.log" 2>&1
  grep -qi "disabled" "$BASE/night3.log" && ok "NIGHT_ENABLED=false gate" || bad "disabled gate failed"
}

s11() {
  hdr "s11 auto-PR: opt-in, branch pushed, gh called, push-fail never fatal"
  new_target t11
  git init --bare -q "$BASE/t11-remote.git"
  export SOSL_FAKE_GH_LOG="$BASE/t11-gh.log"
  cat > "$BASE/t11-autopr.conf" <<EOF
AUTO_PR=true
AUTO_PR_REPO="example/example"
AUTO_PR_REMOTE="$BASE/t11-remote.git"
AUTO_PR_BASE="main"
EOF
  run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1 --config "$BASE/t11-autopr.conf"
  [[ $RC -eq 0 ]] && ok "clean exit" || bad "rc=$RC (see $LOG)"
  local br; br="$(sosl_branch fixture-domain)"
  git --git-dir="$BASE/t11-remote.git" for-each-ref --format='%(refname:short)' 2>/dev/null | grep -qx "$br" \
    && ok "branch pushed to remote" || bad "branch not on remote"
  grep -q -- "pr create.*--repo example/example.*--head $br" "$SOSL_FAKE_GH_LOG" 2>/dev/null \
    && ok "gh pr create called with repo+head" || bad "gh log: $(cat "$SOSL_FAKE_GH_LOG" 2>/dev/null | tr '\n' ' ')"
  [[ -f "$TARGET/.sosl/pr-url.txt" ]] && ok "pr-url.txt written" || bad "no pr-url.txt"

  # Opt-in: without AUTO_PR, gh must never be called
  : > "$SOSL_FAKE_GH_LOG"
  new_target t11b
  run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1
  [[ -s "$SOSL_FAKE_GH_LOG" ]] && bad "gh called without AUTO_PR" || ok "no gh call without AUTO_PR (opt-in)"

  # Unreachable remote: warn + keep the branch, never kill the run
  new_target t11c
  cat > "$BASE/t11c.conf" <<EOF
AUTO_PR=true
AUTO_PR_REPO="example/example"
AUTO_PR_REMOTE="$BASE/does-not-exist.git"
EOF
  run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1 --config "$BASE/t11c.conf"
  [[ $RC -eq 0 ]] && ok "push failure not fatal" || bad "rc=$RC on unreachable remote"
  grep -q "auto-PR: push failed" "$LOG" && ok "push failure logged" || bad "no push-failed warning"
  unset SOSL_FAKE_GH_LOG
}

s12() {
  hdr "s12 planted infra symlinks (.venv) stay out of guards, commits and cleans"
  # gitignore uses the standard trailing-slash form, which does NOT match the
  # symlink SOSL plants in the worktree — the bug this scenario pins down.
  # .sosl/ is ALSO gitignored, like real targets do: an ':(exclude)' pathspec
  # naming an ignored path makes git add exit 1 (second bug pinned here).
  new_target t12
  mkdir -p "$TARGET/.venv/bin"; echo "fake" > "$TARGET/.venv/bin/python"
  printf '.venv/\n.sosl/\n.sosl-worktrees/\n' >> "$TARGET/.gitignore"
  git -C "$TARGET" add .gitignore >/dev/null && git -C "$TARGET" commit -qm "ignore venv"

  run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1
  [[ $RC -eq 0 ]] && ok "clean exit" || bad "rc=$RC (see $LOG)"
  grep -q "outside allowed scope" "$LOG" && bad "scope guard tripped over .venv symlink" || ok "no scope fail on planted symlink"
  local br; br="$(sosl_branch fixture-domain)"
  [[ -n "$br" ]] || { bad "no sosl branch"; return; }
  [[ "$(git -C "$TARGET" show --name-only --format= "$br" 2>/dev/null | grep -c "\.venv")" == "0" ]] \
    && ok ".venv not committed" || bad ".venv leaked into the commit"

  # Guard-fail path: the revert's git clean must spare the planted symlink
  new_target t12b
  mkdir -p "$TARGET/.venv/bin"; echo "fake" > "$TARGET/.venv/bin/python"
  printf '.venv/\n.sosl/\n.sosl-worktrees/\n' >> "$TARGET/.gitignore"
  git -C "$TARGET" add .gitignore >/dev/null && git -C "$TARGET" commit -qm "ignore venv"
  SOSL_FAKE_NEWFILE=1 SOSL_FAKE_NEWFILE_PATH=evil.txt run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1
  [[ -L "$TARGET/.sosl-worktrees/fixture-domain/.venv" ]] \
    && ok "revert clean spared the .venv symlink" || bad "symlink gone after revert"
}

s13() {
  hdr "s13 Claude self-commits are reset and re-judged by the pipeline"
  new_target t13
  SOSL_FAKE_MODE=selfcommit run_sosl "$TESTS_DIR/fixture-domain" --max-iterations 1
  [[ $RC -eq 0 ]] && ok "clean exit" || bad "rc=$RC (see $LOG)"
  grep -q "committed by itself" "$LOG" && ok "self-commit detected and reset" || bad "no self-commit warning"
  local br; br="$(sosl_branch fixture-domain)"
  [[ -n "$br" ]] || { bad "no sosl branch"; return; }
  # grep -c, not grep -q: -q exits on first match, git gets SIGPIPE and
  # under pipefail the pipeline reads as failed.
  [[ "$(git -C "$TARGET" log --format=%s "$br" | grep -c "^feat: self-committed")" == "0" ]] \
    && ok "no foreign commit on branch" || bad "foreign commit survived on the branch"
  [[ "$(git -C "$TARGET" log --oneline "$br" | grep -c "sosl(fixture-domain)")" -ge 1 ]] \
    && ok "work re-landed as a guarded sosl commit" || bad "improvement lost after reset"
  local score; score="$(git -C "$TARGET" show "$br:score.txt" 2>/dev/null | tr -d '[:space:]')"
  [[ "$score" == "43" ]] && ok "score improvement preserved (43)" || bad "branch score = '$score'"
}

all="s01 s02 s03 s04 s05 s06 s07 s08 s09 s10 s11 s12 s13"
if [[ ! -f "$SOSL_DIR/sosl-night.sh" ]]; then
  all="${all/ s10/}"
fi

if [[ $# -gt 0 ]]; then scenarios="$*"; else scenarios="$all"; fi
echo "SOSL offline suite — scenarios: $scenarios"
echo "workdir: $BASE"
for s in $scenarios; do "$s"; done

echo ""
echo "== result: $PASS ok, $FAIL failed =="
[[ $FAIL -eq 0 ]] || exit 1
