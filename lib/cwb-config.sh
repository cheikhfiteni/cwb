_cwb_user_prefs_file() {
  local home_dir="${HOME:?HOME must be set}"
  printf '%s/.cwb/.cwb-prefs' "$home_dir"
}

_cwb_repo_local_dir() {
  local repo_root="$1"
  printf '%s/.cwb' "$repo_root"
}

_cwb_repo_worktrees_root() {
  local repo_root="$1"
  printf '%s/worktrees' "$(_cwb_repo_local_dir "$repo_root")"
}

_cwb_legacy_worktrees_root() {
  local repo_root="$1"
  printf '%s/.claude/worktrees' "$repo_root"
}

_cwb_default_worktree_path() {
  local repo_root="$1" worktree_name="$2"
  printf '%s/%s' "$(_cwb_repo_worktrees_root "$repo_root")" "$worktree_name"
}

_cwb_legacy_worktree_path() {
  local repo_root="$1" worktree_name="$2"
  printf '%s/%s' "$(_cwb_legacy_worktrees_root "$repo_root")" "$worktree_name"
}

_cwb_candidate_worktree_paths() {
  local repo_root="$1" worktree_name="$2"
  printf '%s\n' "$(_cwb_default_worktree_path "$repo_root" "$worktree_name")"
  printf '%s\n' "$(_cwb_legacy_worktree_path "$repo_root" "$worktree_name")"
}

_cwb_first_existing_worktree_path() {
  local repo_root="$1" worktree_name="$2" candidate
  while IFS= read -r candidate; do
    if [[ -d "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done < <(_cwb_candidate_worktree_paths "$repo_root" "$worktree_name")
  return 1
}

_cwb_read_pref_file() {
  local prefs_file="$1" key="$2" default_val="$3"
  [[ -f "$prefs_file" ]] || { printf '%s' "$default_val"; return; }
  local val
  val="$(grep "^${key}=" "$prefs_file" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]')"
  printf '%s' "${val:-$default_val}"
}

_cwb_read_user_pref() {
  local key="$1" default_val="$2"
  local prefs_file
  prefs_file="$(_cwb_user_prefs_file 2>/dev/null)" || { printf '%s' "$default_val"; return; }
  _cwb_read_pref_file "$prefs_file" "$key" "$default_val"
}

_cwb_write_pref_file() {
  local prefs_file="$1" key="$2" val="$3"
  mkdir -p "$(dirname "$prefs_file")"
  local tmpfile
  tmpfile="$(mktemp)"
  { [[ -f "$prefs_file" ]] && grep -v "^${key}=" "$prefs_file"; } > "$tmpfile" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$val" >> "$tmpfile"
  mv "$tmpfile" "$prefs_file"
}

_cwb_write_user_pref() {
  local key="$1" val="$2"
  local prefs_file
  prefs_file="$(_cwb_user_prefs_file)" || return 1
  _cwb_write_pref_file "$prefs_file" "$key" "$val"
}

_cwb_bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|on|ON|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

_cwb_normalize_bool() {
  if _cwb_bool_is_true "$1"; then
    printf 'on'
  else
    printf 'off'
  fi
}

# Alias for readability in display contexts
_cwb_bool_text() { _cwb_normalize_bool "$@"; }

_cwb_shared_flags() {
  printf '%s\n' tmux yolo
}

_cwb_is_shared_flag() {
  local candidate="$1"
  _cwb_shared_flags | grep -Fx "$candidate" >/dev/null
}

_cwb_supported_agents() {
  printf '%s\n' codex claude
}

_cwb_reserved_commands() {
  printf '%s\n' cwb-setup
}

_cwb_is_reserved_command() {
  local candidate="$1"
  _cwb_reserved_commands | grep -Fx "$candidate" >/dev/null
}

_cwb_reserved_command_prompt_file() {
  local repo_root="$1" command_name="$2"
  case "$command_name" in
    # Load from the install directory alongside the cwb script, not from the
    # repo being managed. This makes cwb portable: the prompt ships with the
    # tool and works regardless of where the tool is installed.
    cwb-setup) printf '%s/lib/setup/cwb-repo-setup.md' "$CWB_SCRIPT_DIR" ;;
    *) return 1 ;;
  esac
}

_cwb_shared_flag_equivalent_cwb_flag() {
  case "$1" in
    tmux) printf '%s' '--tmux' ;;
    yolo) printf '%s' '--yolo' ;;
    *) return 1 ;;
  esac
}

