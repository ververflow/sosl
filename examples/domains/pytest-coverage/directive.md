# Test Coverage Optimization

## Objective
Increase pytest test coverage for this Python project.
Current coverage: **{{CURRENT_SCORE}}%**. Target: as high as possible.

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

{{STRATEGY_MODE}}

## Secondary Metrics (tradeoff monitors -- do not optimize these, but avoid degrading them)
{{SECONDARY_METRICS}}

## Session History
{{SESSION_CONTEXT}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope -- ALLOWED
- Add new test files for untested modules
- Add test cases for uncovered branches and edge cases
- Add parametrized tests for functions with multiple code paths
- Improve existing tests to cover more lines
- Add fixtures and helpers that enable better testing

## Scope -- FORBIDDEN
- Do NOT modify the source code being tested (only add/modify test files)
- Do NOT add `# pragma: no cover` or `# type: ignore` comments
- Do NOT write trivial tests that just call a function without assertions
- Do NOT mock everything -- test real behavior where practical
- Do NOT install new packages

## CRITICAL -- Completeness Rule
Every test must be self-contained. All imports must resolve. All fixtures must exist.
If you create a conftest.py, ensure it's in the right directory.

## Strategy
1. Identify the module with the lowest coverage
2. Write meaningful tests for its most important functions
3. Focus on edge cases and error paths, not just happy path
4. One module per iteration
