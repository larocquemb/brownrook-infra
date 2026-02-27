#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 paul@k3s1.brownrook.net"
  exit 2
fi

echo "==> Ensuring Traefik is enabled on ${TARGET}"

ssh "$TARGET" "sudo bash -s" <<'EOF'
set -euo pipefail

KUBECTL="sudo /usr/local/bin/k3s kubectl"
CFG="/etc/rancher/k3s/config.yaml"

if [[ ! -f "$CFG" ]]; then
  echo "ERROR: $CFG not found"
  exit 1
fi

echo "Checking config for '- traefik'..."

if sudo grep -qE '^[[:space:]]*-[[:space:]]*traefik[[:space:]]*$' "$CFG"; then
  echo "Found '- traefik' in config.yaml; removing..."
  # Remove the line, keep everything else as-is
  sudo sed -i -E '/^[[:space:]]*-[[:space:]]*traefik[[:space:]]*$/d' "$CFG"

  echo "Reloading systemd + restarting k3s..."
  sudo systemctl daemon-reload || true
  sudo systemctl restart k3s
else
  echo "Traefik not disabled in config.yaml."
fi

echo
echo "Waiting for Traefik deployment to appear..."
for i in {1..60}; do
  if $KUBECTL -n kube-system get deploy traefik >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "Waiting for Traefik rollout..."
$KUBECTL -n kube-system rollout status deployment/traefik --timeout=180s

echo
echo "Traefik service:"
$KUBECTL -n kube-system get svc traefik -o wide

echo
echo "Traefik pods:"
$KUBECTL -n kube-system get pods -l app.kubernetes.io/name=traefik -o wide

echo "==> Done."
EOF

echo "Completed."
