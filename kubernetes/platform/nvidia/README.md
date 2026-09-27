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

## Host prerequisites

The NVIDIA driver and NVIDIA Container Toolkit must be installed on Arsène before K3s starts. K3s then discovers `/usr/bin/nvidia-container-runtime` and adds the `nvidia` runtime to its generated containerd configuration.

Validated host stack on 2026-09-27:

- NVIDIA driver: 615.71.09
- NVIDIA Container Toolkit: 1.20.1
- CUDA driver capability reported by `nvidia-smi`: 13.4
- PyTorch CUDA compute: validated
- Podman CDI GPU access: validated with privileged/root Podman

Do not disable SELinux to support GPU containers.

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

End-to-end validation was completed with a CUDA 13.0.2 UBI9 pod scheduled specifically to Arsène with:

```yaml
runtimeClassName: nvidia
nodeSelector:
  kubernetes.io/hostname: arsene
resources:
  limits:
    nvidia.com/gpu: 1
```

Inside the pod, `nvidia-smi` successfully reported the RTX 3090 and 24576 MiB VRAM.

## Operational note

As of 2026-09-27, Arsène is running K3s v1.36.4+k3s1 while k3s1 is running v1.34.5+k3s1. Align K3s versions as a separate maintenance action.
