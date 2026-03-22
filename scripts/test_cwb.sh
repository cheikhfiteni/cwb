#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="${CWB_SOURCE_ROOT:-$ROOT_DIR}"
TEST_TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

pass_count=0
fail_count=0

fail() {
  echo "[FAIL] $*" >&2
  return 1
}

assert_file_exists() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    fail "Expected file to exist: $path"
    return 1
  fi
}

assert_file_not_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    fail "Expected file to not exist: $path"
    return 1
  fi
}

assert_contains() {
  local file_path="$1"
  local pattern="$2"
  if ! grep -F -- "$pattern" "$file_path" >/dev/null; then
    fail "Expected '$pattern' in $file_path"
    return 1
  fi
}

assert_not_contains() {
  local file_path="$1"
  local pattern="$2"
  if [[ -f "$file_path" ]] && grep -F -- "$pattern" "$file_path" >/dev/null; then
    fail "Did not expect '$pattern' in $file_path"
    return 1
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    fail "Expected '$expected' but got '$actual'"
    return 1
  fi
}

assert_symlink_target() {
  local path="$1"
  local expected_target="$2"
  local actual_target

  if [[ ! -L "$path" ]]; then
    fail "Expected symlink: $path"
    return 1
  fi

  actual_target="$(readlink "$path")"
  if [[ "$actual_target" != "$expected_target" ]]; then
    fail "Expected $path -> $expected_target, got: $actual_target"
    return 1
  fi
}

setup_repo() {
  local repo_name="$1"
  local repo_path="$TEST_TMP_ROOT/$repo_name"

  mkdir -p "$repo_path"
  git -C "$repo_path" init -b main >/dev/null
  git -C "$repo_path" config user.email "cwb-tests@example.com"
  git -C "$repo_path" config user.name "CWB Tests"

  cp "$SOURCE_ROOT/cwb" "$repo_path/cwb"
  chmod +x "$repo_path/cwb"
  mkdir -p "$repo_path/lib" "$repo_path/lib/setup" \
    "$repo_path/scripts/cwb/lib/lifecycle"
  cp "$SOURCE_ROOT/lib/setup/cwb-repo-setup.md" "$repo_path/lib/setup/cwb-repo-setup.md"
  cp "$SOURCE_ROOT/lib/cwb-config.sh" "$repo_path/lib/cwb-config.sh"
  cp "$SOURCE_ROOT/lib/cwb-status.sh" "$repo_path/lib/cwb-status.sh"

  mkdir -p "$repo_path/.cwb/worktrees" "$repo_path/.claude/worktrees" "$repo_path/bin" "$repo_path/home"

  cat > "$repo_path/scripts/cwb/lib/lifecycle/cwb-worktree-env.sh" <<'ENV_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$1"
worktree_path="$2"
worktree_name="${3:-}"
copy_volumes="${4:-}"
echo "${worktree_path}|${worktree_name}|${copy_volumes}" >> "$repo_root/.test-env-calls"
ENV_SCRIPT
  chmod +x "$repo_path/scripts/cwb/lib/lifecycle/cwb-worktree-env.sh"

  cat > "$repo_path/scripts/cwb/lib/lifecycle/cwb-cleanup.sh" <<'CLEANUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
worktree_path="$1"
initial_commit="$2"
branch_name="$3"
repo_root="$4"
echo "${worktree_path}|${initial_commit}|${branch_name}|${repo_root}" >> "$repo_root/.test-cleanup-calls"
CLEANUP_SCRIPT
  chmod +x "$repo_path/scripts/cwb/lib/lifecycle/cwb-cleanup.sh"

  cat > "$repo_path/bin/claude" <<'CLAUDE_BIN'
#!/usr/bin/env bash
set -euo pipefail
echo "claude|$PWD|$*" >> "${CWB_TEST_LOG:?missing CWB_TEST_LOG}"
CLAUDE_BIN
  chmod +x "$repo_path/bin/claude"

  cat > "$repo_path/bin/codex" <<'CODEX_BIN'
#!/usr/bin/env bash
set -euo pipefail
echo "codex|$PWD|$*" >> "${CWB_TEST_LOG:?missing CWB_TEST_LOG}"
CODEX_BIN
  chmod +x "$repo_path/bin/codex"

  cat > "$repo_path/bin/tmux" <<'TMUX_BIN'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi

if [[ "${1:-}" != "new-session" ]]; then
  echo "unexpected tmux args: $*" >&2
  exit 1
fi

shift
session_name=""
session_cwd=""
session_cmd=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s)
      session_name="$2"
      shift 2
      ;;
    -c)
      session_cwd="$2"
      shift 2
      ;;
    *)
      session_cmd="$1"
      shift
      ;;
  esac
