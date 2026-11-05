#!/usr/bin/env bash
# Build a variant of urunc's caddy FreeBSD block image with another rootfs
# filesystem, to see what the FreeBSD kernel really mounts.
#
# Usage: sudo scripts/make-fs-image.sh <qemu|firecracker> <ext2|ext3|ext4|ufs1|ufs2> <tag>
set -euo pipefail

MON="${1:?monitor}"
FS="${2:?filesystem}"
TAG="${3:?tag}"
REG="harbor.nbfc.io/nubificus/urunc"
BLOCK="$REG/caddy-$MON-freebsd-block:latest"
RAW="$REG/caddy-$MON-freebsd-raw:latest"
LAB="$(cd "$(dirname "$0")" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

docker pull -q "$BLOCK"
docker pull -q "$RAW"

mkdir "$WORK/tree"
cid="$(docker create "$RAW")"
docker export "$cid" | tar -xpf - -C "$WORK/tree"
docker rm "$cid" >/dev/null
rm -rf "$WORK/tree/.boot" "$WORK/tree/urunc.json" "$WORK/tree/.dockerenv"

used_mb="$(du -sm "$WORK/tree" | cut -f1)"
size_mb=$(( used_mb * 3 / 2 + 64 ))
IMG="$WORK/rootfs.img"
case "$FS" in
ext2|ext3|ext4)
	"mkfs.$FS" -q -F -L rootfs -d "$WORK/tree" "$IMG" "${size_mb}M"
	dumpe2fs -h "$IMG" 2>/dev/null | grep -E "Filesystem features|Filesystem revision"
	;;
ufs1|ufs2)
	makefs -t ffs -s "${size_mb}m" -o "version=${FS#ufs}" "$IMG" "$WORK/tree"
	;;
*)
	echo "unknown filesystem: $FS"
	exit 1
	;;
esac
python3 -I "$LAB/fsmagic.py" "$IMG"

cat > "$WORK/Dockerfile" <<EOF
FROM $BLOCK
COPY rootfs.img /.boot/rootfs
EOF
docker build -q -t "$TAG" "$WORK"
echo "built $TAG"
