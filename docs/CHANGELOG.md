# CHANGELOG

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
