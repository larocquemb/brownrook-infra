# Optional Red Hat vLLM on Arsene

`ansible/playbooks/vllm.yml` provisions an **on-demand** system service,
`brownrook-vllm.service`. Applying the playbook does not start the model and
does not stop Ollama. The service is intentionally disabled at boot.

The configured runtime is the pinned Red Hat AI Inference 3.5 image and the
cached `RedHatAI/Qwen3.8-27B-INT4` revision recorded in the role defaults. The
whole Hugging Face hub is mounted read-only because cache blobs are linked
outside individual model directories. The playbook checks the image is already
in Paul's rootless Podman store and checks the pinned model's configuration;
it does not pull an image, download weights or store registry credentials.
It uses the currently active `/run/user/<uid>` and does not enable user linger.
A logged-in user session, or separately managed linger, is required.

The service binds `192.168.2.201:18000`; its unauthenticated OpenAI-compatible
API is limited to the documented private networks by its own nftables table.
That network is a trust boundary. Do not expose the port publicly. A test
request and one short text response passed on the RTX 3090; image extraction,
accuracy and performance relative to Ollama are not yet established. The
3090 is not a Red Hat-supported accelerator for this inference product.

## Provision

From the infrastructure repository on the Mac:

```sh
ansible-playbook ansible/playbooks/vllm.yml --syntax-check
ansible-playbook ansible/playbooks/vllm.yml --ask-become-pass
```

Review `ansible/roles/vllm/defaults/main.yml` before changing the pinned image,
model or private networks. The firewall is installed with the dedicated
`vllm-access.service` and is required by vLLM. The firewall service is enabled
and activated by Ansible; no production service is restarted by provisioning.
If image or model checks fail, use `podman image ls` and `hf cache ls` as Paul;
a registry login or a model download may be needed. Do not put tokens in Git,
unit files, logs, or shell history.

## Switch GPU service

Production and development use the shared GPU Ollama service. The 27B model
requires most of the GPU. Starting vLLM deliberately stops `ollama.service`
through a systemd conflict, which interrupts Ollama inference and can affect
home-budget jobs. Stop or pause receipt processing first. Existing Jupyter or
other CUDA workloads are independent; the preflight requires at least 22,000
MiB free and rejects multiple or unavailable GPUs. This is a point-in-time
check, not a GPU reservation against other processes starting later.

On Arsene, when the GPU is available:

```sh
sudo systemctl start brownrook-vllm.service
sudo systemctl status brownrook-vllm.service --no-pager
journalctl -u brownrook-vllm.service -f
```

Wait for the application startup message. Use Ctrl+C to stop following logs,
then test from an approved host or from Arsene:

```sh
curl -fsS http://192.168.2.201:18000/v1/models
curl -fsS http://192.168.2.201:18000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"redhat-qwen","messages":[{"role":"user","content":"What is a receipt? Answer in one short sentence."}],"chat_template_kwargs":{"enable_thinking":false},"max_tokens":80,"temperature":0}'
```

The service exposes an OpenAI-compatible API; it does not automatically change
home-budget's provider or connect existing Ollama clients to vLLM. Never assume
an API health response proves image extraction quality or GPU exclusivity.

To restore Ollama after the test:

```sh
sudo systemctl stop brownrook-vllm.service
sudo systemctl start ollama.service
systemctl is-active ollama.service
curl -fsS http://127.0.0.1:11434/api/tags
```

If vLLM fails to start, systemd will already have stopped Ollama due to the
conflict; run the same restore commands. `journalctl -u brownrook-vllm.service`
shows startup errors. Reverting the Git change does not remove an installed
systemd unit; disable/stop the service and firewall separately if retiring it.
