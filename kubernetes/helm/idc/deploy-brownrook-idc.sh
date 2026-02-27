#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# BrownRook IDC - k3s (Traefik) + cert-manager + Route53 DNS-01 + Helm deploy
# Idempotent: safe to run repeatedly.
# ------------------------------------------------------------------------------

# ----------------------------
# Required env vars (you set)
# ----------------------------
: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY}"
: "${LE_EMAIL:?Set LE_EMAIL (e.g., paul@brownrook.com)}"
: "${TENANT_ID:?Set TENANT_ID (Entra tenant id for issuer URL)}"
: "${OIDC_AUDIENCE:?Set OIDC_AUDIENCE (API audience / App ID URI / resource)}"

# ----------------------------
# Optional env vars (defaults)
# ----------------------------
HOST="${HOST:-idc.brownrook.com}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Your Helm chart path (local repo path)
CHART_PATH="${CHART_PATH:-./charts/brownrook-idc}"
RELEASE="${RELEASE:-brownrook-idc}"
NAMESPACE="${NAMESPACE:-brownrook-idc}"

# cert-manager install
CERT_MANAGER_NS="${CERT_MANAGER_NS:-cert-manager}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.14.5}"  # pin for repeatability
ROUTE53_SECRET_NAME="${ROUTE53_SECRET_NAME:-route53-credentials}"

# Issuer names
ISSUER_STAGING="${ISSUER_STAGING:-letsencrypt-staging-route53}"
ISSUER_PROD="${ISSUER_PROD:-letsencrypt-prod-route53}"

# Ingress class (Traefik on k3s)
INGRESS_CLASS="${INGRESS_CLASS:-traefik}"
TLS_SECRET_NAME="${TLS_SECRET_NAME:-idc-brownrook-com-tls}"

# Use staging first? (recommended during initial setup)
USE_STAGING_FIRST="${USE_STAGING_FIRST:-0}" # set 1 to use staging issuer for the app install

# ----------------------------
# Helpers
# ----------------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found. Install it and re-run."
    exit 1
  }
}

k() { kubectl "$@"; }
h() { helm "$@"; }

echo "==> Checking required tools..."
need_cmd kubectl
need_cmd helm

echo "==> Checking cluster connectivity..."
k version --short >/dev/null
k get nodes >/dev/null

echo "==> Verifying Traefik ingress class exists (expected: '${INGRESS_CLASS}')..."
if ! k get ingressclass "${INGRESS_CLASS}" >/dev/null 2>&1; then
  echo "WARN: IngressClass '${INGRESS_CLASS}' not found."
  echo "      Available ingress classes:"
  k get ingressclass || true
  echo "      If Traefik isn't installed/enabled, fix that first."
  exit 1
fi

echo "==> Ensuring namespaces exist..."
k create namespace "${CERT_MANAGER_NS}" >/dev/null 2>&1 || true
k create namespace "${NAMESPACE}" >/dev/null 2>&1 || true

echo "==> Installing/Upgrading cert-manager (${CERT_MANAGER_VERSION})..."
h repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
h repo update >/dev/null

h upgrade --install cert-manager jetstack/cert-manager \
  -n "${CERT_MANAGER_NS}" \
  --version "${CERT_MANAGER_VERSION}" \
  --set crds.enabled=true

echo "==> Waiting for cert-manager deployments..."
k -n "${CERT_MANAGER_NS}" rollout status deploy/cert-manager --timeout=180s
k -n "${CERT_MANAGER_NS}" rollout status deploy/cert-manager-webhook --timeout=180s
k -n "${CERT_MANAGER_NS}" rollout status deploy/cert-manager-cainjector --timeout=180s

echo "==> Creating/Updating Route53 credentials secret (${CERT_MANAGER_NS}/${ROUTE53_SECRET_NAME})..."
# Apply via kubectl for idempotency
cat <<EOF | k apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${ROUTE53_SECRET_NAME}
  namespace: ${CERT_MANAGER_NS}
