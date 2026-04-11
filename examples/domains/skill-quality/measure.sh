#!/bin/bash
# SOSL Example Domain: Claude Code Skill Quality
# Metric: structural quality score of SKILL.md (higher = better)
# Measures: frontmatter, structure, clarity, completeness, examples
# Optional: dynamic test with Claude (set SKILL_TEST_PROMPTS env var)
set -euo pipefail

TARGET_DIR="${1:-.}"

# Find the SKILL.md file
SKILL_FILE=""
for f in "$TARGET_DIR/SKILL.md" "$TARGET_DIR"/*.md; do
  if [[ -f "$f" ]] && head -1 "$f" | grep -q "^---"; then
    SKILL_FILE="$f"
    break
  fi
done

if [[ -z "$SKILL_FILE" ]]; then
  echo "0"
  exit 1
fi

# Static quality analysis (deterministic, no Claude calls needed)
score=$(python3 - "$SKILL_FILE" <<'PYEOF'
import sys, re, os

skill_path = sys.argv[1]
with open(skill_path, encoding='utf-8') as f:
    content = f.read()

score = 0
max_score = 0
findings = []

# --- Frontmatter checks (0-5 points) ---
max_score += 5

# Has YAML frontmatter?
if content.startswith('---'):
    fm_end = content.find('---', 3)
    if fm_end > 0:
        fm = content[3:fm_end]
        score += 1  # Has frontmatter

        # Required fields
        for field in ['name:', 'description:', 'user-invocable:']:
            if field in fm:
                score += 1

        # Has argument-hint (helps users know what to pass)
        if 'argument-hint:' in fm:
            score += 1

# --- Structure checks (0-5 points) ---
max_score += 5
body = content[content.find('---', 3)+3:] if '---' in content[3:] else content

# Has h1 title
if re.search(r'^# ', body, re.MULTILINE):
    score += 1

# Has multiple sections (h2)
h2_count = len(re.findall(r'^## ', body, re.MULTILINE))
if h2_count >= 2:
    score += 1
if h2_count >= 4:
    score += 1

# Has subsections (h3) for detail
h3_count = len(re.findall(r'^### ', body, re.MULTILINE))
if h3_count >= 2:
    score += 1

# Has tables or structured data
if '|' in body and '---' in body:
    score += 1

# --- Clarity checks (0-5 points) ---
max_score += 5

lines = [l for l in body.splitlines() if l.strip()]
word_count = len(body.split())

# Not too short (min 100 words)
if word_count >= 100:
    score += 1

# Not too long (max 2000 words -- verbose skills confuse Claude)
if word_count <= 2000:
    score += 1

# Has code blocks or examples
if '```' in body:
    score += 1

# Has bullet points or numbered lists
if re.search(r'^\s*[-*\d]\.*\s', body, re.MULTILINE):
    score += 1

# Has bold keywords for scannability
if '**' in body:
    score += 1

# --- Completeness checks (0-5 points) ---
max_score += 5

# Has output format specification
if re.search(r'(?i)(output|format|template|response)', body):
    score += 1

# Has scope boundaries (what NOT to do)
if re.search(r'(?i)(do not|don\'t|forbidden|avoid|never)', body):
    score += 1

# Has error/edge case handling
if re.search(r'(?i)(error|edge|fallback|exception|fail|default)', body):
    score += 1

# No TODO/FIXME/placeholder text
if not re.search(r'(?i)(TODO|FIXME|TBD|PLACEHOLDER|XXX)', body):
    score += 1

# Has explicit trigger/invocation guidance
if re.search(r'(?i)(trigger|invoke|usage|command|slash)', body):
    score += 1

print(score)
PYEOF
)

# Optional: dynamic test with Claude (expensive, opt-in)
# Set SKILL_TEST_PROMPTS to a file with one test prompt per line
# Each successful test adds 2 points
if [[ -n "${SKILL_TEST_PROMPTS:-}" ]] && [[ -f "$SKILL_TEST_PROMPTS" ]]; then
  skill_content=$(cat "$SKILL_FILE")
  dynamic_score=0

  while IFS= read -r test_prompt; do
    [[ -z "$test_prompt" ]] && continue
    [[ "$test_prompt" == \#* ]] && continue

    # Run test prompt with skill as system context
    output=$(claude -p "You have this skill definition:\n\n$skill_content\n\nNow execute it for: $test_prompt" \
      --output-format json --max-turns 3 --model claude-haiku-4-5 2>/dev/null || echo '{}')

    # Score the output (basic quality check)
    test_score=$(echo "$output" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    text = str(d.get('result', d.get('content', '')))
    points = 0
    if len(text) > 50: points += 1   # Produced substantial output
    if len(text) < 5000: points += 1  # Not runaway output
    print(points)
except:
    print(0)
" 2>/dev/null || echo 0)

    dynamic_score=$((dynamic_score + test_score))
  done < "$SKILL_TEST_PROMPTS"

  score=$((score + dynamic_score))
fi

echo "$score"
