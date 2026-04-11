# Getting Started with SOSL

SOSL optimizes any software metric autonomously. This guide takes you from first run to advanced usage.

## The 3-Step Formula

Every SOSL run needs three things:

```
1. measure.sh  → prints a number (higher = better)
2. guard.sh    → exits 0 if code is safe, 1 if broken
3. directive.md → tells Claude what to optimize and what's off-limits
```

That's it. The framework handles everything else: statistical confidence, session memory, tree search, judge review.

---

## Level 1: First Run (5 minutes)

Use a built-in domain on a JavaScript/TypeScript project.

### Prerequisites
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed (`claude --version`)
- Python 3.8+
- Git
- Node.js (for JS/TS domains)

### Run it

```bash
# Clone SOSL
git clone https://github.com/ververflow/sosl.git
cd sosl

# Dry run first (no Claude calls, shows what SOSL would do)
bash sosl.sh \
  --domain domains/code-quality \
  --target /path/to/your-js-project \
  --max-iterations 3 \
  --dry-run

# Real run (3 iterations = ~5-15 minutes, ~$1-3)
bash sosl.sh \
  --domain domains/code-quality \
  --target /path/to/your-js-project \
  --max-iterations 3
```

### What happens

1. SOSL measures your ESLint error count (baseline)
2. Claude reads the directive and makes one code change
3. Guards check: TypeScript compiles? Tests pass? No cheating?
4. Re-measures: fewer errors? If yes, commit. If no, revert.
5. Repeats 3 times with session memory (learns from each attempt)

### Review the results

```bash
cd /path/to/your-js-project
cat .sosl/JUDGE_REPORT.md          # Judge's review
git log --oneline sosl/code-quality/*  # What was committed
git diff main..sosl/code-quality/*     # The actual changes
```

---

## Level 2: Your Own Metric (15 minutes)

Apply SOSL to any project by creating a custom domain.

### Step 1: Define your metric

What number do you want to improve? Examples:
- Test coverage percentage
- Lint error count (inverted)
- Build time (inverted)
- API response time (inverted)
- Documentation completeness score

**Rule: the number must go UP when things get better.** If your raw metric goes down when things improve (like error count or build time), invert it: `max(0, CEILING - value)`.

### Step 2: Create the three files

Create a directory in your project:

```bash
mkdir -p .sosl/domains/my-metric
```

**measure.sh** -- must print ONE number to stdout:
```bash
#!/bin/bash
set -euo pipefail
cd "${1:-.}"

# Example: test pass rate (uses python3 for portability — works on Windows Git Bash)
python3 -c "
import subprocess, re
result = subprocess.run(['python', '-m', 'pytest', '--tb=no', '-q'],
                        capture_output=True, text=True)
last_line = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ''
passed = int(m.group(1)) if (m := re.search(r'(\d+) passed', last_line)) else 0
failed = int(m.group(1)) if (m := re.search(r'(\d+) failed', last_line)) else 0
total = passed + failed
print(round(passed * 100 / total, 1) if total > 0 else 0)
"
```

**guard.sh** -- must exit 0 if safe:
```bash
#!/bin/bash
set -euo pipefail
cd "${1:-.}"

# Your project's "does it still work?" check
python -m pytest --tb=short -q || { echo "GUARD FAIL: tests broke"; exit 1; }
echo "GUARD PASS"
```

**directive.md** -- tells Claude the rules:
```markdown
# My Metric Optimization

## Objective
Improve [YOUR METRIC] for this project.
Current score: **{{CURRENT_SCORE}}**. Target: as high as possible.

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

## Scope -- ALLOWED
- [What Claude CAN change]

## Scope -- FORBIDDEN
- [What Claude must NOT touch]
- Do NOT add suppression comments
- Do NOT install new packages

## Strategy
1. [How Claude should approach this]
```

### Step 3: Run

```bash
bash /path/to/sosl/sosl.sh \
  --domain .sosl/domains/my-metric \
  --target . \
  --max-iterations 5
```

SOSL auto-detects your stack (Node, Python, Rust, Go) and applies appropriate guards.

---

## Level 3: Overnight Run (set and forget)

Once you've verified SOSL works on your project with 3-5 iterations, scale up.

```bash
bash sosl.sh \
  --domain .sosl/domains/my-metric \
  --target /path/to/project \
  --search tree \
  --max-iterations 30 \
  --max-hours 8 \
  --max-cost 20.00 \
  --health-check http://localhost:3000
```

### What's different at scale

- **Tree search** (`--search tree`): instead of stopping when stuck, backtracks to a previous promising state and tries a different approach. 2-4x more effective than linear.
- **Session memory**: Claude learns from every attempt. Dead ends are marked. What worked is highlighted.
- **Strategy modes**: IMPROVE (normal), DEBUG (fix guard failures), DRAFT (try something completely new when stuck).
- **Judge Agent**: after the loop, a fresh-context Claude reviews all commits and produces an APPROVE/REJECT verdict.
- **Circuit breakers**: automatically stops on time limit, cost limit, or exhausted frontier.

