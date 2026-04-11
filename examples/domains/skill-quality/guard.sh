#!/bin/bash
# SOSL Guard: Skill Quality
# Ensures the SKILL.md is still valid after Claude's changes
set -euo pipefail

TARGET_DIR="${1:-.}"

# Find SKILL.md
SKILL_FILE=""
for f in "$TARGET_DIR/SKILL.md" "$TARGET_DIR"/*.md; do
  if [[ -f "$f" ]] && head -1 "$f" | grep -q "^---"; then
    SKILL_FILE="$f"
    break
  fi
done

if [[ -z "$SKILL_FILE" ]]; then
  echo "GUARD FAIL: No SKILL.md with YAML frontmatter found"
  exit 1
fi

# Validate YAML frontmatter structure
python3 - "$SKILL_FILE" <<'PYEOF'
import sys, re

skill_path = sys.argv[1]
with open(skill_path, encoding='utf-8') as f:
    content = f.read()

errors = []

# Must start with ---
if not content.startswith('---'):
    errors.append('Missing YAML frontmatter (must start with ---)')

# Must have closing ---
if content.count('---') < 2:
    errors.append('Unclosed YAML frontmatter (need opening and closing ---)')

# Extract frontmatter
fm_end = content.find('---', 3)
if fm_end > 0:
    fm = content[3:fm_end]

    # Must have name field
    if 'name:' not in fm:
        errors.append('Missing required field: name')

    # Must have description
    if 'description:' not in fm:
        errors.append('Missing required field: description')

# Body must not be empty
body = content[fm_end+3:] if fm_end > 0 else content
if len(body.strip()) < 50:
    errors.append('Skill body is too short (< 50 characters)')

# Must have at least one heading
if not re.search(r'^#', body, re.MULTILINE):
    errors.append('No headings found in skill body')

if errors:
    for e in errors:
        print(f'GUARD FAIL: {e}')
    sys.exit(1)
PYEOF

echo "GUARD PASS"
