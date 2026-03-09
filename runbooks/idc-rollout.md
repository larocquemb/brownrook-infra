# IDC Deployment Rollout

## Check Argo sync

kubectl get applications -n argocd

## Show deployed infra revision

kubectl get application brownrook-idc -n argocd \
-o jsonpath='{.status.sync.revision}'

## Check deployment image

kubectl get deployment brownrook-idc -n brownrook-idc \
-o jsonpath='{.spec.template.spec.containers[0].image}'

