# hermes-agent-custom-image

This repository builds a thin custom Docker image based on the upstream Hermes Agent image, with GitHub CLI and a small set of daily-use CLI tools installed.

It does not fork or vendor the upstream Hermes source. It only rebuilds from the upstream image and adds a small package layer.

## Base image

```text
nousresearch/hermes-agent:latest
```

The base image can be overridden at build time with `UPSTREAM_IMAGE`.

## Added packages

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

The image installs `gh` from the official GitHub CLI apt repository. Other packages come from the base Debian apt repositories. `ca-certificates` is installed as a minimal prerequisite for HTTPS apt sources.

The current upstream Hermes image is Debian-based and already includes `git`, `curl`, `wget`, `ca-certificates`, build tools, Python, Node.js, npm, ripgrep, ffmpeg, Docker CLI, OpenSSH client, and `procps`, so this repository does not add those as custom packages.

On Debian, `fd-find` may install the binary as `fdfind`, and `bat` may install the binary as `batcat`. The Dockerfile creates compatibility symlinks at `/usr/local/bin/fd` and `/usr/local/bin/bat` when needed.

## Image

```text
ghcr.io/develata/hermes-agent-custom-image:latest
ghcr.io/develata/hermes-agent-custom-image:YYYY-MM-DD
```

## Build locally

```bash
docker build --pull -t hermes-agent-custom-image:latest .
```

To use a different upstream image:

```bash
docker build --pull \
  --build-arg UPSTREAM_IMAGE=nousresearch/hermes-agent:latest \
  -t hermes-agent-custom-image:latest \
  .
```

## Verify

```bash
docker run --rm hermes-agent-custom-image:latest gh --version
```

Optional shell check:

```bash
docker run --rm hermes-agent-custom-image:latest sh -lc "whoami && command -v gh && command -v pip3 && command -v jq && command -v fd && command -v bat && command -v eza"
```

If the upstream image has `bash`:

```bash
docker run --rm -it hermes-agent-custom-image:latest bash
```

Otherwise:

```bash
docker run --rm -it hermes-agent-custom-image:latest sh
```

## Docker Compose

```yaml
services:
  hermes:
    image: ghcr.io/develata/hermes-agent-custom-image:latest
    restart: unless-stopped
```

Then update the running service with:

```bash
docker compose pull
docker compose up -d
```

## Upstream user

This first version leaves the final image user as `root` after installing packages. The current upstream image also starts as `root` and lets its entrypoint drop privileges at runtime.

If the upstream image normally runs as a non-root user, inspect it first:

```bash
docker image inspect nousresearch/hermes-agent:latest --format '{{.Config.User}}'
```

If the output is non-empty, append the corresponding `USER ...` line at the end of `Dockerfile`.

## Automated builds

GitHub Actions builds and pushes the image to GitHub Container Registry on:

- push to `main`
- manual `workflow_dispatch`
- weekly schedule, Monday 03:00 UTC

Each build pushes both `latest` and a date tag.