type: Opaque
stringData:
  aws_access_key_id: "${AWS_ACCESS_KEY_ID}"
  aws_secret_access_key: "${AWS_SECRET_ACCESS_KEY}"
EOF

echo "==> Applying ClusterIssuers (staging + prod)..."
cat <<EOF | k apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${ISSUER_STAGING}
spec:
  acme:
    email: ${LE_EMAIL}
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: ${ISSUER_STAGING}-account-key
    solvers:
    - dns01:
        route53:
          region: ${AWS_REGION}
          accessKeyIDSecretRef:
            name: ${ROUTE53_SECRET_NAME}
            key: aws_access_key_id
          secretAccessKeySecretRef:
            name: ${ROUTE53_SECRET_NAME}
            key: aws_secret_access_key
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${ISSUER_PROD}
spec:
  acme:
    email: ${LE_EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: ${ISSUER_PROD}-account-key
    solvers:
    - dns01:
        route53:
          region: ${AWS_REGION}
          accessKeyIDSecretRef:
            name: ${ROUTE53_SECRET_NAME}
            key: aws_access_key_id
          secretAccessKeySecretRef:
            name: ${ROUTE53_SECRET_NAME}
            key: aws_secret_access_key
EOF

echo "==> Validating ClusterIssuers exist..."
k get clusterissuer "${ISSUER_STAGING}" >/dev/null
k get clusterissuer "${ISSUER_PROD}" >/dev/null

ISSUER_FOR_APP="${ISSUER_PROD}"
if [[ "${USE_STAGING_FIRST}" == "1" ]]; then
  ISSUER_FOR_APP="${ISSUER_STAGING}"
fi

OIDC_ISSUER="https://login.microsoftonline.com/${TENANT_ID}/v2.0"

echo "==> Deploying/Upgrading ${RELEASE} from chart: ${CHART_PATH}"
if [[ ! -d "${CHART_PATH}" ]]; then
  echo "ERROR: CHART_PATH not found: ${CHART_PATH}"
  echo "Set CHART_PATH to your local Helm chart directory."
  exit 1
fi

h upgrade --install "${RELEASE}" "${CHART_PATH}" \
  -n "${NAMESPACE}" \
  --set ingress.enabled=true \
  --set ingress.className="${INGRESS_CLASS}" \
  --set ingress.host="${HOST}" \
  --set ingress.tls.enabled=true \
  --set ingress.tls.secretName="${TLS_SECRET_NAME}" \
  --set ingress.annotations."cert-manager\.io/cluster-issuer"="${ISSUER_FOR_APP}" \
  --set env.OIDC_ISSUER="${OIDC_ISSUER}" \
  --set env.OIDC_AUDIENCE="${OIDC_AUDIENCE}"

echo
echo "==> Status:"
k -n "${NAMESPACE}" get deploy,svc,ingress || true
k -n "${NAMESPACE}" get certificate,order,challenge 2>/dev/null || true

echo
echo "==> Useful checks (copy/paste):"
cat <<'EOF'
# cert-manager logs
kubectl -n cert-manager logs deploy/cert-manager --tail=200

# watch issuance
kubectl -n brownrook-idc get certificate,order,challenge -w

# describe certificate (adjust name if different)
kubectl -n brownrook-idc describe certificate idc-brownrook-com-tls

# verify Traefik service exposure
kubectl -n kube-system get svc traefik -o wide
EOF

echo
echo "==> Next:"
echo "1) Ensure DNS A/CNAME for ${HOST} points to your ingress endpoint (home WAN IP / LB)."
echo "2) Once cert is Ready, test: curl -I https://${HOST}/"
echo "3) Test auth: curl -i https://${HOST}/secure -H \"Authorization: Bearer \${ACCESS_TOKEN}\""
echo
echo "DONE."