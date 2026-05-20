# Aider, run-on-demand via `docker compose run --rm aider ...`.
# The launcher mounts the host repo at /workspace and points aider at the
# LiteLLM proxy via OPENAI_API_BASE.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    AIDER_VERSION=0.69.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip install "aider-chat==${AIDER_VERSION}"

# Aider writes config/cache into $HOME — give it a writable spot inside the
# mounted workspace by default.
ENV HOME=/workspace

WORKDIR /workspace

ENTRYPOINT ["aider"]
