# Arsene Podman development backends (KAN-137)

Application Python and local Caddy/oauth2-proxy stay on each Mac. Dedicated
rootless PostgreSQL, RabbitMQ and Neo4j services run as brownrook-dev on Arsene.
No development database or broker shares production data, storage or credentials.
Podman is managed by systemd Quadlets, not Kubernetes. A native code edit does
not require a container rebuild or cluster deployment.

| Service | Arsene port | Container port | Limit |
| --- | --- | --- | --- |
| PostgreSQL | 15432 | 5432 | 2 GiB |
| AMQP | 15673 | 5672 | 1 GiB broker |
| RabbitMQ management | 15674 | 15672 | shared broker limit |
| Neo4j Bolt | 17687 | 7687 | 6 GiB |
| Neo4j Browser | 17474 | 7474 | shared Neo4j limit |

Only LAN 192.168.2.0/24 and VPN 10.6.0.0/24 are allowed. A dedicated nftables
table filters only these new ports, leaving production rules alone. The rootless
user manager depends on that host access service on boot. The account has no
SSH key and its password is locked. Services use a dedicated Podman network and
persistent named volumes under the account's home storage. Memory, swap and CPU
limits apply explicitly to containers as well as their service units.

## Provision

Generate credentials in home-budget-pipeline with ledger development credentials.
Keep the resulting .dev-backend/secrets.yml private and outside Git. Provisioning
defaults to `$HOME/Developer/home-budget-pipeline/.dev-backend/secrets.yml` on the
Mac running Ansible. Set `BROWNROOK_DEV_SECRETS_FILE` only to override that location;
the playbook fails if the selected file is missing. No production secret is reused.
Review and merge both repositories' KAN-137 changes before applying.

```sh
ansible-playbook --syntax-check ansible/playbooks/development-backends.yml
ansible-lint ansible/playbooks/development-backends.yml
ansible-playbook ansible/playbooks/development-backends.yml --check --diff --ask-become-pass
ansible-playbook ansible/playbooks/development-backends.yml --ask-become-pass
```

Initial check mode cannot simulate creation of a missing account/user manager;
apply only after reviewing syntax, rendering and target host. Secrets suppress
Ansible output. If the production-matching GHCR PostgreSQL image requires registry
login, authenticate the dedicated account with a read-only package credential
through the approved secret workflow, then retry; do not copy production tokens.

The prerequisite DNF transaction disables the `nvidia` plugin for that operation
only. Its stdout notices otherwise corrupt Ansible's JSON response, even when
all prerequisites are already installed. No global plugin settings, driver or
kernel packages are changed by this task.

PostgreSQL uses the production image (including its installed OIDC validator)
but development clients use separate SCRAM roles, not production Entra DB tokens.
Its first-volume initialization creates home_budget_dev and home_budget_test,
owned by matching non-superuser roles, denies PUBLIC database connections, and
sets home_budget.environment=development. Application schema bootstrap is a
separate explicit command from the current pipeline checkout. Init scripts and
POSTGRES_PASSWORD do not rotate existing database passwords. Preserve the private
credentials file; use a separately reviewed rotation procedure if it changes.
RabbitMQ definitions permit each role only its own development or test vhost.
Neo4j Community has a dedicated development instance; it is not shared with
production and is not a multi-database Enterprise installation.

## Inspect and validate

```sh
sudo systemctl --machine brownrook-dev@ --user status brownrook-dev-postgres brownrook-dev-rabbitmq brownrook-dev-neo4j
sudo -iu brownrook-dev podman ps
sudo journalctl --user-unit=brownrook-dev-postgres -n 50
```

Use the pipeline's `ledger development configure --apply` and
`ledger --env-file .env.dev development check` after
services are healthy. Test negative access between dev/test roles and vhosts,
repeat Ansible apply (changed=0 expected), restart services, and test an approved
host reboot. Verify the Mac's native web application through existing local
Colima HTTPS/Entra, including forged identity-header rejection. Record container
memory use, graph replay and UI results before closing KAN-137.

The application guide includes pgAdmin/psql profiles, schema bootstrap/reset and
representative graph replay. Work MacBook validation depends on actual device
policies and must be recorded; it is not assumed from M4 Pro results.

## Idempotence and restart acceptance

After provisioning, reconcile twice and then restart only the dedicated
`brownrook-dev-*` services, using one interactive sudo prompt:

```sh
ansible-playbook ansible/playbooks/development-backends.yml \
  ansible/playbooks/development-backends.yml \
  ansible/playbooks/validate-development-backends.yml --ask-become-pass
```

The second provisioning pass should report no unintended changes. The validation
playbook checks all container health statuses, restarts the three dedicated
user services, then waits for healthy status again. It never restarts K3s,
production services, or the host. Check database identities, receipt/category
counts and graph snapshot counts from the Mac afterward to verify persistence.
A host reboot remains a separate check requiring an approved maintenance window.

## Backup, restore and rollback

Use pg_dump/pg_restore for the development databases and preserve role/marker
initialization. Export broker definitions and back up its named volume if queued
development messages need retention. Stop Neo4j cleanly before a volume backup;
its graph can be rebuilt only while authoritative evidence is retained. Test
restore to separate development volumes. Container image rollback does not safely
downgrade a PostgreSQL data directory across major versions.

Stop only brownrook-dev-* user services and preserve their named volumes and
private configuration. Restore the Mac's .env.dev.before-arsene backup only if
intentionally returning to the old native databases; local HTTPS authentication
continues unchanged. Do not delete rootless storage, production PVCs or unrelated
containers. Reverting Git alone does not remove previously applied services.
