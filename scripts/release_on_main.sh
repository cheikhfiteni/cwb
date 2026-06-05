#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO_SLUG="${GITHUB_REPOSITORY:-cheikhfiteni/cwb}"
TAP_REPO_SLUG="${HOMEBREW_TAP_REPO:-cheikhfiteni/homebrew-tap}"
CI_GIT_NAME="${CI_GIT_NAME:-github-actions[bot]}"
CI_GIT_EMAIL="${CI_GIT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
DRY_RUN="${DRY_RUN:-0}"

log() {
  echo "[release] $*"
}

extract_version() {
  sed -n 's/^CWB_VERSION="\([^"]*\)"$/\1/p' cwb | head -n 1
}

version_cmp() {
  local left="$1"
  local right="$2"
  local -a lhs rhs
  local i max a b

  IFS='.' read -r -a lhs <<< "$left"
  IFS='.' read -r -a rhs <<< "$right"

  max="${#lhs[@]}"
  if (( ${#rhs[@]} > max )); then
    max="${#rhs[@]}"
  fi

  for (( i=0; i<max; i++ )); do
    a="${lhs[i]:-0}"
    b="${rhs[i]:-0}"
    (( a < b )) && return 1
    (( a > b )) && return 2
  done

  return 0
}

next_patch_version() {
  local version="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  patch="${patch:-0}"
  printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))"
}

release_exists() {
  gh release view "v$1" >/dev/null 2>&1
}

tag_exists() {
  git rev-parse -q --verify "refs/tags/v$1" >/dev/null 2>&1
}

tag_points_at_head() {
  git tag --points-at HEAD | grep -Fx "v$1" >/dev/null 2>&1
}

commit_if_needed() {
  local version="$1"

  if git diff --quiet -- cwb; then
    return 0
  fi

  git config user.name "$CI_GIT_NAME"
  git config user.email "$CI_GIT_EMAIL"
  git add cwb

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN=1; skipping commit for v$version"
    return 0
  fi

  git commit -m "release: v$version"
  git push origin HEAD:main
}

sync_homebrew_tap() {
  local version="$1"
  local sha="$2"
  local tarball_url="https://github.com/${REPO_SLUG}/archive/refs/tags/v${version}.tar.gz"
  local tap_token="${HOMEBREW_TAP_PUSH_TOKEN:-}"
  local tap_dir formula_path clone_url

  if [[ -z "$tap_token" ]]; then
    log "HOMEBREW_TAP_PUSH_TOKEN is not set; skipping tap sync"
    return 0
  fi

  tap_dir="$(mktemp -d)"
  clone_url="https://x-access-token:${tap_token}@github.com/${TAP_REPO_SLUG}.git"
  git clone --depth 1 "$clone_url" "$tap_dir" >/dev/null 2>&1

  formula_path="$tap_dir/Formula/cwb.rb"
  if [[ ! -f "$formula_path" ]]; then
    echo "Formula file not found in tap repo: $formula_path" >&2
    return 1
  fi

  perl -0pi -e \
    "s|url \".*?/refs/tags/v[^\"]+\\.tar\\.gz\"|url \"${tarball_url}\"|; s|sha256 \"[^\"]+\"|sha256 \"${sha}\"|" \
    "$formula_path"

  if git -C "$tap_dir" diff --quiet -- Formula/cwb.rb; then
    log "Tap formula already matches v$version"
    rm -rf "$tap_dir"
    return 0
  fi

  git -C "$tap_dir" config user.name "$CI_GIT_NAME"
  git -C "$tap_dir" config user.email "$CI_GIT_EMAIL"
  git -C "$tap_dir" add Formula/cwb.rb

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN=1; skipping tap commit for v$version"
    rm -rf "$tap_dir"
    return 0
  fi

  git -C "$tap_dir" commit -m "cwb: v$version" >/dev/null
  git -C "$tap_dir" push origin HEAD:main >/dev/null
  rm -rf "$tap_dir"
}

git fetch --tags --force origin

current_version="$(extract_version)"
if [[ -z "$current_version" ]]; then
  echo "Unable to read CWB_VERSION from cwb" >&2
  exit 1
fi

latest_tag="$(git tag --list 'v[0-9]*' --sort=-version:refname | head -n 1)"
latest_version="${latest_tag#v}"
target_version="$current_version"

if [[ -n "$latest_version" ]]; then
  if tag_exists "$current_version"; then
    if tag_points_at_head "$current_version"; then
      target_version="$current_version"
    else
      target_version="$(next_patch_version "$latest_version")"
    fi
  else
    if version_cmp "$current_version" "$latest_version"; then
      cmp_status=0
    else
      cmp_status=$?
    fi
    if [[ "$cmp_status" != "2" ]]; then
      target_version="$(next_patch_version "$latest_version")"
    fi
  fi
fi

if [[ "$target_version" != "$current_version" ]]; then
  log "Bumping version from $current_version to $target_version"
  perl -0pi -e "s/^CWB_VERSION=\"[^\"]+\"$/CWB_VERSION=\"${target_version}\"/m" cwb
  commit_if_needed "$target_version"
  current_version="$target_version"
else
  log "Using existing version v$current_version"
fi

if ! tag_exists "$current_version"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN=1; skipping tag creation for v$current_version"
  else
    git tag "v$current_version"
    git push origin "v$current_version"
  fi
fi

if ! release_exists "$current_version"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN=1; skipping GitHub release creation for v$current_version"
  else
    gh release create "v$current_version" --title "v$current_version" --generate-notes
  fi
elif tag_points_at_head "$current_version"; then
  log "Release v$current_version already exists for HEAD"
else
  log "Release v$current_version already exists"
fi

tarball_sha="$(curl -fsSL "https://github.com/${REPO_SLUG}/archive/refs/tags/v${current_version}.tar.gz" | shasum -a 256 | awk '{print $1}')"
log "Tarball SHA for v$current_version: $tarball_sha"

sync_homebrew_tap "$current_version" "$tarball_sha"
