"""Out-of-process, recoverable installer for verified Secure Tiles releases."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


UPDATE_ITEMS = ("main.py", "relay_server.py", "requirements.txt", "README.md", "secure_tiles", "assets")


def _safe_app_root(value: str) -> Path:
    root = Path(value).resolve()
    if root == Path(root.anchor) or root == Path.home().resolve():
        raise ValueError("Refusing to update a broad filesystem location")
    if not (root / "main.py").is_file() or not (root / "secure_tiles").is_dir():
        raise ValueError("Target is not a Secure Tiles installation")
    return root


def apply_update(stage_value: str, target_value: str, pid: int, version: str) -> None:
    stage = Path(stage_value).resolve()
    target = _safe_app_root(target_value)
    if not (stage / "main.py").is_file() or not (stage / "secure_tiles").is_dir():
        raise ValueError("Staged release is incomplete")
    for _ in range(120):
        try:
            os.kill(pid, 0)
        except OSError:
            break
        time.sleep(.25)
    backup = Path.home() / ".secure_tiles" / "update_backups" / version
    backup.mkdir(parents=True, exist_ok=True)
    for name in UPDATE_ITEMS:
        source, saved = target / name, backup / name
        if not source.exists() or saved.exists():
            continue
        if source.is_dir(): shutil.copytree(source, saved)
        else: shutil.copy2(source, saved)
    for name in UPDATE_ITEMS:
        source, destination = stage / name, target / name
        if not source.exists():
            continue
        if destination.is_dir(): shutil.rmtree(destination)
        elif destination.exists(): destination.unlink()
        if source.is_dir(): shutil.copytree(source, destination)
        else: shutil.copy2(source, destination)
    subprocess.Popen([sys.executable, str(target / "main.py")], cwd=str(target), close_fds=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    apply_update(args.stage, args.target, args.pid, args.version)


if __name__ == "__main__":
    main()
