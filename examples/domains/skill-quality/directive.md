# Skill Quality Optimization

## Objective
Improve the quality of this Claude Code skill definition.
Current quality score: **{{CURRENT_SCORE}}** / 20. Target: maximize.

The score measures: frontmatter completeness (5pts), structure (5pts), clarity (5pts), and completeness (5pts).

## Iteration Context
- Iteration: {{ITERATION}} of {{MAX_ITERATIONS}}
- {{SCOPE_GUIDANCE}}

{{STRATEGY_MODE}}

## Session History
{{SESSION_CONTEXT}}

## Previous Experiments
{{RECENT_RESULTS}}

## Scope -- ALLOWED
- Improve YAML frontmatter (add missing fields: name, description, argument-hint)
- Add clear section structure (h2/h3 headings, tables)
- Add examples (code blocks showing input → output)
- Add output format specification (what the skill should produce)
- Add scope boundaries (what the skill should NOT do)
- Add error handling instructions (what to do when input is ambiguous)
- Improve scannability (bold keywords, bullet points, tables)
- Reduce verbosity (cut redundant paragraphs, tighten instructions)

## Scope -- FORBIDDEN
- Do NOT change the skill's core purpose or behavior
- Do NOT remove working functionality
- Do NOT add external dependencies or tool requirements
- Do NOT change the skill name or trigger patterns
- Do NOT fabricate examples with fake data
- Do NOT make the skill longer than 2000 words (verbosity hurts Claude's instruction-following)

## CRITICAL -- Completeness Rule
Every section you add must be complete. Every example must be realistic.
Every reference must point to something that exists.

## Scoring Breakdown
Improve whichever category has the most room:
- **Frontmatter (0-5)**: name, description, user-invocable, argument-hint, and valid YAML
- **Structure (0-5)**: h1 title, 2+ h2 sections, h3 subsections, tables
- **Clarity (0-5)**: 100-2000 words, code blocks, bullet points, bold keywords
- **Completeness (0-5)**: output format, scope boundaries, error handling, no TODOs, trigger guidance

## Strategy
1. Read the current SKILL.md and mentally score each category
2. Identify the lowest-scoring category
3. Make targeted improvements to that category
4. One category per iteration