### Morning review

```bash
cd /path/to/project

# 1. Read the Judge's verdict
cat .sosl/JUDGE_REPORT.md

# 2. See the tree (if tree search)
cat .sosl/SUMMARY.md

# 3. Review changes
git log --oneline sosl/my-metric/*
git diff main..sosl/my-metric/*

# 4. Merge if satisfied
git merge sosl/my-metric/<timestamp>
```

---

## Level 4: Multi-Domain Optimization

Optimize multiple metrics simultaneously. Each runs in its own worktree, independent.

```bash
bash sosl-parallel.sh \
  --target /path/to/project \
  --domains "code-quality,bundle-size,accessibility" \
  --max-iterations 20 \
  --max-hours 8
```

Result: 3 branches of improvements, one per metric. Review and merge independently.

### Secondary metrics (tradeoff monitoring)

Add to your domain's config.sh:
```bash
# config.sh
SECONDARY_DOMAINS="bundle-size,code-quality"
```

SOSL will measure these after each improvement and warn if they degrade. Claude sees the warnings and adjusts its strategy.

---

## Level 5: Branch Finalization

After a tree search run with many commits, use `--finalize` to create independent cherry-pickable branches:

```bash
bash sosl.sh \
  --domain .sosl/domains/my-metric \
  --target /path/to/project \
  --search tree \
  --max-iterations 30 \
  --finalize
```

SOSL groups commits that share files and creates `final-1`, `final-2`, etc. branches. Each can be merged independently -- review and accept what you want, reject what you don't.

```bash
# See the groups
cat .sosl/FINALIZED.md

# Merge just group 1
git merge sosl/my-metric/<timestamp>-final-1
```

---

## Level 6: Optimizing Non-Code Content

SOSL works on anything in files -- not just software code. Prompts, skills, configs, documentation, and data pipelines can all be optimized if you can measure quality with a number.

### The Pattern: Wrap in a Temp Git Repo

Content that doesn't live in a git repo (like Claude Code skills, standalone configs, or prompt files) needs a thin wrapper:

```bash
# 1. Create a temp git repo with your content
mkdir -p /tmp/optimize-target
cp -r ~/.claude/skills/my-skill/* /tmp/optimize-target/
cd /tmp/optimize-target && git init && git add -A && git commit -m "baseline"

# 2. Run SOSL
bash /path/to/sosl/sosl.sh \
  --domain /path/to/sosl/examples/domains/skill-quality \
  --target /tmp/optimize-target \
  --max-iterations 5

# 3. Review
cat .sosl/JUDGE_REPORT.md
git diff main..sosl/skill-quality/*

# 4. Copy back if satisfied
cp SKILL.md ~/.claude/skills/my-skill/SKILL.md
```

### Example: Optimize a Claude Code Skill

Claude Code skills are markdown files with YAML frontmatter. SOSL's `skill-quality` domain scores them on structure (5pts), clarity (5pts), completeness (5pts), and frontmatter (5pts).

```bash
# Copy skill to workspace
mkdir -p /tmp/skill-opt && cd /tmp/skill-opt
cp ~/.claude/skills/my-skill/SKILL.md .
git init && git add -A && git commit -m "baseline"

# Check current score
bash /path/to/sosl/examples/domains/skill-quality/measure.sh .
# Output: 12 (out of 20)

# Run SOSL to improve it
bash /path/to/sosl/sosl.sh \
  --domain /path/to/sosl/examples/domains/skill-quality \
  --target . \
  --max-iterations 5

# Score should be higher now
bash /path/to/sosl/examples/domains/skill-quality/measure.sh .
# Output: 18 (out of 20)
```

### Example: Optimize Configuration Files

```bash
# Webpack config → measure build size
mkdir -p /tmp/config-opt && cd /tmp/config-opt
cp /path/to/project/webpack.config.js .
git init && git add -A && git commit -m "baseline"

# Use build-speed or a custom domain
bash /path/to/sosl/sosl.sh \
  --domain /path/to/sosl/examples/domains/build-speed \
  --target . \
  --max-iterations 5
```

### Example: Optimize Prompts / Templates

For prompt optimization, create a custom measure.sh that:
1. Runs the prompt through Claude with test inputs
2. Scores the output against binary eval criteria
3. Returns the score

