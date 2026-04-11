# SOSL — Self-Optimizing Software Loop

## What this is
Framework for autonomous software optimization using Claude Code. Runs overnight, measures a metric, commits improvements, reverts regressions. Open-source, meant to be forked and adapted.

## Stack
- Pure bash + python3 (no npm/pip dependencies for the framework itself)
- Claude Code CLI (`claude -p`) for AI-driven code changes
- Git for version control and ratchet mechanism

## Structure
```
sosl.sh                  # Main loop runner — the entry point for everything
sosl-parallel.sh         # Multi-domain orchestrator (worktree-based)
lib/
  utils.sh               # Logging, json_get, float math, path conversion, health checks
  eval.sh                # measure_robust: runs measure.sh N times, returns median + MAD
  confidence.sh          # calculate_stats, is_significant (MAD-based noise floor)
  guard.sh               # run_guards: universal + stack-specific + domain-specific guards
  guards/
    node.sh              # JS/TS: eslint-disable, @/ imports, package.json
    python.sh            # Python: noqa, type:ignore, pyproject.toml
    rust.sh              # Rust: #[allow], Cargo.toml
    go.sh                # Go: //nolint, go.mod
  checkpoint.sh          # save/load/clear checkpoint for crash recovery
  annotate.sh            # JSONL experiment log + summary generation
  temperature.sh         # Scope guidance: EXPLORATION → REFINEMENT → POLISHING
  session.sh             # Living session document: tracks strategies, dead ends, key wins
  strategy.sh            # Mode detection: DRAFT / DEBUG / IMPROVE per iteration
  tree.sh                # Tree search: greedy best-first exploration over solution space
  judge.sh               # Judge Agent: fresh-context post-loop review (APPROVE/REJECT)
  secondary.sh           # Secondary metrics: cross-domain tradeoff monitoring
  finalize.sh            # Branch finalization: group commits into cherry-pickable changesets
domains/                 # Each domain = directive.md + measure.sh + guard.sh + optional config.sh
  performance/           # Lighthouse Performance score
  accessibility/         # Lighthouse Accessibility score
  code-quality/          # ESLint error count (inverted)
  bundle-size/           # Next.js build size (inverted)
examples/
  nextjs-performance.conf # Example config for Next.js Lighthouse optimization
docs/
  CHANGELOG.md           # Evolution: braindump → v1 → v2 → v3 → implementation
  architecture.md        # 5-level structure (nano → micro → meso → macro → system)
  writing-directives.md  # How to write effective optimization prompts
  adding-domains.md      # How to create custom domains
```

## Contracts
These are the interfaces that make SOSL work. Get them wrong and the loop breaks.

**measure.sh**: takes target dir as arg, prints ONE number to stdout (higher = better), exit 0 on success. Must complete in < 120s. Median of N runs handles noise — each measure.sh run is a single sample.

**guard.sh**: takes target dir as arg, exit 0 = safe to measure, exit 1 = revert changes (print reason to stdout). Guards run BEFORE measurement — a guard failure means the change never gets measured.

**directive.md**: markdown prompt for Claude. Must contain: objective, allowed scope, forbidden scope, strategy. Uses `{{CURRENT_SCORE}}`, `{{ITERATION}}`, `{{MAX_ITERATIONS}}`, `{{RECENT_RESULTS}}`, `{{SCOPE_GUIDANCE}}`, `{{SESSION_CONTEXT}}`, `{{STRATEGY_MODE}}` placeholders.

**session.md** (auto-generated): living document in `.sosl/session.md` that tracks strategies tried, dead ends, and key wins across iterations. Injected into Claude's prompt via `{{SESSION_CONTEXT}}`. Prevents retrying failed approaches.

