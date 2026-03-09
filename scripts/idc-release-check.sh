#!/usr/bin/env bash

set -euo pipefail

IDC_REPO="${IDC_REPO:-$HOME/Developer/brownrook/brownrook-idc}"
APP="brownrook-idc"
NS="brownrook-idc"
IMAGE="ghcr.io/larocquemb/brownrook-idc"
INFO_URL="https://idc.brownrook.com/info"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd kubectl
need_cmd jq
need_cmd curl
need_cmd skopeo

echo "BrownRook IDC Live Dashboard"
echo "Updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo

LOCAL_COMMIT="$(git -C "$IDC_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
REMOTE_COMMIT="$(git -C "$IDC_REPO" ls-remote origin main 2>/dev/null | awk '{print $1}')"
INFRA_COMMIT="$(kubectl get application "$APP" -n argocd -o json 2>/dev/null | jq -r '.status.sync.revision // "unknown"')"
CLUSTER_IMAGE="$(kubectl get deployment "$APP" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo unknown)"
CLUSTER_COMMIT="${CLUSTER_IMAGE##*:}"

echo "APP"
echo "  local commit:   $LOCAL_COMMIT"
echo "  remote commit:  ${REMOTE_COMMIT:-unknown}"
echo "  cluster image:  $CLUSTER_IMAGE"
echo "  cluster commit: $CLUSTER_COMMIT"
echo

echo "REGISTRY"
if [[ -n "${REMOTE_COMMIT:-}" ]] && skopeo inspect "docker://${IMAGE}:${REMOTE_COMMIT}" >/dev/null 2>&1; then
  echo "  ghcr image:     present for remote main"
else
  echo "  ghcr image:     missing for remote main"
fi
echo

echo "GITOPS"
echo "  argo revision:  $INFRA_COMMIT"
echo

echo "ROLLOUT"
if kubectl rollout status deployment/"$APP" -n "$NS" --timeout=1s >/dev/null 2>&1; then
  echo "  status:         complete"
else
  echo "  status:         progressing or unavailable"
fi
echo

echo "PODS"
kubectl get pods -n "$NS"
echo

echo "API /info"
curl -fsS "$INFO_URL" 2>/dev/null | jq || echo "unavailable"
