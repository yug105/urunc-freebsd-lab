#!/usr/bin/env bash
# Build the static urunc binaries of a checkout and copy them to <out-dir>.
#
# Usage: scripts/build-urunc.sh <path-to-urunc-checkout> <out-dir>
set -euo pipefail

SRC="${1:?usage: build-urunc.sh <src> <out-dir>}"
OUT="${2:?usage: build-urunc.sh <src> <out-dir>}"

make -C "$SRC"
mkdir -p "$OUT"
cp "$SRC/dist/urunc_static_amd64" "$OUT/urunc"
cp "$SRC/dist/containerd-shim-urunc-v2_static_amd64" "$OUT/containerd-shim-urunc-v2"
"$OUT/urunc" --version
