#!/bin/sh
set -eu

for command_name in gh jq rclone sshpass docker cargo codex codegraph agently-cli; do
    command -v "${command_name}" >/dev/null
done

docker compose version >/dev/null
cargo --version >/dev/null
codex --version >/dev/null

python_bin=/opt/hermes/.venv/bin/python
"${python_bin}" - <<'PY'
from importlib import metadata
import inspect
from pathlib import Path
import tomllib

from packaging.requirements import Requirement

pyproject = Path("/opt/hermes/pyproject.toml")
data = tomllib.loads(pyproject.read_text(encoding="utf-8"))
requirements = data["project"]["optional-dependencies"]["feishu"]
parsed = [Requirement(raw) for raw in requirements]
by_name = {req.name.lower(): req for req in parsed}

for required_name in ("lark-oapi", "qrcode"):
    if required_name not in by_name:
        raise SystemExit(f"missing upstream Feishu requirement: {required_name}")

for requirement in parsed:
    if requirement.marker is not None and not requirement.marker.evaluate():
        continue
    installed = metadata.version(requirement.name)
    if requirement.specifier and not requirement.specifier.contains(installed, prereleases=True):
        raise SystemExit(
            f"installed {requirement.name}=={installed} does not satisfy {requirement}"
        )

from lark_oapi.ws import Client
from plugins.platforms.feishu.adapter import FEISHU_AVAILABLE

if not FEISHU_AVAILABLE:
    raise SystemExit("Feishu platform adapter reports FEISHU_AVAILABLE=false")
if "extra_ua_tags" not in inspect.signature(Client.__init__).parameters:
    raise SystemExit("lark_oapi.ws.Client lacks required extra_ua_tags parameter")

print("Feishu optional dependency contract: ok")
PY
