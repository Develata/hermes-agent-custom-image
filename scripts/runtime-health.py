#!/opt/hermes/.venv/bin/python
"""Fail closed on native PM byte verification AND passive startup drift."""
from pathlib import Path
import os
import subprocess
import sys


def main() -> int:
    if os.geteuid() == 0:
        print('Native runtime health must run after entrypoint privilege drop', file=sys.stderr)
        return 1
    root = Path('/opt/hermes')
    # Invoke PM directly: do not start the application CLI/home migrations.
    doctor = subprocess.run([sys.executable, '-m', 'pm.cli', 'doctor'], cwd=root)
    if doctor.returncode:
        return doctor.returncode
    sys.path.insert(0, str(root))
    from hermes_cli.venv_sync import check_runtime
    problem = check_runtime(root)
    if problem:
        print(f'Native passive runtime health failed: {problem}', file=sys.stderr)
        return 1
    print('Native PM doctor and passive runtime health: ok')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
