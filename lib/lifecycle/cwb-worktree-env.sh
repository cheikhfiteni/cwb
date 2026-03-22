#!/usr/bin/env bash
# cwb-worktree-env.sh — Symlink shared .env files into a new worktree and
# create .env.local stubs for worktree-specific overrides.
#
# Usage: bash scripts/cwb/lib/lifecycle/cwb-worktree-env.sh <repo_root> <worktree_path> [worktree_name] [copy_volumes]
#
#   worktree_name  Name of the worktree (used for Docker volume isolation).
#                  Defaults to basename of worktree_path.
#   copy_volumes   "true" (default) or "false". When true, all docker-compose
#                  named volumes are prefixed with the worktree name so each
#                  worktree runs its own isolated Docker volumes.
#
# Called automatically by cwb() after "git worktree add". Safe to re-run
# (idempotent): existing symlinks and stubs are never overwritten.

set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 <repo_root> <worktree_path> [worktree_name] [copy_volumes]" >&2
  exit 1
fi

repo_root="$1"
worktree_path="$2"
worktree_name="${3:-}"
copy_volumes="${4:-true}"

# Derive worktree name from path if not explicitly provided
[[ -z "$worktree_name" ]] && worktree_name="$(basename "$worktree_path")"

# Load port specs from the repo's .cwb/port-specs file (if present).
# Format: one "VAR_NAME|base_port" entry per line; blank lines and # comments ignored.
# If the file is absent, port allocation is skipped entirely.
PORT_OVERRIDE_SPECS=()
_cwb_port_specs_file="$repo_root/.cwb/port-specs"
if [[ -f "$_cwb_port_specs_file" ]]; then
  while IFS= read -r _cwb_port_spec_line; do
    [[ -z "$_cwb_port_spec_line" || "$_cwb_port_spec_line" == '#'* ]] && continue
    # Strip leading/trailing whitespace so e.g. "API_PORT|8000 " doesn't cause
    # arithmetic errors in find_available_port.
    _cwb_port_spec_line="${_cwb_port_spec_line#"${_cwb_port_spec_line%%[![:space:]]*}"}"
    _cwb_port_spec_line="${_cwb_port_spec_line%"${_cwb_port_spec_line##*[![:space:]]}"}"
    [[ -n "$_cwb_port_spec_line" ]] && PORT_OVERRIDE_SPECS+=("$_cwb_port_spec_line")
  done < "$_cwb_port_specs_file"
fi

# Auto-discover .env files from the main repo, excluding worktrees and noise.
# This avoids maintaining a hardcoded list — any new .env file in the repo is
# automatically picked up.
env_files=()
while IFS= read -r line; do
  env_files+=("$line")
done < <(
  find "$repo_root" -name ".env" \( -type f -o -type l \) \
    -not -path "$repo_root/.claude/worktrees/*" \
    -not -path "$repo_root/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/.venv/*" \
    | sed "s|^$repo_root/||" \
    | sort
)

# --- helpers -----------------------------------------------------------------

# Prompt helper: ask before overwriting existing files on reruns.
# Default is "no" to preserve current behavior unless explicitly confirmed.
confirm_overwrite() {
  local prompt="$1"
  local response

  if [[ ! -t 0 ]]; then
    echo "[cwb-env] Non-interactive shell; preserving existing files by default."
    return 1
  fi

  read -r -p "$prompt [y/N]: " response
  [[ "$response" =~ ^([yY]|[yY][eE][sS])$ ]]
}

sanitize_compose_project_suffix() {
  local raw_name="$1"
  local sanitized_name
  sanitized_name="$(
    printf '%s' "$raw_name" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
  )"

  if [[ -z "$sanitized_name" ]]; then
    sanitized_name="worktree"
  fi

  printf '%s' "$sanitized_name"
}

reserved_ports=()
generated_worktree_port_overrides=""
available_port_result=""

