#!/usr/bin/env bash
set -uo pipefail

context=${KUBECTL_CONTEXT:-brownrook-k3s1}
expected_nodes=(k3s1 arsene longbow)
check_longhorn=false
failures=0

if [[ ${1:-} == --longhorn ]]; then
  check_longhorn=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--longhorn]" >&2
  exit 2
fi

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }
info() { printf 'INFO  %s\n' "$*"; }

if ! command -v kubectl >/dev/null; then
  fail "kubectl is not installed"
  exit 1
fi

if ! kubectl --context "${context}" version >/dev/null 2>&1; then
  fail "cannot reach Kubernetes context ${context}"
  exit 1
fi
pass "Kubernetes API is reachable through ${context}"

for node in "${expected_nodes[@]}"; do
  if ! kubectl --context "${context}" get node "${node}" >/dev/null 2>&1; then
    fail "expected node ${node} is absent"
    continue
  fi
  ready=$(kubectl --context "${context}" get node "${node}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  [[ ${ready} == True ]] && pass "${node} is Ready" || fail "${node} is not Ready"

  if kubectl --context "${context}" get node "${node}" \
      -o jsonpath='{.metadata.labels}' | grep -q 'node-role.kubernetes.io/control-plane'; then
    pass "${node} has the control-plane role"
  else
    fail "${node} is not a control-plane server"
  fi

  if kubectl --context "${context}" get node "${node}" \
      -o jsonpath='{.metadata.labels}' | grep -q 'node-role.kubernetes.io/etcd'; then
    pass "${node} has the etcd role"
  else
    fail "${node} is not an embedded-etcd member"
  fi
done

server_count=$(kubectl --context "${context}" get nodes \
  -l node-role.kubernetes.io/control-plane -o name | wc -l | tr -d ' ')
[[ ${server_count} == 3 ]] \
  && pass "exactly three control-plane servers are registered" \
  || fail "expected three control-plane servers; found ${server_count}"

local_path_claims=$(kubectl --context "${context}" get pvc -A \
  -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')
if [[ -n ${local_path_claims} ]]; then
  fail "PVCs still use local-path: $(tr '\n' ' ' <<<"${local_path_claims}")"
else
  pass "no PVC uses local-path"
fi

if ! ${check_longhorn}; then
  info "rerun with --longhorn after all hosts have dedicated storage and prerequisites"
else
  for node in "${expected_nodes[@]}"; do
    label=$(kubectl --context "${context}" get node "${node}" \
      -o jsonpath='{.metadata.labels.node\.longhorn\.io/create-default-disk}' 2>/dev/null)
    [[ ${label} == true ]] \
      && pass "${node} is explicitly enabled for a Longhorn default disk" \
      || fail "${node} lacks node.longhorn.io/create-default-disk=true"

    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${node}" \
      "sudo -n findmnt -n -o FSTYPE --target /var/lib/longhorn 2>/dev/null" \
      | grep -Eq '^(xfs|ext4)$'; then
      pass "${node} has XFS/ext4 mounted at /var/lib/longhorn"
    else
      fail "${node} lacks a verifiable XFS/ext4 Longhorn mount or non-interactive sudo"
    fi

    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${node}" \
      "sudo -n systemctl is-active iscsid 2>/dev/null" | grep -qx active; then
      pass "${node} has active iscsid"
    else
      fail "${node} does not have verifiably active iscsid"
    fi
  done
fi

if (( failures > 0 )); then
  printf '\n%d preflight check(s) failed. Do not proceed to a destructive gate.\n' "${failures}" >&2
  exit 1
fi

printf '\nAll requested preflight checks passed.\n'
