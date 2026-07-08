#!/bin/bash
# Real mini-smoke: one tiny run against the REAL claude CLI (haiku, < $0.10).
# This is the only test that proves the allowedTools grammar end to end: the
# directive asks Claude to run `git status` and mention its output, which only
# works if Bash(git status:*) is actually granted.
#
# Usage: bash tests/run-real-smoke.sh
set -uo pipefail

SOSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$SOSL_DIR/tests"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/sosl-smoke.XXXXXX")"
TARGET="$BASE/target"

command -v claude >/dev/null || { echo "claude CLI not found"; exit 1; }
bash "$TESTS_DIR/create-dummy-target.sh" "$TARGET" >/dev/null

echo "smoke target: $TARGET"
bash "$SOSL_DIR/sosl.sh" \
  --domain "$TESTS_DIR/fixture-domain" \
  --target "$TARGET" \
  --model claude-haiku-4-5 \
  --samples 1 --max-iterations 2 \
  --budget-per-iter 0.30 --max-cost 0.75

echo ""
echo "== smoke checks =="
br="$(git -C "$TARGET" for-each-ref --format='%(refname:short)' 'refs/heads/sosl/fixture-domain/*' | head -1)"
if [[ -n "$br" ]]; then
  echo "branch: $br"
  git -C "$TARGET" log --oneline "$br" | sed 's/^/  /'
  echo "score on branch: $(git -C "$TARGET" show "$br:score.txt")"
else
  echo "NO BRANCH — inspect the run output above and $TARGET/.sosl/"
fi
echo "strategy lines from experiments.jsonl (empty strategy = suspect):"
grep -o '"strategy": "[^"]*"' "$TARGET/.sosl/experiments.jsonl" 2>/dev/null | sed 's/^/  /'
echo "claude stderr log (should be empty or benign):"
sed 's/^/  /' "$TARGET/.sosl/claude-stderr.log" 2>/dev/null | head -5
echo ""
echo "Eyeball: did a commit land, and does the strategy mention git status output?"
