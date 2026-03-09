# IDC Status Checks

## Check application health

curl -s https://idc.brownrook.com/health | jq

## Check application version

curl -s https://idc.brownrook.com/version | jq

## Watch pods

watch -n1 "kubectl get pods -n brownrook-idc"

## Show pod images

kubectl get pods -n brownrook-idc \
-o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image

## Show rollout status

kubectl rollout status deployment/brownrook-idc -n brownrook-idc

