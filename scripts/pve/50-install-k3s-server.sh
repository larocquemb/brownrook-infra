#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./50-install-k3s-server.sh paul@k3s1.brownrook.net
#
# Requires ssh connectivity to the VM.

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 paul@k3s1.brownrook.net"
  exit 2
fi

# Pin k3s version (change consciously)
K3S_VERSION="v1.29.3+k3s1"

REMOTE_BASE="/opt/brownrook/bootstrap/k3s"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Copying k3s config to ${TARGET}:${REMOTE_BASE} ..."
ssh "$TARGET" "sudo mkdir -p ${REMOTE_BASE}"
scp "${LOCAL_DIR}/k3s/config.yaml" "${TARGET}:/tmp/k3s-config.yaml"

echo "Installing k3s on ${TARGET} (version ${K3S_VERSION}) ..."
ssh "$TARGET" "sudo bash -s" <<EOF
set -euo pipefail
sudo mv /tmp/k3s-config.yaml ${REMOTE_BASE}/config.yaml

curl -sfL https://get.k3s.io -o ${REMOTE_BASE}/get.k3s.sh
chmod +x ${REMOTE_BASE}/get.k3s.sh

export INSTALL_K3S_VERSION="${K3S_VERSION}"
export INSTALL_K3S_EXEC="server --config ${REMOTE_BASE}/config.yaml"

sudo ${REMOTE_BASE}/get.k3s.sh

sudo systemctl enable --now k3s

echo
echo "k3s installed."
echo "Try: kubectl get nodes -o wide"
EOF

echo "Done. Verifying..."
ssh "$TARGET" "sudo systemctl --no-pager -l status k3s; kubectl get nodes -o wide"