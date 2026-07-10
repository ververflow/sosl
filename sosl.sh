#!/bin/bash
# SOSL — Self-Optimizing System Loop
# Autonomous software optimization via Claude Code
# https://github.com/ververflow/sosl
#
# Usage: bash sosl.sh [options]

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/compat.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/confidence.sh"
source "$SCRIPT_DIR/lib/eval.sh"
source "$SCRIPT_DIR/lib/guard.sh"
source "$SCRIPT_DIR/lib/checkpoint.sh"
source "$SCRIPT_DIR/lib/annotate.sh"
source "$SCRIPT_DIR/lib/temperature.sh"
source "$SCRIPT_DIR/lib/session.sh"
source "$SCRIPT_DIR/lib/strategy.sh"
source "$SCRIPT_DIR/lib/tree.sh"
source "$SCRIPT_DIR/lib/judge.sh"
source "$SCRIPT_DIR/lib/secondary.sh"
source "$SCRIPT_DIR/lib/finalize.sh"
source "$SCRIPT_DIR/lib/autopr.sh"

# ── Defaults ────────────────────────────────────────────────────────────────
DOMAIN_DIR=""
TARGET_DIR=""
MAX_ITERATIONS=50
MAX_HOURS=10
MAX_COST_USD=25.00
BUDGET_PER_ITER=1.00
SAMPLES=5
MODEL="claude-sonnet-5"
JUDGE_MODEL=""
HEALTH_CHECK_URL=""
RESUME=false
DRY_RUN=false
CONFIG_FILE=""
SEARCH_MODE="linear"
MAX_CHILDREN=3
MAX_DEPTH=5
NO_JUDGE=false
FINALIZE=false
BASE_REF=""
MAX_CONSECUTIVE_ERRORS=3
STAGNATION_THRESHOLD=7
EXTRA_TOOLS=""
AUTO_PR=false
MAX_TURNS=15

# Tool allowlist for the optimizer loop. Modern permission grammar: Bash(cmd
# prefix:*). The legacy colon form (Bash(git:status)) silently grants nothing
# on current CLIs, which blocks git/npm inside the loop without any error.
readonly SOSL_TOOLS_MAIN='Read Edit Write Glob Grep Bash(npm run:*) Bash(npx:*) Bash(git status:*) Bash(git diff:*) Bash(git log:*)'

# ── Parse arguments ─────────────────────────────────────────────────────────
print_usage() {
  cat <<EOF
${BOLD}SOSL — Self-Optimizing System Loop${NC}

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
  --model <model>         Claude model to use (default: claude-sonnet-5)
  --judge-model <model>   Model for the Judge review (default: same as --model)
  --base <ref>            Base the work branch on this ref instead of HEAD
  --health-check <url>    URL to check before starting (e.g., http://localhost:3000)
  --search <mode>         Search strategy: linear (default) or tree (greedy best-first)
  --max-children <N>      Tree search: max attempts per node (default: 3)
  --max-depth <N>         Tree search: max tree depth (default: 5)
  --no-judge              Skip the Judge Agent review after the loop
                          (auto-PR: set AUTO_PR=true + AUTO_PR_REPO in a config
                          file to open a PR with the Judge report after a run
                          with improvements; see lib/autopr.sh)
  --finalize              Create independent cherry-pickable branches from commits
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
    --max-iterations) MAX_ITERATIONS="$2"; _cli_max_iter=1; shift 2 ;;
    --max-hours)      MAX_HOURS="$2"; _cli_max_hours=1; shift 2 ;;
    --max-cost)       MAX_COST_USD="$2"; _cli_max_cost=1; shift 2 ;;
    --budget-per-iter) BUDGET_PER_ITER="$2"; _cli_budget=1; shift 2 ;;
    --samples)        SAMPLES="$2"; _cli_samples=1; shift 2 ;;
    --model)          MODEL="$2"; _cli_model=1; shift 2 ;;
    --judge-model)    JUDGE_MODEL="$2"; _cli_judge_model=1; shift 2 ;;
    --base)           BASE_REF="$2"; _cli_base=1; shift 2 ;;
    --health-check)   HEALTH_CHECK_URL="$2"; shift 2 ;;
    --search)         SEARCH_MODE="$2"; _cli_search=1; shift 2 ;;
    --max-children)   MAX_CHILDREN="$2"; _cli_children=1; shift 2 ;;
    --max-depth)      MAX_DEPTH="$2"; _cli_depth=1; shift 2 ;;
    --no-judge)       NO_JUDGE=true; shift ;;
    --finalize)       FINALIZE=true; shift ;;
    --resume)         RESUME=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    -h|--help)        print_usage; exit 0 ;;
    *) log_err "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

