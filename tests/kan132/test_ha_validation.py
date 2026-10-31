"""A failed or empty API response must never prove storage resilience."""
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def api(tmp_path):
    executable = tmp_path / 'kubectl'
    executable.write_text(f'#!{sys.executable}\n' + '''
import json, os, sys
args = sys.argv[1:]
resource = args[args.index('get') + 1]
if resource == 'nodes':
    if 'json' in args:
        print(json.dumps({'items': [{'status': {'conditions': [{'type': 'Ready', 'status': 'True'}]}} for _ in range(3)]}))
    elif 'name' in args:
        print('node/a\\nnode/b\\nnode/c')
    else:
        print('three healthy nodes')
elif resource == 'storageclass':
    print('driver.longhorn.io')
elif resource == 'pvc':
    if os.getenv('DENY_PVC'):
        print('Forbidden PVC API', file=sys.stderr)
        sys.exit(1)
elif resource == 'volumes.longhorn.io':
    if os.getenv('DENY_VOLUME'):
        print('Forbidden Longhorn API', file=sys.stderr)
        sys.exit(1)
    print(json.dumps({'items': [] if os.getenv('EMPTY_VOLUME') else [{'status': {'robustness': 'healthy'}}]}))
elif resource == 'deployment':
    print('2')
elif resource == 'etcdsnapshotfile':
    print('s3://synthetic-backup/snapshot')
elif resource == 'pods':
    pass
else:
    raise SystemExit('Unexpected API request: ' + str(args))
''')
    executable.chmod(0o755)
    return {'PATH': str(tmp_path) + os.pathsep + os.environ['PATH'],
            'EVIDENCE_DIR': str(tmp_path / 'private-evidence')}


def run_validation(api, **flags):
    return subprocess.run(['bash', str(ROOT / 'scripts/kan-132/validate-ha.sh')],
                          env={**os.environ, **api, **flags}, capture_output=True, text=True)


def test_healthy_api_fixture_and_private_evidence(api):
    result = run_validation(api)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'RESULT: PASS' in result.stdout
    files = list(Path(api['EVIDENCE_DIR']).iterdir())
    assert len(files) == 1 and files[0].stat().st_mode & 0o777 == 0o600


@pytest.mark.parametrize('flag', ['DENY_VOLUME', 'EMPTY_VOLUME', 'DENY_PVC'])
def test_unverified_storage_fails_closed(api, flag):
    result = run_validation(api, **{flag: '1'})
    assert result.returncode != 0
    assert 'RESULT: FAIL' in result.stdout
    assert 'RESULT: PASS' not in result.stdout
