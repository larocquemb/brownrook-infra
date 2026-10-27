#!/usr/bin/env python3
"""Reject vLLM startup unless a single GPU has enough free memory."""
import subprocess
import sys


def check(output: str, minimum_mib: int) -> str:
    values = [line.strip() for line in output.splitlines() if line.strip()]
    if len(values) != 1:
        raise ValueError("Expected exactly one NVIDIA GPU")
    free = int(values[0])
    if free < minimum_mib:
        raise ValueError(f"GPU has {free} MiB free; {minimum_mib} MiB required")
    return f"GPU has {free} MiB free"


def main() -> int:
    try:
        minimum = int(sys.argv[1])
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
            check=True, capture_output=True, text=True, timeout=10,
        )
        print(check(result.stdout, minimum))
        return 0
    except (IndexError, ValueError, OSError, subprocess.SubprocessError) as exc:
        print(f"vLLM GPU preflight failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