# ── Load config file if provided ────────────────────────────────────────────
# Security: config files are parsed by Python, never sourced by bash.
# Only known keys with validated value types are accepted.
if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_err "Config file not found: $CONFIG_FILE"
    exit 1
  fi
  config_json=$(parse_config "$CONFIG_FILE") || exit 1
  # Apply config values (CLI flags override: only apply if CLI left the default)
  _cfg_get() { echo "$config_json" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); v=d.get(sys.argv[1],''); print(v if v!='' else '')" "$1"; }
  _v=$(_cfg_get DOMAIN_DIR);    [[ -n "$_v" ]] && [[ -z "$DOMAIN_DIR" ]]        && DOMAIN_DIR="$_v"
  _v=$(_cfg_get TARGET_DIR);    [[ -n "$_v" ]] && [[ -z "$TARGET_DIR" ]]        && TARGET_DIR="$_v"
  _v=$(_cfg_get MAX_ITERATIONS); [[ -n "$_v" ]] && [[ "$_cli_max_iter" != "1" ]]  && MAX_ITERATIONS="$_v"
  _v=$(_cfg_get MAX_HOURS);     [[ -n "$_v" ]] && [[ "$_cli_max_hours" != "1" ]] && MAX_HOURS="$_v"
  _v=$(_cfg_get MAX_COST_USD);  [[ -n "$_v" ]] && [[ "$_cli_max_cost" != "1" ]]  && MAX_COST_USD="$_v"
  _v=$(_cfg_get BUDGET_PER_ITER); [[ -n "$_v" ]] && [[ "$_cli_budget" != "1" ]]  && BUDGET_PER_ITER="$_v"
  _v=$(_cfg_get SAMPLES);       [[ -n "$_v" ]] && [[ "$_cli_samples" != "1" ]]   && SAMPLES="$_v"
  _v=$(_cfg_get MODEL);         [[ -n "$_v" ]] && [[ "$_cli_model" != "1" ]]     && MODEL="$_v"
  _v=$(_cfg_get JUDGE_MODEL);   [[ -n "$_v" ]] && [[ "$_cli_judge_model" != "1" ]] && JUDGE_MODEL="$_v"
  _v=$(_cfg_get BASE_REF);      [[ -n "$_v" ]] && [[ "$_cli_base" != "1" ]]      && BASE_REF="$_v"
  _v=$(_cfg_get MAX_CONSECUTIVE_ERRORS); [[ -n "$_v" ]] && MAX_CONSECUTIVE_ERRORS="$_v"
  _v=$(_cfg_get STAGNATION_THRESHOLD);   [[ -n "$_v" ]] && STAGNATION_THRESHOLD="$_v"
  _v=$(_cfg_get HEALTH_CHECK_URL); [[ -n "$_v" ]] && [[ -z "$HEALTH_CHECK_URL" ]] && HEALTH_CHECK_URL="$_v"
  _v=$(_cfg_get TARGET_URL);    [[ -n "$_v" ]] && export TARGET_URL="$_v"
  _v=$(_cfg_get SEARCH_MODE);   [[ -n "$_v" ]] && [[ "$_cli_search" != "1" ]]    && SEARCH_MODE="$_v"
  _v=$(_cfg_get MAX_CHILDREN);  [[ -n "$_v" ]] && [[ "$_cli_children" != "1" ]]  && MAX_CHILDREN="$_v"
  _v=$(_cfg_get MAX_DEPTH);     [[ -n "$_v" ]] && [[ "$_cli_depth" != "1" ]]     && MAX_DEPTH="$_v"
  _v=$(_cfg_get URLS);          [[ -n "$_v" ]] && export URLS="$_v"
  _v=$(_cfg_get EXTRA_TOOLS);   [[ -n "$_v" ]] && EXTRA_TOOLS="$_v"
  _v=$(_cfg_get MAX_TURNS);      [[ -n "$_v" ]] && MAX_TURNS="$_v"
  _v=$(_cfg_get AUTO_PR);        [[ -n "$_v" ]] && AUTO_PR="$_v"
  _v=$(_cfg_get AUTO_PR_REPO);   [[ -n "$_v" ]] && AUTO_PR_REPO="$_v"
  _v=$(_cfg_get AUTO_PR_REMOTE); [[ -n "$_v" ]] && AUTO_PR_REMOTE="$_v"
  _v=$(_cfg_get AUTO_PR_BASE);   [[ -n "$_v" ]] && AUTO_PR_BASE="$_v"
fi

# ── Validate ────────────────────────────────────────────────────────────────
[[ -z "$DOMAIN_DIR" ]] && { log_err "Missing --domain"; print_usage; exit 1; }
[[ -z "$TARGET_DIR" ]] && { log_err "Missing --target"; print_usage; exit 1; }
[[ "$SEARCH_MODE" != "linear" && "$SEARCH_MODE" != "tree" ]] && { log_err "--search must be 'linear' or 'tree'"; exit 1; }

# Resolve to absolute paths
DOMAIN_DIR="$(cd "$DOMAIN_DIR" && pwd)"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

DOMAIN_NAME="$(basename "$DOMAIN_DIR")"

# ── Project-local domain override ──────────────────────────────────────────
# If the target repo has .sosl/domains/<domain>/ with all required files,
# use that instead of the built-in domain. This lets projects customize
# SOSL without forking the framework.
PROJECT_LOCAL_DOMAIN="$TARGET_DIR/.sosl/domains/$DOMAIN_NAME"
if [[ -d "$PROJECT_LOCAL_DOMAIN" ]] && [[ -f "$PROJECT_LOCAL_DOMAIN/directive.md" ]] \
   && [[ -f "$PROJECT_LOCAL_DOMAIN/measure.sh" ]] && [[ -f "$PROJECT_LOCAL_DOMAIN/guard.sh" ]]; then
  log "Using project-local domain: $PROJECT_LOCAL_DOMAIN"
  DOMAIN_DIR="$PROJECT_LOCAL_DOMAIN"
fi

DIRECTIVE_FILE="$DOMAIN_DIR/directive.md"
MEASURE_SCRIPT="$DOMAIN_DIR/measure.sh"
GUARD_SCRIPT="$DOMAIN_DIR/guard.sh"