done

echo "tmux|$session_name|$session_cwd|$session_cmd" >> "${CWB_TEST_LOG:?missing CWB_TEST_LOG}"
(cd "$session_cwd" && bash -lc "$session_cmd")
TMUX_BIN
  chmod +x "$repo_path/bin/tmux"

  cat > "$repo_path/README.md" <<'README'
# temp test repo
README

  git -C "$repo_path" add README.md scripts cwb lib
  git -C "$repo_path" commit -m "init" >/dev/null

  echo "$repo_path"
}

run_cwb() {
  local repo_path="$1"
  shift
  run_cwb_with_env "$repo_path" "" "$@"
}

run_cwb_with_env() {
  local repo_path="$1"
  local extra_env="$2"
  shift 2
  (
    cd "$repo_path"
    env \
      PATH="$repo_path/bin:$PATH" \
      HOME="$repo_path/home" \
      CWB_TEST_LOG="$repo_path/.test-cli-calls" \
      ${extra_env:+$extra_env} \
      bash -lc 'source ./cwb; cwb "$@"' bash "$@"
  )
}

run_cwb_with_input() {
  local repo_path="$1"
  local stdin_text="$2"
  shift 2
  (
    cd "$repo_path"
    printf '%s' "$stdin_text" | \
      PATH="$repo_path/bin:$PATH" \
      HOME="$repo_path/home" \
      CWB_TEST_LOG="$repo_path/.test-cli-calls" \
      CWB_TEST_INTERACTIVE=1 \
      bash -lc 'source ./cwb; cwb "$@"' bash "$@"
  )
}

run_env_setup() {
  local repo_path="$1"
  local worktree_path="$2"
  local worktree_name="$3"
  local copy_volumes="${4:-true}"
  (
    cd "$repo_path"
    bash "$SOURCE_ROOT/lib/lifecycle/cwb-worktree-env.sh" "$repo_path" "$worktree_path" "$worktree_name" "$copy_volumes"
  )
}

run_test() {
  local name="$1"
  if "$name"; then
    echo "[PASS] $name"
    pass_count=$((pass_count + 1))
  else
    echo "[FAIL] $name" >&2
    fail_count=$((fail_count + 1))
  fi
}

test_new_branch_creates_worktree_and_runs_cleanup() {
  local repo_path
  repo_path="$(setup_repo "new-branch")"

  run_cwb "$repo_path" alpha >/dev/null

  assert_file_exists "$repo_path/.cwb/worktrees/alpha/.git" || return 1
  assert_contains "$repo_path/.test-env-calls" "/.cwb/worktrees/alpha|alpha|true" || return 1
  assert_contains "$repo_path/.test-cli-calls" "claude|" || return 1
  assert_contains "$repo_path/.test-cli-calls" "/.cwb/worktrees/alpha|" || return 1
  assert_contains "$repo_path/.test-cleanup-calls" "cwb/alpha" || return 1
}

test_existing_local_branch_skips_cleanup() {
  local repo_path
  repo_path="$(setup_repo "existing-local")"

  git -C "$repo_path" branch cwb/existing
  run_cwb "$repo_path" existing >/dev/null

  assert_file_exists "$repo_path/.cwb/worktrees/existing/.git" || return 1
  assert_file_not_exists "$repo_path/.test-cleanup-calls" || return 1
}

