"""GPU guard must fail closed if memory or GPU inventory is ambiguous."""
import importlib.util
from pathlib import Path
import subprocess

import pytest


path = Path(__file__).parents[2] / 'ansible/roles/vllm/files/vllm-gpu-preflight.py'
spec = importlib.util.spec_from_file_location('vllm_gpu_preflight', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_requires_sufficient_free_memory():
    assert module.check('22000\n', 22000) == 'GPU has 22000 MiB free'
    with pytest.raises(ValueError, match='21999 MiB free'):
        module.check('21999\n', 22000)


@pytest.mark.parametrize('output', ['', '24576\n24576\n', '[N/A]\n'])
def test_rejects_unknown_or_multiple_gpu_inventory(output):
    with pytest.raises(ValueError):
        module.check(output, 22000)


def test_nvidia_smi_failure_is_reported(monkeypatch, capsys):
    def fail(*args, **kwargs):
        raise subprocess.TimeoutExpired('nvidia-smi', 10)
    monkeypatch.setattr(module.subprocess, 'run', fail)
    monkeypatch.setattr(module.sys, 'argv', ['preflight', '22000'])
    assert module.main() == 1
    assert 'preflight failed' in capsys.readouterr().err
