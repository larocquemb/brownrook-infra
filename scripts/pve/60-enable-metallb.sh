#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   RUN_TEST=0 ./scripts/pve/60-enable-metallb.sh paul@k3s1.brownrook.net
#   RUN_TEST=1 ./scripts/pve/60-enable-metallb.sh paul@k3s1.brownrook.net

TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
  echo "Usage: $0 paul@k3s1.brownrook.net"
  exit 2
fi

# ---- CONFIG ----
METALLB_VERSION="v0.14.5"

POOL_NAME="brownrook-pool"
L2ADV_NAME="brownrook-l2"
ADDRESS_POOL="192.168.2.240-192.168.2.250"

RUN_TEST="${RUN_TEST:-1}"
TEST_NS="default"
TEST_DEPLOY="nginx"
TEST_SVC="nginx"
# ---------------

echo "==> Enabling MetalLB on ${TARGET}"
echo "    MetalLB: ${METALLB_VERSION}"
echo "    Pool:    ${ADDRESS_POOL}"
echo "    Test:    RUN_TEST=${RUN_TEST}"

ssh "${TARGET}" "sudo bash -s" <<'EOF'
set -euo pipefail

# ---- These must be correct on the TARGET (RHEL node) ----
KUBECTL="/usr/local/bin/kubectl"
K3S="/usr/local/bin/k3s"
CURL="/usr/bin/curl"
# --------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

echo "==> Target diagnostics"
echo "    PATH=$PATH"
ls -la /usr/local/bin >/dev/null 2>&1 || true

[[ -x "${K3S}" ]] || die "k3s not found at ${K3S}. Is k3s installed?"
# kubectl may be a symlink to k3s; accept either
if [[ ! -x "${KUBECTL}" ]]; then
  if [[ -x "${K3S}" ]]; then
    echo "WARN: ${KUBECTL} not found, but ${K3S} exists. Using '${K3S} kubectl' fallback."
    KUBECTL="${K3S} kubectl"
  else
    die "kubectl not found at ${KUBECTL} and no k3s fallback available."
  fi
fi

# curl path on RHEL can vary slightly; try alternatives
if [[ ! -x "${CURL}" ]]; then
  if command -v curl >/dev/null 2>&1; then
    CURL="$(command -v curl)"
  else
    die "curl not found. Install curl on the node."
  fi
fi

echo "    Using kubectl: ${KUBECTL}"
echo "    Using k3s:     ${K3S}"
echo "    Using curl:    ${CURL}"

# Pull variables injected by the outer script via environment is not possible with single-quoted heredoc,
# so we read them from files written below (outer script will pass them via bash heredoc substitution).
EOF

# Re-run SSH with variable substitution (so METALLB_VERSION etc get injected)
ssh "${TARGET}" "sudo bash -s" <<EOF
set -euo pipefail

KUBECTL="/usr/local/bin/kubectl"
K3S="/usr/local/bin/k3s"

# Fallback if kubectl isn't directly present
if [[ ! -x "\${KUBECTL}" ]]; then
  KUBECTL="\${K3S} kubectl"
fi

METALLB_VERSION="${METALLB_VERSION}"
POOL_NAME="${POOL_NAME}"
L2ADV_NAME="${L2ADV_NAME}"
ADDRESS_POOL="${ADDRESS_POOL}"

RUN_TEST="${RUN_TEST}"
TEST_NS="${TEST_NS}"
TEST_DEPLOY="${TEST_DEPLOY}"
TEST_SVC="${TEST_SVC}"

echo "==> Create namespace metallb-system (idempotent)"
\${KUBECTL} get ns metallb-system >/dev/null 2>&1 || \${KUBECTL} create ns metallb-system

echo "==> Apply MetalLB manifests (\${METALLB_VERSION})"
\${KUBECTL} apply -f "https://raw.githubusercontent.com/metallb/metallb/\${METALLB_VERSION}/config/manifests/metallb-native.yaml"

echo "==> Wait for MetalLB controller/speaker"
\${KUBECTL} -n metallb-system rollout status deploy/controller --timeout=240s
\${KUBECTL} -n metallb-system rollout status ds/speaker --timeout=240s

echo "==> Apply IPAddressPool + L2Advertisement"
cat <<YAML | \${KUBECTL} apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: \${POOL_NAME}
  namespace: metallb-system
spec:
  addresses:
  - \${ADDRESS_POOL}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: \${L2ADV_NAME}
  namespace: metallb-system
spec: {}
YAML

echo "==> Show MetalLB status"
\${KUBECTL} -n metallb-system get pods -o wide
\${KUBECTL} -n metallb-system get ipaddresspool,l2advertisement -o wide

if [[ "\${RUN_TEST}" == "1" ]]; then
  echo "==> Smoke test: nginx LoadBalancer service"
  \${KUBECTL} -n "\${TEST_NS}" get deploy/"\${TEST_DEPLOY}" >/dev/null 2>&1 || \
    \${KUBECTL} -n "\${TEST_NS}" create deployment "\${TEST_DEPLOY}" --image=nginx

  \${KUBECTL} -n "\${TEST_NS}" get svc/"\${TEST_SVC}" >/dev/null 2>&1 || \
    \${KUBECTL} -n "\${TEST_NS}" expose deployment "\${TEST_DEPLOY}" --port 80 --type LoadBalancer --name "\${TEST_SVC}"

  echo "==> Waiting for EXTERNAL-IP assignment..."
  for i in {1..90}; do
    EXTERNAL_IP="\$(\${KUBECTL} -n "\${TEST_NS}" get svc "\${TEST_SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "\${EXTERNAL_IP}" ]]; then
      echo "Assigned EXTERNAL-IP: \${EXTERNAL_IP}"
      echo "From your Mac: curl http://\${EXTERNAL_IP}"
      break
    fi
    sleep 2
  done

  \${KUBECTL} -n "\${TEST_NS}" get svc "\${TEST_SVC}" -o wide
fi

echo "==> Done."
EOF

echo "==> Completed."
