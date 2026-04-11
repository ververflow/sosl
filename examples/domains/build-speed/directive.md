# Build Speed Optimization

## Objective
Reduce build time for this project.
Current score: **{{CURRENT_SCORE}}** (inverted: higher = faster build). Target: maximize.

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
- Optimize import structure (reduce circular dependencies)
- Add incremental build configuration
- Reduce unnecessary file processing (exclude patterns)
- Optimize compiler/bundler configuration
- Remove dead code that slows compilation
- Add caching configuration where applicable

## Scope -- FORBIDDEN
- Do NOT change runtime behavior or functionality
- Do NOT remove features to speed up the build
- Do NOT skip type checking or linting steps
- Do NOT modify test files
- Do NOT install new packages

## Strategy
1. Profile what takes the most time in the build
2. Target the slowest step first
3. One optimization per iteration
4. Verify the build output is identical (same functionality)
