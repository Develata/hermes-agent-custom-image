# hermes-agent-custom-image

[中文](#中文) · [English](#english) · [Upstream Hermes Agent](https://github.com/NousResearch/hermes-agent) · [License](./LICENSE)

[![Build and Push Docker Image](https://github.com/Develata/hermes-agent-custom-image/actions/workflows/docker-build.yml/badge.svg)](https://github.com/Develata/hermes-agent-custom-image/actions/workflows/docker-build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![GHCR](https://img.shields.io/badge/GHCR-hermes--agent--custom--image-blue)](https://ghcr.io/develata/hermes-agent-custom-image)

## 中文

一个极小的 Hermes Agent 自定义 Docker 镜像包装仓库。

本仓库不 fork、不复制、不改写上游 Hermes Agent 源码。它只做一件事：以官方上游镜像为基础，额外安装常用命令行工具，然后发布为自己的 GHCR 镜像。

> 上游项目：[`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent)
>
> 本仓库尊重并依赖上游 Hermes Agent 的工作；所有 Hermes Agent 本体能力、入口脚本和基础运行环境均来自上游。本仓库仅维护额外 apt 包这一层。

### 镜像

```text
ghcr.io/develata/hermes-agent-custom-image:latest
ghcr.io/develata/hermes-agent-custom-image:YYYY-MM-DD
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
python3-pip
jq
unzip
fd-find
fzf
bat
eza
tree
htop
tmux
vim
```

`gh` 来自 GitHub CLI 官方 apt 源；其他包来自基础 Debian apt 仓库。`ca-certificates` 作为 HTTPS apt 源的最小前置依赖安装。

当前上游 Hermes Agent 镜像已经包含 `git`、`curl`、`wget`、`ca-certificates`、构建工具、Python、Node.js、npm、ripgrep、ffmpeg、Docker CLI、OpenSSH client 和 `procps`，本仓库不会重复把这些声明为自定义新增工具。

Debian 下 `fd-find` 可能安装为 `fdfind`，`bat` 可能安装为 `batcat`。Dockerfile 会在需要时创建兼容命令：

```text
/usr/local/bin/fd
/usr/local/bin/bat
```

### 本地构建与验证

```bash
docker build --pull -t hermes-agent-custom-image:latest .
```

验证核心工具：

```bash
docker run --rm hermes-agent-custom-image:latest \
  sh -lc "whoami && command -v gh && command -v pip3 && command -v jq && command -v fd && command -v bat && command -v eza"
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

定时任务只在上游 `nousresearch/hermes-agent:latest` digest 变化时构建并推送。push 和手动触发会直接构建。

每次实际构建会同时推送：

```text
latest
YYYY-MM-DD
upstream-<sha256>
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

This repository does not fork, vendor, or modify the upstream Hermes Agent source code. It only rebuilds from the official upstream image, installs a small set of daily-use CLI tools, and publishes the result as a GHCR image.

> Upstream project: [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent)
>
> This repository respects and depends on the upstream Hermes Agent project. The Hermes Agent runtime, entrypoint, and base environment come from upstream. This repository only maintains the extra apt package layer.

### Image

```text
ghcr.io/develata/hermes-agent-custom-image:latest
ghcr.io/develata/hermes-agent-custom-image:YYYY-MM-DD
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
python3-pip
jq
unzip
fd-find
fzf
bat
eza
tree
htop
tmux
vim
```

`gh` is installed from the official GitHub CLI apt repository. Other packages are installed from the base Debian apt repositories. `ca-certificates` is installed as the minimal prerequisite for HTTPS apt sources.

The current upstream Hermes Agent image already includes `git`, `curl`, `wget`, `ca-certificates`, build tools, Python, Node.js, npm, ripgrep, ffmpeg, Docker CLI, OpenSSH client, and `procps`; this repository does not claim those as custom additions.

On Debian, `fd-find` may install the binary as `fdfind`, and `bat` may install the binary as `batcat`. The Dockerfile creates compatibility commands when needed:

```text
/usr/local/bin/fd
/usr/local/bin/bat
```

### Build and verify

```bash
docker build --pull -t hermes-agent-custom-image:latest .
```

Verify the core tools:

```bash
docker run --rm hermes-agent-custom-image:latest \
  sh -lc "whoami && command -v gh && command -v pip3 && command -v jq && command -v fd && command -v bat && command -v eza"
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

Scheduled runs only build and push when the digest of `nousresearch/hermes-agent:latest` changes. Push and manual runs build directly.

Each actual build pushes:

```text
latest
YYYY-MM-DD
upstream-<sha256>
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
