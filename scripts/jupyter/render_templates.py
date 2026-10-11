"""Render deployment templates for native parser checks in CI."""
import argparse
import json
from pathlib import Path
from jinja2 import Environment, StrictUndefined
import yaml

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
variables = yaml.safe_load((root / "ansible/inventories/production/group_vars/jupyter.yml").read_text())
variables.update(jupyter_certificate=str(output / "test-cert.pem"),
                 jupyter_certificate_key=str(output / "test-key.pem"))
env = Environment(undefined=StrictUndefined)
env.filters["to_json"] = json.dumps
for role, template, filename in (
    ("jupyter_runtime", "jupyter-arsene.nft.j2", "jupyter.nft"),
    ("jupyter_runtime", "kernel.json.j2", "kernel.json"),
    ("jupyter_runtime", "jupyter_server_config.py.j2", "jupyter_server_config.py"),
    ("jupyter_proxy", "jupyter-arsene.conf.j2", "jupyter-nginx.conf"),
    ("jupyter_dns", "jupyter.conf.j2", "jupyter-unbound.conf"),
):
    source = root / "ansible/roles" / role / "templates" / template
    (output / filename).write_text(env.from_string(source.read_text()).render(variables) + "\n")
json.loads((output / "kernel.json").read_text())
compile((output / "jupyter_server_config.py").read_text(), "jupyter_server_config.py", "exec")
(output / "nginx.conf").write_text(
    f"pid {output}/nginx.pid;\nerror_log stderr;\nevents {{}}\n"
    f"http {{ include {output}/jupyter-nginx.conf; }}\n")
print(f"PASS: templates rendered to {output}")
