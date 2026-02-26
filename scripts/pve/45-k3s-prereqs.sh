# scripts/pve/45-k3s-prereqs.sh
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./45-k3s-prereqs.sh paul@k3s1.brownrook.net
#
# Purpose:
#   Prepare RHEL 10 node for K3s networking (flannel) with nftables backend.
#   Enforces required kernel module availability (capability), not a specific kernel version.

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 paul@k3s1.brownrook.net"
  exit 2
fi

echo "==> K3s prereqs on ${TARGET}"

ssh "$TARGET" "sudo bash -s" <<'EOF'
set -euo pipefail

echo "==> Kernel: $(uname -r)"
echo "==> iptables: $(iptables --version 2>/dev/null || echo 'iptables not installed')"

# Required kernel modules for K3s + flannel + kube-proxy rules
REQUIRED_MODULES=(br_netfilter overlay xt_comment xt_mark xt_conntrack)

echo "==> Checking module availability (modinfo)..."
missing=0
for mod in "${REQUIRED_MODULES[@]}"; do
  if modinfo "$mod" >/dev/null 2>&1; then
    echo "  [OK] $mod"
  else
    echo "  [MISSING] $mod"
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  cat <<'EOM'

ERROR: One or more required kernel modules are missing for this running kernel.
This commonly happens if you booted an older kernel build (e.g., 6.12.0-124.38 on RHEL10.1)
that lacks certain netfilter modules needed by flannel/kube-proxy.

Fix options:
  1) Reboot into a newer installed kernel that contains these modules (recommended)
     - sudo grubby --default-kernel
     - sudo grubby --info=ALL | grep -E 'kernel=|index='
     - sudo reboot

  2) Ensure full kernel module packages are installed:
     - sudo dnf -y install kernel-modules kernel-modules-core kernel-modules-extra

After reboot, re-run this script.

EOM
  exit 1
fi

echo "==> Persist modules for reboot"
sudo tee /etc/modules-load.d/k3s.conf >/dev/null <<'EOM'
br_netfilter
overlay
xt_comment
xt_mark
xt_conntrack
EOM

echo "==> Load modules now"
for mod in "${REQUIRED_MODULES[@]}"; do
  sudo modprobe "$mod"
done

echo "==> Loaded modules:"
lsmod | egrep 'br_netfilter|overlay|xt_comment|xt_mark|xt_conntrack' || true

echo "==> Persist sysctls required for Kubernetes networking"
sudo tee /etc/sysctl.d/99-k3s.conf >/dev/null <<'EOM'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Loose rp_filter helps overlay CNIs (flannel) avoid asymmetric routing drops
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOM

echo "==> Apply sysctls"
sudo sysctl --system >/dev/null

echo "==> Key sysctls:"
sysctl net.ipv4.ip_forward \
       net.bridge.bridge-nf-call-iptables \
       net.bridge.bridge-nf-call-ip6tables \
       net.ipv4.conf.all.rp_filter \
       net.ipv4.conf.default.rp_filter

echo "==> Done prereqs."
EOF

echo "==> Completed."
