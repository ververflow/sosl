# Writing Effective Directives

The directive is the most important file in a SOSL domain. It determines the quality of Claude's hypotheses and the effectiveness of the optimization loop.

## Required Sections

### 1. Objective
Clear, specific, one-sentence goal. Include the current score and target.

```markdown
## Objective
Improve the Lighthouse Performance score. Current: **{{CURRENT_SCORE}}** / 100.
```

### 2. Scope — ALLOWED
Exhaustive list of what Claude may do. Be specific about directories, file types, and techniques.

```markdown
## Scope — ALLOWED
- Dynamic imports for heavy components in `frontend/src/components/`
- Image optimization with `next/image` in `frontend/src/app/`
- CSS optimization in `frontend/src/app/globals.css`
```

### 3. Scope — FORBIDDEN
Exhaustive list of what Claude must NOT do. This prevents Goodhart gaming.

```markdown
## Scope — FORBIDDEN
- Do NOT delete features, pages, or components
- Do NOT modify test files
- Do NOT add eslint-disable comments
```

### 4. Strategy
Guide Claude's hypothesis generation. Without this, Claude tries random things.

```markdown
## Strategy
1. Check which Lighthouse audits are failing
2. Fix the audit with the highest impact first
3. One change per iteration
```

## Dynamic Placeholders

These are replaced at runtime by sosl.sh:

| Placeholder | Replaced with |
|-------------|---------------|
| `{{CURRENT_SCORE}}` | Current baseline score |
| `{{ITERATION}}` | Current iteration number |
| `{{MAX_ITERATIONS}}` | Total iterations configured |
| `{{RECENT_RESULTS}}` | Last 3 experiment results from JSONL |
| `{{SCOPE_GUIDANCE}}` | Temperature phase (EXPLORATION/REFINEMENT/POLISHING) |
| `{{SESSION_CONTEXT}}` | Living session: recent strategies, dead ends, key wins |
| `{{STRATEGY_MODE}}` | Mode-specific guidance: DRAFT / DEBUG / IMPROVE |

## Tips

- **Be specific about what "better" means.** "Improve performance" is vague. "Reduce Largest Contentful Paint below 2.5s" is actionable.
- **The FORBIDDEN section is your Goodhart defense.** If you can imagine a way Claude could game the metric, forbid it explicitly.
- **Include context.** Link to relevant code, mention the tech stack, note known issues. More context = better hypotheses.
- **Strategy > Freedom.** A constrained agent that follows a strategy outperforms an unconstrained agent that tries random things.
