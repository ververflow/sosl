# Dummy Score Directive (test fixture)

## Objective
Increase the number in `score.txt`. Current score: **{{CURRENT_SCORE}}**. Target: maximize.

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

{{STRATEGY_MODE}}

## Secondary Metrics (monitor, do not degrade)
{{SECONDARY_METRICS}}

## Session History
{{SESSION_CONTEXT}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope - ALLOWED
- Edit `score.txt`: increment the number by exactly 1
- Optionally add a `notes.md`

## Scope - OFF-LIMITS
- Every other file

## Strategy
1. Read `score.txt`
2. Increment the number by exactly 1
3. Run `git status` and mention its output in your reply
4. End with a line: STRATEGY: <one sentence on what you did>
