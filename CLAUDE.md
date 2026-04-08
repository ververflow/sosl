# SOSL — Self-Optimizing Software Loop

## What this is
Framework for autonomous software optimization using Claude Code. Runs overnight, measures a metric, commits improvements, reverts regressions.

## Stack
- Pure bash + python3 (no npm/pip dependencies for the framework itself)
- Claude Code CLI (`claude -p`) for AI-driven code changes
- Git for version control and ratchet mechanism

## Structure
- `sosl.sh` — main loop runner
- `sosl-parallel.sh` — multi-domain orchestrator
- `lib/` — shared libraries (eval, confidence, guards, checkpoint, annotate, temperature)
- `domains/` — per-domain configs (directive.md, measure.sh, guard.sh)
- `docs/` — documentation
- `examples/` — example configs

## Conventions
- All bash scripts use `set -euo pipefail`
- All math/JSON via `python3 -c` (no jq/bc — Windows Git Bash compatible)
- measure.sh contract: exit 0, print single number to stdout (higher = better)
- guard.sh contract: exit 0 = pass, exit 1 = fail (reason on stdout)
- Line endings: LF only (enforced by .gitattributes)

## Commands
```bash
bash sosl.sh --help                    # Show usage
bash sosl.sh --domain domains/performance --target /path/to/repo --dry-run  # Test without Claude
bash sosl.sh --domain domains/performance --target /path/to/repo            # Run optimization
```
