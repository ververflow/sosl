# Accessibility Optimization Directive

## Objective
Improve the Lighthouse Accessibility score for this Next.js application.
Current score: **{{CURRENT_SCORE}}** / 100. Target: 95+.

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

{{STRATEGY_MODE}}

## Secondary Metrics (tradeoff monitors -- do not optimize these, but avoid degrading them)
{{SECONDARY_METRICS}}

## Session History
{{SESSION_CONTEXT}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope — ALLOWED
You may modify files in `frontend/` to improve accessibility:
- **ARIA attributes**: add missing roles, labels, descriptions
- **Semantic HTML**: replace divs with proper elements (nav, main, section, article, aside)
- **Color contrast**: ensure sufficient contrast ratios (WCAG AA: 4.5:1 for normal text, 3:1 for large)
- **Focus management**: add focus styles, ensure keyboard navigation works
- **Alt text**: add meaningful alt attributes to images
- **Form labels**: associate labels with form controls
- **Heading hierarchy**: ensure proper h1-h6 nesting
- **Link text**: replace "click here" with descriptive text

## Scope — FORBIDDEN
- Do NOT change the visual design or layout
- Do NOT modify backend code
- Do NOT modify or delete test files
- Do NOT add eslint-disable comments
- Do NOT install new packages
- Do NOT change functionality or behavior

## Strategy
1. Check which Lighthouse accessibility audits are failing
2. Fix the audit with the highest impact first
3. One fix per iteration
4. Prefer semantic HTML fixes over ARIA patches (ARIA is a last resort)
