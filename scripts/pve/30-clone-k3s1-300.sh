#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00-vars"

qm destroy "$K3S1_VMID" --purge 1 --destroy-unreferenced-disks 1 2>/dev/null || true

qm clone "$TEMPLATE_VMID" "$K3S1_VMID" --name k3s1.brownrook.net --full 1

# Resources
qm set "$K3S1_VMID" --memory 8192 --cores 4 --cpu host

# Resize disk (optional)
qm resize "$K3S1_VMID" scsi0 40G

# Static IP + DNS (Proxmox cloud-init network-config)
qm set "$K3S1_VMID" --ipconfig0 "ip=${K3S1_IP},gw=${K3S1_GW}"

# Attach custom user-data snippet
qm set "$K3S1_VMID" --cicustom "user=${STORAGE_SNIPPETS}:snippets/300-userdata.yaml"

qm cloudinit update "$K3S1_VMID"
qm start "$K3S1_VMID"
