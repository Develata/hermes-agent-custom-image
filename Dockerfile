ARG UPSTREAM_IMAGE=nousresearch/hermes-agent:latest

FROM ${UPSTREAM_IMAGE}

USER root

# Upstream Hermes image already includes ca-certificates, curl, python3,
# git, openssh-client, docker-cli, node 22, npm, uv, ripgrep, ffmpeg,
# gcc/python3-dev/libffi-dev, procps, and xz-utils. Keep this layer only
# for Develata-specific tools that are not part of the base image.
#
# Keep:
# - gh: GitHub workflow automation
# - jq: small JSON inspection in shell scripts
# - unzip: archive handling for user-supplied artifacts
# - rclone: OpenList/WebDAV transfer helper; use copy/sync by default,
#   not FUSE mount
# - Docker Compose CLI plugin: render/validate Compose files with
#   `docker compose config`; no Docker daemon or socket is included
# - build-essential/pkg-config/libssl-dev: common native dependencies for
#   small Rust crates that compile C/OpenSSL bindings
# - Rust minimal stable toolchain: local smoke tests and small scripts only;
#   GitHub Actions remains the authoritative CI environment
# - @openai/codex: Codex CLI delegation/review workflow
# - @colbymchenry/codegraph: CodeGraph MCP/CLI
#
# Deliberately not included:
# - python3-pip: prefer uv / the Hermes venv; avoid PEP 668 friction
# - Docker daemon / dockerd / Docker socket: the long-running Hermes gateway
#   container should not hold host-level container-control privileges
# - rust-analyzer/nightly/extra targets: install per project only if needed
# - fuse3: OpenList should be accessed by explicit rclone copy/sync; mounting
#   needs Docker runtime /dev/fuse + privileges and is not the default
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
        rclone \
        build-essential \
        pkg-config \
        sshpass \
        libssl-dev; \

    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ARG DOCKER_COMPOSE_VERSION=v5.3.0

# Install only the Docker Compose CLI plugin. This enables syntax/env
# validation such as `docker compose config` inside Hermes, but does not add a
# Docker daemon or host Docker socket access.
RUN set -eux; \
    case "$(uname -s)-$(uname -m)" in \
        Linux-x86_64) compose_platform=linux-x86_64 ;; \
        Linux-aarch64) compose_platform=linux-aarch64 ;; \
        *) echo "unsupported Docker Compose plugin platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;; \
    esac; \
    install -m 0755 -d /usr/local/lib/docker/cli-plugins; \
    compose_url="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${compose_platform}"; \
    curl -fsSL "${compose_url}" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose; \
    curl -fsSL "${compose_url}.sha256" \
        -o /tmp/docker-compose.sha256; \
    expected_sha256="$(awk '{print $1}' /tmp/docker-compose.sha256)"; \
    actual_sha256="$(sha256sum /usr/local/lib/docker/cli-plugins/docker-compose | awk '{print $1}')"; \
    test "${expected_sha256}" = "${actual_sha256}"; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose; \
    docker compose version; \
    rm -f /tmp/docker-compose.sha256

# Minimal Rust toolchain for local small scripts and smoke tests.
# For repository-level validation, prefer GitHub Actions with cargo fmt,
# cargo clippy, cargo test, and cargo build.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH \
    CARGO_TERM_COLOR=always

ARG RUST_TOOLCHAIN=stable

RUN set -eux; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        -o /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh -y \
        --no-modify-path \
        --profile minimal \
        --default-toolchain "${RUST_TOOLCHAIN}"; \
    rustup component add rustfmt clippy; \
    rustup --version; \
    rustc --version; \
    cargo --version; \
    printf '%s\n' \
        'export RUSTUP_HOME=/usr/local/rustup' \
        'export CARGO_HOME=/usr/local/cargo' \
        'case ":$PATH:" in *:/usr/local/cargo/bin:*) ;; *) export PATH="/usr/local/cargo/bin:$PATH" ;; esac' \
        'export CARGO_TERM_COLOR=always' \
        > /etc/profile.d/rust.sh; \
    chmod 0644 /etc/profile.d/rust.sh; \
    rm -f /tmp/rustup-init.sh; \
    if id hermes >/dev/null 2>&1; then \
        chown -R hermes:hermes "${RUSTUP_HOME}" "${CARGO_HOME}"; \
    fi; \
    chmod -R u+rwX,go+rX,go-w "${RUSTUP_HOME}" "${CARGO_HOME}"

# Feishu/Lark optional gateway deps are baked into the Hermes venv because
# Feishu is configured as Develata's secondary gateway channel. Derive the
# exact requirements from the upstream pyproject instead of duplicating its
# pins here: an upstream adapter/SDK contract change must update both atomically.
RUN set -eux; \
    /opt/hermes/.venv/bin/python -c \
        'import pathlib, tomllib; p = pathlib.Path("/opt/hermes/pyproject.toml"); d = tomllib.loads(p.read_text()); print("\n".join(d["project"]["optional-dependencies"]["feishu"]))' \
        > /tmp/hermes-feishu-requirements.txt; \
    grep -Eq '^lark-oapi([<>=!~].*)?$' /tmp/hermes-feishu-requirements.txt; \
    grep -Eq '^qrcode([<>=!~].*)?$' /tmp/hermes-feishu-requirements.txt; \
    uv pip install --python /opt/hermes/.venv/bin/python \
        -r /tmp/hermes-feishu-requirements.txt; \
    rm -f /tmp/hermes-feishu-requirements.txt

RUN set -eux; \
    npm install -g \
        @openai/codex \
        @colbymchenry/codegraph \
        @tencent-qqmail/agently-cli; \
    npm cache clean --force

COPY --chmod=0755 scripts/smoke-image.sh /usr/local/bin/hermes-custom-image-smoke
