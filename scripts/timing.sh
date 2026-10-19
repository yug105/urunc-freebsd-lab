#!/usr/bin/env bash
# Collect urunc timestamps for the caddy FreeBSD block image (QEMU).
# Runs <iterations> containers with a warm page cache and <iterations> with
# the page cache dropped before each run.
#
# Usage: sudo scripts/timing.sh <label> <iterations> <out-dir>
set -euo pipefail

LABEL="${1:?label}"
ITER="${2:?iterations}"
OUT="${3:?out dir}"
IMAGE="${TIMING_IMAGE:-harbor.nbfc.io/nubificus/urunc/caddy-qemu-freebsd-block:latest}"

mkdir -p "$OUT"
# urunc runs from the bundle directory, so the timestamps path must be absolute
OUT="$(cd "$OUT" && pwd)"
docker pull -q "$IMAGE"

run_pass() {
	local pass="$1" zlog="$OUT/$LABEL-$1.zlog"
	rm -f "$zlog"
	cat > /etc/urunc/config.toml <<EOF
[log]
level = "info"
syslog = true

[timestamps]
enabled = true
destination = "$zlog"
EOF
	for i in $(seq 1 "$ITER"); do
		if [ "$pass" = "cold" ]; then
			sync
			echo 3 > /proc/sys/vm/drop_caches
		fi
		docker run -d --name "t-$LABEL-$pass-$i" --runtime io.containerd.urunc.v2 "$IMAGE" >/dev/null
		sleep 2
		docker rm -f "t-$LABEL-$pass-$i" >/dev/null
	done
	echo "$pass: $(wc -l < "$zlog") timestamp lines in $zlog"
}

run_pass warm
run_pass cold

# Restore the debug configuration used by the other scripts
cat > /etc/urunc/config.toml <<'EOF'
[log]
level = "debug"
syslog = true
EOF
