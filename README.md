# hermes-agent-custom-image

[中文](#中文) · [English](#english) · [Upstream Hermes Agent](https://github.com/NousResearch/hermes-agent) · [License](./LICENSE)

[![Build and Push Docker Image](https://github.com/Develata/hermes-agent-custom-image/actions/workflows/docker-build.yml/badge.svg)](https://github.com/Develata/hermes-agent-custom-image/actions/workflows/docker-build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![GHCR](https://img.shields.io/badge/GHCR-hermes--agent--custom--image-blue)](https://ghcr.io/develata/hermes-agent-custom-image)

## 中文

一个极小的 Hermes Agent 自定义 Docker 镜像包装仓库。

本仓库不 fork、不复制、不改写上游 Hermes Agent 源码。它只做一件事：以官方上游镜像为基础，额外安装 Develata 常用的命令行工具，然后发布为自己的 GHCR 镜像。

> 上游项目：[`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent)
>
> 本仓库尊重并依赖上游 Hermes Agent 的工作；所有 Hermes Agent 本体能力、入口脚本和基础运行环境均来自上游。本仓库只维护额外工具层。

### 镜像

```text
ghcr.io/develata/hermes-agent-custom-image:latest
ghcr.io/develata/hermes-agent-custom-image:YYYY-MM-DD
ghcr.io/develata/hermes-agent-custom-image:upstream-<sha256>
ghcr.io/develata/hermes-agent-custom-image:build-<custom-sha>-upstream-<base-sha>
```

基础镜像：

```text
nousresearch/hermes-agent:latest
```

也可以在构建时覆盖：

```bash
docker build --pull \
  --build-arg UPSTREAM_IMAGE=nousresearch/hermes-agent:latest \
  -t hermes-agent-custom-image:latest \
  .
```

### 新增工具

```text
gh
jq
unzip
rclone
sshpass
Docker Compose CLI plugin
Rust stable toolchain + rustfmt + clippy
build-essential / pkg-config / libssl-dev
codex
codegraph
agently-cli
Feishu/Lark gateway Python deps: lark-oapi, qrcode
```

`gh` 来自 GitHub CLI 官方 apt 源；`jq`、`unzip`、`rclone`、`sshpass` 和基础编译依赖来自基础 Debian apt 仓库。

Docker Compose 只安装 CLI plugin 到：

```text
/usr/local/lib/docker/cli-plugins/docker-compose
```

用途是在 Hermes 容器内运行 `docker compose config` 这类 Compose 文件渲染/校验命令。镜像不包含 Docker daemon，也不默认挂载宿主机 Docker socket。

Codex / CodeGraph / agently-cli 通过上游镜像已有的 npm 安装：

```bash
npm install -g @openai/codex @colbymchenry/codegraph @tencent-qqmail/agently-cli
```

Feishu/Lark 依赖不在本仓库重复写版本号。构建时会读取上游 `/opt/hermes/pyproject.toml` 的 `project.optional-dependencies.feishu`，把同一组 requirements 安装进 Hermes venv；若上游移除该 extra、缺少 `lark-oapi` / `qrcode`，或 SDK 不再满足 adapter 的 `extra_ua_tags` contract，构建 smoke 会 fail closed。

当前上游 Hermes Agent 镜像已经包含 `git`、`curl`、`wget`、`ca-certificates`、Python、Node.js、npm、ripgrep、ffmpeg、Docker CLI、OpenSSH client 和 `procps`，本仓库不会重复把这些声明为自定义新增工具。

### 本地构建与验证

```bash
docker build --pull -t hermes-agent-custom-image:latest .
```

验证核心工具：

```bash
docker run --rm hermes-agent-custom-image:latest \
  sh -lc hermes-custom-image-smoke
```

进入 shell：

```bash
docker run --rm -it hermes-agent-custom-image:latest bash
```

如果上游镜像没有 `bash`，使用：

```bash
docker run --rm -it hermes-agent-custom-image:latest sh
```

### Docker Compose

```yaml
services:
  hermes:
    image: ghcr.io/develata/hermes-agent-custom-image:latest
    restart: unless-stopped
```

更新：

```bash
docker compose pull
docker compose up -d
```

### 自动构建

GitHub Actions 会在以下场景检查或构建镜像：

- push 到 `main`
- 手动 `workflow_dispatch`
- 每天 UTC 03:00 检查上游镜像 digest

定时任务只在上游 `nousresearch/hermes-agent:latest` digest 变化时构建并推送。push 和手动触发会直接构建。实际构建把 `FROM` 解析为 `tag@digest`，并写入 OCI `source`、`revision`、`created`、`base.name`、`base.digest` labels；因此 `latest` 可追溯到精确 custom commit 与 upstream manifest。

每次实际构建会同时推送：

```text
latest
YYYY-MM-DD
upstream-<sha256>
build-<custom-sha>-upstream-<base-sha>
```

### 默认用户

当前上游镜像 `Config.User` 是 `root`，运行时由上游 entrypoint 降权到 `hermes`。本仓库保持这个行为，不额外覆盖最终 `USER`。

如上游未来修改默认用户，可先检查：

```bash
docker image inspect nousresearch/hermes-agent:latest --format '{{.Config.User}}'
```

再决定是否在 Dockerfile 末尾追加对应的 `USER ...`。

### 许可证

本包装仓库使用 MIT License。Hermes Agent 上游项目本身的许可与版权归上游项目维护者所有。

---

## English

A tiny custom Docker image wrapper for Hermes Agent.

This repository does not fork, vendor, or modify the upstream Hermes Agent source code. It only rebuilds from the official upstream image, installs Develata's daily-use CLI tools, and publishes the result as a GHCR image.

> Upstream project: [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent)
>
> This repository respects and depends on the upstream Hermes Agent project. The Hermes Agent runtime, entrypoint, and base environment come from upstream. This repository only maintains the extra tooling layer.

### Image

```text
ghcr.io/develata/hermes-agent-custom-image:latest
ghcr.io/develata/hermes-agent-custom-image:YYYY-MM-DD
ghcr.io/develata/hermes-agent-custom-image:upstream-<sha256>
ghcr.io/develata/hermes-agent-custom-image:build-<custom-sha>-upstream-<base-sha>
```

Base image:

```text
nousresearch/hermes-agent:latest
```

Override the upstream image at build time:

```bash
docker build --pull \
  --build-arg UPSTREAM_IMAGE=nousresearch/hermes-agent:latest \
  -t hermes-agent-custom-image:latest \
  .
```

### Added tools

```text
gh
jq
unzip
rclone
sshpass
Docker Compose CLI plugin
Rust stable toolchain + rustfmt + clippy
build-essential / pkg-config / libssl-dev
codex
codegraph
agently-cli
Feishu/Lark gateway Python deps: lark-oapi, qrcode
```

`gh` is installed from the official GitHub CLI apt repository. `jq`, `unzip`, `rclone`, `sshpass`, and native build dependencies are installed from the base Debian apt repositories.

Docker Compose is installed only as the CLI plugin at:

```text
/usr/local/lib/docker/cli-plugins/docker-compose
```

This lets Hermes run Compose render/validation commands such as `docker compose config` inside the container. The image does not include a Docker daemon and does not mount the host Docker socket by default.

Codex / CodeGraph / agently-cli are installed via npm, which is already available in the upstream image:

```bash
npm install -g @openai/codex @colbymchenry/codegraph @tencent-qqmail/agently-cli
```

This repository does not duplicate Feishu/Lark dependency versions. Each build reads `project.optional-dependencies.feishu` from the upstream `/opt/hermes/pyproject.toml` and installs those exact requirements into the Hermes venv. The image smoke test fails closed if the extra disappears, omits `lark-oapi` / `qrcode`, or no longer satisfies the adapter's `extra_ua_tags` contract.

The current upstream Hermes Agent image already includes `git`, `curl`, `wget`, `ca-certificates`, Python, Node.js, npm, ripgrep, ffmpeg, Docker CLI, OpenSSH client, and `procps`; this repository does not claim those as custom additions.

### Build and verify

```bash
docker build --pull -t hermes-agent-custom-image:latest .
```

Verify the core tools:

```bash
docker run --rm hermes-agent-custom-image:latest \
  sh -lc hermes-custom-image-smoke
```

Open a shell:

```bash
docker run --rm -it hermes-agent-custom-image:latest bash
```

If `bash` is unavailable:

```bash
docker run --rm -it hermes-agent-custom-image:latest sh
```

### Docker Compose

```yaml
services:
  hermes:
    image: ghcr.io/develata/hermes-agent-custom-image:latest
    restart: unless-stopped
```

Update:

```bash
docker compose pull
docker compose up -d
```

### Automated builds

GitHub Actions checks or builds the image on:

- push to `main`
- manual `workflow_dispatch`
- daily upstream digest check at 03:00 UTC

Scheduled runs only build and push when the digest of `nousresearch/hermes-agent:latest` changes. Push and manual runs build directly. Each build resolves `FROM` as `tag@digest` and records OCI `source`, `revision`, `created`, `base.name`, and `base.digest` labels, so `latest` remains traceable to an exact custom commit and upstream manifest.

Each actual build pushes:

```text
latest
YYYY-MM-DD
upstream-<sha256>
build-<custom-sha>-upstream-<base-sha>
```

### Default user

The current upstream image has `Config.User=root`, and its entrypoint drops privileges to `hermes` at runtime. This repository preserves that behavior and does not override the final `USER`.

If the upstream image changes its default user in the future, inspect it first:

```bash
docker image inspect nousresearch/hermes-agent:latest --format '{{.Config.User}}'
```

Then decide whether to append the corresponding `USER ...` line to the Dockerfile.

### License

This wrapper repository is released under the MIT License. The upstream Hermes Agent project keeps its own license and copyright.
