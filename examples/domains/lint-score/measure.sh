#!/bin/bash
# SOSL Example Domain: Generic Lint Score
# Auto-detects linter (ESLint, pylint, clippy, golangci-lint)
# Metric: max(0, 1000 - error_count) -- higher = fewer errors
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

error_count=0

# Auto-detect stack and run appropriate linter
if [[ -f "package.json" ]]; then
  # Node.js: ESLint
  error_count=$(npx eslint . --format json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    print(sum(len(f.get('messages', [])) for f in data))
except: print(0)
" 2>/dev/null || echo 0)

elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
  # Python: ruff (fast) or pylint (fallback)
  if command -v ruff &>/dev/null; then
    error_count=$(ruff check . --output-format json 2>/dev/null | python3 -c "
import json, sys
try: print(len(json.loads(sys.stdin.read())))
except: print(0)
" 2>/dev/null || echo 0)
  elif command -v pylint &>/dev/null; then
    error_count=$(pylint --output-format=json . 2>/dev/null | python3 -c "
import json, sys
try: print(len(json.loads(sys.stdin.read())))
except: print(0)
" 2>/dev/null || echo 0)
  fi

elif [[ -f "Cargo.toml" ]]; then
  # Rust: clippy
  error_count=$(cargo clippy --message-format=json 2>/dev/null | python3 -c "
import json, sys
count = 0
for line in sys.stdin:
    try:
        msg = json.loads(line)
        if msg.get('reason') == 'compiler-message':
            level = msg.get('message', {}).get('level', '')
            if level in ('error', 'warning'):
                count += 1
    except: pass
print(count)
" 2>/dev/null || echo 0)

elif [[ -f "go.mod" ]]; then
  # Go: golangci-lint or go vet
  if command -v golangci-lint &>/dev/null; then
    error_count=$(golangci-lint run --out-format json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    print(len(data.get('Issues', [])))
except: print(0)
" 2>/dev/null || echo 0)
  else
    error_count=$(go vet ./... 2>&1 | grep -c "^" || echo 0)
  fi
fi

# Invert: higher = better (fewer errors)
python3 -c "print(max(0, 1000 - int($error_count)))"