test_remote_only_branch_creates_tracking_worktree() {
  local repo_path
  repo_path="$(setup_repo "remote-only")"
  local remote_path="$TEST_TMP_ROOT/remote-only.git"

  git init --bare "$remote_path" >/dev/null
  git -C "$repo_path" remote add origin "$remote_path"
  git -C "$repo_path" push -u origin main >/dev/null

  git -C "$repo_path" checkout -b cwb/remoteonly >/dev/null
  echo "remote-only" > "$repo_path/feature.txt"
  git -C "$repo_path" add feature.txt
  git -C "$repo_path" commit -m "remote only branch" >/dev/null
  git -C "$repo_path" push -u origin cwb/remoteonly >/dev/null
  git -C "$repo_path" checkout main >/dev/null
  git -C "$repo_path" branch -D cwb/remoteonly >/dev/null

  run_cwb "$repo_path" remoteonly >/dev/null

  assert_file_exists "$repo_path/.cwb/worktrees/remoteonly/.git" || return 1
  local upstream
  upstream="$(git -C "$repo_path/.cwb/worktrees/remoteonly" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
  if [[ "$upstream" != "origin/cwb/remoteonly" ]]; then
    fail "Expected tracking upstream origin/cwb/remoteonly, got: $upstream"
    return 1
  fi
  assert_file_not_exists "$repo_path/.test-cleanup-calls" || return 1
}

test_existing_worktree_is_reused_even_if_not_default_path() {
  local repo_path
  repo_path="$(setup_repo "reuse-worktree")"

  git -C "$repo_path" branch cwb/reuse
  local custom_worktree="$repo_path/custom/reuse-wt"
  git -C "$repo_path" worktree add "$custom_worktree" cwb/reuse >/dev/null

  run_cwb "$repo_path" reuse >/dev/null

  assert_contains "$repo_path/.test-cli-calls" "/custom/reuse-wt|" || return 1
  assert_contains "$repo_path/.test-env-calls" "/custom/reuse-wt|reuse|true" || return 1
  assert_file_not_exists "$repo_path/.test-cleanup-calls" || return 1
}

test_picker_mode_with_double_dash_selects_typed_name() {
  local repo_path
  repo_path="$(setup_repo "picker-mode")"

  run_cwb_with_input "$repo_path" $'pick-me\n' -- "continue refactor" >/dev/null

  assert_file_exists "$repo_path/.cwb/worktrees/pick-me/.git" || return 1
  assert_contains "$repo_path/.test-cli-calls" "/.cwb/worktrees/pick-me|continue refactor" || return 1
  assert_contains "$repo_path/.test-cleanup-calls" "cwb/pick-me" || return 1
}

test_set_default_persists_in_home_directory() {
  local repo_path
  repo_path="$(setup_repo "prefs-home")"

  run_cwb "$repo_path" set-default=codex >/dev/null

  assert_file_exists "$repo_path/home/.cwb/.cwb-prefs" || return 1
  assert_contains "$repo_path/home/.cwb/.cwb-prefs" "USER_DEFAULT_CLI=codex" || return 1

  run_cwb "$repo_path" beta >/dev/null

  assert_contains "$repo_path/.test-cli-calls" "codex|" || return 1
}

test_yolo_maps_to_claude_flag() {
  local repo_path
  repo_path="$(setup_repo "claude-yolo")"

  run_cwb "$repo_path" alpha --yolo >/dev/null

  assert_contains "$repo_path/.test-cli-calls" "claude|" || return 1
  assert_contains "$repo_path/.test-cli-calls" "--dangerously-skip-permissions" || return 1
}

test_interactive_set_defaults_persists_status_and_runtime_flags() {
  local repo_path
  repo_path="$(setup_repo "shared-defaults")"

  run_cwb "$repo_path" set-default=codex >/dev/null
  local set_defaults_output
  set_defaults_output="$(run_cwb_with_input "$repo_path" $'on\non\n' --set-defaults)"

  assert_contains "$repo_path/home/.cwb/.cwb-prefs" "SHARED_FLAG_yolo=on" || return 1
  assert_contains "$repo_path/home/.cwb/.cwb-prefs" "SHARED_FLAG_tmux=on" || return 1
  [[ "$set_defaults_output" == *"Yes: this will be applied to all supported agents."* ]] || fail "Expected shared-default warning in interactive output" || return 1
  [[ "$set_defaults_output" == *"Equivalent cwb command without a default: cwb <name> --yolo"* ]] || fail "Expected yolo cwb command in interactive output" || return 1
  [[ "$set_defaults_output" == *"claude: --dangerously-skip-permissions"* ]] || fail "Expected claude yolo mapping in interactive output" || return 1
  [[ "$set_defaults_output" == *"codex: --yolo"* ]] || fail "Expected codex yolo mapping in interactive output" || return 1

  local output
  output="$(run_cwb "$repo_path" --status)"
  [[ "$output" == *"Preferences file: $repo_path/home/.cwb/.cwb-prefs"* ]] || fail "Expected shared defaults to use the home prefs file" || return 1
  [[ "$output" == *"Shared default [tmux]: on"* ]] || fail "Expected tmux shared default in status output" || return 1
  [[ "$output" == *"Shared default [yolo]: on"* ]] || fail "Expected yolo shared default in status output" || return 1
  [[ "$output" == *"Agent flag [yolo][claude]: --dangerously-skip-permissions"* ]] || fail "Expected claude mapping in status output" || return 1

  run_cwb "$repo_path" delta >/dev/null

  assert_contains "$repo_path/.test-cli-calls" "tmux|cwb-delta|" || return 1
  assert_contains "$repo_path/.test-cli-calls" "codex|" || return 1
  assert_contains "$repo_path/.test-cli-calls" "--yolo" || return 1
}

