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
# - build-essential/pkg-config/libssl-dev: common native dependencies for
#   small Rust crates that compile C/OpenSSL bindings
# - Rust minimal stable toolchain: local smoke tests and small scripts only;
#   GitHub Actions remains the authoritative CI environment
# - @openai/codex: Codex CLI delegation/review workflow
# - @colbymchenry/codegraph: CodeGraph MCP/CLI
#
# Deliberately not included:
# - python3-pip: prefer uv / the Hermes venv; avoid PEP 668 friction
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
        libssl-dev; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

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
    chmod -R a+w "${RUSTUP_HOME}" "${CARGO_HOME}"

RUN set -eux; \
    npm install -g \
        @openai/codex \
        @colbymchenry/codegraph; \
    npm cache clean --force