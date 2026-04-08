#!/bin/bash
# SOSL — Parallel Multi-Domain Orchestrator
# Runs multiple SOSL instances in parallel via git worktrees
#
# Usage: bash sosl-parallel.sh --target <dir> --domains "performance,accessibility" [sosl.sh flags]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ── Defaults ────────────────────────────────────────────────────────────────
TARGET_DIR=""
DOMAINS=""
SOSL_ARGS=()
PIDS=()
WORKTREES=()

# ── Parse arguments ─────────────────────────────────────────────────────────
print_usage() {
  cat <<EOF
${BOLD}SOSL Parallel — Multi-Domain Orchestrator${NC}

Usage: bash sosl-parallel.sh --target <dir> --domains "domain1,domain2" [sosl.sh options]

Required:
  --target <dir>          Target repository to optimize
  --domains <list>        Comma-separated domain names (must exist in domains/)

All other flags are passed through to sosl.sh per instance.

Example:
  bash sosl-parallel.sh --target /c/Dev/houtcalc \\
    --domains "performance,code-quality" \\
    --max-iterations 20 --max-hours 8
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET_DIR="$2"; shift 2 ;;
    --domains) DOMAINS="$2"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    *)         SOSL_ARGS+=("$1"); shift ;;
  esac
done

[[ -z "$TARGET_DIR" ]] && { log_err "Missing --target"; print_usage; exit 1; }
[[ -z "$DOMAINS" ]]    && { log_err "Missing --domains"; print_usage; exit 1; }

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# ── Validate domains ───────────────────────────────────────────────────────
IFS=',' read -ra DOMAIN_LIST <<< "$DOMAINS"
for domain in "${DOMAIN_LIST[@]}"; do
  domain_dir="$SCRIPT_DIR/domains/$domain"
  if [[ ! -d "$domain_dir" ]]; then
    log_err "Domain not found: $domain_dir"
    exit 1
  fi
done

# ── Cleanup on exit ─────────────────────────────────────────────────────────
cleanup_parallel() {
  log_warn "Shutting down parallel instances..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true

  echo ""
  log_bold "═══ Parallel SOSL Summary ═══"
  for domain in "${DOMAIN_LIST[@]}"; do
    local logfile="$TARGET_DIR/.sosl/parallel-${domain}.log"
    if [[ -f "$logfile" ]]; then
      log "[$domain] Log: $logfile"
    fi
  done

  # Show worktrees for review
  echo ""
  log "Worktrees for review:"
  for wt in "${WORKTREES[@]}"; do
    if [[ -d "$wt" ]]; then
      local branch
      branch=$(git -C "$wt" branch --show-current 2>/dev/null || echo "unknown")
      log "  $wt → branch: $branch"
    fi
  done
  log_bold "═════════════════════════════"
}
trap cleanup_parallel EXIT

# ── Create worktrees and launch instances ───────────────────────────────────
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORKTREE_BASE="$TARGET_DIR/.sosl-worktrees"
mkdir -p "$WORKTREE_BASE"

log_bold "═══ SOSL Parallel Launch ═══"
log "Target: $TARGET_DIR"
log "Domains: ${DOMAIN_LIST[*]}"
log "Timestamp: $TIMESTAMP"
echo ""

PORT_BASE=3000
for i in "${!DOMAIN_LIST[@]}"; do
  domain="${DOMAIN_LIST[$i]}"
  worktree_path="$WORKTREE_BASE/$domain"
  branch_name="sosl/${domain}/${TIMESTAMP}"
  domain_dir="$SCRIPT_DIR/domains/$domain"
  logfile="$TARGET_DIR/.sosl/parallel-${domain}.log"

  # Port offset for domains that need dev servers
  port_offset=$((i + 1))
  frontend_port=$((PORT_BASE + port_offset))
  backend_port=$((8000 + port_offset))

  # Remove existing worktree if present
  if [[ -d "$worktree_path" ]]; then
    git -C "$TARGET_DIR" worktree remove "$worktree_path" --force 2>/dev/null || true
  fi

  # Create worktree
  log "[$domain] Creating worktree at $worktree_path..."
  git -C "$TARGET_DIR" worktree add -b "$branch_name" "$worktree_path" HEAD 2>/dev/null || {
    log_err "[$domain] Failed to create worktree"
    continue
  }
  WORKTREES+=("$worktree_path")

  # Launch SOSL in background
  log "[$domain] Launching SOSL (frontend:$frontend_port, log: $logfile)..."

  TARGET_URL="http://localhost:${frontend_port}" \
  bash "$SCRIPT_DIR/sosl.sh" \
    --domain "$domain_dir" \
    --target "$worktree_path" \
    "${SOSL_ARGS[@]}" \
    > "$logfile" 2>&1 &

  PIDS+=($!)
  log_ok "[$domain] Started (PID: ${PIDS[-1]})"
done

echo ""
log_bold "All instances launched. Waiting for completion..."
log "Monitor logs: tail -f $TARGET_DIR/.sosl/parallel-*.log"
echo ""

# ── Wait for all instances ──────────────────────────────────────────────────
FAILED=0
for i in "${!PIDS[@]}"; do
  pid="${PIDS[$i]}"
  domain="${DOMAIN_LIST[$i]}"
  wait "$pid" 2>/dev/null || {
    log_warn "[$domain] Instance exited with error (PID: $pid)"
    FAILED=$((FAILED + 1))
  }
  log_ok "[$domain] Completed"
done

echo ""
if [[ $FAILED -eq 0 ]]; then
  log_ok "All instances completed successfully."
else
  log_warn "$FAILED instance(s) exited with errors."
fi

# ── Generate per-domain summaries ───────────────────────────────────────────
for domain in "${DOMAIN_LIST[@]}"; do
  worktree_path="$WORKTREE_BASE/$domain"
  if [[ -f "$worktree_path/.sosl/experiments.jsonl" ]]; then
    source "$SCRIPT_DIR/lib/annotate.sh"
    write_summary "$worktree_path" "$domain"
    log "[$domain] Summary: $worktree_path/.sosl/SUMMARY.md"
  fi
done

log ""
log "Review branches and merge improvements manually."
log "Worktrees are at: $WORKTREE_BASE/"
