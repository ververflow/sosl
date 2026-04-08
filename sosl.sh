#!/bin/bash
# SOSL — Self-Optimizing Software Loop
# Autonomous software optimization via Claude Code
# https://github.com/ververflow/sosl
#
# Usage: bash sosl.sh [options]

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/confidence.sh"
source "$SCRIPT_DIR/lib/eval.sh"
source "$SCRIPT_DIR/lib/guard.sh"
source "$SCRIPT_DIR/lib/checkpoint.sh"
source "$SCRIPT_DIR/lib/annotate.sh"
source "$SCRIPT_DIR/lib/temperature.sh"

# ── Defaults ────────────────────────────────────────────────────────────────
DOMAIN_DIR=""
TARGET_DIR=""
MAX_ITERATIONS=50
MAX_HOURS=10
MAX_COST_USD=25.00
BUDGET_PER_ITER=1.00
SAMPLES=5
MODEL="claude-sonnet-4-5"
HEALTH_CHECK_URL=""
RESUME=false
DRY_RUN=false
CONFIG_FILE=""

# ── Parse arguments ─────────────────────────────────────────────────────────
print_usage() {
  cat <<EOF
${BOLD}SOSL — Self-Optimizing Software Loop${NC}

Usage: bash sosl.sh [options]

Required:
  --domain <dir>          Path to domain directory (must contain directive.md, measure.sh, guard.sh)
  --target <dir>          Target repository to optimize

Options:
  --config <file>         Load options from config file (CLI flags override config values)
  --max-iterations <N>    Maximum iterations (default: 50)
  --max-hours <N>         Maximum wall-clock hours (default: 10)
  --max-cost <N>          Maximum total cost in USD (default: 25.00)
  --budget-per-iter <N>   Maximum cost per iteration in USD (default: 1.00)
  --samples <N>           Measurements per evaluation (default: 5)
  --model <model>         Claude model to use (default: claude-sonnet-4-5)
  --health-check <url>    URL to check before starting (e.g., http://localhost:3000)
  --resume                Resume from last checkpoint
  --dry-run               Print prompts without calling Claude
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)         DOMAIN_DIR="$2"; shift 2 ;;
    --target)         TARGET_DIR="$2"; shift 2 ;;
    --config)         CONFIG_FILE="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --max-hours)      MAX_HOURS="$2"; shift 2 ;;
    --max-cost)       MAX_COST_USD="$2"; shift 2 ;;
    --budget-per-iter) BUDGET_PER_ITER="$2"; shift 2 ;;
    --samples)        SAMPLES="$2"; shift 2 ;;
    --model)          MODEL="$2"; shift 2 ;;
    --health-check)   HEALTH_CHECK_URL="$2"; shift 2 ;;
    --resume)         RESUME=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    -h|--help)        print_usage; exit 0 ;;
    *) log_err "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

# ── Load config file if provided ────────────────────────────────────────────
if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_err "Config file not found: $CONFIG_FILE"
    exit 1
  fi
  # Validate config contains only variable assignments and comments (no commands)
  if grep -qvE '^\s*(#|$|[A-Z_]+[A-Z0-9_]*=)' "$CONFIG_FILE"; then
    log_err "Config file contains non-assignment lines (only KEY=value and comments allowed):"
    grep -vnE '^\s*(#|$|[A-Z_]+[A-Z0-9_]*=)' "$CONFIG_FILE" | head -3
    exit 1
  fi
  # Source config (bash key=value format), but don't override CLI args
  _domain="${DOMAIN_DIR}" _target="${TARGET_DIR}"
  source "$CONFIG_FILE"
  # CLI args take precedence: restore if they were set
  [[ -n "$_domain" ]] && DOMAIN_DIR="$_domain"
  [[ -n "$_target" ]] && TARGET_DIR="$_target"
fi

# ── Validate ────────────────────────────────────────────────────────────────
[[ -z "$DOMAIN_DIR" ]] && { log_err "Missing --domain"; print_usage; exit 1; }
[[ -z "$TARGET_DIR" ]] && { log_err "Missing --target"; print_usage; exit 1; }

