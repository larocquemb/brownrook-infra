#!/usr/bin/env bash

set -euo pipefail

IDC_REPO="${IDC_REPO:-$HOME/Developer/brownrook/brownrook-idc}"
INFRA_REPO="${INFRA_REPO:-$HOME/Developer/brownrook/brownrook-infra}"
APP="brownrook-idc"
NS="brownrook-idc"
IMAGE="ghcr.io/larocquemb/brownrook-idc"
INFO_URL="https://idc.brownrook.com/info"

echo "======================================"
echo "BrownRook IDC Release Verification"
echo "======================================"
echo

if [[ ! -d "$IDC_REPO/.git" ]]; then
  echo "❌ IDC repo not found: $IDC_REPO" >&2
  exit 1
fi

if [[ ! -d "$INFRA_REPO/.git" ]]; then
  echo "❌ Infra repo not found: $INFRA_REPO" >&2
  exit 1
fi

if ! command -v skopeo >/dev/null 2>&1; then
  echo "❌ skopeo not found. Install it with: brew install skopeo" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq not found. Install it with: brew install jq" >&2
  exit 1
fi

echo "1️⃣ Local IDC source commit"
LOCAL_IDC_COMMIT="$(git -C "$IDC_REPO" rev-parse HEAD)"
echo "   $LOCAL_IDC_COMMIT"
echo

echo "2️⃣ Remote IDC main commit"
REMOTE_IDC_COMMIT="$(git -C "$IDC_REPO" ls-remote origin main | awk '{print $1}')"
echo "   $REMOTE_IDC_COMMIT"
echo

echo "3️⃣ GHCR image check"
if skopeo inspect "docker://${IMAGE}:${REMOTE_IDC_COMMIT}" >/dev/null 2>&1; then
  echo "   ✔ image exists in GHCR for remote IDC main"
else
  echo "   ❌ image NOT found in GHCR for remote IDC main"
fi
echo

echo "4️⃣ Infra revisions"
LOCAL_INFRA_COMMIT="$(git -C "$INFRA_REPO" rev-parse HEAD)"
REMOTE_INFRA_COMMIT="$(git -C "$INFRA_REPO" ls-remote origin main | awk '{print $1}')"
ARGO_REVISION="$(kubectl get application "$APP" -n argocd -o json | jq -r '.status.sync.revision')"
echo "   local infra:   $LOCAL_INFRA_COMMIT"
echo "   remote infra:  $REMOTE_INFRA_COMMIT"
echo "   argo revision: $ARGO_REVISION"
echo

echo "5️⃣ Kubernetes deployment image"
CLUSTER_IMAGE="$(kubectl get deployment "$APP" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')"
echo "   $CLUSTER_IMAGE"
echo

CLUSTER_COMMIT="${CLUSTER_IMAGE##*:}"

echo "6️⃣ Commit comparison"
echo "   local IDC:     $LOCAL_IDC_COMMIT"
echo "   remote IDC:    $REMOTE_IDC_COMMIT"
echo "   cluster IDC:   $CLUSTER_COMMIT"

if [[ "$REMOTE_IDC_COMMIT" == "$CLUSTER_COMMIT" ]]; then
  echo "   ✔ cluster is running remote IDC main"
else
  echo "   ⚠ cluster is not running remote IDC main"
fi

if [[ "$LOCAL_IDC_COMMIT" == "$CLUSTER_COMMIT" ]]; then
  echo "   ✔ cluster matches local IDC HEAD"
else
  echo "   ℹ cluster does not match local IDC HEAD"
fi

if [[ "$ARGO_REVISION" == "$REMOTE_INFRA_COMMIT" ]]; then
  echo "   ✔ Argo matches remote infra main"
else
  echo "   ⚠ Argo does not match remote infra main"
fi

if [[ "$LOCAL_INFRA_COMMIT" == "$REMOTE_INFRA_COMMIT" ]]; then
  echo "   ✔ local infra matches remote infra main"
else
  echo "   ℹ local infra does not match remote infra main"
fi
echo

echo "7️⃣ Runtime API info"
curl -fsS "$INFO_URL" | jq
echo

echo "======================================"
echo "Verification complete"
echo "======================================"