test_no_yolo_overrides_persisted_default() {
  local repo_path
  repo_path="$(setup_repo "no-yolo-override")"

  run_cwb_with_input "$repo_path" $'on\non\n' --set-defaults >/dev/null

  run_cwb "$repo_path" alpha --no-yolo >/dev/null

  assert_not_contains "$repo_path/.test-cli-calls" "--dangerously-skip-permissions" || return 1
  assert_not_contains "$repo_path/.test-cli-calls" "--yolo" || return 1
}

test_set_defaults_requires_interactive_terminal() {
  local repo_path
  repo_path="$(setup_repo "shared-defaults-interactive-only")"

  if run_cwb "$repo_path" --set-defaults >/dev/null 2>&1; then
    fail "Expected --set-defaults to fail without an interactive terminal"
    return 1
  fi

  assert_not_contains "$repo_path/home/.cwb/.cwb-prefs" "SHARED_FLAG_yolo=" || return 1
  assert_not_contains "$repo_path/home/.cwb/.cwb-prefs" "SHARED_FLAG_tmux=" || return 1
}

test_status_prints_version_and_preferences() {
  local repo_path
  repo_path="$(setup_repo "status-output")"

  run_cwb "$repo_path" set-default=codex >/dev/null

  local output
  output="$(run_cwb "$repo_path" --status)"

  [[ "$output" == *"cwb status"* ]] || fail "Expected status header in output" || return 1
  [[ "$output" == *"Version: 1.4.0"* ]] || fail "Expected version in status output" || return 1
  [[ "$output" == *"Preferences file: $repo_path/home/.cwb/.cwb-prefs"* ]] || fail "Expected prefs path in status output" || return 1
  [[ "$output" == *"Default CLI: codex"* ]] || fail "Expected default CLI in status output" || return 1
  [[ "$output" == *"Shared default [tmux]: off"* ]] || fail "Expected tmux shared default in status output" || return 1
  [[ "$output" == *"Shared default [yolo]: off"* ]] || fail "Expected yolo shared default in status output" || return 1
}

test_help_is_non_interactive_and_does_not_launch_cli() {
  local repo_path
  repo_path="$(setup_repo "help-output")"

  local output
  output="$(run_cwb "$repo_path" --help)"

  [[ "$output" == *"High-level wrapper around coding-agent CLIs"* ]] || fail "Expected help summary in output" || return 1
  [[ "$output" == *"--set-defaults"* ]] || fail "Expected set-defaults flag in help output" || return 1
  [[ "$output" == *"cwb cwb-setup"* ]] || fail "Expected cwb-setup command in help output" || return 1
  assert_file_not_exists "$repo_path/.test-cli-calls" || return 1
  local worktree_count
  worktree_count="$(find "$repo_path/.cwb/worktrees" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')"
  assert_equals "0" "$worktree_count" || return 1
}

test_reserved_cwb_setup_uses_repo_setup_prompt() {
  local repo_path
  repo_path="$(setup_repo "reserved-cwb-setup")"

  run_cwb "$repo_path" cwb-setup >/dev/null

  assert_file_exists "$repo_path/.cwb/worktrees/cwb-setup/.git" || return 1
  assert_contains "$repo_path/.test-cli-calls" "/.cwb/worktrees/cwb-setup|" || return 1
  assert_contains "$repo_path/.test-cli-calls" "Set up cwb for this repository." || return 1
}

