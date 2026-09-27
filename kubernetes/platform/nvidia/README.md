# NVIDIA GPU support for K3s

Arsène is the BrownRook K3s GPU worker.

## Node

- Host: `arsene`
- LAN address: `192.168.2.201`
- OS: Red Hat Enterprise Linux 10.2
- CPU capacity: 32 logical CPUs
- Memory capacity: ~96 GB
- GPU: NVIDIA GeForce RTX 3090, 24 GB VRAM
- K3s role: worker/agent
- Control plane: `k3s1` at `192.168.2.230`
- K3s: `v1.36.4+k3s1` on both k3s1 and Arsène
- containerd: `2.3.4-k3s1.36` on both nodes

## Host prerequisites

The NVIDIA driver and NVIDIA Container Toolkit must be installed on Arsène before K3s starts. K3s then discovers `/usr/bin/nvidia-container-runtime` and adds the `nvidia` runtime to its generated containerd configuration.

Validated host stack on 2026-09-27:

- NVIDIA driver: 615.71.09
- NVIDIA Container Toolkit: 1.20.1
- CUDA driver capability reported by `nvidia-smi`: 13.4
- PyTorch CUDA compute: validated
- Podman CDI GPU access: validated with privileged/root Podman

SELinux remains enforcing.

## K3s networking

K3s uses the Flannel VXLAN backend. Arsène's default RHEL firewalld configuration blocked VXLAN and forwarded pod-to-pod traffic. This caused CoreDNS timeouts, SMB CSI mount failures, and `No route to host` errors from Arsène workloads connecting to RabbitMQ on k3s1.

The BrownRook cluster currently runs K3s nodes without firewalld. On Arsène:

```bash
sudo systemctl disable --now firewalld
sudo systemctl restart k3s-agent
```

After the agent restart, validation from a pod scheduled on Arsène succeeded for both CoreDNS and RabbitMQ on k3s1.

Do not disable SELinux as part of this networking configuration.

## Kubernetes configuration

Apply the NVIDIA RuntimeClass:

```bash
kubectl apply -f kubernetes/platform/nvidia/runtimeclass.yaml
```

The NVIDIA device plugin must run with:

```yaml
runtimeClassName: nvidia
nodeSelector:
  nvidia.com/gpu.present: "true"
```

Label Arsène:

```bash
kubectl label node arsene nvidia.com/gpu.present=true
```

The device plugin is NVIDIA's `k8s-device-plugin`. The cluster was validated with v0.18.0. Keep the upstream manifest/version explicit when upgrading and preserve the RuntimeClass and node selector settings.

## Validation

Kubernetes must advertise one GPU:

```bash
kubectl describe node arsene | grep -A12 -E 'Capacity:|Allocatable:'
```

Expected resource:

```text
nvidia.com/gpu: 1
```

End-to-end GPU validation was completed with a CUDA 13.0.2 UBI9 pod scheduled specifically to Arsène with:

```yaml
runtimeClassName: nvidia
nodeSelector:
  kubernetes.io/hostname: arsene
resources:
  limits:
    nvidia.com/gpu: 1
```

Inside the pod, `nvidia-smi` successfully reported the RTX 3090 and 24576 MiB VRAM.

Cross-node networking was also validated from a BusyBox pod scheduled on Arsène:

```bash
nc -vz rabbitmq 5672
```

The RabbitMQ endpoint on k3s1 (`10.42.1.13:5672`) was reachable.

## Control-plane upgrade

On 2026-09-27, k3s1 was upgraded from `v1.34.5+k3s1` through `v1.35.8+k3s1` to `v1.36.4+k3s1`. A verified offline backup of `/var/lib/rancher/k3s/server` was taken before the upgrade.

Final state:

- k3s1: `v1.36.4+k3s1`, containerd `2.3.4-k3s1.36`
- arsene: `v1.36.4+k3s1`, containerd `2.3.4-k3s1.36`
- both nodes: `Ready`