_cwb_shared_flag_agent_mapping() {
  local flag_name="$1" agent_name="$2"
  case "$flag_name:$agent_name" in
    tmux:codex|tmux:claude) printf '%s' 'launch inside a tmux session' ;;
    yolo:codex) printf '%s' '--yolo' ;;
    yolo:claude) printf '%s' '--dangerously-skip-permissions' ;;
    *) return 1 ;;
  esac
}

_cwb_read_default_cli() {
  local default_cli
  default_cli="$(_cwb_read_user_pref 'USER_DEFAULT_CLI' '')"
  if [[ -z "$default_cli" ]]; then
    default_cli="$(_cwb_read_user_pref 'CWB_CLI' 'claude')"
  fi
  printf '%s' "$default_cli"
}

_cwb_read_shared_flag_default() {
  local flag_name="$1"
  _cwb_read_user_pref "SHARED_FLAG_${flag_name}" "off"
}

_cwb_write_shared_flag_default() {
  local flag_name="$1" value="$2"
  _cwb_write_user_pref "SHARED_FLAG_${flag_name}" "$(_cwb_normalize_bool "$value")"
}

# NOTE: mutates the caller's `cli_args` array (bash dynamic scoping).
_cwb_append_shared_cli_flag() {
  local cwb_cli="$1" shared_flag="$2"
  case "$shared_flag" in
    yolo)
      case "$cwb_cli" in
        codex) cli_args+=("--yolo") ;;
        claude) cli_args+=("--dangerously-skip-permissions") ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# NOTE: mutates the caller's `cli_args` array (bash dynamic scoping).
# tmux is handled separately in cwb() — it controls launch mode, not CLI args.
_cwb_apply_shared_flag_defaults() {
  local cwb_cli="$1" use_yolo="$2"
  if _cwb_bool_is_true "$use_yolo"; then
    _cwb_append_shared_cli_flag "$cwb_cli" "yolo"
  fi
}

_cwb_interactive_available() {
  if [[ -n "${CWB_TEST_INTERACTIVE:-}" ]]; then
    return 0
  fi
  [[ -t 0 && -t 1 ]]
}

_cwb_prompt_shared_default_choice() {
  local flag_name="$1" current_value="$2"
  local choice
  while true; do
    printf '[cwb] %s default [on/off/keep] (current: %s): ' "$flag_name" "$current_value" >&2
    IFS= read -r choice || return 1
    case "${choice:-keep}" in
      on|off|keep)
        printf '%s' "${choice:-keep}"
        return 0
        ;;
      *)
        echo "[cwb] Invalid choice: ${choice:-<empty>}" >&2
        ;;
    esac
  done
}

_cwb_print_shared_default_prompt() {
  local flag_name="$1"
  local cwb_flag
  cwb_flag="$(_cwb_shared_flag_equivalent_cwb_flag "$flag_name")"

  echo "[cwb] Shared default: $flag_name"
  echo "[cwb] Yes: this will be applied to all supported agents."
  echo "[cwb] Equivalent cwb command without a default: cwb <name> $cwb_flag"

  local agent_name mapping
  for agent_name in $(_cwb_supported_agents); do
    mapping="$(_cwb_shared_flag_agent_mapping "$flag_name" "$agent_name")" || continue
    echo "[cwb] $agent_name: $mapping"
  done
}

_cwb_interactive_set_defaults() {
  if ! _cwb_interactive_available; then
    echo "[cwb] --set-defaults requires an interactive terminal" >&2
    return 1
  fi

  local prefs_file
  prefs_file="$(_cwb_user_prefs_file)"
  mkdir -p "$(dirname "$prefs_file")"

  echo "[cwb] Shared defaults are stored in $prefs_file"
  echo "[cwb] These defaults only affect cwb launches; explicit CLI flags still pass through as-is."

  local flag_name current_value choice
  for flag_name in $(_cwb_shared_flags); do
    current_value="$(_cwb_read_shared_flag_default "$flag_name")"
    _cwb_print_shared_default_prompt "$flag_name"
    choice="$(_cwb_prompt_shared_default_choice "$flag_name" "$current_value")" || return 1
    if [[ "$choice" != "keep" ]]; then
      _cwb_write_shared_flag_default "$flag_name" "$choice" || return 1
      echo "[cwb] Saved shared default: $flag_name=$choice"
    else
      echo "[cwb] Keeping shared default: $flag_name=$current_value"
    fi
  done

  echo "[cwb] Shared defaults updated."
  _cwb_print_status
}
