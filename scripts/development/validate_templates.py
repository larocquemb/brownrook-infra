#!/usr/bin/env python3
"""Render development contracts with synthetic secrets, never live credentials."""
from pathlib import Path
import json
import re
import sys
import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

root = Path(__file__).resolve().parents[2]
role = root / 'ansible/roles/development_backends'
values = yaml.safe_load((role / 'defaults/main.yml').read_text())
values['dev_backend_secrets'] = {k: '1' * 64 for k in
    ('postgres_admin','postgres_dev','rabbit_dev','rabbit_test','neo4j')}
env = Environment(loader=FileSystemLoader(role / 'templates'), undefined=StrictUndefined)
env.filters['to_json'] = json.dumps
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for source in sorted((role / 'templates').glob('*.j2')):
    rendered = env.get_template(source.name).render(**values)
    assert '{{' not in rendered
    (out / source.name.removesuffix('.j2')).write_text(rendered)
# A fresh volume must create only the agreed development database, and must
# not need a retired test credential to render or provision.
bootstrap = (out / 'postgres-init.sh').read_text()
assert re.findall(r'^CREATE DATABASE ([a-z_]+)', bootstrap, re.M) == ['home_budget_dev']
assert re.findall(r'^CREATE ROLE ([a-z_]+)', bootstrap, re.M) == ['home_budget_dev']
assert 'HOME_BUDGET_TEST_PASSWORD' not in (out / 'postgres.env').read_text()
definitions = json.loads((out / 'rabbitmq-definitions.json').read_text())
assert {v['name'] for v in definitions['vhosts']} == {'home-budget-dev','home-budget-test'}
assert len(definitions['permissions']) == 2
for name in ('postgres','rabbitmq','neo4j'):
    unit = (out / (name + '.container')).read_text()
    assert 'WantedBy=default.target' in unit
    assert '--memory=' in unit and 'HealthOnFailure=kill' in unit
    assert 'PublishPort=192.168.2.201:' in unit
    assert 'latest' not in unit and 'Privileged' not in unit
(out / 'synthetic-secrets.yml').write_text(yaml.safe_dump({'dev_backend_secrets': values['dev_backend_secrets']}))
print('Development templates and isolation contracts validated')
