# CHANGELOG

## Next: v0.6.0 — Scale & Polish

### Planned
- [ ] Judge Agent: fresh-context Claude instance reviews SOSL's commits before marking as ready
- [ ] Branch finalization: group commits into independent, reviewable changesets
- [ ] Secondary metrics tracking (tradeoff monitoring alongside primary metric)
- [ ] Project-local domain overrides: `your-project/.sosl/domains/performance/`
- [ ] Generic guards that auto-detect stack (Next.js vs Vite vs Python etc.)
- [ ] Scheduler: cron or `claude --schedule` to run SOSL nightly on multiple projects
- [ ] GitHub Actions workflow for cloud-based runs (no local machine needed overnight)

---

## v0.8.0 — Branch Finalization (April 11, 2026)

After a SOSL run, commits that touch overlapping files are grouped into independent changesets — each can be merged or rejected separately.

### What changed
- **`lib/finalize.sh`**: union-find algorithm groups commits by shared files. Creates `sosl/.../final-N` branches from main with cherry-picked commits.
- **`--finalize` flag**: opt-in (skipped when only 1 commit). Runs after summary, before Judge.
- **`.sosl/FINALIZED.md`**: human-readable report with groups, files, merge commands.
- **`.sosl/finalization.json`**: machine-readable for tooling.

### Why this matters
Tree search can produce 10+ commits across multiple paths. Cherry-picking individual commits risks conflicts when they touch shared files. Finalization groups them so each group is independently mergeable — review and merge what you want, reject what you don't.

### Source leveraged
- **pi-autoresearch** (`autoresearch-finalize`): independent commit grouping from merge-base

---

## v0.7.0 — Project Scalability (April 11, 2026)

SOSL is no longer locked to Next.js/TypeScript. Two changes unlock any project:

### What changed
- **Project-local domain overrides**: drop `.sosl/domains/<domain>/` in your target repo with directive.md + measure.sh + guard.sh. SOSL checks there first, falls back to built-in. No forking needed.
- **Stack-aware guards**: auto-detects Node, Python, Rust, Go from marker files. Three-layer guard architecture: universal (file count, scope, deletions) → stack-specific (suppression comments, dependency checks, test patterns) → domain-specific (tsc, build, tests).
- **Guard modules** (`lib/guards/`): node.sh, python.sh, rust.sh, go.sh. Each exports `run_stack_guards()` with stack-appropriate checks.
- **`detect_stack()`**: checks package.json, pyproject.toml, Cargo.toml, go.mod (including monorepo patterns like `frontend/package.json`).

### Why this matters
SOSL was feature-complete but only worked on Next.js/TS. Now any project with a measurable metric can use SOSL: Python ML pipelines (pytest score), Rust binaries (compile time), Go services (benchmark throughput). Users define their own domains without touching the framework.

---

## v0.6.0 — Secondary Metrics (April 11, 2026)

SOSL now monitors tradeoffs across domains. When optimizing performance, it also checks bundle size and code quality — warning if the primary metric improves at the cost of others.

### What changed
- **Secondary metrics** (`lib/secondary.sh`): cross-domain tradeoff monitoring. Reuses existing domain measure.sh scripts (zero new measurement code).
- **`SECONDARY_DOMAINS` config**: set in domain config.sh (e.g., `SECONDARY_DOMAINS="bundle-size,code-quality"`). Runs 1 sample per secondary domain after each committed improvement.
- **`{{SECONDARY_METRICS}}` placeholder**: injected into Claude's prompt so it can factor tradeoffs into its strategy.
- **JSONL tracking**: secondary scores stored in experiment log for post-hoc analysis.
- **Informational only**: secondary metrics warn but never block commits. The primary metric still drives optimization.

### Why this matters
SOSL's #1 production problem is Goodhart's Law. Guards catch broken code, but not legitimate tradeoffs (performance improves because bundle grew, or code quality drops because types were loosened). Secondary metrics make these tradeoffs visible — both to Claude (via prompt) and to humans (via experiment log and warnings).

### Sources leveraged
- **AIDE/Weco** (multi-metric tracking): primary + secondary metrics alongside
- **pi-autoresearch** (secondary metrics in experiment log): tradeoff monitoring per iteration

---

## v0.5.0 — Judge Agent (April 11, 2026)

SOSL now includes a fresh-context code reviewer that runs after the optimization loop. The Judge Agent reviews all commits, experiment history, and code diff, then produces an APPROVE / REQUEST CHANGES / REJECT verdict.