# Load per-domain config (e.g., MIN_NOISE_FLOOR)
# Security: parsed by Python, never sourced. Only known keys accepted.
if [[ -f "$DOMAIN_DIR/config.sh" ]]; then
  domain_cfg=$(parse_config "$DOMAIN_DIR/config.sh") || exit 1
  _dcfg() { echo "$domain_cfg" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get(sys.argv[1],''))" "$1"; }
  _v=$(_dcfg MIN_NOISE_FLOOR);   [[ -n "$_v" ]] && MIN_NOISE_FLOOR="$_v"
  _v=$(_dcfg ALLOWED_PATHS);     [[ -n "$_v" ]] && ALLOWED_PATHS="$_v"
  _v=$(_dcfg MAX_NET_DELETIONS); [[ -n "$_v" ]] && MAX_NET_DELETIONS="$_v"
  # Exported: measure.sh/guard.sh run as child processes and honor it too
  _v=$(_dcfg MEASURE_TIMEOUT);   [[ -n "$_v" ]] && export MEASURE_TIMEOUT="$_v"
  _v=$(_dcfg EXTRA_TOOLS);       [[ -n "$_v" ]] && EXTRA_TOOLS="$_v"
  _v=$(_dcfg MAX_TURNS);         [[ -n "$_v" ]] && MAX_TURNS="$_v"
  _v=$(_dcfg SECONDARY_DOMAINS); [[ -n "$_v" ]] && SECONDARY_DOMAINS="$_v"
  # Per-domain overrides; CLI flags win over domain config
  _v=$(_dcfg MODEL);       [[ -n "$_v" ]] && [[ "${_cli_model:-}" != "1" ]] && MODEL="$_v"
  _v=$(_dcfg JUDGE_MODEL); [[ -n "$_v" ]] && [[ "${_cli_judge_model:-}" != "1" ]] && JUDGE_MODEL="$_v"
  _v=$(_dcfg STACK);       [[ -n "$_v" ]] && export STACK="$_v"
  _v=$(_dcfg BASE_REF);    [[ -n "$_v" ]] && [[ "${_cli_base:-}" != "1" ]] && BASE_REF="$_v"
  _v=$(_dcfg MAX_CONSECUTIVE_ERRORS); [[ -n "$_v" ]] && MAX_CONSECUTIVE_ERRORS="$_v"
  _v=$(_dcfg STAGNATION_THRESHOLD);   [[ -n "$_v" ]] && STAGNATION_THRESHOLD="$_v"
fi

# Validate the base ref early: a typo here must not silently fall back to HEAD
if [[ -n "$BASE_REF" ]]; then
  if ! git -C "$TARGET_DIR" rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null; then
    log_err "--base ref not found in target: $BASE_REF"
    exit 1
  fi
fi
# Judge/finalize diff against this ref; default main for existing behaviour
export SOSL_BASE_REF="${BASE_REF:-main}"

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
CONSECUTIVE_ERRORS=0

# .sosl/ lives in the ORIGINAL target dir (not the worktree)
# Exported so measure.sh/guard.sh can write audit details there
export SOSL_STATE_DIR="$TARGET_DIR/.sosl"
LOG_FILE="$SOSL_STATE_DIR/${RUN_ID}.log"
mkdir -p "$SOSL_STATE_DIR"

# WORK_DIR is where Claude makes changes — a worktree, not the original
WORKTREE_BASE="$TARGET_DIR/.sosl-worktrees"
WORK_DIR="$WORKTREE_BASE/$DOMAIN_NAME"

# ── Cleanup on exit ─────────────────────────────────────────────────────────
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_warn "SOSL interrupted (exit $exit_code). State saved to checkpoint."
    save_checkpoint "$TARGET_DIR" "$RUN_ID" "$ITER" "$BASELINE" "$TOTAL_COST" "$BRANCH" "$DOMAIN_NAME"
  fi
  # Machine-readable contract for sosl-night.sh — written on every exit path
  write_run_manifest "$TARGET_DIR" "$RUN_ID" "$DOMAIN_NAME" "${BRANCH:-}" "${SEARCH_MODE:-linear}" \
    "${INITIAL_BASELINE:-}" "${BASELINE:-}" "${IMPROVEMENTS:-0}" "${ITER:-0}" "${TOTAL_COST:-0}" \
    "$exit_code" "${START_TIME:-0}" || true
  # Summary
  echo ""
  log_bold "═══ SOSL Summary ═══"
  log "Domain:       $DOMAIN_NAME"
  log "Iterations:   ${ITER:-0} / $MAX_ITERATIONS"
  log "Improvements: $IMPROVEMENTS"
  log "Final score:  ${BASELINE:-N/A}"
  log "Total cost:   \$${TOTAL_COST}"
  log "Branch:       $BRANCH"
  log "Worktree:     $WORK_DIR"
  log "Experiment log: $SOSL_STATE_DIR/experiments.jsonl"
  log_bold "════════════════════"
  echo ""
  if [[ $IMPROVEMENTS -gt 0 ]]; then
    log "Review: git -C $TARGET_DIR log --oneline $BRANCH"
    log "Merge:  git -C $TARGET_DIR merge $BRANCH && git -C $TARGET_DIR worktree remove $WORK_DIR"
  fi
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
    # Worktree should still exist from the interrupted run
    if [[ ! -d "$WORK_DIR" ]]; then
      log_err "Worktree not found: $WORK_DIR (cannot resume)"
      exit 1
    fi
  else
    log_warn "No checkpoint found for domain '$DOMAIN_NAME'. Starting fresh."
    RESUME=false
  fi
fi

