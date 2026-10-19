#!/usr/bin/env bash
# Install urunc binaries produced by build-urunc.sh.
#
# Usage: sudo scripts/install-urunc.sh <dir-with-binaries>
set -euo pipefail

DIR="${1:?usage: install-urunc.sh <dir>}"

install -m 755 "$DIR/urunc" /usr/local/bin/urunc
install -m 755 "$DIR/containerd-shim-urunc-v2" /usr/local/bin/containerd-shim-urunc-v2
urunc --version