### What changed
- **Judge Agent** (`lib/judge.sh`): post-loop review with fresh-context Claude. Read-only tools (Read, Glob, Grep, git commands). Produces `.sosl/JUDGE_REPORT.md`.
- **Judge directive** (`domains/judge/directive.md`): review checklist covering score validity, scope compliance, guard patterns, completeness, session learning, and search quality.
- **`--no-judge` flag**: skip the review when not needed (e.g., dry runs, quick tests).
- **Non-blocking**: Judge verdict is logged but doesn't destroy the branch. Human makes the final call.

### Why this matters
Guards catch broken code, but not subtler issues: scope creep, Goodhart gaming that passes guards, incomplete refactors that don't break types, or commits that contradict each other. The Judge provides a second opinion from a fresh perspective — no context carryover from the optimization loop means no shared blind spots.

---

## v0.4.0 — Tree Search (April 11, 2026)

SOSL can now explore multiple paths through the solution space instead of following a single linear chain. When an approach stalls, it backtracks to a previous promising state and tries a different direction.

### What changed
- **Tree search mode** (`--search tree`): greedy best-first exploration. Each successful commit becomes a node; the frontier is all expandable leaves. SOSL always expands the highest-scoring node.
- **`lib/tree.sh`**: complete tree data structure — init, select, add node, record failure, switch branch, ancestor-scoped session context, mode detection, visualization.
- **Git branch-per-node**: each improvement creates a new branch (`sosl/domain/timestamp/node_id`). Single worktree, branches switched via `git checkout`.
- **Tree-scoped context**: Claude sees only its ancestor path + sibling summaries. Dead ends from the current path are injected; unrelated branches are excluded.
- **Tree-scoped mode detection**: 2+ failures on a node triggers DRAFT; last guard fail triggers DEBUG. Independent per node, not global.
- **Tree-aware summary**: `SUMMARY.md` includes ASCII tree visualization, best path, and merge instructions.
- **Backward compatible**: `--search linear` (default) keeps the existing linear loop untouched.
- **New CLI flags**: `--search`, `--max-children` (default: 3), `--max-depth` (default: 5).

### Why this matters
Linear search stops when stagnation hits — but stagnation at depth 15 doesn't mean there's nothing left at depth 8 with a different approach. Tree search (from AIDE research, arXiv 2502.13138) reports 4x improvement over linear on benchmarks by reusing promising solutions and exploring alternatives.

### Sources leveraged
- **AIDE/Weco** (tree search algorithm): greedy best-first, three-mode operator, atomic changes
- **pi-autoresearch** (session persistence): ancestor-scoped context enables per-branch learning

---

## v0.3.0 — Iteration Intelligence (April 11, 2026)

SOSL now learns within a run. Each iteration builds on structured knowledge of what was tried, what failed, and what worked — instead of starting blind every time.

