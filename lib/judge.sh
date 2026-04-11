#!/bin/bash
# SOSL -- Judge Agent: fresh-context post-loop code review
# Runs after the optimization loop completes. Reviews all commits
# and produces an APPROVE / REQUEST CHANGES / REJECT verdict.

# Run the Judge Agent to review SOSL's commits
# Usage: judge_review /target "performance" "sosl/perf/ts" 67.2 62.3 6 4.20 "linear"
# Returns: 0=approve, 1=request changes, 2=reject, 3=error
judge_review() {
  local target_dir="$1"
  local domain="$2"
  local branch="$3"
  local final_score="$4"
  local baseline_score="$5"
  local improvements="$6"
  local total_cost="$7"
  local search_mode="$8"

  local sosl_state_dir="$target_dir/.sosl"
  local judge_directive="$SCRIPT_DIR/domains/judge/directive.md"

  if [[ ! -f "$judge_directive" ]]; then
    log_err "Judge directive not found: $judge_directive"
    return 3
  fi

  log "Collecting context for Judge review..."

  # ── Collect context ──────────────────────────────────────────────────────
  local summary_md=""
  [[ -f "$sosl_state_dir/SUMMARY.md" ]] && summary_md=$(cat "$sosl_state_dir/SUMMARY.md")

  local session_md=""
  [[ -f "$sosl_state_dir/session.md" ]] && session_md=$(cat "$sosl_state_dir/session.md")

  local experiments=""
  [[ -f "$sosl_state_dir/experiments.jsonl" ]] && experiments=$(cat "$sosl_state_dir/experiments.jsonl")

  local directive_text=""
  [[ -f "$DOMAIN_DIR/directive.md" ]] && directive_text=$(cat "$DOMAIN_DIR/directive.md")

  # Git context from the worktree (where the branch lives)
  local git_log
  git_log=$(git -C "$WORK_DIR" log --oneline -30 2>/dev/null || echo "(no git log available)")

  local git_diff
  git_diff=$(git -C "$TARGET_DIR" diff "main..$branch" 2>/dev/null | head -1000 || echo "(no diff available)")

  # ── Build prompt ─────────────────────────────────────────────────────────
  local prompt
  prompt=$(cat "$judge_directive")

  prompt="${prompt//\{\{DOMAIN\}\}/$domain}"
  prompt="${prompt//\{\{BRANCH\}\}/$branch}"
  prompt="${prompt//\{\{BASELINE_SCORE\}\}/$baseline_score}"
  prompt="${prompt//\{\{FINAL_SCORE\}\}/$final_score}"
  prompt="${prompt//\{\{IMPROVEMENT_COUNT\}\}/$improvements}"
  prompt="${prompt//\{\{TOTAL_COST\}\}/$total_cost}"
  prompt="${prompt//\{\{SEARCH_MODE\}\}/$search_mode}"
  prompt="${prompt//\{\{DIRECTIVE_TEXT\}\}/$directive_text}"
  prompt="${prompt//\{\{SUMMARY_MD\}\}/$summary_md}"
  prompt="${prompt//\{\{SESSION_MD\}\}/$session_md}"
  prompt="${prompt//\{\{EXPERIMENTS_JSONL\}\}/$experiments}"
  prompt="${prompt//\{\{GIT_LOG\}\}/$git_log}"
  prompt="${prompt//\{\{GIT_DIFF\}\}/$git_diff}"

  # ── Call Judge (read-only tools) ─────────────────────────────────────────
  log "Calling Judge Agent ($MODEL)..."

  local judge_output
  judge_output=$(cd "$WORK_DIR" && claude -p "$prompt" \
    --output-format json \
    --max-turns 10 \
    --allowedTools "Read Glob Grep Bash(git:status) Bash(git:log) Bash(git:diff) Bash(git:show)" \
    --model "$MODEL" 2>/dev/null || echo '{"is_error": true}')

  # ── Parse verdict ────────────────────────────────────────────────────────
  local verdict
  verdict=$(echo "$judge_output" | python3 -c "
import json, sys, re
try:
    d = json.loads(sys.stdin.read())
    text = d.get('result', d.get('content', ''))
    if isinstance(text, list):
        text = ' '.join(str(b.get('text', '')) for b in text if isinstance(b, dict))
    m = re.search(r'Decision:\s*\[(APPROVE|REQUEST CHANGES|REJECT)\]', str(text), re.IGNORECASE)
    if m:
        print(m.group(1).upper())
    else:
        print('UNCLEAR')
except Exception:
    print('ERROR')
" 2>/dev/null || echo "ERROR")

  # ── Extract full text response ───────────────────────────────────────────
  local judge_text
  judge_text=$(echo "$judge_output" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    text = d.get('result', d.get('content', ''))
    if isinstance(text, list):
        text = '\n'.join(str(b.get('text', '')) for b in text if isinstance(b, dict))
    print(str(text))
except Exception:
    print('(Judge response parsing error)')
" 2>/dev/null || echo "(Judge response parsing error)")

  # ── Extract cost ─────────────────────────────────────────────────────────
  local judge_cost
  judge_cost=$(echo "$judge_output" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('total_cost_usd', d.get('cost_usd', 0)))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  log "Judge cost: \$$judge_cost"

  # ── Write report ─────────────────────────────────────────────────────────
  local report_path="$sosl_state_dir/JUDGE_REPORT.md"
  cat > "$report_path" <<REPORT_EOF
# Judge Review

- **Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Branch:** $branch
- **Domain:** $domain
- **Score:** $baseline_score -> $final_score
- **Verdict:** $verdict
- **Judge cost:** \$$judge_cost

---

$judge_text
REPORT_EOF

  log "Report written: $report_path"

  # ── Return exit code based on verdict ────────────────────────────────────
  case "$verdict" in
    APPROVE)          log_ok  "Judge verdict: APPROVE"; return 0 ;;
    "REQUEST CHANGES") log_warn "Judge verdict: REQUEST CHANGES"; return 1 ;;
    REJECT)           log_err  "Judge verdict: REJECT"; return 2 ;;
    *)                log_warn "Judge verdict unclear ($verdict)"; return 3 ;;
  esac
}
