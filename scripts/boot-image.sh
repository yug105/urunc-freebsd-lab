#!/usr/bin/env bash
# Boot an image with docker + urunc and report whether the guest came up.
# The guest is considered up when it answers ping on the container IP, the
# same check the urunc e2e tests use for the caddy FreeBSD images.
#
# Usage: sudo scripts/boot-image.sh <image> <runtime> <name> <log-dir>
# Exit code: 0 if the guest answered ping, 1 otherwise.
set -uo pipefail

IMAGE="${1:?image}"
RUNTIME="${2:?runtime}"
NAME="${3:?name}"
LOGDIR="${4:?log dir}"
TIMEOUT="${BOOT_TIMEOUT:-90}"

mkdir -p "$LOGDIR"
since="$(date '+%Y-%m-%d %H:%M:%S')"

docker rm -f "$NAME" >/dev/null 2>&1 || true
if ! docker run -d --name "$NAME" --runtime "$RUNTIME" "$IMAGE" > "$LOGDIR/$NAME.run.txt" 2>&1; then
	echo "docker run failed:"
	cat "$LOGDIR/$NAME.run.txt"
	journalctl --identifier=urunc --since "$since" --no-pager > "$LOGDIR/$NAME.urunc.log" 2>&1 || true
	exit 1
fi

ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"
echo "container $NAME ip=$ip"

up=1
for _ in $(seq 1 "$TIMEOUT"); do
	if [ -n "$ip" ] && ping -c1 -W1 "$ip" >/dev/null 2>&1; then
		up=0
		break
	fi
	sleep 1
done

docker logs "$NAME" > "$LOGDIR/$NAME.console.log" 2>&1 || true
journalctl --identifier=urunc --since "$since" --no-pager > "$LOGDIR/$NAME.urunc.log" 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "--- root filesystem the guest tried ---"
# QEMU's -append shows up in urunc's debug log; Firecracker keeps its boot
# args in a JSON file, so also look at what the FreeBSD kernel printed.
grep -o 'vfs\.root\.mountfrom=[^ "]*' "$LOGDIR/$NAME.urunc.log" | sort -u || echo "(mountfrom not in urunc log)"
grep -a 'Trying to mount root from\|mountroot>' "$LOGDIR/$NAME.console.log" | head -5 || echo "(no mountroot lines on the console)"
echo "--- last 25 lines of the guest console ---"
tail -n 25 "$LOGDIR/$NAME.console.log"

if [ "$up" -eq 0 ]; then
	echo "RESULT: $NAME booted (answered ping)"
else
	echo "RESULT: $NAME did NOT come up within ${TIMEOUT}s"
fi
exit "$up"