**strategy modes**: each iteration runs in one of three modes (inspired by AIDE's three-mode operator):
- **IMPROVE**: normal incremental optimization (default)
- **DEBUG**: previous iteration hit a guard failure — fix the specific issue
- **DRAFT**: stagnation or repeated failures — try a completely different approach

**tree.json** (auto-generated, `--search tree` only): search tree state in `.sosl/tree.json`. Flat node map with parent/child relationships, scores, branches. Each successful commit = new node. Failed attempts stored separately. Greedy best-first selection expands highest-scoring frontier node.

**Judge Agent** (`lib/judge.sh`): runs after the loop completes if there are improvements. Fresh-context Claude reviews all commits, experiment log, session history, and git diff. Produces `.sosl/JUDGE_REPORT.md` with APPROVE/REQUEST CHANGES/REJECT verdict. Read-only tools only. Skip with `--no-judge`.

**project-local domain overrides**: drop `.sosl/domains/<domain>/` in your target repo with directive.md + measure.sh + guard.sh. SOSL checks there first, falls back to built-in domains. No forking needed.

**stack-aware guards** (`lib/guard.sh` + `lib/guards/*.sh`): auto-detects the stack (Node, Python, Rust, Go) from marker files and applies appropriate checks (suppression comments, dependency additions, test deletions). Three layers: universal → stack-specific → domain-specific.

**secondary metrics** (`lib/secondary.sh`): cross-domain tradeoff monitoring. Set `SECONDARY_DOMAINS="bundle-size,code-quality"` in domain config.sh. After each committed improvement, runs each secondary domain's measure.sh once (1 sample). Warns if secondary metrics degrade. Informational only — does not block commits. Injected into Claude's prompt via `{{SECONDARY_METRICS}}`.

**config.sh**: optional per-domain config. Currently supports `MIN_NOISE_FLOOR` (default: 0.5, Lighthouse domains use 3.0).

## Hard-Won Rules (from real-world runs)

### Guards are the product, not the loop
The loop is 50 lines of bash. The guards are what make SOSL trustworthy. A metric improving while guards pass does NOT mean the change is good — it means the guards aren't paranoid enough yet.

### Always clear tsc incremental cache before checking
tsc uses cached results from `.tsbuildinfo`. If you don't clear it, tsc will pass on broken code because it's checking against a previous successful run. Clear `tsconfig.tsbuildinfo` only — NOT `.next` (that kills the dev server).

### Dangling import detection is mandatory for JS/TS
Claude's most common failure: move code to a new file but forget to create the file. The universal guard in `lib/guard.sh` checks all `@/` imports resolve to existing files. This catches broken references that tsc might miss due to caching.

### Deterministic metrics beat noisy metrics
`code-quality` (ESLint) produced 4 correct commits in 5 iterations. `performance` (Lighthouse) produced 0 real improvements despite "improving" the score — noise masked the truth. Always recommend `code-quality` or `bundle-size` as first domain for new users/projects.

### Lighthouse on dev servers is noisy
Scores vary 20-30 points on the same code depending on system load, server warmup, and Chrome state. Mitigations:
- Default 5 samples (not 3)
- `MIN_NOISE_FLOOR=3.0` for Lighthouse domains
- Ensure dev server is warm before starting SOSL

### Directive must steer away from risky patterns
Add a "completeness rule" to every directive: all imports must resolve, all callers must be updated, prefer in-place optimizations over file restructuring. Claude routinely creates incomplete refactors.

### Watch for Goodhart's Law
If the score improves but the code is broken, the metric is being gamed. Example: Lighthouse score went up because a broken import meant less JavaScript loaded. The contra-metric guards (tsc, build, import check) exist to catch this.

## Where SOSL writes (important!)

SOSL writes everything into the **target project**, never into the SOSL repo itself. After a run:

```
your-project/                        ← the repo being optimized
├── .sosl/
│   ├── experiments.jsonl            ← log of all iterations (what was tried, scores, costs)
│   └── checkpoint.json              ← crash recovery state (deleted after clean exit)
├── main                             ← UNTOUCHED — SOSL never commits to main
└── sosl/<domain>/<timestamp>        ← SOSL branch with validated commits
    ├── commit 1: sosl(code-quality): 983 → 984
    ├── commit 2: sosl(code-quality): 984 → 986
    └── ...
```

The SOSL framework repo is **never modified** by a run. It's a tool you point at projects.

**After a run, you review:**
- `git log sosl/<domain>/*` — what SOSL committed
- `git diff main..sosl/<domain>/<timestamp>` — the full diff
- `.sosl/experiments.jsonl` — what was tried including reverted attempts
- Then: merge the branch, cherry-pick specific commits, or delete it

## Conventions
- `sosl.sh` and `lib/utils.sh` use `set -eo pipefail` (no -u, trap handlers need unset vars)
- Domain scripts and `sosl-parallel.sh` use `set -euo pipefail` (they run independently)
- All math/JSON via `python3 -c` (no jq/bc — Windows Git Bash compatible)
- Path conversion: use `to_py_path` from utils.sh for any path passed to Python (Git Bash → Windows)
- Line endings: LF only (enforced by .gitattributes)
- Commits by SOSL: `sosl(<domain>): <old_score> → <new_score>`

## Commands
```bash
bash sosl.sh --help                                                          # Show usage
bash sosl.sh --domain domains/performance --target /path/to/repo --dry-run   # Test without Claude
bash sosl.sh --domain domains/performance --target /path/to/repo             # Run optimization
bash sosl.sh --config examples/nextjs-performance.conf                       # Run via config file
bash sosl-parallel.sh --target /path/to/repo --domains "performance,code-quality"  # Parallel
```

## Working on SOSL itself
When modifying the framework:
1. `bash -n <file>` — syntax check every modified script
2. Test path conversion: `source lib/utils.sh && to_py_path "/c/Dev/something"`
3. Test confidence: `source lib/confidence.sh && calculate_stats 58 60 57 59 61`
4. Dry-run before real run: `bash sosl.sh --domain domains/performance --target /path --dry-run --max-iterations 3`
5. Real run with low iteration count first (3), verify experiment log writes, then scale up
