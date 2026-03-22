#!/usr/bin/env bash
# scripts/compile_protos.sh — regenerate protobuf bindings.
#
# Called automatically by the cwb post-worktree-setup hook.
# Run manually after editing .proto files:
#   bash scripts/compile_protos.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROTO_DIR="$REPO_ROOT/proto"
OUT_DIR="$REPO_ROOT/api/proto_gen"

if ! command -v buf >/dev/null 2>&1; then
  echo "buf not found — install via: brew install bufbuild/buf/buf" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
buf generate --template "$PROTO_DIR/buf.gen.yaml" "$PROTO_DIR"
echo "[compile_protos] Done — bindings written to $OUT_DIR"
