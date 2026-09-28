# KAN-132: production K3s hardening

This directory is the implementation record for
[KAN-132](https://brownrook.atlassian.net/browse/KAN-132). It deliberately
separates changes that are safe to merge from changes that are safe to apply.

The live cluster must not install Longhorn or convert its datastore until all
gates in [implementation-plan.md](implementation-plan.md) pass. As of the
2026-09-28 audit, the cluster has two nodes, one K3s server backed by SQLite,
and production PVCs using `local-path`. Those conditions do not satisfy the
story's availability criteria.

Files in this implementation:

- [current-state.md](current-state.md) records the observed starting state.
- [storage-contract.md](storage-contract.md) defines the portable PVC and
  object-storage interfaces consumed by K3s and EKS.
- [implementation-plan.md](implementation-plan.md) provides the ordered,
  gated conversion and migration procedure.
- `scripts/kan-132/` contains repeatable backup, preflight, and validation
  commands.
- `kubernetes/staged/longhorn/` contains the pinned Longhorn deployment. It is
  intentionally not referenced by the Argo CD root application yet.

No credentials, K3s tokens, database dumps, receipt objects, or backup files
belong in Git.
