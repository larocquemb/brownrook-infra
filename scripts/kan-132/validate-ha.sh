#!/usr/bin/env bash
set -uo pipefail
umask 077

context=${KUBECTL_CONTEXT:-brownrook-k3s1}
evidence_dir=${EVIDENCE_DIR:-.validation/kan-132}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
failures=0

mkdir -p "${evidence_dir}"
report=$(mktemp "${evidence_dir}/${timestamp}-ha-validation.XXXXXX")
exec > >(tee "${report}") 2>&1

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

echo "KAN-132 HA validation ${timestamp}"
echo "Context: ${context}"

if ! kubectl --context "${context}" get nodes -o wide; then
  fail "Kubernetes API is unavailable"
  exit 1
fi

if nodes_json=$(kubectl --context "${context}" get nodes -l node-role.kubernetes.io/control-plane -o json); then
  ready_servers=$(python3 -c 'import json,sys; print(sum(any(c.get("type")=="Ready" and c.get("status")=="True" for c in n.get("status",{}).get("conditions",[])) for n in json.load(sys.stdin)["items"]))' <<<"${nodes_json}")
else
  ready_servers=0
  fail "cannot inspect control-plane readiness"
fi
[[ ${ready_servers} -ge 2 ]] \
  && pass "at least two control-plane servers are Ready (${ready_servers})" \
  || fail "fewer than two control-plane servers are Ready (${ready_servers})"

etcd_members=$(kubectl --context "${context}" get nodes \
  -l node-role.kubernetes.io/etcd -o name | wc -l | tr -d ' ')
[[ ${etcd_members} == 3 ]] \
  && pass "three embedded-etcd members are registered" \
  || fail "expected three embedded-etcd members; found ${etcd_members}"

if kubectl --context "${context}" get storageclass brownrook-block-rwo \
    -o jsonpath='{.provisioner}' 2>/dev/null | grep -qx driver.longhorn.io; then
  pass "portable RWO StorageClass uses Longhorn"
else
  fail "brownrook-block-rwo is absent or not backed by Longhorn"
fi

if local_path_claims=$(kubectl --context "${context}" get pvc -A \
  -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); then
  if [[ -z ${local_path_claims} ]]; then
    pass "no PVC uses local-path"
  else
    fail "PVCs still use local-path: $(tr '\n' ' ' <<<"${local_path_claims}")"
  fi
else
  fail "cannot inspect PVCs; storage migration is unverified"
fi

if volumes_json=$(kubectl --context "${context}" -n longhorn-system get volumes.longhorn.io -o json); then
  if python3 -c 'import json,sys; v=json.load(sys.stdin)["items"]; sys.exit(0 if v and all(x.get("status",{}).get("robustness")=="healthy" for x in v) else 1)' <<<"${volumes_json}"; then
    pass "reported Longhorn volumes exist and are healthy"
  else
    fail "Longhorn volumes are absent, unhealthy, or unreadable"
  fi
else
  fail "cannot inspect Longhorn volumes; resilience is unverified"
fi

coredns_available=$(kubectl --context "${context}" -n kube-system get deployment coredns \
  -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
[[ ${coredns_available:-0} -ge 2 ]] \
  && pass "CoreDNS has at least two available replicas" \
  || fail "CoreDNS has fewer than two available replicas"

if kubectl --context "${context}" get etcdsnapshotfile \
    -o jsonpath='{range .items[?(@.spec.location)]}{.spec.location}{"\n"}{end}' 2>/dev/null \
    | grep -q '^s3://'; then
  pass "at least one S3 etcd snapshot is registered"
else
  fail "no S3 etcd snapshot is registered"
fi

kubectl --context "${context}" get pods -A \
  --field-selector=status.phase!=Running,status.phase!=Succeeded -o wide || true

if (( failures > 0 )); then
  echo "RESULT: FAIL (${failures} check(s)); evidence: ${report}"
  exit 1
fi

echo "RESULT: PASS; evidence: ${report}"
