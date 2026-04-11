# SOSL -- Self-Optimizing Software Loop

> Point an AI agent at a metric. Go to sleep. Wake up with improvements.

SOSL translates [Karpathy's autoresearch pattern](https://github.com/karpathy/autoresearch) from ML training to **software applications**. It runs Claude Code in an autonomous loop, measures a specific quality metric after each change, commits improvements, and reverts regressions -- so your software gets better while you sleep.

## How it Works

```
You write:     directive.md  (what to optimize, what's off-limits)
               measure.sh   (outputs a single score -- higher = better)
               guard.sh     (smoke tests that must pass)

SOSL runs:     1. Measure baseline (median of 5)
               2. Claude makes ONE targeted change
               3. Guards check (types, imports, build)
               4. Re-measure (median of 5)
               5. Improved beyond noise floor? Commit. Otherwise revert.
               6. Update session memory (what worked, what failed)
               7. Repeat -- with learning from previous iterations

You review:    A git branch full of validated improvements + a Judge report.
```

## What Makes SOSL Different

SOSL isn't just a loop around Claude. It incorporates patterns from the autoresearch ecosystem:

| Feature | Inspired by | What it does |
|---------|-------------|-------------|
| **Session memory** | [pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) | Tracks strategies tried, dead ends, key wins across iterations |
| **Strategy modes** | [AIDE/Weco](https://github.com/WecoAI/weco-cli) | DRAFT / DEBUG / IMPROVE -- different situations get different prompts |
| **Tree search** | [AIDE](https://arxiv.org/abs/2502.13138) | Greedy best-first exploration -- backtrack when stuck instead of stopping |
| **Judge Agent** | autoresearch ecosystem | Fresh-context Claude reviews all commits before you merge |
| **Secondary metrics** | AIDE + pi-autoresearch | Cross-domain tradeoff monitoring (Goodhart's Law defense) |
| **Contra-metric guards** | [Ralph](https://github.com/frankbria/ralph-claude-code) | Prevent metric gaming -- broken code that improves the score gets caught |
| **Statistical confidence** | pi-autoresearch | MAD-based noise floor -- only commits real improvements, not measurement noise |

## Quick Start

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` command available)
- Python 3.8+ (stdlib only)
- Git

All scripts are invoked with `bash sosl.sh` syntax -- no `chmod +x` needed.

### Setup

```bash
# 1. Clone SOSL
git clone https://github.com/ververflow/sosl.git
cd sosl

# 2. Verify it works
bash sosl.sh --help
source lib/confidence.sh && calculate_stats 58 60 57 59 61
# Should print: 59.0 1.0
```

### Run on your project

```bash
# 3. Start your project's dev servers (SOSL measures against localhost)

# 4. Dry-run first (no Claude calls, just prints prompts)
bash sosl.sh \
  --domain domains/code-quality \
  --target /path/to/your-app \
  --max-iterations 3 \
  --dry-run

# 5. Real run (start small -- 3 iterations)
bash sosl.sh \
  --domain domains/code-quality \
  --target /path/to/your-app \
  --max-iterations 3

# 6. Or use tree search for smarter exploration
bash sosl.sh \
  --domain domains/code-quality \
  --target /path/to/your-app \
  --search tree \
  --max-iterations 20
```

### After a run

```bash
cd /path/to/your-project

# See what SOSL committed
git log --oneline sosl/<domain>/*

# Read the Judge's review
cat .sosl/JUDGE_REPORT.md

# Full diff against main
git diff main..sosl/<domain>/<timestamp>

# Merge if satisfied
git checkout main && git merge sosl/<domain>/<timestamp>
```

## Built-in Domains

| Domain | Metric | Stack | Best for |
|--------|--------|-------|----------|
| `performance` | Lighthouse Performance (0-100) | Next.js | Web app speed |
| `accessibility` | Lighthouse Accessibility (0-100) | Next.js | WCAG compliance |
| `code-quality` | ESLint errors (inverted) | Any JS/TS | Code cleanup |
| `bundle-size` | .next build size (inverted) | Next.js | Smaller bundles |

**Start with `code-quality`, not `performance`.** Deterministic metrics beat noisy ones -- ESLint produces exact counts while Lighthouse varies 20-30 points on the same code.

## Custom Domains

SOSL works with **any measurable metric** on **any stack**. Create a domain in 3 files:

```
domains/your-domain/
  directive.md    # What to optimize and what's off-limits
  measure.sh      # Must print a single number (higher = better)
  guard.sh        # Must exit 0 if safe, exit 1 if not
  config.sh       # Optional: noise floor, allowed paths, secondary metrics
```

Or drop them in your target repo at `.sosl/domains/your-domain/` -- SOSL checks there first (no forking needed).

**measure.sh** contract:
```bash
#!/bin/bash
set -euo pipefail
TARGET_DIR="${1:-.}"
# Your measurement here -- must print ONE number to stdout
echo "42.5"
```

**guard.sh** contract:
```bash
#!/bin/bash
set -euo pipefail
TARGET_DIR="${1:-.}"
cd "$TARGET_DIR" && npm test || { echo "GUARD FAIL: tests broke"; exit 1; }
echo "GUARD PASS"
```

See [docs/adding-domains.md](docs/adding-domains.md) for the full guide and [docs/writing-directives.md](docs/writing-directives.md) for prompt tips.

### Example: Python test pass rate

```bash
# .sosl/domains/pytest-score/measure.sh
#!/bin/bash
set -euo pipefail
cd "${1:-.}"
result=$(python -m pytest --tb=no -q 2>&1 | tail -1)
passed=$(echo "$result" | grep -oP '\d+(?= passed)' || echo 0)
failed=$(echo "$result" | grep -oP '\d+(?= failed)' || echo 0)
total=$((passed + failed))
[[ $total -eq 0 ]] && echo 0 && exit 0
echo "scale=1; $passed * 100 / $total" | bc
```

## Configuration

```bash
bash sosl.sh \
  --domain domains/code-quality \    # Required: which domain
  --target /path/to/repo \           # Required: repo to optimize
  --search tree \                    # Search: linear (default) or tree (greedy best-first)
  --max-children 3 \                 # Tree: max attempts per node (default: 3)
  --max-depth 5 \                    # Tree: max tree depth (default: 5)
  --max-iterations 50 \              # Max iterations (default: 50)
  --max-hours 10 \                   # Max wall-clock hours (default: 10)
  --max-cost 25.00 \                 # Max total USD (default: 25.00)
  --budget-per-iter 1.00 \           # Max per Claude call (default: 1.00)
  --samples 5 \                      # Measurements per eval (default: 5)
  --model claude-sonnet-4-5 \        # Claude model (default: claude-sonnet-4-5)
  --health-check http://localhost:3000 \
  --no-judge \                       # Skip post-loop Judge review
  --config examples/template.conf \  # Load from config file
  --resume \                         # Resume from checkpoint
  --dry-run                          # Print prompts, don't call Claude
```

## Search Modes

### Linear (default)

Sequential optimization: each iteration builds on the last. Stops when stagnation hits.

```
root -> A -> B -> C -> stall -> STOP
```

### Tree (`--search tree`)

Greedy best-first search: when an approach stalls, backtrack to a previous promising state and try a different direction. AIDE research reports 4x improvement over linear.

```
root -> A -> B -> stall -> backtrack to A -> D -> E -> ...
```

Each successful commit becomes a node. The frontier is all expandable leaves. SOSL always expands the highest-scoring node.

After a tree run, SOSL prints an ASCII visualization:

```
root [62.3] "baseline" (2 failed) *
|-- n1 [65.1] "Removed imports" *
|   `-- n3 [67.2] "Dynamic imports" *
`-- n2 [61.0] "Code splitting"

* = best path
```

## Intelligence Layers

### Session Memory

SOSL maintains a living session document (`.sosl/session.md`) that tracks:
- **Strategies Tried**: what was attempted each iteration + result
- **Dead Ends**: approaches that hit guard failures (injected as "do NOT retry")
- **Key Wins**: approaches that produced improvements (injected as "build on these")

Claude sees this context in every prompt. No more retrying failed approaches.

### Strategy Modes

Each iteration runs in one of three modes (inspired by AIDE's three-mode operator):

| Mode | When | Prompt strategy |
|------|------|-----------------|
| **IMPROVE** | Normal case | Incremental refinement, one targeted change |
| **DEBUG** | Last iteration hit a guard failure | Fix the specific issue, keep the approach |
| **DRAFT** | Stagnation or repeated failures | Try a completely different approach |

### Scope Temperature

Early iterations explore boldly (EXPLORATION), middle iterations refine (REFINEMENT), late iterations polish (POLISHING).

## Safety Layers

1. **Git branch isolation** -- never touches main
2. **Three-layer guards** -- universal (file count, scope, deletions) + stack-specific (auto-detected: Node/Python/Rust/Go) + domain-specific (tsc, build, tests)
3. **Statistical confidence** -- median of 5 samples with MAD-based noise floor
4. **Circuit breakers** -- time limit, cost limit, stagnation (linear) or exhausted frontier (tree)
5. **Tool whitelist** -- Claude gets Read, Edit, Write, Glob, Grep, and scoped Bash only
6. **Judge Agent** -- fresh-context Claude reviews all commits before merge
7. **Secondary metrics** -- cross-domain tradeoff monitoring (Goodhart's Law defense)
8. **Measurement timeout** -- measure.sh calls timeout after 120s

### Stack-Aware Guards

SOSL auto-detects your stack and applies appropriate checks:

| Stack | Detected by | Suppression check | Dependency check | Test patterns |
|-------|-------------|-------------------|------------------|---------------|
| Node/TS | package.json | eslint-disable, ts-ignore | package.json | .test., .spec., e2e/ |
| Python | pyproject.toml | # noqa, # type: ignore | pyproject.toml, requirements.txt | test_*.py, _test.py |
| Rust | Cargo.toml | #[allow(...)] | Cargo.toml | tests/, _test.rs |
| Go | go.mod | //nolint | go.mod | _test.go |

## Where SOSL Writes

SOSL writes everything into **your project**, not into the SOSL repo:

```
your-project/
  .sosl/
    experiments.jsonl      # Log of all iterations (tried, scores, costs, strategies)
    session.md             # Living session: strategies, dead ends, wins
    tree.json              # Tree search state (--search tree only)
    SUMMARY.md             # Human-readable run summary
    JUDGE_REPORT.md        # Judge Agent's review + verdict
    checkpoint.json        # Crash recovery (deleted after clean exit)
  main                     # UNTOUCHED -- SOSL never commits to main
  sosl/<domain>/<timestamp>  # Branch with validated commits
```

## Parallel Optimization

Run multiple domains simultaneously, each in its own git worktree:

```bash
bash sosl-parallel.sh \
  --target /path/to/your-app \
  --domains "performance,accessibility,code-quality" \
  --max-iterations 20 \
  --max-hours 8
```

## Architecture

SOSL operates on 5 levels:

| Level | What | Scope |
|-------|------|-------|
| **Nano** | Atomic change | One git commit |
| **Micro** | REFITA loop | Detect mode -> change -> guard -> measure -> commit/revert -> annotate |
| **Micro+** | Session memory | Cross-iteration learning: strategies, dead ends, wins |
| **Meso** | Self-annealing | Scope temperature + tree search (backtracking, branching) |
| **Macro** | Night run | One domain, hours of autonomous optimization + Judge review |
| **System** | Parallel SOSL | Multiple domains via worktrees |

See [docs/architecture.md](docs/architecture.md) for the full breakdown.

## Lessons from Production Use

SOSL has been tested on [HoutCalc](https://houtcalc.nl) (Next.js 16 + FastAPI SaaS). Key findings:

- **Guards are the product, not the loop.** The loop is trivial. The guards determine whether SOSL commits good code or broken code.
- **Goodhart's Law manifests immediately.** First run: Lighthouse score improved because a broken import meant less JS. Secondary metrics and Judge Agent now catch this.
- **Deterministic metrics beat noisy metrics.** `code-quality` (ESLint) produced 4 correct commits in 5 iterations. `performance` (Lighthouse) produced 0 real improvements in 5 despite "improving" the score.
- **Session memory prevents loops.** Without it, Claude retries the same failed approach because each iteration starts blind. With dead end tracking, hit rate improved significantly.
- **Tree search beats linear when stuck.** Linear stops at stagnation. Tree backtracks and tries a different path from a promising ancestor node.

## Born From

SOSL builds on the shoulders of:
- [karpathy/autoresearch](https://github.com/karpathy/autoresearch) -- the original autonomous experiment loop
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) -- intelligent exit detection for Claude Code loops
- [davebcn87/pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) -- statistical confidence scoring, session persistence
- [WecoAI/weco-cli](https://github.com/WecoAI/weco-cli) -- tree search algorithm (AIDE), decoupled evaluation

## License

MIT -- [VerverFlow Innovations](https://ververflow.nl)
