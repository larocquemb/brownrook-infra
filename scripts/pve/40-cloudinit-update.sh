#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00-vars"

qm stop "$K3S1_VMID" || true
qm cloudinit update "$K3S1_VMID"
qm start "$K3S1_VMID"

qm cloudinit dump "$K3S1_VMID" user | sed -n '1,140p'
qm cloudinit dump "$K3S1_VMID" network
