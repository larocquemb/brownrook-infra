#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root on the active K3s SQLite server." >&2
  exit 1
fi

data_dir=${K3S_DATA_DIR:-/build/k3s}
source_db="${data_dir}/server/db/state.db"
source_token="${data_dir}/server/token"
backup_root=${BACKUP_ROOT:-/var/backups/k3s}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
destination="${backup_root}/pre-etcd-${timestamp}"

for required in "${source_db}" "${source_token}" /etc/rancher/k3s/config.yaml; do
  if [[ ! -r ${required} ]]; then
    echo "Required file is not readable: ${required}" >&2
    exit 1
  fi
done

if k3s etcd-snapshot save --name kan-132-probe >/dev/null 2>&1; then
  echo "Embedded etcd is active; use k3s etcd-snapshot instead of this SQLite backup." >&2
  exit 1
fi

install -d -m 0700 "${destination}/public" "${destination}/secret"

SOURCE_DB=${source_db} DEST_DB="${destination}/public/state.db" python3 - <<'PY'
import os
import sqlite3

source = sqlite3.connect(f"file:{os.environ['SOURCE_DB']}?mode=ro", uri=True)
destination = sqlite3.connect(os.environ["DEST_DB"])
with destination:
    source.backup(destination)
result = destination.execute("PRAGMA quick_check").fetchone()[0]
source.close()
destination.close()
if result != "ok":
    raise SystemExit(f"SQLite quick_check failed: {result}")
PY

install -m 0600 /etc/rancher/k3s/config.yaml "${destination}/public/config.yaml"
install -m 0600 "${source_token}" "${destination}/secret/server-token"

cat >"${destination}/README.txt" <<EOF
KAN-132 pre-conversion K3s SQLite backup created ${timestamp}.

public/state.db is a consistent SQLite backup verified with PRAGMA quick_check.
secret/server-token is required to decrypt confidential datastore content.

Protect both directories, store the token separately in the approved secret
store, copy the database off this host using encrypted transport, and verify
SHA256SUMS after transfer. Never commit this directory to Git.
EOF

(
  cd "${destination}"
  sha256sum README.txt public/config.yaml public/state.db secret/server-token >SHA256SUMS
)
chmod 0600 "${destination}/SHA256SUMS" "${destination}/README.txt"

echo "Created and verified ${destination}"
echo "Next: copy the public backup off-node and store secret/server-token separately."
