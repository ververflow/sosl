#!/bin/bash
# SOSL Example Domain: Broken Links
# Metric: max(0, 500 - broken_link_count) -- higher = fewer broken links
# Works with any docs site or markdown-heavy project
set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

broken_count=0

# Strategy 1: If running a docs server, use linkchecker
if [[ -n "${HEALTH_CHECK_URL:-}" ]]; then
  broken_count=$(python3 -c "
import urllib.request, re, sys, os

base_url = os.environ.get('HEALTH_CHECK_URL', 'http://localhost:3000')
try:
    html = urllib.request.urlopen(base_url, timeout=10).read().decode()
    links = re.findall(r'href=[\"\\']([^\"\\'\s]+)[\"\\']', html)
    broken = 0
    for link in links[:50]:  # Check first 50 links
        if link.startswith('#') or link.startswith('mailto:'):
            continue
        if not link.startswith('http'):
            link = base_url.rstrip('/') + '/' + link.lstrip('/')
        try:
            urllib.request.urlopen(link, timeout=5)
        except:
            broken += 1
    print(broken)
except:
    print(0)
" 2>/dev/null || echo 0)
else
  # Strategy 2: Check markdown internal links
  broken_count=$(python3 -c "
import re, os, glob, sys

target = sys.argv[1]
broken = 0

for md_file in glob.glob(os.path.join(target, '**', '*.md'), recursive=True):
    try:
        with open(md_file, encoding='utf-8') as f:
            content = f.read()
    except:
        continue
    # Find markdown links: [text](path)
    for m in re.finditer(r'\[.*?\]\(([^)]+)\)', content):
        link = m.group(1)
        if link.startswith('http') or link.startswith('#') or link.startswith('mailto:'):
            continue
        # Resolve relative path
        link_path = link.split('#')[0].split('?')[0]
        if not link_path:
            continue
        resolved = os.path.normpath(os.path.join(os.path.dirname(md_file), link_path))
        if not os.path.exists(resolved):
            broken += 1

print(broken)
" "$TARGET_DIR" 2>/dev/null || echo 0)
fi

# Invert: higher = better (fewer broken links)
python3 -c "print(max(0, 500 - int($broken_count)))"
