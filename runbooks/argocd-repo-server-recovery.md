# Recover Argo CD repo-server after copyutil fails

Argo CD v3.3.2 can fail when its `copyutil` init container reruns against an
existing `var-files` volume. The symlink already exists, so `/bin/ln -s` exits
with `Already exists`. The main container may appear as `Completed` while the
init container is in `CrashLoopBackOff`. Applications report `Unknown` sync
status and a `ComparisonError` connecting to repo-server on TCP 8081.

Upstream report: https://github.com/argoproj/argo-cd/issues/26595

## Diagnose and recover

```sh
kubectl --context brownrook-k3s1 -n argocd get pods \
  -l app.kubernetes.io/name=argocd-repo-server
kubectl --context brownrook-k3s1 -n argocd logs \
  deployment/argocd-repo-server -c copyutil --tail=40
```

For this specific failure, apply the narrow strategic merge patch from the
repository root. It replaces the init container's symlink command with `ln -sf`,
preserving its image, security context, volumes, and the rest of the Deployment.
The pod template change starts a replacement pod.

```sh
kubectl --context brownrook-k3s1 -n argocd patch deployment argocd-repo-server \
  --type=strategic --patch-file runbooks/patches/argocd-repo-server-copyutil.yaml
kubectl --context brownrook-k3s1 -n argocd rollout status \
  deployment/argocd-repo-server --timeout=120s
kubectl --context brownrook-k3s1 -n argocd annotate application ledger \
  argocd.argoproj.io/refresh=hard --overwrite
kubectl --context brownrook-k3s1 -n argocd get applications
```

Existing automated sync policies may deploy pending Git changes after repo-server
recovers. Verify application conditions, rollout health, and the intended image
and environment before declaring an application update complete.

The patch persists in the live Deployment across pod and node restarts. The base
Argo CD Deployment is installed separately from this repository's GitOps
configuration; reapplying an older upstream installation manifest can overwrite
the fix. Retain this patch for v3.3.2 reinstalls. For an upgrade, inspect the
version's upstream init command and remove the workaround when no longer needed.
