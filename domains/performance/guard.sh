#!/bin/bash
# SOSL Domain: Performance — Guard script
# Ensures optimization changes don't break functionality
#
# Usage: bash guard.sh /path/to/target
# Exit 0 = pass, exit 1 = fail (reason on stdout)

set -euo pipefail

TARGET_DIR="${1:-.}"
FRONTEND_DIR="$TARGET_DIR/frontend"

# ── 1. TypeScript must compile (strictest check) ────────────────────────────
if [[ -f "$FRONTEND_DIR/tsconfig.json" ]]; then
  cd "$FRONTEND_DIR"
  # Clear any tsc cache to ensure fresh check
  python3 -c "import shutil; shutil.rmtree('node_modules/.cache', ignore_errors=True); shutil.rmtree('.next', ignore_errors=True)" 2>/dev/null || true
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1) || {
    echo "GUARD FAIL: TypeScript compilation errors"
    echo "$TSC_OUTPUT" | head -15
    exit 1
  }
fi

# ── 2. All imports must resolve to existing files ────────────────────────────
if [[ -d "$FRONTEND_DIR/src" ]]; then
  cd "$FRONTEND_DIR"
  BROKEN_IMPORTS=$(python3 -c "
import re, os, glob

src_dir = 'src'
alias_base = src_dir  # @/ maps to src/

broken = []
for fpath in glob.glob(os.path.join(src_dir, '**', '*.ts'), recursive=True) + \
             glob.glob(os.path.join(src_dir, '**', '*.tsx'), recursive=True):
    with open(fpath, encoding='utf-8') as f:
        try:
            content = f.read()
        except:
            continue
    # Find all @/ imports
    for m in re.finditer(r'from [\"\\']@/([^\"\\'\s]+)[\"\\']', content):
        import_path = m.group(1)
        resolved = os.path.join(alias_base, import_path)
        # Check: file.ts, file.tsx, file/index.ts, file/index.tsx
        candidates = [
            resolved + '.ts', resolved + '.tsx',
            os.path.join(resolved, 'index.ts'),
            os.path.join(resolved, 'index.tsx'),
            resolved  # exact file
        ]
        if not any(os.path.exists(c) for c in candidates):
            broken.append(f'{fpath}: @/{import_path}')

if broken:
    for b in broken[:10]:
        print(b)
" 2>/dev/null)

  if [[ -n "$BROKEN_IMPORTS" ]]; then
    echo "GUARD FAIL: Broken imports detected"
    echo "$BROKEN_IMPORTS"
    exit 1
  fi
fi

# ── 3. No pages deleted (feature protection) ────────────────────────────────
if [[ -d "$FRONTEND_DIR/src/app" ]]; then
  PAGE_COUNT=$(find "$FRONTEND_DIR/src/app" -name "page.tsx" | wc -l | tr -d '[:space:]')
  if [[ "$PAGE_COUNT" -lt 2 ]]; then
    echo "GUARD FAIL: Too few pages remaining ($PAGE_COUNT). Possible feature deletion."
    exit 1
  fi
fi

# ── 4. Build must succeed ────────────────────────────────────────────────────
if [[ -f "$FRONTEND_DIR/package.json" ]]; then
  cd "$FRONTEND_DIR"
  BUILD_OUTPUT=$(npm run build 2>&1) || {
    echo "GUARD FAIL: Build failed"
    echo "$BUILD_OUTPUT" | tail -10
    exit 1
  }
fi

echo "GUARD PASS"
exit 0