### What changed
- **Living session document** (`lib/session.sh`): `.sosl/session.md` tracks strategies tried, dead ends (don't retry), and key wins (what works) across iterations. Injected into Claude's prompt via `{{SESSION_CONTEXT}}`.
- **Strategy modes** (`lib/strategy.sh`): each iteration runs as DRAFT (fresh approach), DEBUG (fix guard failure), or IMPROVE (incremental refinement). Inspired by AIDE's three-mode operator.
- **Mode detection logic**: guard fail → DEBUG, repeated guard fails → DRAFT, stagnation ≥ 4 → DRAFT, normal → IMPROVE. High stagnation overrides everything.
- **Strategy extraction**: Claude's output is parsed for `STRATEGY:` lines to capture what was attempted — stored in experiments.jsonl and session.md.
- **Enhanced experiment log**: `mode` and `strategy` fields added to JSONL entries.
- **Enhanced prompt**: new `{{SESSION_CONTEXT}}` and `{{STRATEGY_MODE}}` placeholders in all domain directives.

### Why this matters
Without session memory, Claude retries the same failed approach because it has no memory of previous iterations beyond recent scores. With session memory:
- Dead ends are explicitly marked — Claude won't retry approaches that hit guard failures
- Successful strategies are highlighted — Claude builds on what works
- Mode-specific prompts give targeted instructions (fix the error vs. try something new)
- The strategy modes map to AIDE's research: different situations need fundamentally different prompting strategies

### Sources leveraged
- **pi-autoresearch** (`autoresearch.md`): living session document pattern
- **AIDE/Weco** (three-mode operator): DRAFT/DEBUG/IMPROVE distinction
- **Ralph** (circuit breaker + response analysis): stuck-loop detection via pattern analysis

---

## v0.2.0 — Post-Audit Hardening (April 8, 2026)

Tested on HoutCalc (Next.js 16 + FastAPI SaaS). Two runs exposed critical issues, all fixed.

### What changed
- **Windows path resolution**: Git Bash `/c/Dev/` → `cygpath -w` → `C:\Dev\` for Python. Experiment log and checkpoints now work on Windows.
- **Noise threshold**: default samples 3→5, per-domain `MIN_NOISE_FLOOR` config (Lighthouse: 3.0). Prevents committing measurement noise.
- **Guard safety**: only clear `tsconfig.tsbuildinfo`, not `.next` (was crashing the dev server mid-run).
- **Dangling import detector**: universal guard that checks all `@/` imports resolve to existing files. Catches Claude's most common failure mode.
- **Suppression blocking**: guards now catch `@ts-ignore` and `@ts-expect-error` in addition to `eslint-disable`.
- **Directive hardening**: completeness rule, steer toward in-place optimizations.
- **CLAUDE.md**: comprehensive project guide with hard-won rules from production use.
- **README.md**: corrected docs, added onboarding guide, production lessons section.

### Lessons learned
1. **Goodhart's Law manifests on run 1.** Lighthouse score improved because broken import = less JS loaded. Guards caught it after hardening.
2. **tsc cache causes false positives.** Must clear `tsconfig.tsbuildinfo` before every guard check.
3. **Lighthouse on dev servers varies 29 points.** Fixed with 5 samples + MIN_NOISE_FLOOR=3.0 → variance dropped to 3 points.
4. **Claude creates incomplete refactors.** Moves code to new file, forgets to create the file. Dangling import detector is mandatory.

---

## v0.1.0 — First Implementation (April 8, 2026)

Initial working implementation of the SOSL framework.

### What's included
- Core loop runner (`sosl.sh`) with full REFITA cycle
- Eval harness with MAD-based statistical confidence
- 4 built-in domains: performance, accessibility, code-quality, bundle-size
- Contra-metric guard system (universal + per-domain)
- Scope temperature (exploration → refinement → polishing)
- State persistence with checkpoint/resume
- JSONL experiment logging
- Parallel orchestrator via git worktrees
- HoutCalc example config

### Key design decisions made during implementation
- **External bash loop over Claude /loop**: `/loop` dies with the session; external loop survives and supports resume
- **python3 for all math/JSON**: no jq/bc dependency — Windows Git Bash compatible
- **measure.sh outputs a single number**: simplest possible contract, higher = better
- **guard.sh is binary**: exit 0 or exit 1, no scoring — either it's safe or it isn't
- **Scope temperature over score temperature**: controlling change magnitude is safer than accepting regressions

---

## Pre-release: Design Evolution

All design phases completed in a single day — rapid prototyping from braindump to architecture lock.

### v3 — Architecture Lock (April 8, 2026)
Critical additions from research synthesis:
- **Runtime isolation**: git worktrees aren't enough — parallel instances need separate ports, caches, DBs
- **Temperature schedule debate**: decided scope-based (change magnitude) over score-based (accepting worse scores) — software metrics are discontinuous, not smooth like ML metrics
- **Judge Agent concept**: fresh-context agent reviews work of optimization agents (deferred to post-v1)
- **5-level structure**: nano (commit) → micro (REFITA) → meso (annealing) → macro (night run) → system (parallel)
- **Context rot as primary risk**: fully stateless per iteration via subprocess calls, all state to disk

### v2 — Pattern Synthesis (April 8, 2026)
Deep analysis of reference implementations revealed:
- **REFITA**: added Annotate step to REFIT — the difference between a system that repeats mistakes and one that learns
- **Contra-metric guards**: operationalized Goodhart's Law protection with specific guard per domain
- **Development-first metrics**: all measurement must work locally with headless tools (Lighthouse CI, Playwright, ESLint) — no production data dependency
- **Context rot**: identified as the #1 risk for long-running loops — old failed hypotheses corrupt agent reasoning
- **Statistical confidence**: adopted MAD-based noise floor from pi-autoresearch — prevent committing measurement noise

### v1 — Core Concept (April 8, 2026)
Translated Karpathy's autoresearch to software applications:
- Named the framework: **SOSL (Self-Optimizing Software Loop)**
- Defined the metrics matrix per domain (performance, UI/UX, onboarding, code quality, bugs)
- Designed loop control: hard limits, circuit breakers, dual-condition exit gates
- Proposed parallel multi-domain architecture with hub-and-spoke orchestration
- Identified the eval function as the critical differentiator: "the eval harness is the product, not the loop"

### v0 — Raw Braindump (April 8, 2026)
The initial idea that started it all:
- "What if Claude Code optimized my software overnight while I sleep?"
- Inspired by Karpathy's autoresearch, Nick Saraev's advanced Claude Code patterns, and the REFIT framework
- Core insight: anything measurable can be autonomously optimized by an agent that self-corrects on that measurement
- Vision: parallel instances optimizing every axis of software quality simultaneously
