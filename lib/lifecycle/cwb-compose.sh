#!/usr/bin/env bash
set -euo pipefail

compose_dir="$PWD"
args=("$@")

for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-f" || "${args[$i]}" == "--file" ]]; then
    if (( i + 1 < ${#args[@]} )); then
      compose_dir="$(cd "$(dirname "${args[$((i + 1))]}")" && pwd)"
      break
    fi
  fi
done

load_override_file() {
  local override_file="$1"
  local line key value

  [[ -f "$override_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue

    key="${line%%=*}"
    value="${line#*=}"

    if [[ -n "${!key+x}" ]]; then
      continue
    fi

    export "${key}=${value}"
  done < "$override_file"

  return 0
}

load_override_file "$compose_dir/.env.local"
load_override_file "$compose_dir/.env.override"

exec docker compose "$@"
