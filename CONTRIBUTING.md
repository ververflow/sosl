# Contributing

Thanks for taking an interest. PRs and issues are welcome.

## What SOSL is and isn't

SOSL is a thin loop. The loop itself is a few hundred lines of bash; the
intelligence lives in the **domain** files (`directive.md`, `measure.sh`,
`guard.sh`). Most useful contributions are new domains, not framework changes.

## Local setup

```bash
git clone https://github.com/ververflow/sosl.git
cd sosl

# Dry-run on any project — no Claude calls, just shows what SOSL would do
bash sosl.sh \
  --domain examples/domains/lint-score \
  --target /path/to/your-project \
  --max-iterations 3 \
  --dry-run
```

Requirements:
- Bash (works on Linux, macOS, and Windows Git Bash)
- Python 3.8+ (stdlib only — used for math/JSON, no pip deps)
- Git
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) on PATH for real runs

## Adding a domain

The fastest, most valuable contribution. A domain is three files:

```
your-domain/
  directive.md   # Tell Claude what to optimise and what's off-limits
  measure.sh     # Print ONE number to stdout (higher = better), exit 0
  guard.sh       # Exit 0 if safe, exit 1 if broken
  config.sh      # Optional: MIN_NOISE_FLOOR, allowed paths, secondary metrics
```

Drop it in `examples/domains/<your-domain>/` and open a PR. See
[`docs/adding-domains.md`](docs/adding-domains.md) and
[`docs/writing-directives.md`](docs/writing-directives.md) for the full guide.

## Code style

- Bash: `set -eo pipefail` in `sosl.sh`/`lib/utils.sh`, `set -euo pipefail`
  elsewhere. LF line endings (enforced by `.gitattributes`).
- Python (inside `python3 -c ...` blocks): keep them short, stdlib-only, no
  external dependencies.
- All math/JSON via `python3 -c` — no `jq`/`bc` (Git Bash compatibility).

## Running checks before a PR

```bash
# Syntax check every modified script
bash -n sosl.sh
bash -n lib/*.sh

# Run shellcheck if you have it installed
shellcheck sosl.sh sosl-parallel.sh lib/*.sh

# Dry-run on a small real project (3 iterations, no Claude calls)
bash sosl.sh --domain examples/domains/lint-score --target ../some-project --dry-run --max-iterations 3
```

## Submitting changes

1. For framework changes, open an issue first — the loop is intentionally
   small; new flags / behaviour need to justify their complexity cost.
2. For new domains, just open a PR — examples are additive and low-risk.
3. PR description: what changed, what problem it solves, and (for framework
   changes) a transcript of a 3-iteration dry-run on at least one domain.

## Out of scope

- Replacing the Claude CLI with a direct Anthropic API client — the CLI's
  tool-use loop is part of SOSL's value
- Adding a Python wrapper "for convenience" — bash is the contract
- A web UI — runs autonomously; if you need a UI, write your own