port_is_reserved() {
  local candidate="$1"
  local reserved_port
  for reserved_port in "${reserved_ports[@]-}"; do
    if [[ "$reserved_port" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

port_is_available() {
  local candidate="$1"
  local python_bin

  if port_is_reserved "$candidate"; then
    return 1
  fi

  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$candidate" -sTCP:LISTEN >/dev/null 2>&1; then
    return 1
  fi

  python_bin="$(command -v python3 || command -v python || true)"
  if [[ -z "$python_bin" ]]; then
    echo "[cwb-env] WARNING: python not found; cannot check port availability for $candidate" >&2
    return 0
  fi

  "$python_bin" - "$candidate" <<'PY'
import socket
import sys

port = int(sys.argv[1])

def can_bind(family, address):
    with socket.socket(family, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((address, port))
        except OSError:
            return False
    return True

if not can_bind(socket.AF_INET, "127.0.0.1"):
    raise SystemExit(1)

if socket.has_ipv6 and not can_bind(socket.AF_INET6, "::1"):
    raise SystemExit(1)
PY
}

find_available_port() {
  local default_port="$1"
  local candidate=$((default_port + 100))
  local max_candidate=$((candidate + 100))

  while ! port_is_available "$candidate"; do
    candidate=$((candidate + 1))
    if (( candidate > max_candidate )); then
      echo "[cwb-env] WARNING: could not find free port in range $((default_port + 100))..$max_candidate; using $((default_port + 100))" >&2
      candidate=$((default_port + 100))
      break
    fi
  done

  reserved_ports+=("$candidate")
  available_port_result="$candidate"
}

generate_worktree_port_overrides() {
  local spec env_name default_port assigned_port
  local lines=()

  if [[ -n "$generated_worktree_port_overrides" ]]; then
    printf '%s' "$generated_worktree_port_overrides"
    return
  fi

  if [[ "$worktree_path" == "$repo_root" ]]; then
    return
  fi

  for spec in "${PORT_OVERRIDE_SPECS[@]-}"; do
    IFS='|' read -r env_name default_port <<< "$spec"
    find_available_port "$default_port"
    assigned_port="$available_port_result"
    lines+=("${env_name}=${assigned_port}")
  done

  [[ ${#lines[@]} -eq 0 ]] && return

  generated_worktree_port_overrides="$(printf '%s\n' "${lines[@]}")"
  printf '%s' "$generated_worktree_port_overrides"
}

# Create a symlink for a single .env file into the worktree.
# Skips silently if the source does not exist in the main repo.
link_env_file() {
  local relative_path="$1"
  local source_path="$repo_root/$relative_path"
  local target_path="$worktree_path/$relative_path"
  local target_dir
  local desired_target
  target_dir="$(dirname "$target_path")"

  # Check both real files and symlinks (including dangling ones)
  if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
    echo "[cwb-env] Skipping $relative_path (not found in main repo)"
    return
  fi

  mkdir -p "$target_dir"

  if [[ -L "$source_path" ]]; then
    # Source is itself a symlink — reproduce the same link target in the worktree
    # so worktree/.env -> same-target rather than worktree/.env -> main-repo/.env -> target
    desired_target="$(readlink "$source_path")"
  else
    desired_target="$source_path"
  fi

  if [[ -L "$target_path" ]]; then
    local current_target
    current_target="$(readlink "$target_path" 2>/dev/null || true)"
    if [[ "$current_target" == "$desired_target" ]]; then
      echo "[cwb-env] Already linked: $relative_path"
      return
    fi
    if ! confirm_overwrite "[cwb-env] $relative_path points to '$current_target'. Overwrite link target to '$desired_target'?"; then
      echo "[cwb-env] Preserved existing link: $relative_path"
      return
    fi
    rm -f "$target_path"
  elif [[ -e "$target_path" ]]; then
    if ! confirm_overwrite "[cwb-env] $relative_path exists and is not a symlink. Replace with symlink to '$desired_target'?"; then
      echo "[cwb-env] Preserved existing file: $relative_path"
      return
    fi
    rm -f "$target_path"
  fi

  ln -sfn "$desired_target" "$target_path"
  if [[ -L "$source_path" ]]; then
    echo "[cwb-env] Linked (preserved symlink): $relative_path -> $desired_target"
  else
    echo "[cwb-env] Linked: $relative_path -> $desired_target"
  fi
}

# Create a .env.local stub next to a symlinked .env file.
# The stub is for worktree-local overrides (e.g. unique ports, API base URLs)
# so each worktree can run its own services independently.
create_env_local_stub() {
  local relative_path="$1"
  local source_path="$repo_root/$relative_path"
  local env_local_path="$worktree_path/$(dirname "$relative_path")/.env.local"
  local env_local_target
  local current_target

  if [[ -L "$source_path" ]]; then
    env_local_target="$(readlink "$source_path")"
    env_local_target="${env_local_target%.env}.env.local"

    if [[ -L "$env_local_path" ]]; then
      current_target="$(readlink "$env_local_path" 2>/dev/null || true)"
      if [[ "$current_target" == "$env_local_target" ]]; then
        echo "[cwb-env] Already linked stub: $(dirname "$relative_path")/.env.local -> $env_local_target"
        return
      fi
      if ! confirm_overwrite "[cwb-env] Stub symlink exists at $(dirname "$relative_path")/.env.local. Overwrite it?"; then
        echo "[cwb-env] Preserved stub: $(dirname "$relative_path")/.env.local"
        return
      fi
      rm -f "$env_local_path"
    elif [[ -e "$env_local_path" ]]; then
      if ! confirm_overwrite "[cwb-env] Stub exists at $(dirname "$relative_path")/.env.local. Replace it with a symlink?"; then
        echo "[cwb-env] Preserved stub: $(dirname "$relative_path")/.env.local"
        return
      fi
      rm -f "$env_local_path"
    fi

    ln -sfn "$env_local_target" "$env_local_path"
    echo "[cwb-env] Linked stub: $(dirname "$relative_path")/.env.local -> $env_local_target"
    return
  fi

  if [[ -f "$env_local_path" && "$worktree_path" != "$repo_root" && ${#PORT_OVERRIDE_SPECS[@]} -gt 0 ]]; then
    local _first_var
    IFS='|' read -r _first_var _ <<< "${PORT_OVERRIDE_SPECS[0]}"
    if ! grep -q "^${_first_var}=" "$env_local_path"; then
      {
        echo ""
        echo "# Auto-selected ports for this worktree. Edit any of these if they clash."
        generate_worktree_port_overrides
      } >> "$env_local_path"
      echo "[cwb-env] Upgraded existing stub with auto-selected ports: $(dirname "$relative_path")/.env.local"
      return
    fi
  fi

  if [[ -e "$env_local_path" ]]; then
    if ! confirm_overwrite "[cwb-env] Stub exists at $(dirname "$relative_path")/.env.local. Overwrite it?"; then
      echo "[cwb-env] Preserved stub: $(dirname "$relative_path")/.env.local"
      return
    fi
  fi

  cat > "$env_local_path" <<'STUB'
# .env.local — worktree-specific overrides
#
# This file is NOT tracked by git and is NOT symlinked from the main repo.
# Use it to override values from .env so that this worktree can run its own
# services independently (e.g. on different ports) without conflicting with
# other worktrees or the main dev environment.
#
# Edit as needed. Use `bash scripts/cwb/lib/lifecycle/cwb-compose.sh ...` for Docker Compose
# commands so the cwb layer exports these overrides before Compose evaluates the file.
#
# Example overrides:
# DATABASE_PORT=5433
# FASTAPI_PORT=8001
# API_BASE_URL=http://localhost:8001
# MOBILE_BACKEND_PORT=8091
# MOBILE_API_BASE_URL=http://localhost:8091
# GRPC_PORT=50053
# PREVIEW_ATC_GRPC_URL=localhost:50053
# HATCHET_SERVER_URL=http://localhost:8889
STUB

  if [[ "$worktree_path" != "$repo_root" && ${#PORT_OVERRIDE_SPECS[@]} -gt 0 ]]; then
    {
      echo ""
      echo "# Auto-selected ports for this worktree. Edit any of these if they clash."
      generate_worktree_port_overrides
    } >> "$env_local_path"
  fi

  echo "[cwb-env] Created stub: $(dirname "$relative_path")/.env.local"
}

# --- main --------------------------------------------------------------------

echo "[cwb-env] Setting up .env symlinks in $worktree_path"

for relative_path in "${env_files[@]}"; do
  link_env_file "$relative_path"
  # Only create the stub next to files that actually exist in the main repo.
  # Use -e || -L to match the same dangling-symlink awareness as link_env_file.
  if [[ -e "$repo_root/$relative_path" || -L "$repo_root/$relative_path" ]]; then
    create_env_local_stub "$relative_path"
  fi
done

# --- docker-compose volume isolation -----------------------------------------
# When copy_volumes=true (the default), ensure every compose invocation in the
# worktree uses project name "cwb-<worktree_name>".  Docker Compose v2 prefixes
# all named volumes with the project name, so each worktree gets its own
# isolated volumes (e.g. cwb-swift-river-stone_hatchet_postgres_data).
#
# Two complementary mechanisms (belt-and-suspenders):
#   1. docker-compose.override.yml with `name:` — auto-loaded for default
#      `docker compose up` invocations (without -f).  Gitignored via
#      worktree-local exclude.
#   2. COMPOSE_PROJECT_NAME in .env — read by Docker Compose for ALL
#      invocations including `docker compose -f <file>`.  The .env symlink
#      is converted to a real copy so we can append without modifying the
#      main repo.  Safe because worktrees are ephemeral.

if [[ "$copy_volumes" == "true" ]]; then
  echo "[cwb-env] Setting up docker-compose volume isolation via project name..."

  # Register the override filename in the worktree-local git exclude so it is
  # invisible to git without modifying any tracked file (e.g. .gitignore).
  git_dir="$(git -C "$worktree_path" rev-parse --git-dir)"
  exclude_file="$git_dir/info/exclude"
  mkdir -p "$(dirname "$exclude_file")"
  if ! grep -qxF "docker-compose.override.yml" "$exclude_file" 2>/dev/null; then
    echo "docker-compose.override.yml" >> "$exclude_file"
    echo "[cwb-env] Registered docker-compose.override.yml in worktree gitignore."
  fi

  # Docker project name must stay within Compose's allowed character set even
  # when worktree names include nested paths such as "ios/state-caching".
  project_name="cwb-$(sanitize_compose_project_suffix "$worktree_name")"

  # Find every unique directory that contains a compose file and write an
  # override that sets the project name.  Auto-discovered — no list to maintain.
  created_count=0
  while IFS= read -r compose_dir; do
    # --- docker-compose.override.yml (for default invocations without -f) ---
    override_file="$compose_dir/docker-compose.override.yml"
    if [[ -e "$override_file" ]]; then
      if ! confirm_overwrite "[cwb-env] Override exists at ${compose_dir#$worktree_path/}/docker-compose.override.yml. Overwrite it?"; then
        echo "[cwb-env] Preserved override: ${compose_dir#$worktree_path/}/docker-compose.override.yml"
      else
        cat > "$override_file" << OVERRIDE
# Auto-generated by cwb-worktree-env.sh — do not commit (gitignored).
# Sets the Docker Compose project name so this worktree uses its own isolated
# volumes (e.g. ${project_name}_hatchet_postgres_data) and does not share
# state with other worktrees or the main dev environment.
name: ${project_name}
OVERRIDE
        echo "[cwb-env] Overwrote override: ${compose_dir#$worktree_path/}/docker-compose.override.yml (project: $project_name)"
      fi
    else
      cat > "$override_file" << OVERRIDE
# Auto-generated by cwb-worktree-env.sh — do not commit (gitignored).
# Sets the Docker Compose project name so this worktree uses its own isolated
# volumes (e.g. ${project_name}_hatchet_postgres_data) and does not share
# state with other worktrees or the main dev environment.
name: ${project_name}
OVERRIDE
      echo "[cwb-env] Created override: ${compose_dir#$worktree_path/}/docker-compose.override.yml (project: $project_name)"
      created_count=$((created_count + 1))
    fi

    # --- COMPOSE_PROJECT_NAME in .env (for -f invocations) ---
    # docker-compose.override.yml is only auto-loaded without -f.  Setting
    # COMPOSE_PROJECT_NAME in the directory's .env ensures volume isolation for
    # ALL compose invocations (e.g. docker compose -f docker-compose.eval.yaml).
    env_file="$compose_dir/.env"
    if [[ -L "$env_file" ]]; then
      # .env is a symlink from the linking phase — convert to a real copy so we
      # can append COMPOSE_PROJECT_NAME without modifying the main repo.
      # Ephemeral worktrees don't need live-updating symlinks.
      resolved="$(readlink -f "$env_file" 2>/dev/null || true)"
      if [[ -n "$resolved" && -f "$resolved" ]]; then
        rm "$env_file"
        cp "$resolved" "$env_file"
      else
        rm "$env_file"
        touch "$env_file"
      fi
      echo "[cwb-env] Converted .env symlink to copy in ${compose_dir#$worktree_path/}/"
    fi
    if grep -q '^COMPOSE_PROJECT_NAME=' "$env_file" 2>/dev/null; then
      existing_project_name="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$env_file" | tail -n 1)"
      if [[ "$existing_project_name" == "$project_name" ]]; then
        echo "[cwb-env] COMPOSE_PROJECT_NAME already set in ${compose_dir#$worktree_path/}/.env"
      elif confirm_overwrite "[cwb-env] ${compose_dir#$worktree_path/}/.env has COMPOSE_PROJECT_NAME=$existing_project_name. Overwrite with $project_name?"; then
        temp_env_file="${env_file}.tmp.$$"
        awk -v project_name="$project_name" '
          BEGIN { replaced = 0 }
          /^COMPOSE_PROJECT_NAME=/ {
            if (!replaced) {
              print "COMPOSE_PROJECT_NAME=" project_name
              replaced = 1
            }
            next
          }
          { print }
          END {
            if (!replaced) {
              print "COMPOSE_PROJECT_NAME=" project_name
            }
          }
        ' "$env_file" > "$temp_env_file"
        mv "$temp_env_file" "$env_file"
        echo "[cwb-env] Updated COMPOSE_PROJECT_NAME=$project_name in ${compose_dir#$worktree_path/}/.env"
      else
        echo "[cwb-env] Preserved COMPOSE_PROJECT_NAME in ${compose_dir#$worktree_path/}/.env"
      fi
    else
      {
        echo ""
        echo "# Auto-added by cwb-worktree-env.sh — Docker volume isolation"
        echo "COMPOSE_PROJECT_NAME=$project_name"
      } >> "$env_file"
      echo "[cwb-env] Set COMPOSE_PROJECT_NAME=$project_name in ${compose_dir#$worktree_path/}/.env"
    fi
  done < <(
    find "$worktree_path" \
      \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \
         -o -name "compose.yml"      -o -name "compose.yaml" \) \
      -not -name "docker-compose.override.yml" \
      -not -path "*/node_modules/*" \
      -not -path "*/.venv/*" \
      -not -path "*/.git/*" \
      | xargs -I{} dirname {} \
      | sort -u
  )

  if [[ $created_count -eq 0 ]]; then
    echo "[cwb-env] No new docker-compose overrides created (already exist or no compose files found)."
  fi
fi

# --- post-worktree-setup hook ------------------------------------------------
# Run the repo's custom hook if present. The hook handles any repo-specific
# setup steps (e.g. proto compilation, derived service URL injection).
# Place the hook at .cwb/hooks/post-worktree-setup.sh in the repo root.
# Called with: <worktree_path> <repo_root>. Failures are non-fatal.

hook_path="$repo_root/.cwb/hooks/post-worktree-setup.sh"
if [[ -f "$hook_path" ]]; then
  echo "[cwb-env] Running post-worktree-setup hook..."
  if (bash "$hook_path" "$worktree_path" "$repo_root" 2>&1 | sed 's/^/[cwb-env]   /'); then
    echo "[cwb-env] post-worktree-setup hook completed."
  else
    echo "[cwb-env] WARNING: post-worktree-setup hook failed (non-fatal)." >&2
  fi
fi

echo "[cwb-env] Done."
