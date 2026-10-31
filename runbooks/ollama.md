# Shared GPU Ollama on Arsene

The Ollama role owns one shared GPU-backed `ollama.service` on the default
port 11434. It binds IPv4 interfaces because private LAN and Kubernetes clients
need the service as well as local command-line clients. The dedicated nftables
table restricts port 11434 and telemetry port 11435 to loopback and approved
sources. Ollama has no authentication; keep these network restrictions active.

The service uses `/home/ollama/models`, with one loaded model and one parallel
request. Production and development share the runner and may queue. Jupyter and
other CUDA programs also share GPU memory. The older CPU-only service and
`ollama-development.service` are retired; the playbook stops and removes the
latter during cutover. Do not apply the obsolete home-budget Ollama role.

On the Mac, provide the existing private monitoring certificate path and run:

```sh
cd /Users/paul/Developer/brownrook/brownrook-infra
set -a
source /Users/paul/Developer/home-budget-pipeline/.env.monitoring
set +a
ansible-playbook ansible/playbooks/ollama.yml --ask-become-pass
```

Cutover interrupts inference: coordinate production worker, Jupyter and local
client changes from port 11436 to 11434. On Arsene, remove any user shell
`OLLAMA_HOST` override still pointing to 11436. Verify the local default and
private LAN API, client endpoints, GPU placement, and `/metrics` on port 11435.
Do not delete model files. To roll back, restore a reviewed prior host and
client configuration together; a Git revert alone does not reconcile systemd.
