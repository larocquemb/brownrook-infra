#!/usr/bin/env bash

echo "===== IDC HEALTH ====="
curl -s https://idc.brownrook.com/health | jq

echo
echo "===== PODS ====="
kubectl get pods -n brownrook-idc

echo
echo "===== IMAGE ====="
kubectl get deployment brownrook-idc -n brownrook-idc \
-o jsonpath='{.spec.template.spec.containers[0].image}'
echo

echo
echo "===== ARGO REVISION ====="
kubectl get application brownrook-idc -n argocd \
-o jsonpath='{.status.sync.revision}'
echo
