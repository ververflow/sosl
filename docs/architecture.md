# SOSL Architecture

## The 5-Level Structure

### Level 0: Atomic Change (nano)
One git commit. One or a few file modifications. Covered by contra-metric guards.

### Level 1: REFITA Loop (micro)
A single iteration of the optimization cycle:

```
Run      → Claude makes one targeted change
Eval     → Measure the target metric (median of N samples)
Fix      → If metric worsened or guard failed: git revert
Iterate  → If metric improved: git commit, update baseline
Test     → Verify contra-metrics (guards) aren't violated
Annotate → Log the experiment to JSONL for future iterations
```

### Level 2: Self-Annealing (meso)
Scope temperature across iterations within a single run:

- **0-33% of iterations**: EXPLORATION — larger architectural changes welcome
- **33-66%**: REFINEMENT — moderate, targeted changes only
- **66-100%**: POLISHING — small micro-optimizations only

Plus: circuit breaker (stagnation detection stops the loop when no progress is being made).

### Level 3: SOSL Night Run (macro)
One domain, one branch, one overnight session:

```
Configure → Write directive.md, choose metric and guards
Launch    → bash sosl.sh --domain ... --target ... --max-hours 8
Sleep     → SOSL runs 20-50 iterations autonomously
Review    → Morning: review the git branch, merge improvements
```

### Level 4: Parallel SOSL (system)
Multiple domains optimizing simultaneously:

```
Orchestrator → Create git worktrees per domain
               Launch sosl.sh instances in parallel
               Each instance: independent branch, independent measurements
Review       → Morning: 3-4 branches of improvements ready for merge
```

## Core Contracts

### measure.sh
- Takes one argument: target directory path
- Outputs a single number to stdout (higher = better)
- Exit 0 on success, non-zero on failure
- Must be deterministic (same code → same score, within noise margin)
- Must run in < 120 seconds for practical iteration speed

### guard.sh
- Takes one argument: target directory path
- Exit 0 = all checks pass (safe to measure)
- Exit 1 = guard violation (reason on stdout, changes will be reverted)
- Guards are binary: either the change is safe or it isn't

### directive.md
- Markdown file with instructions for Claude
- Must define: objective, allowed scope, forbidden scope, strategy
- Dynamic placeholders replaced at runtime: `{{CURRENT_SCORE}}`, `{{ITERATION}}`, `{{MAX_ITERATIONS}}`, `{{RECENT_RESULTS}}`, `{{SCOPE_GUIDANCE}}`

## State Management

SOSL is **stateless per iteration**: each Claude call is a fresh subprocess with no session memory. All state lives on disk:

- `.sosl/experiments.jsonl` — append-only experiment log (survives crashes)
- `.sosl/checkpoint.json` — current iteration + baseline (enables resume)
- `.sosl/SUMMARY.md` — human-readable summary (generated after completion)
- Git history — the commits themselves are the primary record

## Safety Layers

1. **Git branch isolation** — never touches main
2. **Guard rails** — domain-specific + universal (file count, test deletion, eslint-disable)
3. **Statistical confidence** — only commits improvements that exceed the noise floor
4. **Circuit breakers** — stops on: time limit, cost limit, stagnation
5. **Tool whitelist** — Claude only gets access to Read, Edit, Write, and safe Bash commands
