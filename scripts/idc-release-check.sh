#!/usr/bin/env bash

set -e

IDC_REPO=~/Developer/brownrook/brownrook-idc
APP=brownrook-idc
NS=brownrook-idc
IMAGE=ghcr.io/larocquemb/brownrook-idc

echo "======================================"
echo "BrownRook IDC Release Verification"
echo "======================================"
echo

echo "1️⃣ Local source commit"
LOCAL_COMMIT=$(git -C $IDC_REPO rev-parse HEAD)
echo "   $LOCAL_COMMIT"
echo

echo "2️⃣ GHCR image check"
if podman manifest inspect ${IMAGE}:${LOCAL_COMMIT} >/dev/null 2>&1; then
    echo "   ✔ image exists in GHCR"
else
    echo "   ❌ image NOT found in GHCR"
fi
echo

echo "3️⃣ ArgoCD deployed infra commit"
INFRA_COMMIT=$(kubectl get application $APP -n argocd -o json | jq -r '.status.sync.revision')
echo "   $INFRA_COMMIT"
echo

echo "4️⃣ Kubernetes deployment image"
CLUSTER_IMAGE=$(kubectl get deployment $APP -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "   $CLUSTER_IMAGE"
echo

CLUSTER_COMMIT=$(echo $CLUSTER_IMAGE | cut -d: -f2)

echo "5️⃣ Commit comparison"
echo "   local commit:   $LOCAL_COMMIT"
echo "   cluster commit: $CLUSTER_COMMIT"

if [[ "$LOCAL_COMMIT" == "$CLUSTER_COMMIT" ]]; then
    echo "   ✔ cluster is running latest commit"
else
    echo "   ⚠ cluster not running latest commit"
fi
echo

echo "6️⃣ Runtime API info"
curl -s https://idc.brownrook.com/info | jq
echo

echo "======================================"
echo "Verification complete"
echo "======================================"

