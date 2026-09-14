# K3s node monitoring

KAN-93 manages host monitoring for `k3s1.brownrook.net` as reviewed infrastructure code. The exporter, its service
account, systemd unit, and firewall policy run on the RHEL host outside K3s. Prometheus and Grafana remain on the
dedicated monitoring host at `192.168.2.202`.

## Managed resources

- node_exporter `1.12.1`, verified with the upstream Linux amd64 SHA-256 digest before extraction
- the unprivileged `node_exporter` service account and hardened `node_exporter.service`
- a dedicated nftables table that accepts TCP 9100 only on loopback and from `192.168.2.202`
- the complete Prometheus configuration at `/etc/prometheus/prometheus.yml`
- the Grafana file provider and **K3s Node** dashboard

The role does not enable the host-wide `nftables.service` or alter K3s-generated tables. A small oneshot systemd unit
owns only the `inet brownrook_node_exporter` table, preventing an nftables reload from flushing Kubernetes rules.

## Prerequisites

- SSH key access as `paul` to `k3s1.brownrook.net` and `192.168.2.202`
- sudo access on both hosts; provide the become password interactively
- Prometheus and Grafana installed and running on the monitoring host
- Ansible installed locally (`python -m pip install --requirement requirements-dev.txt` is sufficient)

Do not put sudo passwords, SSH private keys, Grafana credentials, or tokens in inventory. Ansible prompts for the sudo
password and uses the operator's SSH agent or standard SSH configuration.

## Review and deploy

From the repository root, first review the pending changes:

```sh
ansible-playbook ansible/playbooks/site.yml --check --diff --ask-become-pass
```

Deploy both hosts in dependency order:

```sh
ansible-playbook ansible/playbooks/site.yml --diff --ask-become-pass
```

The monitoring role owns the complete Prometheus configuration. Merge intentional monitoring-host changes into
`monitoring/prometheus/prometheus.yml` before applying; Ansible also asks Prometheus's installed `promtool` to validate
the temporary file and creates a backup before replacement.

Run the deployment command a second time. The play recap must report `changed=0` for both hosts; any changes on the
second run should be investigated as an idempotence defect.

## Verify

On `k3s1`:

```sh
sudo systemctl is-active node_exporter brownrook-node-exporter-firewall
sudo systemctl is-enabled node_exporter brownrook-node-exporter-firewall
sudo nft list table inet brownrook_node_exporter
curl --fail --silent http://127.0.0.1:9100/metrics | grep node_uname_info
```

From the monitoring host:

```sh
curl --fail --silent http://k3s1.brownrook.net:9100/metrics | grep node_uname_info
curl --get --silent http://127.0.0.1:9090/api/v1/query \
  --data-urlencode 'query=up{instance="k3s1.brownrook.net:9100"}'
curl --get --silent http://127.0.0.1:9090/api/v1/query \
  --data-urlencode 'query=node_uname_info{instance="k3s1.brownrook.net:9100"}'
```

The first Prometheus query must return `1`; the second must include the k3s1 hostname. In Grafana, open the **Brown
Rook / K3s Node** dashboard and confirm CPU, memory, filesystem, load, disk, and network panels contain data.

From a host other than `192.168.2.202`, a connection to `k3s1.brownrook.net:9100` must time out. The nftables counter
on the drop rule can be inspected if troubleshooting is necessary.

## Upgrade or roll back node_exporter

Change `node_exporter_version` and `node_exporter_sha256` together in
`ansible/roles/node_exporter/defaults/main.yml`, review the upstream release digest, and run the site playbook. Each
release lives in a versioned directory under `/opt/node_exporter`; the stable symlink changes atomically.

To roll back, restore the previous version and digest in Git and run the playbook again. Previously extracted versions
are retained specifically to make this operation independent of a fresh download.

## Remove K3s node monitoring

The removal playbook first removes the Prometheus target and Grafana dashboard, then stops the exporter and deletes its
dedicated firewall table, systemd units, service account, cached archive, and installed versions:

```sh
ansible-playbook ansible/playbooks/remove-node-monitoring.yml --diff --ask-become-pass
```

This does not uninstall the shared `nftables`, Prometheus, or Grafana packages and does not change other Prometheus
targets. Running the removal playbook again is safe and should report no changes.
