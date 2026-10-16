# Arsene Jupyter deployment from Git

This playbook adopts the working host deployment and adds a separate Python
3.15.0 GPU kernel. JupyterLab itself continues to use system Python 3.12.
The existing Python 3.12 PyTorch venv and kernelspec are retained.

## Desired state

- Arsene: `192.168.2.201`, user `paul`, notebooks in `/home/paul/notebooks`.
- Public hostname: `https://jupyter.idc.brownrook.com`.
- Backend: TCP 8888, accepted only from loopback and proxy `192.168.2.210`.
- Proxy: existing Nginx and wildcard TLS certificate, with WebSocket forwarding.
- DNS1: only the Jupyter hostname is overridden to the proxy LAN address.
- Public Route 53 CNAME: maintained in `brownrook-edge` and applied by its
  existing main-branch GitHub Actions workflow.
- `runtime/jupyter/server/uv.lock` locks all server dependencies.
- `runtime/jupyter/pytorch315/uv.lock` locks all GPU dependencies, including
  PyTorch 2.14.1 CUDA 13.0, torchvision 0.29.1 and compatible mpmath 1.3.0.
- Python 3.15.0 is installed by pinned uv 0.13.0 alongside the OS interpreter.
- Jupyter and new kernels inherit `OLLAMA_HOST` and `OLLAMA_BASE_URL` pointing
  to the managed Ollama service at `http://192.168.2.201:11436`. Set
  `jupyter_ollama_url` in the production group variables to change this endpoint.
  PyTorch execution is independent of these settings; code must explicitly
  call Ollama to use inference. Clients that hard-code an endpoint override them.

This is Git-managed Ansible infrastructure. CI validates pull requests; host
changes are applied by the operator after review. There is no automatic host
reconciliation timer or publicly hosted runner with LAN credentials. Argo CD
continues to manage Kubernetes only.

## Credentials and prerequisites

The controller needs Python >=3.12, Git, Ansible and SSH access to all three
hosts. Keep strict SSH host-key checking enabled. Verify new fingerprints
before adding known-host entries. Arsene requires sudo; proxy and DNS1 use
root SSH. Apply from a controller on the LAN or VPN.

The role requires the existing password hash at
`/home/paul/.jupyter/jupyter_server_config.json`. It verifies a nonempty
`IdentityProvider.hashed_password` (written by the password command) or
`PasswordIdentityProvider.hashed_password` with `no_log`, preserves the file,
and enforces mode 0600. Passwords, hashes, notebook contents, TLS private keys,
and SSH credentials are never stored in Git. Bootstrap or change a password
as `paul` with `~/venvs/jupyter/bin/jupyter server password`.

## Validate and apply

From the reviewed main-branch checkout on your Mac:

```bash
python3 -m venv /tmp/brownrook-ansible
/tmp/brownrook-ansible/bin/python -m pip install -r requirements-dev.txt
source /tmp/brownrook-ansible/bin/activate
ansible-playbook --syntax-check ansible/playbooks/jupyter.yml
ansible-playbook ansible/playbooks/jupyter.yml --list-hosts
ansible-playbook ansible/playbooks/jupyter.yml --ask-become-pass
```

After the initial adoption, `--check --ask-become-pass` previews configuration
changes but skips downloads, environment
synchronization, service probes and CUDA execution. An initial host missing
the password file fails preflight deliberately. Apply runs the plays in order:
Arsene, proxy, then DNS1. It replaces the manual service drop-ins with one
managed service retaining the verified Bash launch workaround. It changes
only the dedicated `jupyter_arsene` nftables table; it does not enable
Firewalld or modify K3s firewall tables.

Environment synchronization is exact. Add personal libraries to the manifest
and update the lockfile through a PR rather than installing them ad hoc in a
managed venv. The server restart briefly interrupts active kernels; apply
when notebooks are saved and kernels can be restarted. Notebook files are
never synchronized or deleted by the playbook.

## Verification

The playbook verifies a GET login redirect, rejection of unauthenticated
kernel API access, the HTTPS certificate and proxy route, internal DNS, and
actual CUDA matrix multiplication under Python 3.15. The GPU smoke test is
`scripts/jupyter/cuda_smoke.py`; CI has no GPU and does not claim to run it.

