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
#       aider.tar        (docker save, built locally, ~190 MB)
#     ollama-data/
#       models/...       (pre-pulled Ollama blobs, ~8.4 GB for 14b)
#
# Sources:
#   - ollama/ollama:0.4.7                  Docker Hub
#   - ghcr.io/berriai/litellm:main-stable  GitHub Container Registry
#   - qwen2.5-coder:14b                    registry.ollama.ai
#
# Re-runnable: skips images and model pulls that are already present.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

MODEL_SIZE="${MODEL_SIZE:-14b}"
BASE_MODEL="qwen2.5-coder:${MODEL_SIZE}"

OLLAMA_IMAGE="ollama/ollama:0.4.7"
LITELLM_IMAGE="ghcr.io/berriai/litellm:main-stable"
AIDER_IMAGE="claude-offline/aider:local"

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

say "Building $AIDER_IMAGE"
docker build -t "$AIDER_IMAGE" ./aider
save_image "$AIDER_IMAGE" assets/images/aider.tar

# --- 2. Pre-populate the Ollama model store ----------------------------------
# Run a throwaway ollama container against ./assets/ollama-data so the pulled
# blobs land in the repo, not in a docker-managed volume. Same dir gets mounted
# by the real `up` later.
say "Starting throwaway Ollama to pull $BASE_MODEL into assets/ollama-data"
docker rm -f claude-offline-bundle-ollama >/dev/null 2>&1 || true
docker run -d --rm \
  --name claude-offline-bundle-ollama \
  -v "$REPO_ROOT/assets/ollama-data:/root/.ollama" \
  -p 127.0.0.1:11500:11434 \
  "$OLLAMA_IMAGE" >/dev/null

cleanup() { docker rm -f claude-offline-bundle-ollama >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Wait for it to come up.
for _ in $(seq 1 60); do
  if docker exec claude-offline-bundle-ollama ollama list >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if docker exec claude-offline-bundle-ollama ollama list | awk '{print $1}' | grep -qx "$BASE_MODEL"; then
  say "Base model $BASE_MODEL already in assets/ollama-data."
else
  say "Pulling $BASE_MODEL (this can take a while)..."
  docker exec claude-offline-bundle-ollama ollama pull "$BASE_MODEL"
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
