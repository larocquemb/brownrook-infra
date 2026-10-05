# Current-state audit

Audit date: 2026-09-28

## Cluster

| Node | Address | Current role | Failure domain |
| --- | --- | --- | --- |
| `k3s1` | `192.168.2.230` | K3s server/control plane | PVE VM and its underlying PVE/ZFS host |
| `arsene` | `192.168.2.201` | K3s agent | Physical MSI host |
| `longbow` | `192.168.2.175` | Not joined | Physical MSI host |

The running K3s version is `v1.36.4+k3s1` on `k3s1` and `arsene`. The active
datastore is SQLite at `/build/k3s/server/db/state.db`; the presence of an
`etcd` directory alone is not evidence that embedded etcd is active. `k3s
etcd-snapshot save` currently reports that the etcd datastore is disabled.

Consequences:

- `k3s1` is a control-plane and datastore single point of failure.
- There is no two-of-three etcd quorum.
- A consistent SQLite backup and the original server token are required before
  conversion to embedded etcd.
- `arsene` must be changed from an agent to a server, and `longbow` must join as
  the third server.

## Persistent data

The only dynamic StorageClass is the default `local-path` provisioner. It has
`Delete` reclaim policy and `WaitForFirstConsumer` binding. The observed
production claims are:

| Claim | Size/access | Current backing | Risk |
| --- | --- | --- | --- |
| `home-budget/postgres18-data` | 10 GiB RWO | `local-path` on `k3s1` | PostgreSQL unavailable if `k3s1` fails |
| `home-budget/postgres-data-postgres-0` | 10 GiB RWO | `local-path` on `k3s1` | Older PostgreSQL claim; ownership/use must be confirmed before cleanup |
| `home-budget/rabbitmq-data-rabbitmq-0` | 8 GiB RWO | `local-path` on `k3s1` | RabbitMQ unavailable if `k3s1` fails |
| `home-budget/otel-collector-storage` | 2 GiB RWO | `local-path` on `k3s1` | Telemetry state unavailable if `k3s1` fails |
| `home-budget/home-budget-data` | 100 GiB RWX | PVE SMB `//pve/files`, `brownrook/home-budget` | PVE, SMB service, and zpool remain one failure domain |

The 100 GiB claim currently holds shared receipt files through SMB. The target
design retains a restricted SMB scan inbox for the Canon printer, but moves the
authoritative receipt binaries behind the object-storage contract and keeps
relational metadata and object keys in PostgreSQL. The inbox is an edge intake
queue rather than durable application storage.

## Capacity and prerequisite gaps

- `k3s1` has only about 7.7 GiB free on `/build`; this is not sufficient for
  three-replica migration of the existing production volumes.
- A dedicated PVE-backed virtual disk must be attached to `k3s1`, formatted
  XFS or ext4 inside the guest, and mounted at `/var/lib/longhorn`.
- Equivalent dedicated, persistent Longhorn capacity is required on `arsene`
  and `longbow`.
- Longhorn V1 uses sparse files and requires an extent-based filesystem such
  as XFS or ext4. A ZFS dataset is not the Longhorn filesystem data path. The
  PVE zpool may back the virtual disk presented to `k3s1`.
- `open-iscsi`/`iscsiadm` must be installed and active on every storage node;
  NFS client support is also required for Longhorn RWX volumes.
- Passwordless non-interactive root access is not currently available on
  `arsene` or `longbow`. Host preparation therefore needs an interactive sudo
  run or a tightly scoped temporary automation policy.
- A stable, redundant API endpoint such as `k3s-api.brownrook.net` needs an
  approved VIP/load-balancer address before server conversion.

## Current conclusion

Do not run a node-failure exercise yet. Losing `k3s1` currently loses both the
control plane and production `local-path` state. Complete the backup, quorum,
storage, and restore gates first.
