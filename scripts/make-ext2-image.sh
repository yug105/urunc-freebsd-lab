#!/usr/bin/env bash
# Build an ext2 variant of urunc's caddy FreeBSD block image.
#
# The upstream image caddy-<monitor>-freebsd-block keeps a UFS2 rootfs at
# /.boot/rootfs and the kernel at /.boot/kernel (its labels say so). The
# caddy-<monitor>-freebsd-raw image holds the same FreeBSD tree as a normal
# container rootfs and ships the same kernel, which has EXT2FS. We turn that
# tree into an ext2 image and put it at /.boot/rootfs of the block image.
# Everything else (kernel, urunc.json, entrypoint, cmd) stays the same, so
# the only difference from the upstream block image is the rootfs filesystem.
#
# Usage: sudo scripts/make-ext2-image.sh <qemu|firecracker> <tag>
set -euo pipefail

MON="${1:?monitor (qemu|firecracker)}"
TAG="${2:?tag for the resulting image}"
REG="harbor.nbfc.io/nubificus/urunc"
BLOCK="$REG/caddy-$MON-freebsd-block:latest"
RAW="$REG/caddy-$MON-freebsd-raw:latest"
LAB="$(cd "$(dirname "$0")" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

docker pull -q "$BLOCK"
docker pull -q "$RAW"

echo "--- labels of $BLOCK ---"
docker inspect -f '{{json .Config.Labels}}' "$BLOCK" | jq .
block_path="$(docker inspect -f '{{index .Config.Labels "com.urunc.unikernel.block"}}' "$BLOCK")"
[ "$block_path" = "/.boot/rootfs" ] || { echo "unexpected block path: $block_path"; exit 1; }

echo "--- exporting the FreeBSD tree of $RAW ---"
mkdir "$WORK/tree"
cid="$(docker create "$RAW")"
docker export "$cid" | tar -xpf - -C "$WORK/tree"
docker rm "$cid" >/dev/null
# The kernel and urunc's metadata are not needed inside the guest rootfs
rm -rf "$WORK/tree/.boot" "$WORK/tree/urunc.json" "$WORK/tree/.dockerenv"
for f in urunit usr/local/bin/caddy etc/Caddyfile; do
	[ -e "$WORK/tree/$f" ] || { echo "missing /$f in the raw tree"; exit 1; }
done

echo "--- building the ext2 rootfs ---"
used_mb="$(du -sm "$WORK/tree" | cut -f1)"
size_mb=$(( used_mb * 3 / 2 + 64 ))
mkfs.ext2 -q -F -L rootfs -d "$WORK/tree" "$WORK/rootfs.ext2" "${size_mb}M"
python3 -I "$LAB/fsmagic.py" "$WORK/rootfs.ext2"

cat > "$WORK/Dockerfile" <<EOF
FROM $BLOCK
COPY rootfs.ext2 $block_path
EOF
docker build -q -t "$TAG" "$WORK"
echo "built $TAG"
