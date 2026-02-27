#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   RUN_TEST=0 ./60-enable-metallb.sh paul@k3s1.brownrook.net
#
# Default:
#   RUN_TEST=1  -> deploys a test LoadBalancer service
#   RUN_TEST=0  -> no test workload

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: RUN_TEST=0 $0 paul@k3s1.brownrook.net"
  exit 2
fi

METALLB_VERSION="v0.14.5"
POOL_RANGE="192.168.2.240-192.168.2.250"
RUN_TEST="${RUN_TEST:-1}"

echo "==> Enabling MetalLB on ${TARGET}"
echo "    MetalLB: ${METALLB_VERSION}"
echo "    Pool:    ${POOL_RANGE}"
echo "    Test:    RUN_TEST=${RUN_TEST}"

ssh "$TARGET" "sudo bash -s" <<EOF
set -euo pipefail

echo "==> Applying MetalLB upstream manifest (includes namespace)"
/usr/local/bin/kubectl apply -f \
  https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

echo "==> Waiting for controller rollout"
/usr/local/bin/kubectl -n metallb-system rollout status deployment/controller --timeout=180s

echo "==> Waiting for speaker rollout"
/usr/local/bin/kubectl -n metallb-system rollout status daemonset/speaker --timeout=180s

echo "==> Applying IPAddressPool + L2Advertisement"
cat <<YAML | /usr/local/bin/kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: brownrook-pool
  namespace: metallb-system
spec:
  addresses:
  - ${POOL_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: brownrook-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - brownrook-pool
YAML

echo "==> Current MetalLB status"
/usr/local/bin/kubectl -n metallb-system get pods -o wide
/usr/local/bin/kubectl -n metallb-system get ipaddresspools
EOF

if [[ "$RUN_TEST" == "1" ]]; then
  echo "==> Deploying test LoadBalancer service"

  ssh "$TARGET" "sudo bash -s" <<'EOF'
set -euo pipefail

/usr/local/bin/kubectl create namespace test-lb --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -

/usr/local/bin/kubectl -n test-lb create deploy hello --image=nginx \
  --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -

/usr/local/bin/kubectl -n test-lb expose deploy hello \
  --port 80 --type LoadBalancer \
  --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -

echo
echo "==> Waiting for EXTERNAL-IP..."
/usr/local/bin/kubectl -n test-lb get svc hello -w
EOF
fi

echo "==> Completed."
