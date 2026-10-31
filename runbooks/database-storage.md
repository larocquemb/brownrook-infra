# Database storage capacity

Use the infrastructure Ansible playbooks, through Make. They do not put live
Neo4j or PostgreSQL files on SMB/NFS. Original receipt documents and independent
backups can remain on PVE shared storage.

## k3s1

```sh
make storage-check
make storage-k3s1 ANSIBLE_ARGS=--check
make storage-k3s1
```

The playbook verifies VM 300's exact existing `scsi1` image on PVE SSD storage,
requires expansion capacity plus a 30 GiB host reserve, and grows it to 120 GiB.
It then verifies `/dev/sda1` is the XFS filesystem mounted at `/build`, rescans,
grows partition 1, and grows XFS online. No partition recreation, formatting,
shrink, service restart, database reset or PVC replacement is performed.
A subsequent apply must report zero changes. `df -h /build` is the real shared
filesystem capacity; local-path PVC requests are not per-volume disk quotas.
Disk growth is deliberately irreversible: XFS cannot be shrunk. Rollback of an
application does not require shrinking the filesystem.

## Arsene

Run from the controller Mac with its existing production kubeconfig/context
`brownrook-k3s1`. Enter the sudo password only in the Terminal prompt:

```sh
make storage-check
make storage-arsene ANSIBLE_ARGS='--check --ask-become-pass'
make storage-arsene ANSIBLE_ARGS=--ask-become-pass
```

The migration is restricted to the known Neo4j volume, and refuses to proceed
if another local volume appears or migration destination copies already exist.
It requires the local `/dev/mapper/rhel-home` XFS filesystem and capacity for two
copies plus a 50 GiB reserve. Existing development Podman storage is unchanged.

During the first migration it pauses Argo reconciliation for `ledger`, scales
Neo4j to zero, and waits for its pod/volume mount to disappear. Receipt/OCR
workers and PostgreSQL remain running. It copies the stopped volume twice with
numeric ownership, ACLs, hard links, sparse-file handling and extended attributes
(including SELinux labels):

* `/home/brownrook-k3s-storage/retained-before-migration`: preserved original data.
* `/home/brownrook-k3s-storage/live`: new working volume data.

Both copies must pass rsync content-checksum and metadata comparison against
the stopped source. Only then is the source renamed to
`/build/k3s/storage.before-home-migration` and a persistent bind mount activated
at `/build/k3s/storage`. Existing PV paths therefore remain valid. No force-log
recovery or transaction-log truncation is used.

The database replica and Argo reconciliation are restored on exit. If switching
fails, the playbook first unmounts the new mount, removes its fstab entry, and
restores the original directory. If rollback itself fails, it deliberately leaves
Neo4j stopped and Argo paused: inspect the failed task before resuming either.
Never mount an empty directory as the database volume.

A systemd override makes `k3s-agent` require the database mount on boot. The
playbook checks the actual `neo4j` database is online through the authenticated
system database, rather than relying only on the TCP readiness probe. Only after
this succeeds does it delete the obsolete root-filesystem copy, retaining the
original copy under `/home`. The retained copy is on the same NVMe and is not an
independent backup. This playbook does not claim to validate a host reboot.

If database validation fails after a successful mount, live data remains on
`/home`, the old root copy is retained, and a repeat apply retries validation.
If failure occurs before switching, retained directories require manual review
before retrying; the playbook refuses to overwrite them. Do not delete original
or retained data to force a rerun.

After success verify database status, `findmnt /build/k3s/storage`, `df -h / /home`,
and the next normal graph projection. Existing failed CronJob history may remain
visible. The electronic-importer path repair is a separate application change;
storage recovery alone does not resolve that failure.

## Evidence and accounting

Keep original apply/check/repeat logs and capacity/database readbacks privately
under the active BrownRook Jira story artifact index. Human work duration remains
pending unless Paul supplies a supported duration. Machine execution is not
human labour. Backups, retention expiry and database growth/compaction require
separate review; the graph's historical store size is not a receipt count.
