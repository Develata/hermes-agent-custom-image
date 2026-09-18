ARG UPSTREAM_IMAGE=nousresearch/hermes-agent:latest

FROM ${UPSTREAM_IMAGE}

USER root

# Upstream Hermes image already includes ca-certificates, curl, python3,
# git, openssh-client, docker-cli, node 26, npm, uv, ripgrep, ffmpeg,
# gcc/python3-dev/libffi-dev, procps, and xz-utils. Keep this layer only
# for Develata-specific tools that are not part of the base image.
#
# Keep:
# - gh: GitHub workflow automation
# - jq: small JSON inspection in shell scripts
# - unzip: archive handling for user-supplied artifacts
# - rclone: OpenList/WebDAV transfer helper; use copy/sync by default,
#   not FUSE mount
# - git-lfs: Git Large File Storage support for repositories under /opt/gitclone
# - Docker Compose CLI plugin: render/validate Compose files with
#   `docker compose config`; no Docker daemon or socket is included
# - pkg-config/libssl-dev: native metadata/headers for small Rust crates that
#   compile OpenSSL bindings; upstream already provides gcc/g++/make/cmake
# - Rust minimal stable toolchain: local smoke tests and small scripts only;
#   GitHub Actions remains the authoritative CI environment
# - Elan + pinned stable Lean 4: direct Lean/Lake work while preserving each
#   project's lean-toolchain selection; Mathlib stays project-local
# - Tectonic: pinned single-binary TeX/LaTeX compiler; support files are
#   downloaded and cached on demand instead of baking in a full TeX Live tree
# - Bun: pinned JavaScript runtime/package manager for custom global CLI installs
# - @colbymchenry/codegraph: CodeGraph MCP/CLI
# - @jackwener/opencli: website/browser/local-tool CLI hub for agents
# - Agent Reach: internet capability installer/doctor, isolated via uv tool
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
        git-lfs \
        pkg-config \
        sshpass \
        libssl-dev; \
    git lfs install --system --skip-repo; \
    git lfs version; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Install Bun from the pinned official release asset and verify its SHA-256.
# Avoid executing a mutable remote install script during the image build.
# Global Bun packages and their command shims live under /usr/local.
# Runtime Bun global installs belong on the durable Hermes data volume. The
# build-time preinstalled CLIs override these variables inline to /usr/local.
ENV BUN_INSTALL=/opt/data/.bun \
    BUN_INSTALL_BIN=/opt/data/.local/bin \
    BUN_INSTALL_GLOBAL_DIR=/opt/data/.bun/install/global

ARG BUN_VERSION=1.4.2
ARG BUN_X86_64_SHA256=36368faef7527875d5ffa52e53cd48021741f2a83eb6208a8dd64068d422a913
ARG BUN_AARCH64_SHA256=54328bbc2d9c8e0c9f892c544d66c57a83b84139e34909e5ee81758f1ac8fda7

RUN set -eux; \
    case "$(uname -m)" in \
        x86_64) bun_target=linux-x64; bun_sha256="${BUN_X86_64_SHA256}" ;; \
        aarch64) bun_target=linux-aarch64; bun_sha256="${BUN_AARCH64_SHA256}" ;; \
        *) echo "unsupported Bun platform: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    bun_archive="/tmp/bun-${bun_target}.zip"; \
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
        "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-${bun_target}.zip" \
        -o "${bun_archive}"; \
    printf '%s  %s\n' "${bun_sha256}" "${bun_archive}" | sha256sum -c -; \
    rm -rf /tmp/bun-extract; \
    unzip -q "${bun_archive}" -d /tmp/bun-extract; \
    install -m 0755 "/tmp/bun-extract/bun-${bun_target}/bun" /usr/local/bin/bun; \
    bun --version | grep -Fx "${BUN_VERSION}"; \
    rm -rf "${bun_archive}" /tmp/bun-extract

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
    CARGO_TERM_COLOR=always

ARG RUST_TOOLCHAIN=stable