# Resolve to absolute paths
DOMAIN_DIR="$(cd "$DOMAIN_DIR" && pwd)"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

DOMAIN_NAME="$(basename "$DOMAIN_DIR")"
DIRECTIVE_FILE="$DOMAIN_DIR/directive.md"
MEASURE_SCRIPT="$DOMAIN_DIR/measure.sh"
GUARD_SCRIPT="$DOMAIN_DIR/guard.sh"

# Load per-domain config (e.g., MIN_NOISE_FLOOR)
if [[ -f "$DOMAIN_DIR/config.sh" ]]; then
  source "$DOMAIN_DIR/config.sh"
fi

[[ ! -f "$DIRECTIVE_FILE" ]] && { log_err "Missing: $DIRECTIVE_FILE"; exit 1; }
[[ ! -f "$MEASURE_SCRIPT" ]] && { log_err "Missing: $MEASURE_SCRIPT"; exit 1; }
[[ ! -f "$GUARD_SCRIPT" ]]   && { log_err "Missing: $GUARD_SCRIPT"; exit 1; }
[[ ! -d "$TARGET_DIR/.git" ]] && { log_err "Target is not a git repo: $TARGET_DIR"; exit 1; }

# ── State ───────────────────────────────────────────────────────────────────
START_TIME=$(date +%s)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_ID="${DOMAIN_NAME}-${TIMESTAMP}"
BRANCH="sosl/${DOMAIN_NAME}/${TIMESTAMP}"
TOTAL_COST=0.00
IMPROVEMENTS=0
STAGNATION=0
STAGNATION_THRESHOLD=7
LOG_FILE="$TARGET_DIR/.sosl/${RUN_ID}.log"

# Ensure .sosl directory exists
mkdir -p "$TARGET_DIR/.sosl"

# ── Cleanup on exit ─────────────────────────────────────────────────────────
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_warn "SOSL interrupted (exit $exit_code). State saved to checkpoint."
    save_checkpoint "$TARGET_DIR" "$RUN_ID" "$ITER" "$BASELINE" "$TOTAL_COST" "$BRANCH"
  fi
  # Summary
  echo ""
  log_bold "═══ SOSL Summary ═══"
  log "Domain:       $DOMAIN_NAME"
  log "Iterations:   ${ITER:-0} / $MAX_ITERATIONS"
  log "Improvements: $IMPROVEMENTS"
  log "Final score:  ${BASELINE:-N/A}"
  log "Total cost:   \$${TOTAL_COST}"
  log "Branch:       $BRANCH"
  log "Experiment log: $TARGET_DIR/.sosl/experiments.jsonl"
  log_bold "════════════════════"
}
trap cleanup EXIT

# ── Resume or fresh start ───────────────────────────────────────────────────
ITER=0

if [[ "$RESUME" == true ]]; then
  checkpoint=$(load_checkpoint "$TARGET_DIR" "$DOMAIN_NAME")
  if [[ -n "$checkpoint" ]]; then
    ITER=$(echo "$checkpoint" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['iteration'])")
    BASELINE=$(echo "$checkpoint" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['baseline'])")
    TOTAL_COST=$(echo "$checkpoint" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['total_cost_usd'])")
    BRANCH=$(echo "$checkpoint" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['branch'])")
    ITER=$((ITER + 1))
    log_ok "Resuming run from iteration $ITER (baseline: $BASELINE, cost: \$$TOTAL_COST)"
    cd "$TARGET_DIR"
    git checkout "$BRANCH" 2>/dev/null
  else
    log_warn "No checkpoint found for domain '$DOMAIN_NAME'. Starting fresh."
    RESUME=false
  fi
fi

