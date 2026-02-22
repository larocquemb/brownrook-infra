#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00-vars"

qm destroy "$TEMPLATE_VMID" --purge 1 --destroy-unreferenced-disks 1 2>/dev/null || true

qm create "$TEMPLATE_VMID" \
  --name rhel10-cloud-template \
  --memory 8192 --cores 2 --cpu host \
  --machine q35 --bios ovmf \
  --net0 virtio,bridge=vmbr0 \
  --agent enabled=1 \
  --serial0 socket --vga serial0 \
  --scsihw virtio-scsi-single

# EFI disk
qm set "$TEMPLATE_VMID" --efidisk0 "$STORAGE_LVMTHIN:0,efitype=4m,pre-enrolled-keys=1"

# Import qcow2 to scsi0
qm importdisk "$TEMPLATE_VMID" "$RHEL_QCOW2" "$STORAGE_LVMTHIN"
# Proxmox creates unused0 with the imported disk; attach it
qm set "$TEMPLATE_VMID" --scsi0 "$STORAGE_LVMTHIN:vm-${TEMPLATE_VMID}-disk-0,discard=on,iothread=1"
qm set "$TEMPLATE_VMID" --boot order=scsi0

# Cloud-init drive
qm set "$TEMPLATE_VMID" --ide2 "$STORAGE_LVMTHIN:cloudinit"

# Convert to template
qm template "$TEMPLATE_VMID"

echo "Template $TEMPLATE_VMID ready."
