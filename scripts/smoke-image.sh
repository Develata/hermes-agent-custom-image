#!/bin/sh
set -eu

for command_name in gh jq rclone sshpass git-lfs docker cargo elan lean lake tectonic codex codegraph agently-cli; do
    command -v "${command_name}" >/dev/null
done

git lfs version >/dev/null
test "$(git config --system --get filter.lfs.required)" = "true"
docker compose version >/dev/null
cargo --version >/dev/null
elan --version | grep -F 'elan 4.2.3' >/dev/null
lean --version | grep -F 'Lean (version 4.32.0' >/dev/null
lake --version >/dev/null
tectonic --version | grep -F 'Tectonic 0.16.9' >/dev/null
codex --version >/dev/null

smoke_dir="$(mktemp -d)"
trap 'rm -rf "${smoke_dir}"' EXIT HUP INT TERM

cat > "${smoke_dir}/Smoke.lean" <<'LEAN'
def answer : Nat := 42
example : answer = 42 := rfl
LEAN
(cd "${smoke_dir}" && lean Smoke.lean)

cat > "${smoke_dir}/smoke.tex" <<'TEX'
\documentclass{article}
\begin{document}
Hermes Tectonic smoke: $1 + 1 = 2$.
\end{document}
TEX
TECTONIC_UNTRUSTED_MODE=1 tectonic -X compile \
    --outdir "${smoke_dir}" \
    "${smoke_dir}/smoke.tex"
test -s "${smoke_dir}/smoke.pdf"

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