RUN set -eux; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        -o /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh -y \
        --no-modify-path \
        --profile minimal \
        --default-toolchain "${RUST_TOOLCHAIN}"; \
    "${CARGO_HOME}/bin/rustup" component add rustfmt clippy; \
    "${CARGO_HOME}/bin/rustup" --version; \
    "${CARGO_HOME}/bin/rustc" --version; \
    "${CARGO_HOME}/bin/cargo" --version; \
    for rust_bin in cargo rustc rustup rustfmt cargo-clippy clippy-driver; do \
        test ! -e "${CARGO_HOME}/bin/${rust_bin}" || ln -sf "${CARGO_HOME}/bin/${rust_bin}" "/usr/local/bin/${rust_bin}"; \
    done; \
    printf '%s\n' \
        'export RUSTUP_HOME=/usr/local/rustup' \
        'export CARGO_HOME=/usr/local/cargo' \
        'export CARGO_TERM_COLOR=always' \
        > /etc/profile.d/rust.sh; \
    chmod 0644 /etc/profile.d/rust.sh; \
    rm -f /tmp/rustup-init.sh; \
    if id hermes >/dev/null 2>&1; then \
        chown -R hermes:hermes "${RUSTUP_HOME}" "${CARGO_HOME}"; \
    fi; \
    chmod -R u+rwX,go+rX,go-w "${RUSTUP_HOME}" "${CARGO_HOME}"

# Elan follows each project's checked-in lean-toolchain file and falls back to
# this pinned stable Lean release outside a project. Keep ELAN_HOME outside the
# /opt/data bind mount so the default toolchain remains part of the image.
ENV ELAN_HOME=/usr/local/elan

ARG ELAN_VERSION=4.2.3
ARG LEAN_TOOLCHAIN=leanprover/lean4:v4.32.0
ARG ELAN_X86_64_SHA256=df0b2b3a439961ffcbb3985214365ffe40f49bc871df04dff268c7d8e21ca8b2
ARG ELAN_AARCH64_SHA256=cb69af0803b04157bc30201c29c12fca882bb3ad8b43476b8d2d3064810bc3ac

RUN set -eux; \
    case "$(uname -m)" in \
        x86_64) elan_target=x86_64-unknown-linux-gnu; elan_sha256="${ELAN_X86_64_SHA256}" ;; \
        aarch64) elan_target=aarch64-unknown-linux-gnu; elan_sha256="${ELAN_AARCH64_SHA256}" ;; \
        *) echo "unsupported Elan platform: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    elan_archive="/tmp/elan-${elan_target}.tar.gz"; \
    curl --proto '=https' --tlsv1.2 -fsSL \
        "https://github.com/leanprover/elan/releases/download/v${ELAN_VERSION}/elan-${elan_target}.tar.gz" \
        -o "${elan_archive}"; \
    printf '%s  %s\n' "${elan_sha256}" "${elan_archive}" | sha256sum -c -; \
    tar -xzf "${elan_archive}" -C /tmp elan-init; \
    /tmp/elan-init -y \
        --no-modify-path \
        --default-toolchain "${LEAN_TOOLCHAIN}"; \
    "${ELAN_HOME}/bin/elan" --version | grep -F "elan ${ELAN_VERSION}"; \
    "${ELAN_HOME}/bin/lean" --version | grep -F 'Lean (version 4.32.0'; \
    "${ELAN_HOME}/bin/lake" --version; \
    for lean_bin in elan lean leanc lake; do \
        test ! -e "${ELAN_HOME}/bin/${lean_bin}" || ln -sf "${ELAN_HOME}/bin/${lean_bin}" "/usr/local/bin/${lean_bin}"; \
    done; \
    printf '%s\n' \
        'export ELAN_HOME=/usr/local/elan' \
        > /etc/profile.d/lean.sh; \
    chmod 0644 /etc/profile.d/lean.sh; \
    rm -f "${elan_archive}" /tmp/elan-init; \
    if id hermes >/dev/null 2>&1; then \
        chown -R hermes:hermes "${ELAN_HOME}"; \
    fi; \
    chmod -R u+rwX,go+rX,go-w "${ELAN_HOME}"

