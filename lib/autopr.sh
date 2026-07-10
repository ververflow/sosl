#!/bin/bash
# SOSL — Auto-PR: push the sosl branch and open a PR with the Judge report
# as its body. Opt-in via AUTO_PR=true (+ AUTO_PR_REPO). Never fatal: a
# GitHub hiccup must not kill an unattended night run, so every failure path
# logs a warning and returns 0 — the branch always stays available locally.
#
# Config keys (run config or domain config.sh):
#   AUTO_PR=true                 opt-in switch (default: false)
#   AUTO_PR_REPO="owner/repo"    GitHub repo for `gh pr create` (required)
#   AUTO_PR_REMOTE="<url|name>"  push target (default: git@github.com:<repo>.git)
#   AUTO_PR_BASE="main"          PR base branch (default: main)

create_auto_pr() {
  local target="$1" domain="$2" branch="$3" old_score="$4" new_score="$5" improvements="$6"

  command -v gh >/dev/null 2>&1 || { log_warn "auto-PR: gh CLI not found — skipping"; return 0; }
  [[ -n "${AUTO_PR_REPO:-}" ]] || { log_warn "auto-PR: AUTO_PR_REPO not set — skipping"; return 0; }
  [[ -n "$branch" ]] || { log_warn "auto-PR: no branch — skipping"; return 0; }

  local remote="${AUTO_PR_REMOTE:-git@github.com:${AUTO_PR_REPO}.git}"
  local base="${AUTO_PR_BASE:-main}"

  log "auto-PR: pushing $branch"
  local push_out
  if ! push_out=$(git -C "$target" push "$remote" "$branch" 2>&1); then
    log_warn "auto-PR: push failed: $(echo "$push_out" | tail -1) — branch stays local"
    return 0
  fi

  local title="sosl($domain): $old_score → $new_score ($improvements commits)"
  local body_file="$target/.sosl/pr-body.md"
  {
    echo "Autonomous SOSL run: \`$domain\`, **$old_score → $new_score** in $improvements validated commit(s)."
    echo
    echo "Every commit passed the guards (scope, tests, lint) and beat the noise floor."
    echo "The full attempt log, including reverted tries, is in \`.sosl/experiments.jsonl\` on the runner."
    echo
    if [[ -f "$target/.sosl/JUDGE_REPORT.md" ]]; then
      echo "## Judge review"
      echo
      cat "$target/.sosl/JUDGE_REPORT.md"
      echo
    fi
    echo "🤖 Generated with [SOSL](https://github.com/ververflow/sosl)"
  } > "$body_file"

  local url
  if url=$(gh pr create --repo "$AUTO_PR_REPO" --base "$base" --head "$branch" \
        --title "$title" --body-file "$body_file" 2>&1); then
    log_ok "auto-PR: $url"
    echo "$url" > "$target/.sosl/pr-url.txt"
  else
    log_warn "auto-PR: gh pr create failed: $(echo "$url" | tail -1) — branch is pushed, PR it by hand"
  fi
  return 0
}
