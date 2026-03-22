#!/usr/bin/env bash
# cwb-cleanup.sh — Evaluate whether a cwb worktree has changes and clean up if not.
#
# Usage: bash scripts/cwb/lib/lifecycle/cwb-cleanup.sh <worktree_path> <initial_commit> <branch_name> <repo_root>
#
# Called by cwb() after claude exits (both tmux and non-tmux paths).
# Keeps the worktree if there are commits, uncommitted changes, or a detached HEAD.
# Removes the worktree and branch if HEAD is unchanged and the working tree is clean.

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/../cwb-config.sh"

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <worktree_path> <initial_commit> <branch_name> <repo_root>" >&2
  exit 1
fi

worktree_path="$1"
initial_commit="$2"
branch_name="$3"
repo_root="$4"

if [[ ! -d "$worktree_path" ]]; then
  relative_branch_name="${branch_name#cwb/}"
  worktree_path="$(_cwb_first_existing_worktree_path "$repo_root" "$relative_branch_name")" || {
    echo "[cwb] Worktree not found at any candidate path — skipping cleanup"
    exit 0
  }
fi

dirty="$(git -C "$worktree_path" status --porcelain 2>/dev/null)"
current_commit="$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null)"
is_detached=false
git -C "$worktree_path" symbolic-ref HEAD >/dev/null 2>&1 || is_detached=true

if [[ "$is_detached" == true ]]; then
  echo "[cwb] Detached HEAD — keeping worktree: $worktree_path"
elif [[ -n "$dirty" || "$current_commit" != "$initial_commit" ]]; then
  echo "[cwb] Changes detected — keeping worktree: $worktree_path (branch: $branch_name)"
else
  echo "[cwb] No changes — cleaning up worktree and branch..."
  git -C "$repo_root" worktree remove --force "$worktree_path"
  git -C "$repo_root" branch -d "$branch_name" 2>/dev/null || \
    git -C "$repo_root" branch -D "$branch_name"
fi
