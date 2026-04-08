# Adding Custom Domains

SOSL domains are modular: 3 files define a complete optimization target.

## Step 1: Create the domain directory

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

## Previous Experiments
{{RECENT_RESULTS}}

## Scope — ALLOWED
[What Claude may change]

## Scope — FORBIDDEN
[What Claude must NOT change]

## Strategy
[How to approach optimization]
```

## Step 5: Test it

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
