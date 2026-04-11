# Bundle Size Optimization Directive

## Objective
Reduce the Next.js production bundle size.
Current score: **{{CURRENT_SCORE}}** (inverted: higher = smaller bundle). Target: maximize.

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

{{STRATEGY_MODE}}

## Session History
{{SESSION_CONTEXT}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope — ALLOWED
You may modify files in `frontend/` to reduce bundle size:
- **Dynamic imports**: `next/dynamic` for heavy components (3D viewers, charts, editors)
- **Tree shaking**: replace barrel imports with direct imports (`import { X } from 'lib/X'`)
- **Dead code removal**: remove unused exports, components, utilities
- **Dependency analysis**: find and remove unused imports from heavy libraries
- **Image optimization**: ensure images use `next/image` with proper sizing
- **CSS purging**: ensure Tailwind purges unused styles

## Scope — FORBIDDEN
- Do NOT remove features or pages
- Do NOT change visual appearance
- Do NOT modify backend code or test files
- Do NOT remove npm packages from package.json
- Do NOT add eslint-disable comments

## Strategy
1. Analyze which modules contribute most to bundle size
2. Target the largest unnecessary inclusion first
3. Prefer dynamic imports for components not needed on initial load
4. One change per iteration
