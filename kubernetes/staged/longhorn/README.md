# Staged Longhorn deployment

This directory is intentionally not included in
`kubernetes/gitops/kustomization.yaml`. Applying it before KAN-132 gates 0-3
pass could schedule replicas on root disks, create degraded volumes, or imply
availability that the two-node SQLite cluster does not have.

The chart is pinned to Longhorn 1.12.1 and uses the V1 data engine. Every
eligible node must have:

- dedicated XFS or ext4 storage mounted at `/var/lib/longhorn`;
- `node.longhorn.io/create-default-disk=true`;
- active `iscsid` and the required NFS client packages;
- enough real capacity for three full copies of every protected volume;
- a distinct physical failure domain.

The PVE zpool may back a virtual disk attached to `k3s1`. Format and mount that
disk inside the guest; do not configure a ZFS dataset itself as the Longhorn V1
data path.

After `scripts/kan-132/preflight.sh --longhorn` succeeds:

```bash
kubectl --context brownrook-k3s1 apply -f kubernetes/staged/longhorn/application.yaml
argocd app sync longhorn
kubectl --context brownrook-k3s1 apply -f kubernetes/staged/longhorn/storage-classes.yaml
```

Keep `local-path` as the cluster default until application-aware backup and
restore into the portable StorageClasses has been proven. Existing PVCs are not
migrated by changing a StorageClass.
