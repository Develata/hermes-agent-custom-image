ARG UPSTREAM_IMAGE=nousresearch/hermes-agent:latest

FROM ${UPSTREAM_IMAGE}

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       gh \
       python3-pip \
       jq \
       unzip \
       fd-find \
       fzf \
       bat \
       eza \
       tree \
       htop \
       tmux \
       vim \
    && if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then \
       ln -s "$(command -v fdfind)" /usr/local/bin/fd; \
       fi \
    && if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then \
       ln -s "$(command -v batcat)" /usr/local/bin/bat; \
       fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
