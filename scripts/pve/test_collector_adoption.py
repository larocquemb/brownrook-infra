"""Exercise the deployed Ansible ownership assertion against partial-install cases."""
import base64
from copy import deepcopy
import os
from pathlib import Path
import subprocess
import tempfile
import yaml

root = Path(__file__).resolve().parents[2]
tasks = yaml.safe_load((root / 'ansible/roles/pve_kernel_logs/tasks/main.yml').read_text())
assertion = deepcopy(next(task for task in tasks if task['name'] == 'Preserve unrelated Alloy configurations'))
assertion.pop('no_log', None)
checksum = 'abc123'
for name, content, state, package_hash, expected in [
    ('inactive package default', 'logging {}', 'stopped', checksum, True),
    ('custom configuration', 'custom pipeline', 'stopped', 'different', False),
    ('running unrelated collector', 'logging {}', 'running', checksum, False),
    ('managed running collector', '// Managed by brownrook-infra: PVE kernel journals only.', 'running', 'different', True),
]:
    with tempfile.TemporaryDirectory(prefix='pve-adoption-') as directory:
        path = Path(directory)
        play = [{'hosts':'localhost', 'gather_facts':False, 'vars':{
            'pve_kernel_logs_existing':{'stat':{'exists':True,'checksum':checksum}},
            'pve_kernel_logs_existing_content':{'content':base64.b64encode(content.encode()).decode()},
            'pve_kernel_logs_package_files':{'stdout':f' /etc/alloy/config.alloy {package_hash}'},
            'ansible_facts':{'services':{'alloy.service':{'state':state}}},
        }, 'tasks':[assertion]}]
        (path / 'test.yml').write_text(yaml.safe_dump(play))
        result = subprocess.run(['ansible-playbook','-i','localhost,','-c','local',str(path / 'test.yml')],
            capture_output=True,text=True,timeout=30,
            env={**os.environ,'ANSIBLE_LOCAL_TEMP':str(path / 'ansible')})
        if (result.returncode == 0) != expected:
            raise AssertionError(name + '\n' + result.stdout + result.stderr)
        print('PASS: ' + name)
