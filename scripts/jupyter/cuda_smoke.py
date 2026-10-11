"""Verify the managed Python 3.15 PyTorch kernel on Arsene."""
import sys
import torch

assert sys.version_info[:2] == (3, 15), sys.version
assert torch.__version__ == "2.14.1+cu130", torch.__version__
assert torch.version.cuda == "13.0", torch.version.cuda
assert torch.cuda.is_available(), "CUDA unavailable"
a = torch.ones((1024, 1024), device="cuda")
b = a @ a
torch.cuda.synchronize()
assert b.is_cuda and torch.all(b == 1024).item()
print(f"PASS: Python {sys.version.split()[0]}, PyTorch {torch.__version__}, "
      f"CUDA {torch.version.cuda}, {torch.cuda.get_device_name(0)}")
