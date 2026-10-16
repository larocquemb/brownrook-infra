#!/usr/bin/env bash
set -uo pipefail

context=${KUBECTL_CONTEXT:-brownrook-k3s1}
evidence_dir=${EVIDENCE_DIR:-evidence/kan-132}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
report="${evidence_dir}/${timestamp}-ha-validation.txt"
failures=0

mkdir -p "${evidence_dir}"
exec > >(tee "${report}") 2>&1

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

echo "KAN-132 HA validation ${timestamp}"
echo "Context: ${context}"

if ! kubectl --context "${context}" get nodes -o wide; then
  fail "Kubernetes API is unavailable"
  exit 1
fi

ready_servers=$(kubectl --context "${context}" get nodes \
  -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{range .items[?(@.status.conditions[?(@.type=="Ready")].status=="True")]}{.metadata.name}{"\n"}{end}' \
  | wc -l | tr -d ' ')
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

local_path_claims=$(kubectl --context "${context}" get pvc -A \
  -o jsonpath='{range .items[?(@.spec.storageClassName=="local-path")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')
[[ -z ${local_path_claims} ]] \
  && pass "no PVC uses local-path" \
  || fail "PVCs still use local-path: $(tr '\n' ' ' <<<"${local_path_claims}")"

if kubectl --context "${context}" -n longhorn-system get volumes.longhorn.io \
    -o jsonpath='{range .items[?(@.status.robustness!="healthy")]}{.metadata.name}{"="}{.status.robustness}{"\n"}{end}' \
    2>/dev/null | grep -q .; then
  fail "one or more Longhorn volumes are not healthy"
else
  pass "all reported Longhorn volumes are healthy"
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
