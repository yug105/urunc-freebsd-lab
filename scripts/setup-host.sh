#!/usr/bin/env bash
# Prepare a GitHub ubuntu-22.04 runner to run FreeBSD guests with urunc.
# Mirrors the amd64 steps of urunc's .github/workflows/vm_test.yml.
#
# Usage: sudo -E scripts/setup-host.sh <path-to-urunc-checkout>
set -euo pipefail

URUNC_SRC="${1:?usage: setup-host.sh <path-to-urunc-checkout>}"

RUNC_VERSION="${RUNC_VERSION:-1.3.0}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-2.1.3}"
CNI_VERSION="${CNI_VERSION:-1.7.1}"
NERDCTL_VERSION="${NERDCTL_VERSION:-2.1.3}"
# FreeBSD needs Firecracker >= 1.12 (upstream CI uses v1.16.1 for it)
FC_FREEBSD_VERSION="${FC_FREEBSD_VERSION:-v1.16.1}"

ARCH_DEB="$(dpkg --print-architecture)"
ARCH_UNAME="$(uname -m)"
WORK="$(mktemp -d)"
cd "$WORK"

echo "::group::Base packages"
apt-get update
apt-get install -y git wget curl build-essential libseccomp-dev pkg-config \
	bc make qemu-system-x86 jq e2fsprogs python3
echo "::endgroup::"

echo "::group::runc ${RUNC_VERSION}"
wget -q "https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH_DEB}"
install -m 755 "runc.${ARCH_DEB}" /usr/local/sbin/runc
echo "::endgroup::"

echo "::group::containerd ${CONTAINERD_VERSION}"
wget -q "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH_DEB}.tar.gz"
tar Cxzf /usr/local "containerd-${CONTAINERD_VERSION}-linux-${ARCH_DEB}.tar.gz"
wget -q "https://raw.githubusercontent.com/containerd/containerd/v${CONTAINERD_VERSION}/containerd.service"
rm -f /lib/systemd/system/containerd.service
mv containerd.service /lib/systemd/system/containerd.service
systemctl daemon-reload
systemctl enable --now containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
echo "::endgroup::"

echo "::group::devmapper (ext2, like upstream CI)"
mkdir -p /usr/local/bin/scripts
install -m 755 "${URUNC_SRC}/script/dm_create.sh" /usr/local/bin/scripts/dm_create.sh
/usr/local/bin/scripts/dm_create.sh
sed -i "/\[plugins\.'io\.containerd\.snapshotter\.v1\.devmapper'\]/,/^$/d" /etc/containerd/config.toml
cat >> /etc/containerd/config.toml <<'EOT'
[plugins.'io.containerd.snapshotter.v1.devmapper']
  pool_name = "containerd-pool"
  root_path = "/var/lib/containerd/io.containerd.snapshotter.v1.devmapper"
  base_image_size = "10GB"
  fs_type = "ext2"
EOT
systemctl restart containerd
echo "::endgroup::"

echo "::group::CNI ${CNI_VERSION}"
wget -q "https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-${ARCH_DEB}-v${CNI_VERSION}.tgz"
mkdir -p /opt/cni/bin /etc/cni/net.d
tar Cxzf /opt/cni/bin "cni-plugins-linux-${ARCH_DEB}-v${CNI_VERSION}.tgz"
cat > /etc/cni/net.d/10-containerd-net.conflist <<'EOT'
{
  "cniVersion": "1.0.0",
  "name": "containerd-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "hairpinMode": true,
      "ipam": {
        "type": "host-local",
        "ranges": [[{ "subnet": "10.88.0.0/16" }]],
        "routes": [{ "dst": "0.0.0.0/0" }]
      }
    },
    { "type": "portmap", "capabilities": { "portMappings": true } },
    { "type": "firewall" }
  ]
}
EOT
systemctl restart containerd
echo "::endgroup::"

echo "::group::nerdctl ${NERDCTL_VERSION}"
wget -q "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-${ARCH_DEB}.tar.gz"
tar Cxzf /usr/local/bin "nerdctl-${NERDCTL_VERSION}-linux-${ARCH_DEB}.tar.gz"
echo "::endgroup::"

echo "::group::Firecracker ${FC_FREEBSD_VERSION} for FreeBSD"
release_url="https://github.com/firecracker-microvm/firecracker/releases"
curl -fsSL "${release_url}/download/${FC_FREEBSD_VERSION}/firecracker-${FC_FREEBSD_VERSION}-${ARCH_UNAME}.tgz" | tar -xz
mv "release-${FC_FREEBSD_VERSION}-${ARCH_UNAME}/firecracker-${FC_FREEBSD_VERSION}-${ARCH_UNAME}" /usr/local/bin/firecracker-freebsd
echo "::endgroup::"

echo "::group::urunc configuration"
mkdir -p /etc/urunc
cat > /etc/urunc/config.toml <<'EOF'
[log]
level = "debug"
syslog = true
EOF
# Same trick as upstream CI: a second shim name whose urunc config points
# Firecracker at the newer binary. The e2e tests use it for images whose
# name contains "firecracker-freebsd" (tests/e2e/common.go).
cat > /etc/urunc/config-freebsd.toml <<'EOF'
[log]
level = "debug"
syslog = true

[monitors.firecracker]
path = "/usr/local/bin/firecracker-freebsd"
EOF
cat > /usr/local/bin/containerd-shim-urunc-fc-v2 <<'EOF'
#!/bin/bash
URUNC_CONFIG_FILE=/etc/urunc/config-freebsd.toml exec /usr/local/bin/containerd-shim-urunc-v2 "$@"
EOF
chmod +x /usr/local/bin/containerd-shim-urunc-fc-v2
echo "::endgroup::"

echo "::group::KVM access"
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' > /etc/udev/rules.d/99-kvm4all.rules
udevadm control --reload-rules
udevadm trigger --name-match=kvm
ls -l /dev/kvm
echo "::endgroup::"

# Docker on the runner talks to the containerd we just replaced
systemctl restart docker

rm -rf "$WORK"
