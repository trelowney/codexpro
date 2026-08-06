# The Python 3.13 base image is required: hass-mcp does not install on 3.12.
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-python:3.13-alpine3.21
FROM ${BUILD_FROM}

LABEL org.opencontainers.image.title="Codex Pro for Home Assistant"
LABEL org.opencontainers.image.description="OpenAI Codex CLI in the Home Assistant sidebar, with persistent sessions, in-container updates and full config access"
LABEL org.opencontainers.image.licenses="MIT"

ENV \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

# Base tooling. bubblewrap is what the Codex sandbox uses for workspace-write mode.
RUN apk add --no-cache \
        bash \
        bubblewrap \
        ca-certificates \
        coreutils \
        curl \
        findutils \
        gawk \
        git \
        grep \
        jq \
        less \
        nano \
        ncurses \
        ncurses-terminfo-base \
        nodejs \
        npm \
        openssh-client \
        openssl \
        ripgrep \
        sed \
        tar \
        tmux \
        tree \
        vim \
        wget \
        yq \
    && update-ca-certificates

# ttyd: prefer the Alpine package, fall back to the upstream static binary.
ARG BUILD_ARCH
RUN if ! apk add --no-cache ttyd; then \
        case "${BUILD_ARCH:-amd64}" in \
            amd64)   TTYD_ARCH="x86_64" ;; \
            aarch64) TTYD_ARCH="aarch64" ;; \
            *)       echo "Unsupported arch for ttyd fallback: ${BUILD_ARCH}" && exit 1 ;; \
        esac; \
        curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" -o /usr/bin/ttyd && \
        chmod +x /usr/bin/ttyd; \
    fi && ttyd --version

# Codex CLI. The npm package ships prebuilt binaries for linux x64/arm64 only,
# which is why this add-on does not offer armv7/armhf.
RUN NPM_CONFIG_CACHE=/tmp/npm-cache npm install -g @openai/codex \
    && codex --version \
    && rm -rf /tmp/npm-cache

# Home Assistant MCP server (optional at runtime, controlled by enable_ha_mcp).
# One of its dependencies drops a stray pytest launcher at /usr/local/bin/test,
# which shadows coreutils' /usr/bin/test on PATH and is broken (pytest is not
# installed). Remove it so `test` keeps meaning what every script expects.
RUN pip3 install --no-cache-dir --break-system-packages hass-mcp \
    && rm -f /usr/local/bin/test

# Home Assistant CLI
RUN case "${BUILD_ARCH:-amd64}" in \
        amd64)   HA_ARCH="amd64" ;; \
        aarch64) HA_ARCH="aarch64" ;; \
        *)       HA_ARCH="amd64" ;; \
    esac && \
    HA_VERSION="$(curl -fsSL https://api.github.com/repos/home-assistant/cli/releases/latest | jq -r '.tag_name')" && \
    curl -fsSL -o /usr/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${HA_VERSION}/ha_${HA_ARCH}" && \
    chmod +x /usr/bin/ha

# GitHub CLI
RUN case "${BUILD_ARCH:-amd64}" in \
        amd64)   GH_ARCH="amd64" ;; \
        aarch64) GH_ARCH="arm64" ;; \
        *)       GH_ARCH="amd64" ;; \
    esac && \
    GH_VERSION="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name' | sed 's/^v//')" && \
    curl -fsSL -o /tmp/gh.tar.gz \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    mv "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/bin/gh && \
    chmod +x /usr/bin/gh && \
    rm -rf /tmp/gh*

# Image paste service (browser -> /data/images -> path pasted into the terminal)
COPY image-service/ /opt/image-service/
RUN cd /opt/image-service \
    && npm install --omit=dev --no-optional \
    && npm cache clean --force

COPY rootfs/ /
COPY run.sh /run.sh
RUN chmod +x /run.sh /usr/local/bin/*

WORKDIR /homeassistant

CMD ["/run.sh"]
