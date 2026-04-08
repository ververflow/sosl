# Code Quality Optimization Directive

## Objective
Reduce ESLint errors and warnings in this Next.js frontend codebase.
Current score: **{{CURRENT_SCORE}}** (inverted: higher = fewer errors). Target: maximize.

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope — ALLOWED
You may modify TypeScript/TSX files in `frontend/src/` to fix lint issues:
- **Fix actual code issues**: unused variables, missing return types, type errors
- **Improve code patterns**: replace `any` with proper types, add missing imports
- **Clean up**: remove dead code, unused imports, unreachable code
- **Type safety**: add missing type annotations, fix type mismatches

## Scope — FORBIDDEN
- Do NOT add `eslint-disable` comments (that's gaming the metric)
- Do NOT add `@ts-ignore` or `@ts-expect-error`
- Do NOT change functionality or behavior
- Do NOT modify test files
- Do NOT modify backend code
- Do NOT change the ESLint configuration
- Do NOT install new packages

## Strategy
1. Run ESLint mentally to identify the most common error category
2. Fix one category of errors per iteration (e.g., all unused imports, or all missing return types)
3. Verify the fixes don't change behavior