# Tectonic is a real TeX/LaTeX compiler, unlike Typst, but remains a small
# static binary. It fetches TeX support files on demand into the user's cache.
ARG TECTONIC_VERSION=0.16.9
ARG TECTONIC_X86_64_SHA256=60b13a0826ae7ad9ce34b4a2df06bff2cfcfa6dda8a915477c0cbb84e1a4a902
ARG TECTONIC_AARCH64_SHA256=f9aa39017dbd51f111fdb93dda222178cbe51c8193508fc567b523cc74fff9c1

RUN set -eux; \
    case "$(uname -m)" in \
        x86_64) tectonic_target=x86_64-unknown-linux-musl; tectonic_sha256="${TECTONIC_X86_64_SHA256}" ;; \
        aarch64) tectonic_target=aarch64-unknown-linux-musl; tectonic_sha256="${TECTONIC_AARCH64_SHA256}" ;; \
        *) echo "unsupported Tectonic platform: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    tectonic_archive="/tmp/tectonic-${tectonic_target}.tar.gz"; \
    curl --proto '=https' --tlsv1.2 -fsSL \
        "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic@${TECTONIC_VERSION}/tectonic-${TECTONIC_VERSION}-${tectonic_target}.tar.gz" \
        -o "${tectonic_archive}"; \
    printf '%s  %s\n' "${tectonic_sha256}" "${tectonic_archive}" | sha256sum -c -; \
    tar -xzf "${tectonic_archive}" -C /usr/local/bin tectonic; \
    chmod 0755 /usr/local/bin/tectonic; \
    tectonic --version | grep -F "Tectonic ${TECTONIC_VERSION}"; \
    rm -f "${tectonic_archive}"

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

ARG CODEGRAPH_VERSION=1.6.0
ARG AGENTLY_CLI_VERSION=1.0.18
ARG OPENCLI_VERSION=1.8.7

# Keep trusted lifecycle scripts for these explicitly selected CLIs, but pin
# the top-level versions so a rebuild cannot silently move to a new release.
# Use a throwaway HOME so package postinstall scripts cannot bake root-owned
# user configuration such as /root/.opencli into the image.
RUN set -eux; \
    install -d -m 0700 /tmp/bun-global-home; \
    HOME=/tmp/bun-global-home \
    BUN_INSTALL=/usr/local/bun \
    BUN_INSTALL_BIN=/usr/local/bin \
    BUN_INSTALL_GLOBAL_DIR=/usr/local/bun/install/global \
    bun add -g --trust \
        "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" \
        "@tencent-qqmail/agently-cli@${AGENTLY_CLI_VERSION}" \
        "@jackwener/opencli@${OPENCLI_VERSION}"; \
    command -v codegraph; \
    command -v agently-cli; \
    command -v opencli; \
    rm -rf /tmp/bun-global-home; \
    BUN_INSTALL=/usr/local/bun bun pm cache rm

# Agent Reach is a Python CLI, so keep it isolated from Hermes' own venv with
# uv tool. Pin the exact upstream revision rather than installing the unrelated
# PyPI project with the same name. Expose yt-dlp from the same tool environment
# because Agent Reach treats it as a core upstream CLI.
ARG AGENT_REACH_REV=a19a171fa980a0785849596492e0af4db800c82f

RUN set -eux; \
    command -v opencli; \
    UV_TOOL_DIR=/usr/local/share/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install --python /usr/bin/python3 \
        --with-executables-from yt-dlp \
        "git+https://github.com/Panniantong/Agent-Reach.git@${AGENT_REACH_REV}"; \
    command -v agent-reach; \
    command -v yt-dlp; \
    agent-reach version

COPY --chmod=0755 scripts/smoke-image.sh /usr/local/bin/hermes-custom-image-smoke
