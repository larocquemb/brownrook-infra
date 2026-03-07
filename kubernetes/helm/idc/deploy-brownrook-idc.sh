#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# deploy-brownrook-idc.sh
#
# Deploys:
#   - cert-manager (Helm)
#   - Route53 credentials Secret (local file: *.secret.yaml, gitignored)
#   - ClusterIssuers (staging + prod) for Route53 DNS-01
#   - brownrook-idc Helm release with Traefik Ingress + cert-manager TLS
#
# No heredocs: all K8s objects are applied from files.
# ------------------------------------------------------------------------------

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Namespaces / release
CERT_NS="${CERT_NS:-cert-manager}"
APP_NS="${APP_NS:-brownrook-idc}"
RELEASE="${RELEASE:-brownrook-idc}"

# ---- cert-manager (pin version for repeatability)
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.14.5}"

# ---- Files (relative to this script directory)
ROUTE53_SECRET_FILE="${ROUTE53_SECRET_FILE:-${BASE_DIR}/route53-credentials.secret.yaml}"
ISSUER_STAGING_FILE="${ISSUER_STAGING_FILE:-${BASE_DIR}/clusterissuer-letsencrypt-staging-route53.yaml}"
ISSUER_PROD_FILE="${ISSUER_PROD_FILE:-${BASE_DIR}/clusterissuer-letsencrypt-prod-route53.yaml}"

VALUES_FILE="${VALUES_FILE:-${BASE_DIR}/values-k3s.yaml}"

# ---- Chart location (adjust default to your environment)
# You can override with: CHART_PATH=/path/to/charts/brownrook-idc
CHART_PATH="${CHART_PATH:-${BASE_DIR}/../../../../brownrook-idc/charts/brownrook-idc}"

# ---- Helpers
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found in PATH."
    exit 1
  }
}

check_file() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Required file not found: $f"
    exit 1
  fi
}

echo "==> Checking tools..."
need_cmd kubectl
need_cmd helm

echo "==> Checking required files..."
check_file "${ROUTE53_SECRET_FILE}"
check_file "${ISSUER_STAGING_FILE}"
check_file "${ISSUER_PROD_FILE}"
check_file "${VALUES_FILE}"

if [[ ! -d "${CHART_PATH}" ]]; then
  echo "ERROR: CHART_PATH directory not found: ${CHART_PATH}"
  echo "Set CHART_PATH to the brownrook-idc Helm chart directory."
  exit 1
fi

echo "==> Checking cluster connectivity..."
kubectl version --short >/dev/null
kubectl get nodes >/dev/null

echo "==> Ensuring namespaces exist..."
kubectl create namespace "${CERT_NS}" >/dev/null 2>&1 || true
kubectl create namespace "${APP_NS}"  >/dev/null 2>&1 || true

echo "==> Installing/Upgrading cert-manager (${CERT_MANAGER_VERSION})..."
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install cert-manager jetstack/cert-manager \
  -n "${CERT_NS}" \
  --version "${CERT_MANAGER_VERSION}" \
  --set crds.enabled=true

echo "==> Waiting for cert-manager to become ready..."
kubectl -n "${CERT_NS}" rollout status deploy/cert-manager --timeout=180s
kubectl -n "${CERT_NS}" rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n "${CERT_NS}" rollout status deploy/cert-manager-cainjector --timeout=180s

echo "==> Applying Route53 credentials Secret (local-only, gitignored)..."
kubectl apply -f "${ROUTE53_SECRET_FILE}"

echo "==> Applying ClusterIssuers (staging + prod)..."
kubectl apply -f "${ISSUER_STAGING_FILE}"
kubectl apply -f "${ISSUER_PROD_FILE}"

echo "==> Deploying/Upgrading brownrook-idc Helm release..."
helm upgrade --install "${RELEASE}" "${CHART_PATH}" \
  -n "${APP_NS}" \
  -f "${VALUES_FILE}"

echo
echo "==> Status:"
kubectl -n "${APP_NS}" get deploy,svc,ingress || true
kubectl -n "${APP_NS}" get certificate,order,challenge 2>/dev/null || true

echo
echo "==> Quick diagnostics (copy/paste):"
echo "kubectl -n ${CERT_NS} logs deploy/cert-manager --tail=200"
echo "kubectl -n ${APP_NS} describe certificate idc-brownrook-com-tls || true"
echo "kubectl -n ${APP_NS} get order,challenge"
echo "kubectl -n kube-system get svc traefik -o wide"

echo
echo "DONE."
