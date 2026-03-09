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

short() {
  local v="${1:-unknown}"
  [[ "$v" == "unknown" || -z "$v" ]] && echo "unknown" || echo "${v:0:7}"
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
printf "  %-8s %s\n" "local"   "$(short "$LOCAL_COMMIT")"
printf "  %-8s %s\n" "remote"  "$(short "${REMOTE_COMMIT:-unknown}")"
printf "  %-8s %s\n" "cluster" "$(short "$CLUSTER_COMMIT")"
echo

echo "REGISTRY"
if [[ -n "${REMOTE_COMMIT:-}" ]] && skopeo inspect "docker://${IMAGE}:${REMOTE_COMMIT}" >/dev/null 2>&1; then
  printf "  %-8s %s\n" "ghcr" "present"
else
  printf "  %-8s %s\n" "ghcr" "missing"
fi
echo

echo "GITOPS"
printf "  %-8s %s\n" "argo" "$(short "$INFRA_COMMIT")"
echo

echo "ROLLOUT"
if kubectl rollout status deployment/"$APP" -n "$NS" --timeout=1s >/dev/null 2>&1; then
  printf "  %-8s %s\n" "status" "complete"
else
  printf "  %-8s %s\n" "status" "progressing"
fi
echo

echo "PODS"
kubectl get pods -n "$NS" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].ready}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.metadata.creationTimestamp}{"\t"}{.spec.nodeName}{"\t"}{.spec.containers[0].image}{"\n"}{end}' \
| awk -F'\t' '
BEGIN {
  printf "%-34s %-5s %-4s %-20s %-10s %s\n", "POD", "RDY", "RST", "CREATED", "NODE", "SHA"
}
{
  n=split($6,a,":")
  sha=a[n]
  if (length(sha) > 7) sha=substr(sha,1,7)
  printf "%-34s %-5s %-4s %-20s %-10s %s\n", $1, $2, $3, $4, $5, sha
}'
echo

echo "API /info"
curl -fsS "$INFO_URL" 2>/dev/null | jq || echo "unavailable"