# SOSL — Self-Optimizing Software Loop

> Point an AI agent at a metric. Go to sleep. Wake up with improvements.

SOSL translates [Karpathy's autoresearch pattern](https://github.com/karpathy/autoresearch) from ML training to **software applications**. It runs Claude Code in an autonomous loop overnight, measures a specific quality metric after each change, commits improvements, and reverts regressions — so your software gets better while you sleep.

## How it Works

```
You write:     directive.md  (what to optimize, what's off-limits)
               measure.sh   (outputs a single score — higher = better)
               guard.sh     (smoke tests that must pass)

SOSL runs:     ┌──────────────────────────────────────┐
               │  1. Measure baseline (median of N)    │
               │  2. Claude makes ONE targeted change  │
               │  3. Guards check (tests, types, etc.) │
               │  4. Re-measure (median of N)          │
               │  5. Improved? → git commit            │
               │     Not improved? → git revert        │
               │  6. Repeat until done                 │
               └──────────────────────────────────────┘

You review:    A git branch full of validated improvements.
```

This is the **REFITA loop**: **R**un → **E**val → **F**ix → **I**terate → **T**est → **A**nnotate.

## Features

- **Git ratchet** — only improvements survive; regressions are reverted instantly
- **Statistical confidence** — median of N measurements with MAD-based noise floor; no committing measurement noise
- **Contra-metric guards** — prevent [Goodhart's Law](https://en.wikipedia.org/wiki/Goodhart%27s_law) gaming (e.g., can't improve perf by deleting features)
- **Scope temperature** — early iterations explore boldly, later iterations polish carefully
- **Crash recovery** — JSONL experiment log + checkpoints; resume interrupted runs
- **Parallel domains** — optimize performance, accessibility, code quality, and bundle size simultaneously via git worktrees
- **Zero dependencies** — pure bash + python3 (stdlib only); no npm/pip install for the framework itself

## Quick Start

```bash
# 1. Clone SOSL
git clone https://github.com/your-username/sosl.git
cd sosl

# 2. Start your dev servers (SOSL measures against localhost)
# e.g.: bash /path/to/your-project/scripts/dev-start.sh

# 3. Run a single domain
bash sosl.sh \
  --domain domains/performance \
  --target /path/to/your-nextjs-app \
  --health-check http://localhost:3000 \
  --max-iterations 30 \
  --max-hours 8

# 4. Next morning: review the branch
cd /path/to/your-nextjs-app
git log sosl/performance/*  # See what SOSL found
```

## Built-in Domains

| Domain | Metric | Measurement | Guard |
|--------|--------|-------------|-------|
| `performance` | Lighthouse Performance (0-100) | Lighthouse CI headless | Playwright E2E smoke + TypeScript |
| `accessibility` | Lighthouse Accessibility (0-100) | Lighthouse CI headless | TypeScript compilation |
| `code-quality` | ESLint errors (inverted) | ESLint JSON output | TypeScript + Vitest |
| `bundle-size` | .next build size (inverted) | `npm run build` + `du` | Build success + page count |

## Parallel Optimization

Run multiple domains simultaneously, each in its own git worktree:

```bash
bash sosl-parallel.sh \
  --target /path/to/your-app \
  --domains "performance,accessibility,code-quality" \
  --max-iterations 20 \
  --max-hours 8
```

Wake up with 3 branches of improvements ready for review.

## Custom Domains

Create a new domain in 3 files:

```
domains/your-domain/
├── directive.md    # Instructions for Claude (what to optimize, scope limits)
├── measure.sh      # Must output a single number (higher = better)
└── guard.sh        # Must exit 0 if changes are safe, exit 1 if not
```

See [docs/adding-domains.md](docs/adding-domains.md) for the full guide.

## Configuration

All options can be set via CLI flags or a config file:

```bash
# Via config file
bash sosl.sh --config examples/houtcalc-perf.conf

# Via flags
bash sosl.sh \
  --domain domains/performance \
  --target /path/to/repo \
  --max-iterations 50 \
  --max-hours 10 \
  --max-cost 25.00 \
  --budget-per-iter 1.00 \
  --samples 3 \
  --model claude-sonnet-4-5 \
  --health-check http://localhost:3000
```

## Architecture

SOSL operates on 5 levels:

| Level | What | Scope |
|-------|------|-------|
| **Nano** | Atomic change | One git commit, one file modification |
| **Micro** | REFITA loop | Single iteration: measure → change → verify → commit/revert |
| **Meso** | Self-annealing | Scope temperature across iterations: explore → refine → polish |
| **Macro** | SOSL night run | One domain, one branch, 8 hours of autonomous optimization |
| **System** | Parallel SOSL | Multiple domains optimizing simultaneously via worktrees |

See [docs/architecture.md](docs/architecture.md) for the full breakdown.

## Requirements

- **Claude Code CLI** (`claude` command available)
- **Python 3.8+** (stdlib only, no packages needed)
- **Git** (for branch management and ratchet)
- **Node.js** (for Lighthouse CI, Playwright, ESLint — depending on domain)

## Born From

SOSL builds on the shoulders of:
- [karpathy/autoresearch](https://github.com/karpathy/autoresearch) — the original autonomous experiment loop
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — intelligent exit detection for Claude Code loops
- [davebcn87/pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) — statistical confidence scoring for software metrics
- [WecoAI/weco-cli](https://github.com/WecoAI/weco-cli) — decoupled evaluation framework

## License

MIT
