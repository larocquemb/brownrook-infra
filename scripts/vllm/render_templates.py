"""Render vLLM host files with fixed CI inputs for native validators."""
import argparse
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
role = root / 'ansible/roles/vllm'
values = yaml.safe_load((role / 'defaults/main.yml').read_text())
values.update(vllm_listen_address='192.168.2.201', vllm_uid='1000', vllm_binary='/usr/bin/true')
args.output.mkdir(parents=True, exist_ok=True)
env = Environment(loader=FileSystemLoader(role / 'templates'), undefined=StrictUndefined)
for source, target in [('vllm.service.j2', 'brownrook-vllm.service'),
                       ('vllm-access.nft.j2', 'vllm-access.nft')]:
    (args.output / target).write_text(env.get_template(source).render(values))
(args.output / 'vllm-access.service').write_text((role / 'files/vllm-access.service').read_text())
