# maude-webterm — a web terminal that runs opencode against the local stack.
#
# Composition:
#   - debian:bookworm-slim base
#   - ttyd (single static Go binary) serving an xterm.js front-end on :7681
#   - opencode installed globally via npm
#   - start.sh wires ttyd's xterm theme to the maude palette and exec's opencode
#
# The container bind-mounts the host workspace ($WORKSPACE) into /workspace
# and runs as the host UID/GID, so files edited through the web terminal end
# up owned by the host user — same on-disk result as ./maude.

FROM debian:bookworm-slim

ARG TTYD_VERSION=1.7.7
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_MAJOR=20

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git bash unzip jq tini procps \
      gnupg \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install ttyd from upstream releases.
RUN case "${TARGETARCH:-arm64}" in \
      amd64) ttyd_arch=x86_64 ;; \
      arm64) ttyd_arch=aarch64 ;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2 ; exit 1 ;; \
    esac && \
    curl -fL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ttyd_arch}" \
      -o /usr/local/bin/ttyd && \
    chmod 0755 /usr/local/bin/ttyd && \
    /usr/local/bin/ttyd --version

# Install opencode globally. npm publishes platform-specific native binaries
# behind the `opencode-ai` package, so this resolves to the right linux build.
RUN npm install -g opencode-ai \
    && opencode --version || true

# /workspace is the bind-mount point. We pre-create it so a container without
# a mount still has a writable cwd. HOME is set to /workspace at runtime so
# opencode writes its state alongside the user's other tooling.
RUN install -d -m 0777 /workspace /etc/maude

COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh

EXPOSE 7681
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start.sh"]