if [[ "$RESUME" == false ]]; then
  # Create optimization branch
  cd "$TARGET_DIR"
  git checkout -b "$BRANCH" 2>/dev/null || {
    log_err "Could not create branch: $BRANCH"
    exit 1
  }
  log_ok "Created branch: $BRANCH"

  # Health check
  if [[ -n "$HEALTH_CHECK_URL" ]]; then
    log "Health check: $HEALTH_CHECK_URL"
    if ! check_url "$HEALTH_CHECK_URL"; then
      log_err "Health check failed. Are dev servers running?"
      exit 1
    fi
    log_ok "Health check passed"
  fi

  # Baseline measurement
  log "Measuring baseline ($SAMPLES samples)..."
  baseline_result=$(measure_robust "$MEASURE_SCRIPT" "$TARGET_DIR" "$SAMPLES")
  BASELINE=$(echo "$baseline_result" | awk '{print $1}')
  NOISE_FLOOR=$(echo "$baseline_result" | awk '{print $2}')
  log_ok "Baseline: ${BOLD}$BASELINE${NC} (noise floor: $NOISE_FLOOR)"
fi

# If noise floor wasn't set (resume path), re-measure
if [[ -z "${NOISE_FLOOR:-}" ]]; then
  log "Re-measuring noise floor..."
  nf_result=$(measure_robust "$MEASURE_SCRIPT" "$TARGET_DIR" "$SAMPLES")
  NOISE_FLOOR=$(echo "$nf_result" | awk '{print $2}')
fi

echo ""
log_bold "═══ Starting SOSL Loop ═══"
log "Domain:     $DOMAIN_NAME"
log "Target:     $TARGET_DIR"
log "Baseline:   $BASELINE"
log "Noise:      $NOISE_FLOOR"
log "Max iter:   $MAX_ITERATIONS"
log "Max hours:  $MAX_HOURS"
log "Max cost:   \$$MAX_COST_USD"
log "Model:      $MODEL"
log_bold "══════════════════════════"
echo ""

# ── Main loop ───────────────────────────────────────────────────────────────
while [[ $ITER -lt $MAX_ITERATIONS ]]; do
  ITER_START=$(date +%s)

  # ── Circuit breakers ──────────────────────────────────────────────────────
  hours_elapsed=$(elapsed_hours "$START_TIME")
  if [[ $(float_gte "$hours_elapsed" "$MAX_HOURS") == "1" ]]; then
    log_warn "Time limit reached ($hours_elapsed hours). Stopping."
    break
  fi
  if [[ $(float_gte "$TOTAL_COST" "$MAX_COST_USD") == "1" ]]; then
    log_warn "Cost limit reached (\$$TOTAL_COST). Stopping."
    break
  fi
  # Pre-check: if remaining budget < budget_per_iter, don't start (prevents overshoot)
  remaining=$(float_add "$MAX_COST_USD" "-$TOTAL_COST")
  if [[ $(float_gt "$BUDGET_PER_ITER" "$remaining") == "1" ]]; then
    log_warn "Remaining budget (\$$remaining) < per-iter budget (\$$BUDGET_PER_ITER). Stopping."
    break
  fi
  if [[ $STAGNATION -ge $STAGNATION_THRESHOLD ]]; then
    log_warn "Stagnation threshold ($STAGNATION_THRESHOLD iterations without improvement). Stopping."
    break
  fi

  log_bold "── Iteration $((ITER + 1)) / $MAX_ITERATIONS ──"

  # ── Build prompt ──────────────────────────────────────────────────────────
  recent=$(get_recent "$TARGET_DIR" 3 2>/dev/null || echo "No previous experiments.")
  scope_guidance=$(get_scope_guidance "$ITER" "$MAX_ITERATIONS")

  prompt=$(build_prompt "$DIRECTIVE_FILE" "$BASELINE" "$((ITER + 1))" "$MAX_ITERATIONS" "$recent" "$scope_guidance" "$TARGET_DIR")

  if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN — Prompt for iteration $((ITER + 1)):"
    echo "---"
    echo "$prompt"
    echo "---"
    ITER=$((ITER + 1))
    continue
  fi

  # ── Call Claude ───────────────────────────────────────────────────────────
  log "Calling Claude ($MODEL, budget: \$$BUDGET_PER_ITER)..."

  claude_output=$(cd "$TARGET_DIR" && claude -p "$prompt" \
    --output-format json \
    --max-turns 15 \
    --allowedTools "Read Edit Write Glob Grep Bash(npm:*) Bash(npx:*) Bash(node:*) Bash(git:status) Bash(git:diff) Bash(git:log)" \
    --max-budget-usd "$BUDGET_PER_ITER" \
    --model "$MODEL" 2>/dev/null || echo '{"is_error": true}')

  # Parse Claude response
  iter_cost=$(echo "$claude_output" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('total_cost_usd', d.get('cost_usd', 0)))
