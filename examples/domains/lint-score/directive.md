# Lint Score Optimization

## Objective
Reduce linting errors and warnings in this codebase.
Current score: **{{CURRENT_SCORE}}** (inverted: higher = fewer errors). Target: maximize.

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
- Fix actual code issues: unused variables, missing types, unreachable code
- Improve code patterns: replace `any` with proper types, add missing annotations
- Clean up: remove dead code, unused imports, deprecated patterns
- Fix formatting issues flagged by the linter

## Scope -- FORBIDDEN
- Do NOT add suppression comments (eslint-disable, noqa, #[allow], //nolint)
- Do NOT change functionality or behavior
- Do NOT modify test files
- Do NOT change the linter configuration
- Do NOT install new packages

## CRITICAL -- Completeness Rule
Every change must be self-contained. If you remove a variable, remove ALL references.
If you rename something, update ALL callers. Incomplete changes will be reverted.

## Strategy
1. Identify the most common error category
2. Fix one category per iteration (e.g., all unused imports, or all missing types)
3. Prefer fixes that don't change runtime behavior
