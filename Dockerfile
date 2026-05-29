ARG UPSTREAM_IMAGE=nousresearch/hermes-agent:latest

FROM ${UPSTREAM_IMAGE}

USER root

# Upstream Hermes image already includes ca-certificates, curl, python3,
# git, openssh-client, docker-cli, node 22, npm, uv, ripgrep, ffmpeg,
# gcc/python3-dev/libffi-dev, procps, and xz-utils.  Keep this layer only
# for Develata-specific tools that are not part of the base image.
#
# Keep:
# - gh: GitHub workflow automation
# - jq: small JSON inspection in shell scripts
# - unzip: archive handling for user-supplied artifacts
# - rclone: OpenList/WebDAV transfer helper; no FUSE mount by default
# - @openai/codex: Codex CLI delegation/review workflow
#
# Drop from the old custom layer:
# - ca-certificates/curl/python3/npm/node: already in upstream image
# - python3-pip: prefer uv / the Hermes venv; avoid PEP 668 friction
# - fd-find/fzf/bat/eza/tree/htop/tmux/vim: interactive convenience tools,
#   not needed for the Telegram/gateway runtime path
RUN set -eux; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        gh \
        jq \
        unzip \
        rclone; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    npm install -g @openai/codex; \
    npm cache clean --force
