#!/usr/bin/env bash
#
# fetch-assets.sh — populate ./assets/ from upstream sources.
#
# The repo ships only code; the heavy binaries (multi-GB Docker images +
# model weights) live outside git. Run this once on a machine with internet
# access and you have everything needed for fully-offline ./turnup.sh:
#
#   assets/
#     images/
#       ollama.tar       (docker save, ~2.3 GB)
#       litellm.tar      (docker save, ~373 MB)
#       open-webui.tar   (docker save, ~1.5 GB)
#       webterm.tar      (docker save, ~600 MB — locally-built ttyd + opencode)
#       nginx.tar        (docker save, ~50 MB — launcher front-end)
#     ollama-data/
#       models/...       (pre-pulled Ollama blobs, ~19 GB for qwen3-coder:30b)
#
# The agent (OpenCode) is a separate native install (brew install
# anomalyco/tap/opencode); it isn't bundled here. See the README.
#
# Sources:
#   - ollama/ollama:0.4.7                       Docker Hub
#   - ghcr.io/berriai/litellm:main-stable       GitHub Container Registry
#   - ghcr.io/open-webui/open-webui:main        GitHub Container Registry
#   - qwen3-coder:30b                           registry.ollama.ai
#
# Re-runnable: skips images and model pulls that are already present.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

MODEL_SIZE="${MODEL_SIZE:-30b}"
BASE_MODEL="qwen3-coder:${MODEL_SIZE}"

OLLAMA_IMAGE="ollama/ollama:0.4.7"
LITELLM_IMAGE="ghcr.io/berriai/litellm:main-stable"
WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
WEBTERM_IMAGE="maude-webterm:local"
NGINX_IMAGE="nginx:alpine"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

command -v docker >/dev/null || { warn "Docker not found. Install Docker Desktop first."; exit 1; }

mkdir -p assets/images assets/ollama-data

# --- 1. Pull/build + IMMEDIATELY save each image -----------------------------
# We save right after each pull so Docker Desktop's automatic image GC, which
# can fire during the multi-minute model pull below, can't delete an image we
# haven't checkpointed to disk yet.
save_image() {
  local image="$1" out="$2"
  if [[ -s "$out" ]]; then
    say "Saved image already present: $out"
  else
    say "Saving $image -> $out"
    docker save "$image" -o "$out"
  fi
}

say "Pulling $OLLAMA_IMAGE"
docker pull "$OLLAMA_IMAGE"
save_image "$OLLAMA_IMAGE" assets/images/ollama.tar

say "Pulling $LITELLM_IMAGE"
docker pull "$LITELLM_IMAGE"
save_image "$LITELLM_IMAGE" assets/images/litellm.tar

say "Pulling $WEBUI_IMAGE"
docker pull "$WEBUI_IMAGE"
save_image "$WEBUI_IMAGE" assets/images/open-webui.tar

say "Pulling $NGINX_IMAGE"
docker pull "$NGINX_IMAGE"
save_image "$NGINX_IMAGE" assets/images/nginx.tar

# webterm is built locally from ./webterm/Dockerfile — there's no upstream
# pull. The build itself reaches out to deb.nodesource.com, the npm registry,
# and the ttyd GitHub release, so it still counts as the "online step" for
# this image. Subsequent ./turnup.sh runs use the saved tar offline.
say "Building $WEBTERM_IMAGE from ./webterm"
docker compose build webterm
save_image "$WEBTERM_IMAGE" assets/images/webterm.tar

# --- 2. Pre-populate the Ollama model store ----------------------------------
# Run a throwaway ollama container against ./assets/ollama-data so the pulled
# blobs land in the repo, not in a docker-managed volume. Same dir gets mounted
# by the real `up` later.
say "Starting throwaway Ollama to pull $BASE_MODEL into assets/ollama-data"
docker rm -f maude-bundle-ollama >/dev/null 2>&1 || true
docker run -d --rm \
  --name maude-bundle-ollama \
  -v "$REPO_ROOT/assets/ollama-data:/root/.ollama" \
  -p 127.0.0.1:11500:11434 \
  "$OLLAMA_IMAGE" >/dev/null

cleanup() { docker rm -f maude-bundle-ollama >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Wait for it to come up.
for _ in $(seq 1 60); do
  if docker exec maude-bundle-ollama ollama list >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if docker exec maude-bundle-ollama ollama list | awk '{print $1}' | grep -qx "$BASE_MODEL"; then
  say "Base model $BASE_MODEL already in assets/ollama-data."
else
  say "Pulling $BASE_MODEL (this can take a while)..."
  docker exec maude-bundle-ollama ollama pull "$BASE_MODEL"
fi

cleanup
trap - EXIT

say "Done."
echo
echo "  Asset tree:"
du -sh assets/images/*.tar assets/ollama-data 2>/dev/null || true
echo
echo "  Bring the stack up:   ./turnup.sh             (docker mode, CPU)"
echo "                        MODE=metal ./turnup.sh  (host ollama, Apple GPU)"