if [[ "$RESUME" == false ]]; then
  # Create worktree — isolated copy so you can keep working on main
  mkdir -p "$WORKTREE_BASE"
  if [[ -d "$WORK_DIR" ]]; then
    git -C "$TARGET_DIR" worktree remove "$WORK_DIR" --force 2>/dev/null || true
  fi
  git -C "$TARGET_DIR" worktree add -b "$BRANCH" "$WORK_DIR" "${BASE_REF:-HEAD}" 2>/dev/null || {
    log_err "Could not create worktree: $WORK_DIR"
    exit 1
  }
  log_ok "Created worktree: $WORK_DIR (branch: $BRANCH, base: ${BASE_REF:-HEAD})"
  log "You can keep working on main in $TARGET_DIR"

  # Symlink node_modules from original to worktree (worktrees don't share them).
  # Track every link we plant: gitignore patterns like `node_modules/` or
  # `.venv/` match directories only, NOT symlinks — without an explicit
  # exclude, git sees the link as untracked, the scope guard fails on
  # infrastructure SOSL itself created, add -A would commit it, and the
  # revert's git clean would delete it.
  SOSL_WT_LINKS=""
  for nm_dir in $(find "$TARGET_DIR" -maxdepth 3 -name "node_modules" -type d 2>/dev/null); do
    _relative="${nm_dir#$TARGET_DIR/}"
    _wt_parent="$WORK_DIR/$(dirname "$_relative")"
    if [[ -d "$_wt_parent" ]] && [[ ! -e "$_wt_parent/node_modules" ]]; then
      ln -s "$nm_dir" "$_wt_parent/node_modules" 2>/dev/null && {
        log "Linked: $_relative"
        SOSL_WT_LINKS="$SOSL_WT_LINKS $_relative"
      }
    fi
  done
  # Also link Python venv if present
  for _venv_dir in "$TARGET_DIR"/.venv "$TARGET_DIR"/backend/.venv; do
    if [[ -d "$_venv_dir" ]]; then
      _relative="${_venv_dir#$TARGET_DIR/}"
      _wt_target="$WORK_DIR/$_relative"
      if [[ ! -e "$_wt_target" ]]; then
        ln -s "$_venv_dir" "$_wt_target" 2>/dev/null && \
          SOSL_WT_LINKS="$SOSL_WT_LINKS $_relative"
      fi
    fi
  done
  export SOSL_WT_LINKS

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
  baseline_result=$(measure_robust "$MEASURE_SCRIPT" "$WORK_DIR" "$SAMPLES")
  BASELINE=$(echo "$baseline_result" | awk '{print $1}')
  NOISE_FLOOR=$(echo "$baseline_result" | awk '{print $2}')
  log_ok "Baseline: ${BOLD}$BASELINE${NC} (noise floor: $NOISE_FLOOR)"
fi
INITIAL_BASELINE="$BASELINE"

# Measure secondary metrics baseline (1 sample each, informational only)
SECONDARY_BEFORE=""
SECONDARY_CONTEXT=""
if [[ -n "${SECONDARY_DOMAINS:-}" ]]; then
  log "Measuring secondary baselines ($SECONDARY_DOMAINS)..."
  SECONDARY_BEFORE=$(measure_secondary "$SCRIPT_DIR" "$SECONDARY_DOMAINS" "$WORK_DIR")
  SECONDARY_CONTEXT=$(format_secondary_baseline "$SECONDARY_BEFORE")
  log_ok "Secondary baselines: $SECONDARY_BEFORE"
fi

# If noise floor wasn't set (resume path), re-measure
if [[ -z "${NOISE_FLOOR:-}" ]]; then
  log "Re-measuring noise floor..."
  nf_result=$(measure_robust "$MEASURE_SCRIPT" "$WORK_DIR" "$SAMPLES")
  NOISE_FLOOR=$(echo "$nf_result" | awk '{print $2}')
fi

# Initialize session document (skip on resume — session.md already exists)
if [[ "$RESUME" == false ]]; then
  session_init "$TARGET_DIR" "$DOMAIN_NAME" "$BASELINE"
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
log "Search:     $SEARCH_MODE"
export SOSL_SEARCH_MODE="$SEARCH_MODE"
log_bold "══════════════════════════"
echo ""

if [[ "$SEARCH_MODE" == "tree" ]]; then
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ TREE SEARCH LOOP — greedy best-first exploration                        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# Initialize tree with root node
if [[ "$RESUME" == false ]]; then
  tree_init "$TARGET_DIR" "$BRANCH" "$BASELINE" "$NOISE_FLOOR"
  log_ok "Tree search initialized (root: $BASELINE, children: $MAX_CHILDREN, depth: $MAX_DEPTH)"
fi

GLOBAL_ITER=0

