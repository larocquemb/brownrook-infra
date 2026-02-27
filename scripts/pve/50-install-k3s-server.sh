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

# Pin version consciously (change consciously)
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

# Pass K3S_VERSION to the remote script as $1 (avoids heredoc expansion problems)
ssh "$TARGET" "sudo bash -s -- '${K3S_VERSION}'" <<'EOF'
set -euo pipefail

K3S_VERSION="${1:?missing K3S_VERSION}"

REMOTE_BASE="/opt/brownrook/bootstrap/k3s"
REMOTE_CFG_DIR="/etc/rancher/k3s"
REMOTE_CFG_PATH="${REMOTE_CFG_DIR}/config.yaml"

echo "Placing config..."
sudo install -d -m 0755 "${REMOTE_CFG_DIR}"
sudo install -m 0644 /tmp/k3s-config.yaml "${REMOTE_CFG_PATH}"

echo "Downloading installer..."
sudo install -d -m 0755 "${REMOTE_BASE}"
sudo curl -sfL https://get.k3s.io -o "${REMOTE_BASE}/get.k3s.sh"
sudo chmod 0755 "${REMOTE_BASE}/get.k3s.sh"

# Decide whether to restart or (re)install
have_k3s_bin=0
command -v k3s >/dev/null 2>&1 && have_k3s_bin=1

have_unit=0
systemctl list-unit-files --no-legend | awk '{print $1}' | grep -qx 'k3s.service' && have_unit=1

if [[ "${have_k3s_bin}" -eq 1 && "${have_unit}" -eq 1 ]]; then
  echo "k3s already installed + unit exists; restarting to apply config..."
  sudo systemctl daemon-reload || true
  sudo systemctl restart k3s
else
  echo "k3s missing or unit missing; installing pinned version ${K3S_VERSION}..."
  # IMPORTANT: put env vars on the same sudo invocation line
  sudo INSTALL_K3S_VERSION="${K3S_VERSION}" \
       INSTALL_K3S_CHANNEL="" \
       sh "${REMOTE_BASE}/get.k3s.sh"

  sudo systemctl daemon-reload || true
  sudo systemctl enable --now k3s
fi

echo
echo "Installed:"
sudo /usr/local/bin/k3s --version || true

echo
echo "k3s status:"
sudo systemctl --no-pager -l status k3s || true
EOF

echo "Verifying cluster..."
ssh "$TARGET" "sudo systemctl --no-pager -l status k3s; sudo /usr/local/bin/k3s kubectl get nodes -o wide"

echo
echo "Done."
