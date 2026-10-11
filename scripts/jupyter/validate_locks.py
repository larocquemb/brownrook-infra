"""Validate the reviewed runtime contracts without downloading GPU libraries."""
from pathlib import Path
import tomllib

root = Path(__file__).resolve().parents[2]
for project in ("server", "pytorch315"):
    folder = root / "runtime" / "jupyter" / project
    manifest = tomllib.loads((folder / "pyproject.toml").read_text())
    lock = tomllib.loads((folder / "uv.lock").read_text())
    minor = {"server": "3.12", "pytorch315": "3.15"}[project]
    assert lock["requires-python"] == f"=={minor}.*"
    assert manifest["project"]["requires-python"] == {
        "server": ">=3.12,<3.13", "pytorch315": ">=3.15,<3.16"
    }[project]
    packages = {p["name"]: p for p in lock["package"]}
    for package in packages.values():
        for artifact in package.get("wheels", []):
            assert artifact["hash"].startswith("sha256:")
            assert artifact["url"].startswith("https://")
    if project == "pytorch315":
        assert packages["mpmath"]["version"] == "1.3.0"
        assert packages["cuda-toolkit"]["version"] == "13.0.3.0"
        for name, version in (("torch", "2.14.1+cu130"), ("torchvision", "0.29.1+cu130")):
            package = packages[name]
            assert package["version"] == version
            assert package["source"]["registry"] == "https://download.pytorch.org/whl/cu130"
            assert any("cp315-cp315-manylinux" in w["url"] for w in package["wheels"])
    else:
        assert "jupyterlab" in packages and "jupyter-server" in packages
    print(f"PASS: {project} lockfile contract")
