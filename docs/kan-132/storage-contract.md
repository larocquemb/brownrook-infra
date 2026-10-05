# Portable storage and object-data contract

## Data placement

| Data | System of record | K3s implementation | EKS implementation |
| --- | --- | --- | --- |
| Receipt metadata, extracted fields, classifications, users, and relationships | PostgreSQL | `brownrook-block-rwo` on Longhorn | `brownrook-block-rwo` mapped to EBS CSI |
| Original receipt images and PDFs | S3-compatible object API | Independent S3-compatible endpoint | Amazon S3 |
| Derived images and binary OCR artifacts | S3-compatible object API | Independent S3-compatible endpoint | Amazon S3 |
| Shared POSIX files, only where an application truly requires them | RWX PVC | `brownrook-files-rwx` on Longhorn share manager or external NFS | `brownrook-files-rwx` mapped to EFS CSI |
| PostgreSQL backups and WAL archives | Off-cluster object storage | S3-compatible backup bucket | Amazon S3 |
| Longhorn-native volume backups | Off-cluster object storage | Longhorn S3 backup target | Used only to restore a Longhorn cluster, not EBS |
| K3s etcd snapshots and recovery metadata | Off-cluster object storage | K3s S3 snapshot support | Not restored to EKS; EKS manages its control plane |
| K3s server token | Approved secret store | Separate from snapshots | Not used by EKS |

Longhorn is replicated block storage, not object storage. An in-cluster MinIO
instance backed only by Longhorn may provide an S3 API, but it does not satisfy
off-cluster backup or site-disaster-recovery requirements.

## Canon scan-to-folder ingress

The Canon printer may continue to scan to SMB. Use a dedicated subdirectory
such as:

```text
\\pve\files\brownrook\home-budget\scan-inbox
```

This folder is a bounded ingress queue. It is not the authoritative receipt
archive and does not replace object storage. Configure a dedicated printer
account with write/create permission only to the inbox; do not give the printer
database, Kubernetes, backup-bucket, or general file-share credentials.

The receipt importer must:

1. Ignore files that are still changing. Require a stable size/mtime interval
   or an atomic rename from a temporary name before ingestion.
2. Compute a content checksum and claim the file idempotently so multiple
   workers cannot create duplicate receipts.
3. Upload the original bytes to object storage using the immutable receipt key
   scheme below.
4. Read the stored object metadata or bytes back sufficiently to verify size
   and checksum.
5. Commit the PostgreSQL receipt metadata and object reference.
6. Only after both object and database commits succeed, move the source file to
   a short-retention `processed` directory or remove it according to policy.
7. Move partial, unsupported, corrupt, or repeatedly failing files to a
   `quarantine` directory and alert without deleting the source.

Because PVE/SMB is a local failure domain, an SMB outage may temporarily stop
new scans. It must not make already ingested receipts unavailable. Monitor
inbox age, importer failures, quarantine count, and free space.

## Receipt object model

Applications store receipt binaries with immutable, non-identifying object
keys. A recommended form is:

```text
receipts/<tenant-id>/<yyyy>/<mm>/<receipt-uuid>/original.<extension>
receipts/<tenant-id>/<yyyy>/<mm>/<receipt-uuid>/normalized.<extension>
receipts/<tenant-id>/<yyyy>/<mm>/<receipt-uuid>/ocr/<artifact-name>
```

PostgreSQL stores the receipt UUID, bucket or logical store, object key,
content type, byte length, checksum, object version identifier, creation time,
and processing state. The database must not store long-lived presigned URLs.

Minimum application configuration contract:

```text
OBJECT_STORE_ENDPOINT
OBJECT_STORE_REGION
OBJECT_STORE_RECEIPTS_BUCKET
OBJECT_STORE_RECEIPTS_PREFIX
OBJECT_STORE_PATH_STYLE
OBJECT_STORE_ACCESS_KEY_ID       # injected from a Secret
OBJECT_STORE_SECRET_ACCESS_KEY   # injected from a Secret
SCAN_INBOX_PATH
SCAN_PROCESSED_PATH
SCAN_QUARANTINE_PATH
```

Use workload identity instead of static access keys on EKS. Local credentials
must be injected from a secret manager and must never be committed to Git.

## Protection requirements

- Require TLS, server-side encryption, bucket versioning, and blocked public
  access.
- Grant the receipt application access only to its bucket and prefix.
- Use a different principal and prefix for backups.
- Record a checksum when each receipt object is written and verify it during
  restore exercises.
- Treat deletion as a controlled business operation. Lifecycle rules must not
  delete a source receipt before the corresponding retention requirement ends.
- Replicate required receipt and backup objects to a destination that remains
  reachable when the Brown Rook site and K3s cluster are unavailable.

## Initial recovery objectives

These are starting targets and must be replaced by measured drill evidence:

| Workload/data | RPO | RTO |
| --- | --- | --- |
| Receipt objects and PostgreSQL | 15 minutes | 4 hours |
| K3s control plane | 6 hours | 2 hours |
| GitOps-managed stateless services | Git commit | 1 hour |

Meeting the PostgreSQL RPO requires continuous WAL archiving or an equivalent
database-native mechanism. Longhorn snapshots alone are not a database backup.
