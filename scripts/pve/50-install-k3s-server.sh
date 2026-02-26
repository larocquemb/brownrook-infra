#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Brown Rook :: Install K3s Server (PVE VM)
#
# Usage:
#   ./50-install-k3s-server.sh paul@k3s1.brownrook.net
#
# Requires SSH connectivity to the VM.
# ------------------------------------------------------------

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 paul@k3s1.brownrook.net"
  exit 2
fi

# Pin version consciously
K3S_VERSION="v1.35.1+k3s1"

REMOTE_BOOTSTRAP="/opt/brownrook/bootstrap/k3s"
REMOTE_CFG_DIR="/etc/rancher/k3s"
REMOTE_CFG_PATH="${REMOTE_CFG_DIR}/config.yaml"

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Preparing remote directories on ${TARGET} ..."
ssh "$TARGET" "sudo mkdir -p '${REMOTE_BOOTSTRAP}' '${REMOTE_CFG_DIR}'"

echo "Copying config.yaml ..."
scp "${LOCAL_DIR}/config.yaml" "${TARGET}:/tmp/k3s-config.yaml"

echo "Installing k3s on ${TARGET} (version ${K3S_VERSION}) ..."

ssh "$TARGET" "sudo bash -s" <<EOF
set -euo pipefail

echo "Placing config..."
mv /tmp/k3s-config.yaml '${REMOTE_CFG_PATH}'
chmod 0644 '${REMOTE_CFG_PATH}'

# Check if k3s already exists
if command -v k3s >/dev/null 2>&1; then
  echo "k3s already installed."
  CURRENT_VERSION=\$(/usr/local/bin/k3s --version | awk '{print \$3}')
  echo "Current version: \$CURRENT_VERSION"

  if [[ "\$CURRENT_VERSION" != "${K3S_VERSION}" ]]; then
    echo "Version mismatch."
    echo "Uninstall first if you want to change versions:"
    echo "  sudo /usr/local/bin/k3s-uninstall.sh"
    exit 1
  else
    echo "Pinned version already installed."
    systemctl restart k3s
  fi
else
  echo "Downloading installer..."
  curl -sfL https://get.k3s.io -o '${REMOTE_BOOTSTRAP}/get.k3s.sh'
  chmod +x '${REMOTE_BOOTSTRAP}/get.k3s.sh'

  echo "Installing pinned version ${K3S_VERSION}..."

  INSTALL_K3S_VERSION='${K3S_VERSION}' \
  '${REMOTE_BOOTSTRAP}/get.k3s.sh'
fi

systemctl enable --now k3s

echo
echo "k3s installation complete."
EOF

echo "Verifying cluster..."

ssh "$TARGET" "sudo systemctl --no-pager -l status k3s; sudo /usr/local/bin/k3s kubectl get nodes -o wide"

echo
echo "Done."