test_reserved_cwb_setup_keeps_passthrough_args() {
  local repo_path
  repo_path="$(setup_repo "reserved-cwb-setup-args")"

  run_cwb "$repo_path" cwb-setup -- --model gpt-5.4 "extra setup note" >/dev/null

  assert_contains "$repo_path/.test-cli-calls" "--model gpt-5.4 extra setup note" || return 1
  assert_not_contains "$repo_path/.test-cli-calls" "Set up cwb for this repository." || return 1
}

test_zsh_source_wrapper_loads_help_helpers() {
  local repo_path
  repo_path="$(setup_repo "zsh-source-wrapper")"

  local output
  output="$(cd "$repo_path" && HOME="$repo_path/home" zsh -lc '. ./cwb && cwb --help | sed -n "1,6p"')"

  [[ "$output" == *"cwb 1.4.0"* ]] || fail "Expected cwb version in zsh-sourced help output" || return 1
  [[ "$output" == *"High-level wrapper around coding-agent CLIs"* ]] || fail "Expected help summary in zsh-sourced help output" || return 1
}

test_new_flag_creates_random_worktree_non_interactively() {
  local repo_path
  repo_path="$(setup_repo "new-flag")"

  run_cwb "$repo_path" --new >/dev/null

  local worktree_count
  worktree_count="$(find "$repo_path/.cwb/worktrees" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')"
  assert_equals "1" "$worktree_count" || return 1
}

test_env_setup_sanitizes_nested_worktree_name_for_compose() {
  local repo_path
  repo_path="$(setup_repo "nested-compose-name")"

  mkdir -p "$repo_path/web"
  cat > "$repo_path/web/.env" <<'ENV'
FOO=bar
ENV
  cat > "$repo_path/web/docker-compose.mobile.yaml" <<'COMPOSE'
services:
  example:
    image: busybox
COMPOSE

  git -C "$repo_path" add web/.env web/docker-compose.mobile.yaml
  git -C "$repo_path" commit -m "add compose fixtures" >/dev/null

  mkdir -p "$repo_path/.cwb/worktrees/ios"
  git -C "$repo_path" worktree add "$repo_path/.cwb/worktrees/ios/state-caching" -b cwb/ios/state-caching >/dev/null

  run_env_setup "$repo_path" "$repo_path/.cwb/worktrees/ios/state-caching" "ios/state-caching" >/dev/null

  assert_contains "$repo_path/.cwb/worktrees/ios/state-caching/web/.env" "COMPOSE_PROJECT_NAME=cwb-ios-state-caching" || return 1
  assert_contains "$repo_path/.cwb/worktrees/ios/state-caching/web/docker-compose.override.yml" "name: cwb-ios-state-caching" || return 1
  assert_not_contains "$repo_path/.cwb/worktrees/ios/state-caching/web/.env" "COMPOSE_PROJECT_NAME=cwb-ios/state-caching" || return 1
}

test_env_setup_generates_worktree_port_overrides() {
  local repo_path
  repo_path="$(setup_repo "worktree-port-overrides")"

  mkdir -p "$repo_path/web/app"
  cat > "$repo_path/web/.env" <<'ENV'
FASTAPI_PORT=8000
API_BASE_URL=http://localhost:8000
PROMPT_SERVICE_PORT=8001
GRPC_PORT=50052
ENV
  ln -s ../.env "$repo_path/web/app/.env"
  cat > "$repo_path/web/docker-compose.yaml" <<'COMPOSE'
services:
  web:
    image: busybox
COMPOSE

  # Provide port-specs so cwb-worktree-env.sh allocates ports for this repo.
  # Derived URLs (API_BASE_URL etc.) are now injected by the repo's own
  # .cwb/hooks/post-worktree-setup.sh, not by the generic tool.
  mkdir -p "$repo_path/.cwb"
  cat > "$repo_path/.cwb/port-specs" <<'SPECS'
FASTAPI_PORT|8000
PROMPT_SERVICE_PORT|8001
SPECS

  git -C "$repo_path" add web/.env web/app/.env web/docker-compose.yaml .cwb/port-specs
  git -C "$repo_path" commit -m "add env fixtures" >/dev/null

  git -C "$repo_path" worktree add "$repo_path/.claude/worktrees/ports" -b cwb/ports >/dev/null

  run_env_setup "$repo_path" "$repo_path/.claude/worktrees/ports" "ports" >/dev/null

  local worktree_root="$repo_path/.claude/worktrees/ports"
  local fastapi_port
  local prompt_service_port
  fastapi_port="$(sed -n 's/^FASTAPI_PORT=//p' "$worktree_root/web/.env.local" | head -n 1)"
  prompt_service_port="$(sed -n 's/^PROMPT_SERVICE_PORT=//p' "$worktree_root/web/.env.local" | head -n 1)"

  [[ -n "$fastapi_port" ]] || fail "Expected FASTAPI_PORT in generated .env.local" || return 1
  [[ -n "$prompt_service_port" ]] || fail "Expected PROMPT_SERVICE_PORT in generated .env.local" || return 1
  [[ "$fastapi_port" != "8000" ]] || fail "Expected worktree FASTAPI_PORT to move off default port" || return 1
  [[ "$fastapi_port" != "$prompt_service_port" ]] || fail "Expected distinct generated ports per runtime" || return 1

  assert_symlink_target "$worktree_root/web/app/.env.local" "../.env.local" || return 1
}

