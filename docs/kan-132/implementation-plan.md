# Gated implementation plan

Apply these gates in order. Stop at the first failed gate; do not compensate by
weakening replica, backup, or quorum requirements.

## Gate 0: capture the starting state

1. Run `scripts/kan-132/preflight.sh` and retain its output as evidence.
2. On `k3s1`, run `sudo scripts/kan-132/backup-sqlite.sh` from a checked-out
   copy of this repository.
3. Copy the SQLite backup off `k3s1` using an encrypted transport and verify
   the SHA-256 manifest.
4. Store the K3s server token separately in the approved secret store. Do not
   place the token in the same unauthenticated location as the datastore copy.
5. Take and verify PostgreSQL logical backups and inventory the current SMB
   receipt tree before changing any PVC.

## Gate 1: independent node and disk preparation

1. Attach a dedicated zpool-backed virtual disk to the `k3s1` VM. Format it
   XFS or ext4 inside RHEL and persistently mount it at `/var/lib/longhorn`.
2. Prepare dedicated XFS/ext4 storage at the same path on `arsene` and
   `longbow`. A single shared zpool is not three storage failure domains.
3. Install and enable `open-iscsi`; install the NFS client packages required by
   RWX volumes.
4. Reserve enough usable capacity on every node for the selected replica count
   after Longhorn's free-space threshold. Do not count thin-provisioned logical
   capacity as physically available recovery capacity.
5. Label only prepared nodes:

   ```bash
   kubectl label node k3s1 arsene longbow \
     node.longhorn.io/create-default-disk=true \
     storage.brownrook.net/tier=production
   ```

## Gate 2: stable API endpoint and SQLite conversion

1. Allocate the internal API VIP/load-balancer address and create
   `k3s-api.brownrook.net`. Confirm redundant ownership and restrict TCP/6443
   to the administration network and cluster nodes.
2. Add the API DNS name and VIP to `tls-san` on every server.
3. During a maintenance window, restart `k3s1` once with `cluster-init: true`.
   This converts the existing SQLite cluster to embedded etcd. Remove the
   one-time setting after conversion.
4. Verify `k3s etcd-snapshot save` succeeds before joining peers.
5. Convert `arsene` from an agent to a server and join it through the stable API
   endpoint using the original server token.
6. Install and join `longbow` as the third server using the same pinned K3s
   version and token.
7. Verify three distinct etcd members, three Ready server nodes, and continued
   API operation with one server stopped at a time.

Do not copy the SQLite database to the additional servers. They join the newly
created embedded-etcd cluster through the K3s server API.

## Gate 3: off-cluster etcd backups

1. Create the S3 configuration Secret from
   `kubernetes/staged/k3s-etcd-s3-secret.example.yaml` using a secret manager.
2. Add the non-secret settings from
   `kubernetes/staged/k3s-server-config.example.yaml` to every server.
3. Save an on-demand snapshot, verify both local and S3 entries, and confirm
   the object can be retrieved without relying on the K3s cluster.
4. Complete a restore rehearsal on isolated infrastructure using the saved
   server token. Never restore an untrusted snapshot into production.

## Gate 4: Longhorn

1. Run `scripts/kan-132/preflight.sh --longhorn` until it passes.
2. Apply `kubernetes/staged/longhorn/application.yaml` manually and sync the
   Argo CD application. It is intentionally absent from the root app.
3. Apply `kubernetes/staged/longhorn/storage-classes.yaml`.
4. Verify all Longhorn managers and instance managers are healthy, all three
   prepared disks are schedulable, and a three-replica test volume is healthy.
5. Run a test pod, checksum its data, move the pod after a node drain, and
   verify the checksum again.

## Gate 5: application-aware migration

1. Configure independent S3-compatible object storage and migrate existing
   receipt objects from the SMB tree while retaining checksums and a reversible
   source copy.
2. Retain a restricted Canon SMB `scan-inbox`, but deploy an idempotent importer
   that verifies completed scans, writes the source object, commits PostgreSQL
   metadata, and only then archives or removes the source. Quarantine failures.
3. Deploy application support for the object-storage contract before removing
   any legacy SMB archive dependency. Do not remove the printer inbox.
4. Restore PostgreSQL into a new `brownrook-block-rwo` claim from a logical
   backup. Validate row counts, schema version, application health, and sampled
   receipt-object checksums.
5. Re-create RabbitMQ state only if required by application semantics; prefer
   draining/replaying durable work from the system of record over filesystem
   copying.
6. Migrate any remaining production `local-path` claims. Keep old volumes
   retained until restore and rollback checks pass.

## Gate 6: failure evidence

Run `scripts/kan-132/validate-ha.sh` before and after each controlled failure.
For each of `k3s1`, `arsene`, and `longbow`:

1. Record baseline API, etcd, Longhorn, ingress, PostgreSQL, and receipt-object
   health.
2. Cordon and drain the node when possible, then stop K3s or power off the host
   as required by the test.
3. Verify the API, DNS, ingress, PostgreSQL, and a representative receipt read
   and write remain available. Verify that a Canon scan is either ingested or
   safely retained in the SMB inbox during the tested failure.
4. Recover the node, verify etcd and Longhorn convergence, and retain the
   timestamped evidence.

Do not mark KAN-132 complete until the restore and single-node failure evidence
is attached to the story.
