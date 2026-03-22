_cwb_print_help() {
  cat <<EOF
cwb ${CWB_VERSION}

High-level wrapper around coding-agent CLIs that creates or reuses a git worktree,
applies optional shared defaults, and launches the selected agent inside that worktree.

Usage:
  cwb
  cwb --new [cwb flags] [-- <agent args...>]
  cwb <name> [cwb flags] [-- <agent args...>]
  cwb cwb-setup [-- <agent args>]
  cwb set-default=<claude|codex>
  cwb --set-defaults
  cwb --status
  cwb --help

Launch defaults:
  No args: interactive picker on a TTY; random branch when non-interactive.
  --new: skip the picker and force a fresh random branch name.
  Shared defaults are stored in ~/.cwb/.cwb-prefs and are set only via --set-defaults.

CWB flags:
  --tmux                Run the agent in a new tmux session.
  --no-tmux             Disable the tmux default for this launch.
  --yolo                Enable the shared "dangerous permissions" mode for this launch.
  --no-yolo             Disable the yolo default for this launch.
  --copy-volumes=true   Prefix Docker volumes with the worktree name.
  --copy-volumes=false  Disable Docker volume isolation.
  --no-mcp              Disable project MCP servers in the worktree session.
  --new                 Force a new random branch instead of opening the picker.
  --set-defaults        Interactively set shared defaults for supported agents.
  --status              Print version, prefs path, and effective defaults.
  --version             Print the cwb version.
  --help, -h            Print this help text.

Reserved commands:
  cwb cwb-setup [-- <agent args>]
                        Opens (or reuses) the cwb-setup worktree and injects the
                        repo-setup prompt by default. Pass -- <agent args> to skip
                        the default prompt and supply custom instructions instead.

Forwarding args:
  Unless a shared default is enabled, cwb stays passthrough.
  Use "--" to separate cwb flags from raw agent flags when needed.
  Example: cwb fix-auth --yolo -- --model gpt-5.4 -c

Shared flag mapping:
  yolo -> cwb flag: --yolo
    codex: --yolo
    claude: --dangerously-skip-permissions
  tmux -> cwb flag: --tmux
    codex: launch inside a tmux session
    claude: launch inside a tmux session

Examples:
  cwb
  cwb cwb-setup
  cwb --set-defaults
  cwb --new --yolo
  cwb inbox-refactor --tmux -- --model gpt-5.4
  cwb set-default=codex
EOF
}

_cwb_print_status() {
  local prefs_file default_cli key val flag_name agent_name mapping
  prefs_file="$(_cwb_user_prefs_file)"
  default_cli="$(_cwb_read_default_cli)"

  echo "cwb status"
  echo "Version: $CWB_VERSION"
  echo "Preferences file: $prefs_file"
  echo "Default CLI: $default_cli"
  for flag_name in $(_cwb_shared_flags); do
    echo "Shared default [$flag_name]: $(_cwb_read_shared_flag_default "$flag_name")"
    echo "Equivalent cwb flag [$flag_name]: $(_cwb_shared_flag_equivalent_cwb_flag "$flag_name")"
    for agent_name in $(_cwb_supported_agents); do
      mapping="$(_cwb_shared_flag_agent_mapping "$flag_name" "$agent_name")" || continue
      echo "Agent flag [$flag_name][$agent_name]: $mapping"
    done
  done

  if [[ -f "$prefs_file" ]]; then
    while IFS='=' read -r key val; do
      [[ -n "$key" ]] || continue
      case "$key" in
        USER_DEFAULT_CLI|CWB_CLI|SHARED_FLAG_*) continue ;;
      esac
      echo "User pref [$key]: $val"
    done < "$prefs_file"
  fi
}
