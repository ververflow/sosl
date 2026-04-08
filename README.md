# SOSL — Self-Optimizing Software Loop

> Point an AI agent at a metric. Go to sleep. Wake up with improvements.

SOSL translates [Karpathy's autoresearch pattern](https://github.com/karpathy/autoresearch) from ML training to **software applications**. It runs Claude Code in an autonomous loop overnight, measures a specific quality metric after each change, commits improvements, and reverts regressions — so your software gets better while you sleep.

## How it Works

```
You write:     directive.md  (what to optimize, what's off-limits)
               measure.sh   (outputs a single score — higher = better)
               guard.sh     (smoke tests that must pass)

SOSL runs:     ┌──────────────────────────────────────┐
               │  1. Measure baseline (median of 5)    │
               │  2. Claude makes ONE targeted change  │
               │  3. Guards check (types, imports, etc)│
               │  4. Re-measure (median of 5)          │
               │  5. Improved beyond noise floor?       │
               │     Yes → git commit                  │
               │     No  → git revert                  │
               │  6. Repeat until done                 │
               └──────────────────────────────────────┘

You review:    A git branch full of validated improvements.
```

This is the **REFITA loop**: **R**un → **E**val → **F**ix → **I**terate → **T**est → **A**nnotate.

## Features

- **Git ratchet** — only improvements survive; regressions are reverted instantly
- **Statistical confidence** — median of 5 measurements with MAD-based noise floor; no committing measurement noise
- **Contra-metric guards** — prevent [Goodhart's Law](https://en.wikipedia.org/wiki/Goodhart%27s_law) gaming (e.g., can't improve perf by deleting features)
- **Dangling import detection** — catches Claude's most common failure: referencing files it never created
- **Scope temperature** — early iterations explore boldly, later iterations polish carefully
- **Crash recovery** — JSONL experiment log + checkpoints; resume interrupted runs
- **Parallel domains** — optimize performance, accessibility, code quality, and bundle size simultaneously via git worktrees
- **Zero dependencies** — pure bash + python3 (stdlib only); no npm/pip install for the framework itself
- **Windows compatible** — works in Git Bash on Windows (path conversion, no jq/bc dependency)

## Quick Start

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` command available)
- Python 3.8+ (stdlib only)
- Git
- Node.js (for Lighthouse/ESLint domains)

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
# 3. Start your project's dev servers
#    SOSL measures against localhost — your app must be running

# 4. Dry-run first (no Claude calls, just prints prompts)
bash sosl.sh \
  --domain domains/performance \
  --target /path/to/your-nextjs-app \
  --max-iterations 3 \
  --dry-run

# 5. Real run (start small — 3 iterations)
bash sosl.sh \
  --domain domains/performance \
  --target /path/to/your-nextjs-app \
  --health-check http://localhost:3000 \
  --max-iterations 3

# 6. Review what SOSL did
cd /path/to/your-nextjs-app
git log --oneline sosl/performance/*
git diff main..sosl/performance/<timestamp>

# 7. If satisfied, scale up (overnight run)
bash sosl.sh \
  --domain domains/performance \
  --target /path/to/your-nextjs-app \
  --health-check http://localhost:3000 \
  --max-iterations 30 \
  --max-hours 8 \
  --max-cost 20.00
```

### Where SOSL writes

SOSL writes everything into **your project**, not into the SOSL repo:

```
your-project/                          ← the repo you pointed --target at
├── .sosl/
│   ├── experiments.jsonl              ← log of all iterations (tried, scores, costs)
│   └── checkpoint.json                ← crash recovery (deleted after clean exit)
├── main                               ← UNTOUCHED — SOSL never commits to main
└── sosl/<domain>/<timestamp>          ← branch with validated improvement commits
```

The SOSL framework itself is never modified by a run — it's a tool you point at projects.

### After each run

Review and decide:

```bash
cd /path/to/your-project

# See what SOSL committed
git log --oneline sosl/<domain>/*

# Full diff against main
git diff main..sosl/<domain>/<timestamp>

# Merge if satisfied
git checkout main && git merge sosl/<domain>/<timestamp>

# Or delete if not
git branch -D sosl/<domain>/<timestamp>
```

## Built-in Domains

| Domain | Metric | Guard | Best for |
|--------|--------|-------|----------|
| `performance` | Lighthouse Performance (0-100) | TypeScript + imports + build | Next.js/React apps |
| `accessibility` | Lighthouse Accessibility (0-100) | TypeScript | Any web app |
| `code-quality` | ESLint errors (inverted) | TypeScript + Vitest | Any TS/JS project |
| `bundle-size` | .next build size (inverted) | Build success + page count | Next.js apps |

## Custom Domains

Create a new domain in 3 files:

```
domains/your-domain/
├── directive.md    # What to optimize and what's off-limits
├── measure.sh      # Must print a single number (higher = better)
├── guard.sh        # Must exit 0 if safe, exit 1 if not
└── config.sh       # Optional: MIN_NOISE_FLOOR, other settings
```

**measure.sh** contract:
```bash
#!/bin/bash
set -euo pipefail
TARGET_DIR="${1:-.}"
# Your measurement here — must print ONE number to stdout
echo "42.5"
```

**guard.sh** contract:
```bash
#!/bin/bash
set -euo pipefail
TARGET_DIR="${1:-.}"
# Your checks here — exit 1 with reason to revert changes
cd "$TARGET_DIR" && npm test || { echo "GUARD FAIL: tests broke"; exit 1; }
echo "GUARD PASS"
```

See [docs/adding-domains.md](docs/adding-domains.md) for the full guide and [docs/writing-directives.md](docs/writing-directives.md) for prompt tips.

## Configuration

```bash
# All flags
bash sosl.sh \
  --domain domains/performance \   # Required: which domain
  --target /path/to/repo \         # Required: repo to optimize
  --config examples/config.conf \  # Optional: load from file
  --max-iterations 50 \            # Default: 50
  --max-hours 10 \                 # Default: 10
  --max-cost 25.00 \               # Default: 25.00 USD
  --budget-per-iter 1.00 \         # Default: 1.00 USD per Claude call
  --samples 5 \                    # Default: 5 (measurements per eval)
  --model claude-sonnet-4-5 \      # Default: claude-sonnet-4-5
  --health-check http://localhost:3000 \  # Optional: URL check before start
  --resume \                       # Resume from checkpoint
  --dry-run                        # Print prompts, don't call Claude
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
| **Micro** | REFITA loop | Single iteration: measure → change → verify → commit/revert |
| **Meso** | Self-annealing | Scope temperature: explore → refine → polish |
| **Macro** | SOSL night run | One domain, one branch, hours of autonomous optimization |
| **System** | Parallel SOSL | Multiple domains via worktrees |

See [docs/architecture.md](docs/architecture.md) for the full breakdown.

## Lessons from Production Use

SOSL has been tested on [HoutCalc](https://houtcalc.nl) (Next.js 16 + FastAPI SaaS). Key findings:

- **Guards are the product, not the loop.** The loop is trivial. The guards determine whether SOSL commits good code or broken code. Invest time in guards first.
- **Goodhart's Law manifests immediately.** First run: Lighthouse score improved because a broken import meant less JavaScript loaded. The "improvement" was actually broken code. Contra-metric guards (TypeScript check, import resolution, build check) caught this after we hardened them.
- **Lighthouse on dev servers is noisy.** Scores varied 29 points on the same code. Fixed with 5 samples + MIN_NOISE_FLOOR=3.0. Variance dropped to 3 points.
- **Claude creates incomplete refactors.** It will move code to a new file but forget to create the file. The dangling import detector in `lib/guard.sh` catches this.

## Born From

SOSL builds on the shoulders of:
- [karpathy/autoresearch](https://github.com/karpathy/autoresearch) — the original autonomous experiment loop
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — intelligent exit detection for Claude Code loops
- [davebcn87/pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) — statistical confidence scoring for software metrics
- [WecoAI/weco-cli](https://github.com/WecoAI/weco-cli) — decoupled evaluation framework

## License

MIT — [VerverFlow Innovations](https://ververflow.nl)