Refresh JupyterLab and choose **Arsene PyTorch — Python 3.15**. Run the smoke
script in that kernel. Test a notebook from cellular data to verify the public
DNS/NAT path and WebSocket execution, which LAN checks cannot prove.

After changing the Ollama endpoint, save notebooks before applying: the Jupyter
service restarts. Restart existing kernels so they inherit the new environment.
Verify inside the restarted kernel:

```python
import os
print(os.environ.get("OLLAMA_HOST"))
print(os.environ.get("OLLAMA_BASE_URL"))
```

Both should print the managed endpoint. These variables do not configure or
restart the Ollama server itself.

## Review an upgrade

```bash
uv lock --project runtime/jupyter/pytorch315 --upgrade-package PACKAGE
uv lock --check --project runtime/jupyter/pytorch315
python3 scripts/jupyter/validate_locks.py
```

Change direct version pins in `pyproject.toml` when upgrading a pinned
package. Review the lockfile diff, open a PR, merge after CI passes, then run
the Ansible playbook. Never regenerate lockfiles on hosts during deployment:
`uv sync --locked` fails if manifests and locks disagree. Updating the
interpreter requires changing `jupyter_gpu_python_version` and the GPU
project's `.python-version` together.

## Recovery

For notebook issues, switch back to **Arsene PyTorch** (Python 3.12). That
working venv and kernel are not managed or removed by this playbook.
For a managed environment rollback, revert its manifest and lockfile together
in Git, review and merge, then reapply. Service or proxy configuration rolls
back the same way. Host password files and notebooks remain outside Git.

## Internal Brownrook CA alias (KAN-135)

Both https://jupyter.idc.brownrook.com/ and
https://jupyter.idc.brownrook.net/ reach the same authenticated Jupyter service
and Python 3.15 GPU kernel. DNS1 resolves both names to the existing proxy VM.
The internal route accepts LAN 192.168.2.0/24 and VPN 10.6.0.0/24 clients;
the public route retains its existing Let's Encrypt wildcard certificate.

Reuse the existing Brownrook CA wildcard certificate covering
`*.idc.brownrook.net`. No new certificate or YubiKey signing is required.

The external files are:

- `~/brownrook-ca/leafs/k3ingress/k3ingress.fullchain.crt`
- `~/brownrook-ca/leafs/k3ingress/k3ingress.key`
- `~/brownrook-ca/root/root_ca.crt`

Set `BROWNROOK_PKI_DIR` to override the CA directory. Ansible verifies the
certificate chain, hostname and matching private key. The proxy stores its
copy under `/etc/nginx/tls/jupyter-arsene/` with root-only permissions.
Private keys remain outside Git.

For renewal, renew the existing wildcard through the established Brownrook CA
workflow and reapply the playbook to each consumer. Certificate changes reload
Nginx. The public route retains its separate Let's Encrypt certificate.

Install the Brownrook root CA in each LAN/VPN client's browser/OS trust store.
For a terminal-only check, without bypassing certificate validation:

```sh
curl --cacert ~/brownrook-ca/root/root_ca.crt -I https://jupyter.idc.brownrook.net/login
```

Verify both addresses from LAN and VPN: sign in, start the Arsene PyTorch kernel,
and run `scripts/jupyter/cuda_smoke.py` in a notebook. Kernel WebSocket access
requires an authenticated browser test; the playbook's redirect probes do not
prove it. Kernels execute on Arsene, not on the browser machine.

Jupyter inherits the development GPU Ollama endpoint on port 11436. Notebook
PyTorch CUDA operations and development Ollama share the RTX 3090 VRAM.
Avoid simultaneous large loads; unload an idle Ollama model using
`OLLAMA_HOST=http://192.168.2.201:11436 ollama stop MODEL` before a large CUDA
notebook experiment. Production CPU Ollama on 11434 does not use GPU memory.

## Arsene boot space

Ansible excludes Nouveau from future initramfs builds through
`/etc/dracut.conf.d/90-brownrook-no-nouveau.conf`. Arsene uses the NVIDIA
driver; Nouveau is already blacklisted in the kernel command line.
The tested kernel .66 image decreased from 179 MiB to 78 MiB and passed
reboot, NVIDIA detection, and Ollama/Jupyter service recovery checks.
This task does not rebuild existing images or restart services.
The .62 fallback and standalone rescue image remain unchanged.
