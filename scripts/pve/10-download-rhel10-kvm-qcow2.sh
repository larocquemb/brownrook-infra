#!/usr/bin/env bash
set -euo pipefail

: "${RHEL_QCOW2:?set RHEL_QCOW2}"
: "${RHEL_URL:?set RHEL_URL (signed Red Hat URL)}"

mkdir -p "$(dirname "$RHEL_QCOW2")"
wget -O "$RHEL_QCOW2" "$RHEL_URL"
qemu-img info "$RHEL_QCOW2"
