#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[cwb] setup-macos.sh only supports macOS." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[cwb] curl is required." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "[cwb] Homebrew is required before running this script." >&2
  exit 1
fi

# Resolve Brewfile: prefer a sibling Brewfile (installed alongside this script),
# then fall back to CWB_BREWFILE_URL if explicitly set.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BREWFILE="$SCRIPT_DIR/Brewfile"

if [[ -f "$LOCAL_BREWFILE" ]]; then
  brewfile_arg="$LOCAL_BREWFILE"
elif [[ -n "${CWB_BREWFILE_URL:-}" ]]; then
  tmp_brewfile="$(mktemp)"
  trap 'rm -f "$tmp_brewfile"' EXIT
  echo "[cwb] Downloading Brewfile from $CWB_BREWFILE_URL"
  curl -fsSL "$CWB_BREWFILE_URL" -o "$tmp_brewfile"
  brewfile_arg="$tmp_brewfile"
else
  echo "[cwb] Error: Brewfile not found at $LOCAL_BREWFILE." >&2
  echo "[cwb]   Set CWB_BREWFILE_URL to a raw URL, or run this script from its" >&2
  echo "[cwb]   installed location alongside the Brewfile." >&2
  exit 1
fi

if xcode-select -p >/dev/null 2>&1; then
  echo "[cwb] Xcode Command Line Tools already installed"
else
  echo "[cwb] Installing Xcode Command Line Tools"
  xcode-select --install
fi

if command -v flowdeck >/dev/null 2>&1; then
  echo "[cwb] Flowdeck already installed"
else
  echo "[cwb] Installing Flowdeck"
  curl -fsSL https://flowdeck.studio/install.sh | sh
fi

echo "[cwb] Running brew bundle"
brew bundle --file "$brewfile_arg"
