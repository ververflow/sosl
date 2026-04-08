# Performance Optimization Directive

## Objective
Improve the Lighthouse Performance score for this Next.js application.
Current score: **{{CURRENT_SCORE}}** / 100. Target: as high as possible.

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope — ALLOWED
You may modify files in `frontend/` to improve performance:
- **Bundle optimization**: code splitting, dynamic imports (`next/dynamic`), tree shaking
- **Image optimization**: `next/image`, lazy loading, WebP/AVIF format, proper sizing
- **CSS optimization**: remove unused styles, critical CSS, reduce Tailwind output
- **JavaScript optimization**: reduce main thread work, defer non-critical scripts, remove unused deps
- **Font optimization**: subset fonts, `font-display: swap`, preload critical fonts
- **Caching & headers**: configure `next.config.ts` for optimal caching
- **Component optimization**: memoization, virtualization for large lists, reduce re-renders

## Scope — FORBIDDEN
Do NOT do any of the following:
- Delete pages, components, or features (optimization must preserve all functionality)
- Change the visual appearance of the application
- Modify backend code (`backend/` directory)
- Modify or delete test files (`e2e/`, `*.test.*`, `*.spec.*`)
- Change environment variables or deployment configuration
- Add `eslint-disable`, `@ts-ignore`, or `@ts-expect-error` comments
- Install new npm packages (optimize with what's available)
- Modify `package.json` dependencies

## CRITICAL — Completeness Rule
Every change must be **self-contained and complete**. After your changes:
- All imports must point to files that exist
- If you extract code to a new file, you MUST create that file
- If you move a function, update ALL callers
- Run `npx tsc --noEmit` mentally before finishing — would it pass?
- Incomplete refactors (referencing files you didn't create) will be automatically reverted

## Strategy
1. Focus on the **lowest-scoring Lighthouse audit** first (check the audit details)
2. Make **one targeted change** per iteration — not sweeping rewrites
3. Prefer changes with the highest impact-to-risk ratio
4. If previous experiments show a pattern of what works, build on it
5. If previous experiments show a pattern of what fails, avoid repeating it
6. Prefer **in-place optimizations** over file restructuring (less risk of incomplete changes)

## Output
After making your change, briefly state:
- What you changed and why
- Which Lighthouse audit you targeted
- Expected impact
