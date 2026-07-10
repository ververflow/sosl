#!/bin/bash
# Create a disposable dummy target repo for the offline SOSL test suite.
# The repo has a trivially measurable metric: the number in score.txt.
# HEAD is left on a feature branch so --base tests can prove main-based worktrees.
# Usage: create-dummy-target.sh <dir> [--monorepo]
set -euo pipefail

dir="${1:?usage: create-dummy-target.sh <dir> [--monorepo]}"
flavor="${2:-}"

rm -rf "$dir"
mkdir -p "$dir"
cd "$dir"
git init -q -b main
git config user.email "sosl-suite@invalid"
git config user.name "SOSL Suite"

echo "42" > score.txt
printf '.sosl/\n.sosl-worktrees/\n' > .gitignore

if [[ "$flavor" == "--monorepo" ]]; then
  mkdir -p frontend backend/tests
  echo '{"name": "dummy", "private": true}' > frontend/package.json
  printf '[project]\nname = "dummy"\nversion = "0.0.1"\n' > backend/pyproject.toml
  printf 'x = 0\n' > backend/app.py
  printf 'def test_x():\n    assert True\n' > backend/tests/test_x.py
fi

git add -A
git commit -qm "init: score 42"

git checkout -qb feature/afleiding
echo "noise" > ruis.txt
git add ruis.txt
git commit -qm "noise commit on feature branch"

echo "dummy target ready: $dir (HEAD: $(git branch --show-current))"