test_cwb_compose_exports_env_local_overrides() {
  local repo_path
  repo_path="$(setup_repo "cwb-compose-overrides")"

  mkdir -p "$repo_path/web"
  cat > "$repo_path/web/.env" <<'ENV'
FASTAPI_PORT=8000
ENV
  cat > "$repo_path/web/.env.local" <<'ENV'
FASTAPI_PORT=8013
API_BASE_URL=http://localhost:8013
ENV
  cat > "$repo_path/web/docker-compose.mobile.yaml" <<'COMPOSE'
services:
  web:
    image: busybox
COMPOSE
  cat > "$repo_path/bin/docker" <<'DOCKER_BIN'
#!/usr/bin/env bash
set -euo pipefail
printf 'FASTAPI_PORT=%s\n' "${FASTAPI_PORT:-}" >> "${CWB_TEST_LOG:?missing CWB_TEST_LOG}"
printf 'API_BASE_URL=%s\n' "${API_BASE_URL:-}" >> "${CWB_TEST_LOG:?missing CWB_TEST_LOG}"
printf 'docker|%s\n' "$*" >> "${CWB_TEST_LOG:?missing CWB_TEST_LOG}"
DOCKER_BIN
  chmod +x "$repo_path/bin/docker"

  (
    cd "$repo_path"
    PATH="$repo_path/bin:$PATH" \
    CWB_TEST_LOG="$repo_path/.test-cli-calls" \
    bash "$SOURCE_ROOT/lib/lifecycle/cwb-compose.sh" -f web/docker-compose.mobile.yaml config >/dev/null
  )

  assert_contains "$repo_path/.test-cli-calls" "FASTAPI_PORT=8013" || return 1
  assert_contains "$repo_path/.test-cli-calls" "API_BASE_URL=http://localhost:8013" || return 1
  assert_contains "$repo_path/.test-cli-calls" "docker|compose -f web/docker-compose.mobile.yaml config" || return 1
}

run_test test_new_branch_creates_worktree_and_runs_cleanup
run_test test_existing_local_branch_skips_cleanup
run_test test_remote_only_branch_creates_tracking_worktree
run_test test_existing_worktree_is_reused_even_if_not_default_path
run_test test_picker_mode_with_double_dash_selects_typed_name
run_test test_set_default_persists_in_home_directory
run_test test_yolo_maps_to_claude_flag
run_test test_interactive_set_defaults_persists_status_and_runtime_flags
run_test test_no_yolo_overrides_persisted_default
run_test test_set_defaults_requires_interactive_terminal
run_test test_status_prints_version_and_preferences
run_test test_help_is_non_interactive_and_does_not_launch_cli
run_test test_reserved_cwb_setup_uses_repo_setup_prompt
run_test test_reserved_cwb_setup_keeps_passthrough_args
run_test test_zsh_source_wrapper_loads_help_helpers
run_test test_new_flag_creates_random_worktree_non_interactively
run_test test_env_setup_sanitizes_nested_worktree_name_for_compose
run_test test_env_setup_generates_worktree_port_overrides
run_test test_cwb_compose_exports_env_local_overrides

echo "[RESULT] Passed: $pass_count, Failed: $fail_count"
[[ "$fail_count" -eq 0 ]]
