# Proxmox kernel logs in Grafana

Native Alloy on PVE forwards only `_TRANSPORT=kernel` entries from the systemd
journal to the existing Loki service over Brownrook mTLS. This includes NIC,
PCIe, link-state, and kernel errors at all severity levels. Prometheus metrics
remain separate. Local journals remain intact and PVE already retains previous
boots. No journal retention, Proxmox network, VM, or firewall settings are changed.

Configuration is reviewed in Git and applied with Ansible. Signed certificates
and private keys stay outside Git. The role reuses the existing alloy-loki-client
identity; a dedicated client identity can be supplied through source variables.
No CA signing is automated. The Alloy release matches monitoring's observed
Debian package version 1.20.1-1.

From the reviewed repository on a LAN/VPN controller with root SSH access to PVE:

```sh
export BROWNROOK_PKI_DIR="$HOME/brownrook-ca"
ansible-playbook --syntax-check ansible/playbooks/pve-kernel-logs.yml
ansible-playbook ansible/playbooks/pve-kernel-logs.yml
```

An initial check-mode run cannot validate files/users from a not-yet-installed
package; use syntax/lint for initial preflight, then `--check` after the first
apply. The playbook verifies kernel journal access as alloy, Loki mTLS readiness,
and collector readiness. A ready collector alone does not prove Loki ingestion.

In Grafana Explore select Loki and query:

```logql
{host="pve", service="kernel"} | json | line_format "{{.MESSAGE}}"
```

For hardware diagnostics:

```logql
{host="pve", service="kernel"} | json | MESSAGE =~ "(?i).*(pcie|aer|link|nic|e1000|igc|r8169|enp).*"
```

Entries preserve the original JSON journal fields, including timestamps and boot
ID. Severity becomes a low-cardinality `level` label. Set Explore's time range
appropriately: first startup reads retained entries from up to seven days (168 hours) ago.
Existing NIC outage logs can be recovered if still present in the local journal
and accepted by Loki's retention/ingestion policy.

Alloy keeps its journal cursor and write-ahead state under /var/lib/alloy. This
supports retries when Loki is unreachable, but cannot guarantee delivery after
power loss, journal rotation, exhausted storage, or prolonged outages. No fake
kernel test event is injected. Compare a real retained kernel message/timestamp
with the Loki query, then check new kernel entries when they occur.

On PVE:

```sh
systemctl is-active alloy
journalctl -u alloy -n 50 --no-pager
journalctl -k -b -1 --no-pager
curl --fail http://127.0.0.1:12345/-/ready
```

To roll back, disable the collector with `systemctl disable --now alloy`, revert
its Git configuration, and remove only its pve-kernel.conf override/configuration
once forwarding is no longer required. Retain /var/lib/alloy for recovery and
never delete PVE journal files. Do not run unrelated monitoring reconciliation
against PVE; this playbook owns only the kernel collector.


## Seven-day backfill

`pve_kernel_logs_max_age: 168h` requests up to the last seven days on initial
startup. It does not reconstruct missing/rotated journal files or override Loki
age rejection and out-of-order limits. A persisted journal cursor controls
subsequent restarts; changing max_age does not rewind an already-established
cursor. Configure the requested window before the first apply. Set Grafana
Explore to Last 7 days and verify the earliest available timestamps.

The source backfill window is separate from local journal retention and Loki
retention. The role preserves existing retention settings. If older entries
were already deleted, they cannot be recovered by installing a collector.


Loki delivery uses monitoring's fixed LAN IP 192.168.2.202 while TLS SNI and
certificate verification still require monitoring.idc.brownrook.net. No insecure
TLS bypass is used, and delivery does not require DNS1 to be available. The
readiness check uses the same hostname/IP mapping and mTLS identity.

The observed Loki configuration retains logs for two weeks and rejects entries
older than one week. The seven-day startup window fits that policy; entries near
the age boundary can still expire before delivery. There is no retention change
in this PR.


If Loki returns HTTP 503 while its ingesters become ready, the mTLS preflight
retries for about 40 seconds. Persistent errors still fail before collector
activation. Rerunning after an interrupted initial install accepts the inactive,
unmodified package-default configuration, verified against dpkg's conffile
checksum. A custom configuration or active unrelated collector is not adopted.
