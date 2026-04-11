# Adding Custom Domains

SOSL domains are modular: 3 files define a complete optimization target.

## Option A: Project-Local Domain (recommended)

Drop your domain in your project's `.sosl/domains/` directory. SOSL checks there first, no forking needed:

```bash
mkdir -p your-project/.sosl/domains/my-metric
# Create measure.sh, guard.sh, directive.md there
# Then:
bash sosl.sh --domain domains/my-metric --target your-project
# SOSL auto-discovers .sosl/domains/my-metric/ in the target
```

## Option B: Domain in SOSL Repo

For reusable domains you want to share across projects:

```bash
mkdir -p domains/your-domain
```

## Step 2: Write measure.sh

Your measurement script must:
- Accept one argument: the target directory path
- Output a **single number** to stdout (higher = better)
- Exit 0 on success, non-zero on failure
- Complete in under 120 seconds (for practical iteration speed)
- Be deterministic: same code should produce the same score (within noise margin)

```bash
#!/bin/bash
set -euo pipefail
TARGET_DIR="${1:-.}"

# Your measurement logic here
# Must print a single number to stdout
echo "42.5"
```

**Important**: if your metric is "lower = better" (like error count or latency), invert it:
```bash
ERRORS=$(count_errors)
python3 -c "print(max(0, 1000 - int($ERRORS)))"
```

## Step 3: Write guard.sh

Your guard script must:
- Accept one argument: the target directory path
- Exit 0 if the changes are safe
- Exit 1 if the changes should be reverted (print reason to stdout)

```bash
#!/bin/bash
set -euo pipefail
TARGET_DIR="${1:-.}"

# Run smoke tests
cd "$TARGET_DIR"
npm test 2>&1 || {
  echo "GUARD FAIL: Tests failed"
  exit 1
}

echo "GUARD PASS"
exit 0
```

## Step 4: Write directive.md

See [writing-directives.md](writing-directives.md) for the full guide. Minimum template:

```markdown
# [Domain] Optimization Directive

## Objective
[What to optimize]. Current: **{{CURRENT_SCORE}}**. Target: [goal].

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

{{STRATEGY_MODE}}

## Secondary Metrics
{{SECONDARY_METRICS}}

## Session History
{{SESSION_CONTEXT}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope — ALLOWED
[What Claude may change]

## Scope — FORBIDDEN
[What Claude must NOT change]

## Strategy
[How to approach optimization]
```

## Step 5: Optional config.sh

Add a config.sh for domain-specific settings:

```bash
# config.sh
MIN_NOISE_FLOOR=0.5           # Minimum threshold for significance (Lighthouse: 3.0)
ALLOWED_PATHS="src/*"          # Restrict Claude to these paths
SECONDARY_DOMAINS="lint-score" # Monitor tradeoff metrics
MAX_NET_DELETIONS=100          # Max net lines deleted per iteration
MEASURE_TIMEOUT=120            # Seconds before measure.sh times out
```

## Step 6: Test it

```bash
# Test measure.sh standalone
bash domains/your-domain/measure.sh /path/to/target
# Should output a number

# Test guard.sh standalone
bash domains/your-domain/guard.sh /path/to/target
# Should exit 0 with "GUARD PASS"

# Dry run
bash sosl.sh --domain domains/your-domain --target /path/to/target --max-iterations 3 --dry-run
```

## Domain Ideas

| Domain | Metric | measure.sh approach |
|--------|--------|---------------------|
| API latency | p95 response time | k6/autocannon benchmark, inverted |
| Test coverage | Line coverage % | `vitest --coverage`, parse JSON |
| Build speed | Build time in seconds | `time npm run build`, inverted |
| SEO | Lighthouse SEO score | Lighthouse CI |
| Security headers | Security header count | curl + count headers |
| Dead code | Unused export count | ts-prune, inverted |
| Image weight | Total image KB | find + du, inverted |
