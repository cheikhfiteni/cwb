#!/usr/bin/env bash
# .cwb/hooks/post-worktree-setup.sh — post-worktree setup hook.
#
# Called by cwb-worktree-env.sh after .env symlinking and port allocation.
# Arguments: <worktree_path> <repo_root>
#
# Responsibilities:
#   1. Append derived service URLs to .env.local from the allocated ports.
#   2. Compile proto files so the worktree starts with consistent generated bindings.

set -euo pipefail

worktree_path="$1"
repo_root="$2"

# --- Derived service URLs ---------------------------------------------------
env_local="$worktree_path/.env.local"
if [[ -f "$env_local" && "$worktree_path" != "$repo_root" ]]; then
  _read_port() { grep "^${1}=" "$env_local" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]'; }

  API_PORT="$(_read_port API_PORT)"

  if [[ -n "$API_PORT" ]] && ! grep -q '^API_BASE_URL=' "$env_local"; then
    {
      echo ""
      echo "# Derived service URLs (auto-generated from allocated ports above)"
      [[ -n "$API_PORT" ]] && echo "API_BASE_URL=http://localhost:${API_PORT}"
    } >> "$env_local"
    echo "[cwb-hook] Appended derived service URLs to .env.local"
  fi
fi

# --- Proto compilation -------------------------------------------------------
if [[ -f "$worktree_path/scripts/compile_protos.sh" ]]; then
  if (cd "$worktree_path" && bash scripts/compile_protos.sh); then
    echo "[cwb-hook] Protos generated."
  else
    echo "[cwb-hook] WARNING: proto generation failed (non-fatal)." >&2
  fi
fi
