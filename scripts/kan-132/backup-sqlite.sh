#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root on the active K3s SQLite server." >&2
  exit 1
fi

data_dir=${K3S_DATA_DIR:-/build/k3s}
source_db="${data_dir}/server/db/state.db"
source_token="${data_dir}/server/token"
backup_root=${BACKUP_ROOT:-/var/backups/k3s}
source_config=${K3S_CONFIG_FILE:-/etc/rancher/k3s/config.yaml}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)


for required in "${source_db}" "${source_token}" "${source_config}"; do
  if [[ ! -r ${required} ]]; then
    echo "Required file is not readable: ${required}" >&2
    exit 1
  fi
done

# Do not create an etcd snapshot as a probe or back up a stale SQLite file
# after conversion. Configuration and a member directory are conservative gates.
if [[ -d "${data_dir}/server/db/etcd/member" ]] ||
   grep -Eq '^[[:space:]]*(datastore-endpoint[[:space:]]*:|cluster-init[[:space:]]*:[[:space:]]*true)' "${source_config}"; then
  echo "External/embedded-etcd configuration found; use its native backup procedure." >&2
  exit 1
fi

install -d -m 0700 "${backup_root}"
destination=$(mktemp -d "${backup_root}/pre-etcd-${timestamp}-XXXXXX")
install -d -m 0700 "${destination}/datastore" "${destination}/secret"

SOURCE_DB=${source_db} DEST_DB="${destination}/datastore/state.db" python3 - <<'PY'
import os
import sqlite3

from pathlib import Path
source = sqlite3.connect(Path(os.environ["SOURCE_DB"]).resolve().as_uri() + "?mode=ro", uri=True)
destination = sqlite3.connect(os.environ["DEST_DB"])
with destination:
    source.backup(destination)
result = destination.execute("PRAGMA quick_check").fetchone()[0]
source.close()
destination.close()
if result != "ok":
    raise SystemExit(f"SQLite quick_check failed: {result}")
PY

install -m 0600 "${source_config}" "${destination}/datastore/config.yaml"
install -m 0600 "${source_token}" "${destination}/secret/server-token"

cat >"${destination}/README.txt" <<EOF
KAN-132 pre-conversion K3s SQLite backup created ${timestamp}.

datastore/state.db is a consistent SQLite backup verified with PRAGMA quick_check.
secret/server-token is required to decrypt confidential datastore content.

Protect both directories, store the token separately in the approved secret
store, treat the database/configuration as confidential (they can contain Kubernetes
credentials), copy the database off this host using encrypted transport, and verify
SHA256SUMS after transfer. Never commit this directory to Git.
EOF

(
  cd "${destination}"
  sha256sum README.txt datastore/config.yaml datastore/state.db secret/server-token >SHA256SUMS
)
chmod 0600 "${destination}/SHA256SUMS" "${destination}/README.txt"

echo "Created and verified ${destination}"
echo "Next: copy the restricted datastore backup off-node and store secret/server-token separately."