except (json.JSONDecodeError, KeyError, TypeError):
    print(0)
" 2>/dev/null || echo "0")

  is_error=$(echo "$claude_output" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print('true' if d.get('is_error', False) else 'false')
except (json.JSONDecodeError, KeyError, TypeError):
    print('true')
" 2>/dev/null || echo "true")

  TOTAL_COST=$(float_add "$TOTAL_COST" "$iter_cost")
  log "Claude cost: \$$iter_cost (total: \$$TOTAL_COST)"

  if [[ "$is_error" == "true" ]]; then
    log_err "Claude returned an error. Skipping iteration."
    git_revert_changes "$TARGET_DIR"
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "" false "$iter_cost" "Claude error"
    STAGNATION=$((STAGNATION + 1))
    ITER=$((ITER + 1))
    continue
  fi

  # ── Check for changes ────────────────────────────────────────────────────
  if ! git_has_changes "$TARGET_DIR"; then
    log_warn "No code changes made. Skipping."
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "$BASELINE" false "$iter_cost" "No changes"
    STAGNATION=$((STAGNATION + 1))
    ITER=$((ITER + 1))
    continue
  fi

  # ── Run guards ────────────────────────────────────────────────────────────
  log "Running guards..."
  guard_result=$(run_guards "$GUARD_SCRIPT" "$TARGET_DIR" 2>&1) || {
    log_err "Guard failed: $guard_result"
    git_revert_changes "$TARGET_DIR"
    safe_result=$(sanitize_for_log "$guard_result")
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "" false "$iter_cost" "Guard fail: $safe_result"
    STAGNATION=$((STAGNATION + 1))
    ITER=$((ITER + 1))
    continue
  }
  log_ok "Guards passed"

  # ── Measure ───────────────────────────────────────────────────────────────
  log "Measuring ($SAMPLES samples)..."
  measure_result=$(measure_robust "$MEASURE_SCRIPT" "$TARGET_DIR" "$SAMPLES")
  new_score=$(echo "$measure_result" | awk '{print $1}')
  log "Score: $BASELINE → $new_score"

  # ── Compare ───────────────────────────────────────────────────────────────
  if is_significant "$BASELINE" "$new_score" "$NOISE_FLOOR"; then
    log_ok "Improvement detected! Committing."
    git_commit_sosl "$TARGET_DIR" "$DOMAIN_NAME" "$BASELINE" "$new_score"
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "$new_score" true "$iter_cost" "Improved"
    BASELINE="$new_score"
    IMPROVEMENTS=$((IMPROVEMENTS + 1))
    STAGNATION=0
  else
    log_warn "No significant improvement ($new_score vs baseline $BASELINE, noise $NOISE_FLOOR). Reverting."
    git_revert_changes "$TARGET_DIR"
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "$new_score" false "$iter_cost" "Below noise floor"
    STAGNATION=$((STAGNATION + 1))
  fi

  # ── Checkpoint ────────────────────────────────────────────────────────────
  save_checkpoint "$TARGET_DIR" "$RUN_ID" "$ITER" "$BASELINE" "$TOTAL_COST" "$BRANCH"

  ITER_DURATION=$(($(date +%s) - ITER_START))
  log "Iteration $((ITER + 1)) completed in ${ITER_DURATION}s"
  echo ""

  ITER=$((ITER + 1))
done

# Clear checkpoint on clean completion
clear_checkpoint "$TARGET_DIR" "$RUN_ID"

# Generate summary
write_summary "$TARGET_DIR" "$DOMAIN_NAME"

log_ok "SOSL loop completed."
