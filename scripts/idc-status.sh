#!/usr/bin/env bash

echo "IDC health"
curl -s https://idc.brownrook.com/health | jq

echo
echo "Pods"
kubectl get pods -n brownrook-idc

echo
echo "Image"
kubectl get deployment brownrook-idc -n brownrook-idc \
-o jsonpath='{.spec.template.spec.containers[0].image}'
echo

