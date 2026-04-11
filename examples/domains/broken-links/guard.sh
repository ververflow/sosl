#!/bin/bash
# SOSL Guard: Broken Links
# Ensures docs still build and content isn't corrupted
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# If there's a docs build command, run it
if [[ -f "package.json" ]] && grep -q '"docs"' package.json 2>/dev/null; then
  npm run docs 2>&1 || { echo "GUARD FAIL: docs build failed"; exit 1; }
elif [[ -f "mkdocs.yml" ]]; then
  mkdocs build --strict 2>&1 || { echo "GUARD FAIL: mkdocs build failed"; exit 1; }
fi

# Check that no markdown files were deleted
deleted_docs=$(git diff --name-only --diff-filter=D | grep -E '\.(md|mdx|rst)$' || true)
if [[ -n "$deleted_docs" ]]; then
  echo "GUARD FAIL: Documentation files deleted: $deleted_docs"
  exit 1
fi

echo "GUARD PASS"