```bash
# measure.sh for a prompt
#!/bin/bash
set -euo pipefail
cd "${1:-.}"

# Run prompt with 3 test cases, score each
score=$(python3 -c "
import subprocess, json

prompt = open('prompt.md').read()
tests = ['test input 1', 'test input 2', 'test input 3']
total = 0

for test in tests:
    r = subprocess.run(
        ['claude', '-p', f'{prompt}\n\nInput: {test}'],
        capture_output=True, text=True, timeout=60)
    out = r.stdout
    # Binary criteria (each yes = 1 point)
    total += int(len(out) > 50)        # substantial output
    total += int(len(out) < 2000)      # not runaway
    total += int('error' not in out.lower())  # no error messages

print(total)  # max = 9 (3 criteria x 3 tests)
")
echo "$score"
```

Note: dynamic prompt testing uses Claude API calls for measurement, so costs ~$0.50-2 per iteration. Use `--samples 1` to minimize measurement cost.

### When to Use This Pattern

| Content type | Measure with | Cost |
|-------------|-------------|------|
| Claude skills | `skill-quality` domain (static) | Free |
| Prompts/templates | Custom eval with Claude calls | ~$1/iteration |
| Config files | Build speed or output quality | Free (build) |
| Documentation | `broken-links` domain | Free |
| Data pipelines | Processing time or output quality | Varies |

---

## Example Domains (copy and adapt)

SOSL ships with ready-to-use example domains:

| Domain | Stack | Metric | Copy from |
|--------|-------|--------|-----------|
| **skill-quality** | Claude skills | Structural quality score | `examples/domains/skill-quality/` |
| **pytest-coverage** | Python | Test coverage % | `examples/domains/pytest-coverage/` |
| **lint-score** | Any (autodetect) | Lint errors (inverted) | `examples/domains/lint-score/` |
| **build-speed** | Any (autodetect) | Build time (inverted) | `examples/domains/build-speed/` |
| **broken-links** | Docs/Markdown | Broken links (inverted) | `examples/domains/broken-links/` |
| **performance** | Next.js | Lighthouse score | `domains/performance/` |
| **accessibility** | Next.js | Lighthouse a11y | `domains/accessibility/` |
| **code-quality** | JS/TS | ESLint errors | `domains/code-quality/` |
| **bundle-size** | Next.js | Build size | `domains/bundle-size/` |

To use an example:
```bash
# Copy to your project
cp -r /path/to/sosl/examples/domains/lint-score .sosl/domains/lint-score

# Edit directive.md for your specific project
# Then run
bash /path/to/sosl/sosl.sh --domain .sosl/domains/lint-score --target .
```

---

## Tips for Writing Good Domains

### Measure.sh

- **One number, stdout, higher = better.** That's the entire contract.
- **Deterministic > noisy.** ESLint count: exact. Lighthouse score: varies 30 points. Start deterministic.
- **Fast > thorough.** Each iteration measures 5 times. If measure.sh takes 60s, that's 5 minutes per iteration just measuring.
- **Invert when needed.** Error count: `max(0, 1000 - errors)`. Build time: `max(0, 300 - seconds)`.

### Guard.sh

- **Guards are more important than the metric.** A good metric with bad guards produces creative garbage. A mediocre metric with good guards produces safe improvements.
- **Test the minimum.** Does it compile? Do tests pass? Did it stay in scope? That's enough.
- **Fast guards first.** Syntax check (ms) before full build (minutes).

### Directive.md

- **Be specific about scope.** "Improve performance" is vague. "Reduce Largest Contentful Paint by optimizing images and code splitting in `src/pages/`" is actionable.
- **FORBIDDEN section is your Goodhart defense.** If you can imagine Claude gaming the metric, forbid it.
- **Include the placeholders.** `{{CURRENT_SCORE}}`, `{{RECENT_RESULTS}}`, `{{SESSION_CONTEXT}}`, `{{STRATEGY_MODE}}` give Claude context from previous iterations.

---

## Troubleshooting

### "All measurements failed"
Your measure.sh isn't printing a number. Test it manually:
```bash
bash .sosl/domains/my-metric/measure.sh /path/to/project
# Should print a single number
```

### "Guard failed" on every iteration
Your guard.sh is too strict, or the project has pre-existing issues. Test:
```bash
bash .sosl/domains/my-metric/guard.sh /path/to/project
echo $?  # Should be 0
```

### "No significant improvement" on every iteration
The noise floor is eating your improvements. Either:
- Your metric is too noisy (try a more deterministic metric)
- The improvements are too small (lower `MIN_NOISE_FLOOR` in config.sh)
- Claude is making changes that don't actually help (check the session.md for patterns)

### Claude keeps retrying the same thing
Session memory should prevent this. Check `.sosl/session.md` -- are dead ends being recorded? If yes, your directive might be too vague (Claude doesn't know what else to try).

### Tree search stays on one branch
Increase `--max-children` (default: 3) or check if the best node is significantly better than alternatives. Tree search is greedy -- it always expands the highest-scoring node.
