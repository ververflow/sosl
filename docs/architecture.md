# SOSL Architecture

## The 5-Level Structure

### Level 0: Atomic Change (nano)
One git commit. One or a few file modifications. Covered by contra-metric guards.

### Level 1: REFITA Loop (micro)
A single iteration of the optimization cycle:

```
Detect   → Choose strategy mode: DRAFT / DEBUG / IMPROVE (based on history)
Run      → Claude makes one targeted change (mode-specific prompt)
Eval     → Guards check first (types, imports, build). If fail → revert immediately
Fix      → Measure the target metric (median of N samples)
Iterate  → If improved beyond noise floor: git commit, update baseline. Else: revert
Test     → Contra-metric guards ran before measurement — no broken code gets scored
Annotate → Log the experiment to JSONL + update session document
```

Note: Guards run BEFORE measurement. This prevents Goodhart gaming — broken code
that happens to improve the metric score never reaches the commit decision.

**Strategy modes** (inspired by AIDE's three-mode operator):
- **IMPROVE**: default — incremental refinement, one targeted change
- **DEBUG**: previous iteration hit a guard failure — fix the specific issue
- **DRAFT**: stagnation or repeated failures — try a completely different approach

Mode detection priority: high stagnation (≥4) → DRAFT, last was guard fail → DEBUG (3+ consecutive → DRAFT), "no changes" → DRAFT if repeated, default → IMPROVE.

### Level 1.5: Session Memory (micro-meso bridge)
Cross-iteration learning within a single run:

```
.sosl/session.md tracks:
  - Strategies Tried:  what was attempted each iteration + result
  - Dead Ends:         approaches that hit guard failures (don't retry)
  - Key Wins:          approaches that produced improvements (build on these)
```

Session context is injected into each prompt via `{{SESSION_CONTEXT}}`. This prevents
Claude from retrying failed approaches and encourages building on what works.

### Level 2: Self-Annealing (meso)
Scope temperature across iterations within a single run:

- **0-33% of iterations**: EXPLORATION — larger architectural changes welcome
- **33-66%**: REFINEMENT — moderate, targeted changes only
- **66-100%**: POLISHING — small micro-optimizations only

Plus: circuit breaker (stagnation detection stops the loop when no progress is being made).

### Level 2.5: Tree Search (meso, `--search tree`)
Optional greedy best-first search over the solution space (inspired by AIDE/Weco):

```
Linear:  root -> A -> B -> C -> stall -> STOP
Tree:    root -> A -> B -> stall -> backtrack to A -> D -> E -> ...
```

Each successful commit becomes a **node** in a search tree. Failed attempts are recorded
but don't create nodes. The **frontier** is all expandable leaf nodes.

Selection: always expand the highest-scoring node (greedy best-first).
Backtracking: `git checkout` to the selected node's branch within the same worktree.
Session context: ancestor-scoped (Claude sees only the path from root to current node).
Mode detection: per-node (2+ failures on a node -> DRAFT, last failure was guard -> DEBUG).

State lives in `.sosl/tree.json`. Each node stores: id, parent, branch, score, depth, visits.
Branches named `sosl/${domain}/${timestamp}/${node_id}` (hierarchical).

### Level 2.75: Judge Agent (post-loop review)
After the optimization loop completes, a fresh-context Claude instance reviews everything:

```
Loop completes → write SUMMARY.md
                → collect context (experiments.jsonl, session.md, git diff, directive)
                → claude -p (read-only tools) reviews all commits
                → verdict: APPROVE / REQUEST CHANGES / REJECT
                → write .sosl/JUDGE_REPORT.md
```

The Judge has no context from the optimization run — it sees everything fresh. It checks:
score validity, scope compliance, guard patterns, code completeness, session learning,
and search quality (tree mode). Skip with `--no-judge`.

### Level 3: SOSL Night Run (macro)
One domain, one branch, one overnight session:

```
Configure → Write directive.md, choose metric and guards
Launch    → bash sosl.sh --domain ... --target ... --max-hours 8
Sleep     → SOSL runs 20-50 iterations autonomously
Judge     → Fresh-context review: APPROVE / REQUEST CHANGES / REJECT
Review    → Morning: review JUDGE_REPORT.md + the git branch, merge improvements
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

### guard.sh (domain-specific)
- Takes one argument: target directory path
- Exit 0 = all checks pass (safe to measure)
- Exit 1 = guard violation (reason on stdout, changes will be reverted)
- Guards are binary: either the change is safe or it isn't
- Runs AFTER universal and stack-specific guards

### Guard layers (lib/guard.sh)
Three layers execute in order — first failure stops:
1. **Universal** (any stack): file count limit, scope enforcement, deletion limit
2. **Stack-specific** (auto-detected): suppression comments, dependency checks, test patterns
   - Auto-detected from marker files: package.json → node, pyproject.toml → python, etc.
   - Modules in `lib/guards/`: node.sh, python.sh, rust.sh, go.sh
3. **Domain-specific**: the domain's guard.sh (tsc, build, tests, etc.)

### Project-local domain overrides
SOSL checks `$TARGET_DIR/.sosl/domains/$DOMAIN_NAME/` before using built-in domains.
If directive.md + measure.sh + guard.sh exist there, that version takes precedence.

### directive.md
- Markdown file with instructions for Claude
- Must define: objective, allowed scope, forbidden scope, strategy
- Dynamic placeholders replaced at runtime: `{{CURRENT_SCORE}}`, `{{ITERATION}}`, `{{MAX_ITERATIONS}}`, `{{RECENT_RESULTS}}`, `{{SCOPE_GUIDANCE}}`, `{{SESSION_CONTEXT}}`, `{{STRATEGY_MODE}}`

## State Management

SOSL is **stateless per iteration**: each Claude call is a fresh subprocess with no session memory. All state lives on disk:

- `.sosl/experiments.jsonl` — append-only experiment log with mode, strategy, and secondary metric fields (survives crashes)
- `.sosl/session.md` — living session document: strategies tried, dead ends, key wins (updated per iteration)
- `.sosl/checkpoint.json` — current iteration + baseline (enables resume)
- `.sosl/SUMMARY.md` — human-readable summary (generated after completion, both solo and parallel runs)
- `.sosl/last-audit.txt` — top failing Lighthouse audits (injected into Claude's prompt)
- Git history — the commits themselves are the primary record

## Safety Layers

1. **Git branch isolation** — never touches main
2. **Guard rails** — domain-specific + universal (file count, test deletion, eslint-disable)
3. **Statistical confidence** — only commits improvements that exceed the noise floor
4. **Circuit breakers** — stops on: time limit, cost limit, stagnation
5. **Tool whitelist** — Claude gets Read, Edit, Write, Glob, Grep, and scoped Bash (npm/npx/node/git status/diff/log only)
6. **Measurement timeout** — measure.sh calls timeout after 120s (configurable via MEASURE_TIMEOUT)