while [[ $GLOBAL_ITER -lt $MAX_ITERATIONS ]]; do
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
  remaining=$(float_add "$MAX_COST_USD" "-$TOTAL_COST")
  if [[ $(float_gt "$BUDGET_PER_ITER" "$remaining") == "1" ]]; then
    log_warn "Remaining budget (\$$remaining) < per-iter budget (\$$BUDGET_PER_ITER). Stopping."
    break
  fi
  # Tree mode previously had no stagnation breaker at all: a systematic
  # failure could burn every iteration before the frontier ran dry.
  if [[ $STAGNATION -ge $STAGNATION_THRESHOLD ]]; then
    log_warn "Stagnation threshold ($STAGNATION_THRESHOLD iterations without a new node). Stopping."
    break
  fi

  # ── Select node from frontier ─────────────────────────────────────────────
  node_json=$(tree_select_node "$TARGET_DIR" "$MAX_CHILDREN" "$MAX_DEPTH")
  if [[ -z "$node_json" ]]; then
    log_warn "No expandable nodes remain. Stopping."
    break
  fi

  node_id=$(echo "$node_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['id'])")
  node_branch=$(echo "$node_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['branch'])")
  node_score=$(echo "$node_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['score'])")
  node_noise=$(echo "$node_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['noise_floor'])")
  node_depth=$(echo "$node_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['depth'])")

  log_bold "── Iteration $((GLOBAL_ITER + 1)) / $MAX_ITERATIONS (node: $node_id, depth: $node_depth) ──"

  # Export node_id for annotate.sh to include in JSONL
  export SOSL_NODE_ID="$node_id"

  # ── Switch branch if needed ───────────────────────────────────────────────
  current_branch=$(git -C "$WORK_DIR" branch --show-current 2>/dev/null || echo "")
  if [[ "$current_branch" != "$node_branch" ]]; then
    log "Switching to branch: $node_branch"
    tree_switch_to_node "$WORK_DIR" "$node_branch"
  fi

  BASELINE="$node_score"
  NOISE_FLOOR="$node_noise"

  # ── Detect strategy mode (tree-scoped) ────────────────────────────────────
  ITER_MODE=$(tree_detect_mode "$TARGET_DIR" "$node_id")
  guard_error=""
  if [[ "$ITER_MODE" == "DEBUG" ]]; then
    guard_error=$(tree_get_last_guard_error "$TARGET_DIR" "$node_id")
  fi
  mode_guidance=$(get_mode_guidance "$ITER_MODE" "$guard_error")
  log "Mode: ${BOLD}$ITER_MODE${NC} | Score: $BASELINE"

  # ── Build prompt (tree-scoped session) ────────────────────────────────────
  recent=$(get_recent "$TARGET_DIR" 3 2>/dev/null || echo "No previous experiments.")
  scope_guidance=$(get_scope_guidance "$GLOBAL_ITER" "$MAX_ITERATIONS")
  session_ctx=$(tree_session_get "$TARGET_DIR" "$node_id" 2>/dev/null || echo "")

  prompt=$(build_prompt "$DIRECTIVE_FILE" "$BASELINE" "$((GLOBAL_ITER + 1))" "$MAX_ITERATIONS" "$recent" "$scope_guidance" "$WORK_DIR" "$session_ctx" "$mode_guidance" "${SECONDARY_CONTEXT:-}")

  if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN — Prompt for iteration $((GLOBAL_ITER + 1)) (node $node_id):"
    echo "---"
    echo "$prompt"
    echo "---"
    GLOBAL_ITER=$((GLOBAL_ITER + 1))
    continue
  fi

  # ── Call Claude ───────────────────────────────────────────────────────────
  log "Calling Claude ($MODEL, budget: \$$BUDGET_PER_ITER)..."
  pre_claude_head=$(git -C "$WORK_DIR" rev-parse HEAD 2>/dev/null)

  claude_output=$(cd "$WORK_DIR" && claude -p "$prompt" \
    --output-format json \
    --max-turns "$MAX_TURNS" \
    --allowedTools "$SOSL_TOOLS_MAIN${EXTRA_TOOLS:+ $EXTRA_TOOLS}" \
    --max-budget-usd "$BUDGET_PER_ITER" \
    --model "$MODEL" < /dev/null 2>>"$SOSL_STATE_DIR/claude-stderr.log") || true
  # On e.g. error_max_budget_usd the CLI exits non-zero but still prints a
  # result JSON with the real cost. An `|| echo fallback` inside the capture
  # would append a second JSON to it, break parsing, and drop that cost from
  # the budget accounting — so only substitute when nothing came back at all.
  [[ -n "$claude_output" ]] || claude_output='{"is_error": true}'
  hb_touch

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

  strategy_summary=$(echo "$claude_output" | python3 -c "
import json, sys, re
try:
    d = json.loads(sys.stdin.read())
    text = d.get('result', d.get('content', ''))
    if isinstance(text, list):
        text = ' '.join(str(b.get('text', '')) for b in text if isinstance(b, dict))
    m = re.search(r'STRATEGY:\s*(.+?)(?:\n|$)', str(text))
    if m:
        s = re.sub(r'[^\w\s\.\-\>\:\(\)\/,\'\"]', '', m.group(1))
        print(s[:200])
except Exception:
    pass
" 2>/dev/null || echo "")

  # ── Handle errors ─────────────────────────────────────────────────────────
  if [[ "$is_error" == "true" ]]; then
    err_subtype=$(claude_error_subtype "$claude_output" "$SOSL_STATE_DIR")
    log_err "Claude returned an error ($err_subtype). Recording failure."
    git_revert_changes "$WORK_DIR"
    tree_record_failure "$TARGET_DIR" "$node_id" "$ITER_MODE" "${strategy_summary:-Claude error}" "error" "$iter_cost" "$((GLOBAL_ITER + 1))"
    append_experiment "$TARGET_DIR" "$GLOBAL_ITER" "$DOMAIN_NAME" "$BASELINE" "" false "$iter_cost" "Claude error ($err_subtype)" "$ITER_MODE" "$strategy_summary"
    GLOBAL_ITER=$((GLOBAL_ITER + 1))
    STAGNATION=$((STAGNATION + 1))
    CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    # A usage/session limit won't clear by retrying inside the same window —
    # every further iteration just burns quota on a rejected call. Stop now
    # with a clear signal instead of grinding to the consecutive-error cap.
    if [[ "$err_subtype" == "usage_limit" ]]; then
      log_err "Claude usage/session limit hit — stopping run (resets on Anthropic's clock, not ours)."
      break
    fi
    # Errors cost ~$0, so neither the cost breaker nor the budget pre-check
    # would ever stop a dead/logged-out CLI from burning all iterations.
    if [[ $CONSECUTIVE_ERRORS -ge $MAX_CONSECUTIVE_ERRORS ]]; then
      log_err "$CONSECUTIVE_ERRORS consecutive Claude errors (raw JSON: $SOSL_STATE_DIR/claude-errors.jsonl). Aborting run."
      break
    fi
    continue
  fi
  CONSECUTIVE_ERRORS=0

  # Claude must never commit its own work — that bypasses guards, scope
  # checks and measurement entirely (the loop sees a clean tree, records
  # "No changes", and an unguarded commit rides the branch to the merge).
  # Soft-land any self-commits back into the working tree so the normal
  # guard → measure → commit/revert pipeline judges them like any change.
  if [[ -n "${pre_claude_head:-}" ]] && \
     [[ "$(git -C "$WORK_DIR" rev-parse HEAD 2>/dev/null)" != "$pre_claude_head" ]]; then
    _n_self=$(git -C "$WORK_DIR" rev-list --count "$pre_claude_head..HEAD" 2>/dev/null || echo "?")
    log_warn "Claude committed by itself ($_n_self commit(s)) — resetting into working tree for guards"
    git -C "$WORK_DIR" reset --mixed -q "$pre_claude_head" 2>/dev/null || true
  fi

  if ! git_has_changes "$WORK_DIR"; then
    log_warn "No code changes made. Recording failure."
    tree_record_failure "$TARGET_DIR" "$node_id" "$ITER_MODE" "${strategy_summary:-No changes}" "no_changes" "$iter_cost" "$((GLOBAL_ITER + 1))"
    append_experiment "$TARGET_DIR" "$GLOBAL_ITER" "$DOMAIN_NAME" "$BASELINE" "$BASELINE" false "$iter_cost" "No changes" "$ITER_MODE" "$strategy_summary"
    GLOBAL_ITER=$((GLOBAL_ITER + 1))
    STAGNATION=$((STAGNATION + 1))
    continue
  fi

  # ── Run guards ────────────────────────────────────────────────────────────
  log "Running guards..."
  guard_result=$(run_guards "$GUARD_SCRIPT" "$WORK_DIR" 2>&1) || {
    log_err "Guard failed: $guard_result"
    git_revert_changes "$WORK_DIR"
    safe_result=$(sanitize_for_log "$guard_result")
    tree_record_failure "$TARGET_DIR" "$node_id" "$ITER_MODE" "${strategy_summary:-Unknown}" "guard_fail" "$iter_cost" "$((GLOBAL_ITER + 1))"
    append_experiment "$TARGET_DIR" "$GLOBAL_ITER" "$DOMAIN_NAME" "$BASELINE" "" false "$iter_cost" "Guard fail: $safe_result" "$ITER_MODE" "$strategy_summary"
    GLOBAL_ITER=$((GLOBAL_ITER + 1))
    STAGNATION=$((STAGNATION + 1))
    continue
  }
  log_ok "Guards passed"

  # ── Measure ───────────────────────────────────────────────────────────────
  log "Measuring ($SAMPLES samples)..."
  measure_result=$(measure_robust "$MEASURE_SCRIPT" "$WORK_DIR" "$SAMPLES")
  new_score=$(echo "$measure_result" | awk '{print $1}')
  new_noise=$(echo "$measure_result" | awk '{print $2}')
  log "Score: $BASELINE → $new_score"

  # ── Compare & branch ──────────────────────────────────────────────────────
  if is_significant "$BASELINE" "$new_score" "$NOISE_FLOOR"; then
    new_id=$(tree_generate_id)
    new_branch="${node_branch}/${new_id}"
    log_ok "Improvement! Creating node $new_id on $new_branch"

    # Create new branch and commit
    git -C "$WORK_DIR" checkout -b "$new_branch" 2>/dev/null
    git_commit_sosl "$WORK_DIR" "$DOMAIN_NAME" "$BASELINE" "$new_score"

    # Add to tree
    tree_add_node "$TARGET_DIR" "$new_id" "$node_id" "$new_branch" "$new_score" "$new_noise" "$ITER_MODE" "${strategy_summary:-Improvement}" "$iter_cost"
    append_experiment "$TARGET_DIR" "$GLOBAL_ITER" "$DOMAIN_NAME" "$BASELINE" "$new_score" true "$iter_cost" "Improved" "$ITER_MODE" "$strategy_summary"
    session_update "$TARGET_DIR" "$((GLOBAL_ITER + 1))" "$ITER_MODE" "committed" "$BASELINE" "$new_score" "${strategy_summary:-Improvement}" ""
    IMPROVEMENTS=$((IMPROVEMENTS + 1))
    STAGNATION=0

    # Secondary metrics check (after commit, informational only)
    if [[ -n "${SECONDARY_DOMAINS:-}" ]]; then
      sec_after=$(measure_secondary "$SCRIPT_DIR" "$SECONDARY_DOMAINS" "$WORK_DIR")
      sec_comparison=$(compare_secondary "$SECONDARY_BEFORE" "$sec_after")
      if has_warnings "$sec_comparison"; then
        log_warn "Tradeoff: $(format_secondary "$sec_comparison")"
      fi
      SECONDARY_CONTEXT=$(format_secondary "$sec_comparison")
      export SOSL_SECONDARY="$sec_comparison"
    fi
  else
    log_warn "No significant improvement ($new_score vs $BASELINE). Recording failure."
    git_revert_changes "$WORK_DIR"
    tree_record_failure "$TARGET_DIR" "$node_id" "$ITER_MODE" "${strategy_summary:-Below noise floor}" "no_improvement" "$iter_cost" "$((GLOBAL_ITER + 1))"
    append_experiment "$TARGET_DIR" "$GLOBAL_ITER" "$DOMAIN_NAME" "$BASELINE" "$new_score" false "$iter_cost" "Below noise floor" "$ITER_MODE" "$strategy_summary"
    STAGNATION=$((STAGNATION + 1))
  fi

  # ── Update tree iteration counter ─────────────────────────────────────────
  tree_update_iteration "$TARGET_DIR" "$((GLOBAL_ITER + 1))"

  ITER_DURATION=$(($(date +%s) - ITER_START))
  log "Iteration $((GLOBAL_ITER + 1)) completed in ${ITER_DURATION}s"
  echo ""

  GLOBAL_ITER=$((GLOBAL_ITER + 1))
done

# Tree search summary
echo ""
log_bold "═══ Tree Search Results ═══"
tree_summary "$TARGET_DIR"
log "Best path:"
tree_get_best_path "$TARGET_DIR"
read best_score best_branch <<< $(tree_get_best "$TARGET_DIR")
log "Merge best: git -C $TARGET_DIR merge $best_branch"
log_bold "═══════════════════════════"

# Set ITER for cleanup summary
ITER=$GLOBAL_ITER
BASELINE="$best_score"
BRANCH="$best_branch"

else
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ LINEAR LOOP — original sequential optimization                          ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

  # ── Detect strategy mode ─────────────────────────────────────────────────
  ITER_MODE=$(detect_mode "$TARGET_DIR" "$STAGNATION")
  guard_error=""
  if [[ "$ITER_MODE" == "DEBUG" ]]; then
    guard_error=$(get_last_guard_error "$TARGET_DIR")
  fi
  mode_guidance=$(get_mode_guidance "$ITER_MODE" "$guard_error")
  log "Mode: ${BOLD}$ITER_MODE${NC}"

  # ── Build prompt ──────────────────────────────────────────────────────────
  recent=$(get_recent "$TARGET_DIR" 3 2>/dev/null || echo "No previous experiments.")
  scope_guidance=$(get_scope_guidance "$ITER" "$MAX_ITERATIONS")
  session_ctx=$(session_get "$TARGET_DIR" 2>/dev/null || echo "")

  prompt=$(build_prompt "$DIRECTIVE_FILE" "$BASELINE" "$((ITER + 1))" "$MAX_ITERATIONS" "$recent" "$scope_guidance" "$WORK_DIR" "$session_ctx" "$mode_guidance" "${SECONDARY_CONTEXT:-}")

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
  pre_claude_head=$(git -C "$WORK_DIR" rev-parse HEAD 2>/dev/null)

  claude_output=$(cd "$WORK_DIR" && claude -p "$prompt" \
    --output-format json \
    --max-turns "$MAX_TURNS" \
    --allowedTools "$SOSL_TOOLS_MAIN${EXTRA_TOOLS:+ $EXTRA_TOOLS}" \
    --max-budget-usd "$BUDGET_PER_ITER" \
    --model "$MODEL" < /dev/null 2>>"$SOSL_STATE_DIR/claude-stderr.log") || true
  # On e.g. error_max_budget_usd the CLI exits non-zero but still prints a
  # result JSON with the real cost. An `|| echo fallback` inside the capture
  # would append a second JSON to it, break parsing, and drop that cost from
  # the budget accounting — so only substitute when nothing came back at all.
  [[ -n "$claude_output" ]] || claude_output='{"is_error": true}'
  hb_touch

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

  # Extract strategy summary from Claude's output (looks for "STRATEGY: ..." line)
  strategy_summary=$(echo "$claude_output" | python3 -c "
import json, sys, re
try:
    d = json.loads(sys.stdin.read())
    text = d.get('result', d.get('content', ''))
    if isinstance(text, list):
        text = ' '.join(str(b.get('text', '')) for b in text if isinstance(b, dict))
    m = re.search(r'STRATEGY:\s*(.+?)(?:\n|$)', str(text))
    if m:
        # Sanitize: strip non-printable, cap length
        s = re.sub(r'[^\w\s\.\-\>\:\(\)\/,\'\"]', '', m.group(1))
        print(s[:200])
except Exception:
    pass
" 2>/dev/null || echo "")

  if [[ "$is_error" == "true" ]]; then
    err_subtype=$(claude_error_subtype "$claude_output" "$SOSL_STATE_DIR")
    log_err "Claude returned an error ($err_subtype). Skipping iteration."
    git_revert_changes "$WORK_DIR"
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "" false "$iter_cost" "Claude error ($err_subtype)" "$ITER_MODE" "$strategy_summary"
    session_update "$TARGET_DIR" "$((ITER + 1))" "$ITER_MODE" "error" "$BASELINE" "" "${strategy_summary:-Claude error}" ""
    STAGNATION=$((STAGNATION + 1))
    CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    ITER=$((ITER + 1))
    # A usage/session limit won't clear by retrying inside the same window —
    # every further iteration just burns quota on a rejected call. Stop now
    # with a clear signal instead of grinding to the consecutive-error cap.
    if [[ "$err_subtype" == "usage_limit" ]]; then
      log_err "Claude usage/session limit hit — stopping run (resets on Anthropic's clock, not ours)."
      break
    fi
    # Errors cost ~$0, so neither the cost breaker nor the budget pre-check
    # would ever stop a dead/logged-out CLI from burning all iterations.
    if [[ $CONSECUTIVE_ERRORS -ge $MAX_CONSECUTIVE_ERRORS ]]; then
      log_err "$CONSECUTIVE_ERRORS consecutive Claude errors (raw JSON: $SOSL_STATE_DIR/claude-errors.jsonl). Aborting run."
      break
    fi
    continue
  fi
  CONSECUTIVE_ERRORS=0

  # Claude must never commit its own work — that bypasses guards, scope
  # checks and measurement entirely (the loop sees a clean tree, records
  # "No changes", and an unguarded commit rides the branch to the merge).
  # Soft-land any self-commits back into the working tree so the normal
  # guard → measure → commit/revert pipeline judges them like any change.
  if [[ -n "${pre_claude_head:-}" ]] && \
     [[ "$(git -C "$WORK_DIR" rev-parse HEAD 2>/dev/null)" != "$pre_claude_head" ]]; then
    _n_self=$(git -C "$WORK_DIR" rev-list --count "$pre_claude_head..HEAD" 2>/dev/null || echo "?")
    log_warn "Claude committed by itself ($_n_self commit(s)) — resetting into working tree for guards"
    git -C "$WORK_DIR" reset --mixed -q "$pre_claude_head" 2>/dev/null || true
  fi

  # ── Check for changes ────────────────────────────────────────────────────
  if ! git_has_changes "$WORK_DIR"; then
    log_warn "No code changes made. Skipping."
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "$BASELINE" false "$iter_cost" "No changes" "$ITER_MODE" "$strategy_summary"
    session_update "$TARGET_DIR" "$((ITER + 1))" "$ITER_MODE" "reverted" "$BASELINE" "" "${strategy_summary:-No changes made}" ""
    STAGNATION=$((STAGNATION + 1))
    ITER=$((ITER + 1))
    continue
  fi

  # ── Run guards ────────────────────────────────────────────────────────────
  log "Running guards..."
  guard_result=$(run_guards "$GUARD_SCRIPT" "$WORK_DIR" 2>&1) || {
    log_err "Guard failed: $guard_result"
    git_revert_changes "$WORK_DIR"
    safe_result=$(sanitize_for_log "$guard_result")
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "" false "$iter_cost" "Guard fail: $safe_result" "$ITER_MODE" "$strategy_summary"
    session_update "$TARGET_DIR" "$((ITER + 1))" "$ITER_MODE" "guard_fail" "$BASELINE" "" "${strategy_summary:-Unknown}" "$safe_result"
    STAGNATION=$((STAGNATION + 1))
    ITER=$((ITER + 1))
    continue
  }
  log_ok "Guards passed"

  # ── Measure ───────────────────────────────────────────────────────────────
  log "Measuring ($SAMPLES samples)..."
  measure_result=$(measure_robust "$MEASURE_SCRIPT" "$WORK_DIR" "$SAMPLES")
  new_score=$(echo "$measure_result" | awk '{print $1}')
  log "Score: $BASELINE → $new_score"

  # ── Compare ───────────────────────────────────────────────────────────────
  if is_significant "$BASELINE" "$new_score" "$NOISE_FLOOR"; then
    log_ok "Improvement detected! Committing."
    git_commit_sosl "$WORK_DIR" "$DOMAIN_NAME" "$BASELINE" "$new_score"
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "$new_score" true "$iter_cost" "Improved" "$ITER_MODE" "$strategy_summary"
    session_update "$TARGET_DIR" "$((ITER + 1))" "$ITER_MODE" "committed" "$BASELINE" "$new_score" "${strategy_summary:-Improvement}" ""
    BASELINE="$new_score"
    IMPROVEMENTS=$((IMPROVEMENTS + 1))
    STAGNATION=0

    # Secondary metrics check (after commit, informational only)
    if [[ -n "${SECONDARY_DOMAINS:-}" ]]; then
      sec_after=$(measure_secondary "$SCRIPT_DIR" "$SECONDARY_DOMAINS" "$WORK_DIR")
      sec_comparison=$(compare_secondary "$SECONDARY_BEFORE" "$sec_after")
      if has_warnings "$sec_comparison"; then
        log_warn "Tradeoff: $(format_secondary "$sec_comparison")"
      fi
      SECONDARY_CONTEXT=$(format_secondary "$sec_comparison")
      export SOSL_SECONDARY="$sec_comparison"
    fi
  else
    log_warn "No significant improvement ($new_score vs baseline $BASELINE, noise $NOISE_FLOOR). Reverting."
    git_revert_changes "$WORK_DIR"
    append_experiment "$TARGET_DIR" "$ITER" "$DOMAIN_NAME" "$BASELINE" "$new_score" false "$iter_cost" "Below noise floor" "$ITER_MODE" "$strategy_summary"
    session_update "$TARGET_DIR" "$((ITER + 1))" "$ITER_MODE" "reverted" "$BASELINE" "$new_score" "${strategy_summary:-Below noise floor}" ""
    STAGNATION=$((STAGNATION + 1))
  fi

  # ── Checkpoint ────────────────────────────────────────────────────────────
  save_checkpoint "$TARGET_DIR" "$RUN_ID" "$ITER" "$BASELINE" "$TOTAL_COST" "$BRANCH" "$DOMAIN_NAME"

  ITER_DURATION=$(($(date +%s) - ITER_START))
  log "Iteration $((ITER + 1)) completed in ${ITER_DURATION}s"
  echo ""

  ITER=$((ITER + 1))
done

fi  # end SEARCH_MODE if/else

# Clear checkpoint on clean completion
clear_checkpoint "$TARGET_DIR" "$RUN_ID"

# Generate summary
write_summary "$TARGET_DIR" "$DOMAIN_NAME"

# ── Branch finalization ─────────────────────────────────────────────────────
if [[ "$FINALIZE" == "true" ]] && [[ "$DRY_RUN" != "true" ]] && [[ ${IMPROVEMENTS:-0} -gt 1 ]]; then
  echo ""
  log_bold "═══ Branch Finalization ═══"
  finalize_branch "$TARGET_DIR" "$BRANCH" "$WORK_DIR"
  log_bold "═══════════════════════════"
  echo ""
fi

# ── Judge Agent review ─────────────────────────────────────────────────────
if [[ "$NO_JUDGE" != "true" ]] && [[ "$DRY_RUN" != "true" ]] && [[ ${IMPROVEMENTS:-0} -gt 0 ]]; then
  echo ""
  log_bold "═══ Judge Agent Review ═══"
  judge_review "$TARGET_DIR" "$DOMAIN_NAME" "$BRANCH" "${BASELINE:-0}" "${INITIAL_BASELINE:-0}" "${IMPROVEMENTS:-0}" "$TOTAL_COST" "$SEARCH_MODE" || true
  log_bold "══════════════════════════"
  echo ""
fi

# ── Auto-PR (after the Judge, so the report can ride along as PR body) ──────
if [[ "$AUTO_PR" == "true" ]] && [[ "$DRY_RUN" != "true" ]] && [[ ${IMPROVEMENTS:-0} -gt 0 ]]; then
  echo ""
  log_bold "═══ Auto-PR ═══"
  create_auto_pr "$TARGET_DIR" "$DOMAIN_NAME" "$BRANCH" "${INITIAL_BASELINE:-0}" "${BASELINE:-0}" "${IMPROVEMENTS:-0}" || true
  log_bold "═══════════════"
  echo ""
fi

log_ok "SOSL loop completed."
