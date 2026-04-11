# Broken Links Optimization

## Objective
Fix broken internal links in this project's documentation.
Current score: **{{CURRENT_SCORE}}** (inverted: higher = fewer broken links). Target: maximize.

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

{{STRATEGY_MODE}}

## Secondary Metrics
{{SECONDARY_METRICS}}

## Session History
{{SESSION_CONTEXT}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope -- ALLOWED
- Fix broken internal links in markdown files (wrong paths, missing anchors)
- Update moved/renamed file references
- Fix relative path issues (../ navigation)
- Add missing anchor targets for fragment links
- Fix image paths that don't resolve

## Scope -- FORBIDDEN
- Do NOT change the content or meaning of documentation
- Do NOT delete documentation files
- Do NOT restructure the docs hierarchy (only fix links within current structure)
- Do NOT modify source code files
- Do NOT add external links

## Strategy
1. Find the file with the most broken links
2. Fix all broken links in that file
3. One file per iteration
4. Verify fixed links actually resolve to existing files
