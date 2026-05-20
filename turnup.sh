#!/usr/bin/env bash
#
# turnup.sh — bring the offline stack online.
#
#   MODE=docker (default)  Ollama runs as a container. CPU-only on macOS.
#   MODE=metal             Ollama runs natively on the host (Metal GPU).
#                          Only LiteLLM (and on-demand Aider) live in compose.
#
# Loads bundled Docker images from assets/images/*.tar (skipping any already
# present) and starts the compose stack. Idempotent.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

MODE="${MODE:-docker}"
export MODE

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

case "$MODE" in
  docker|metal) ;;
  *) warn "MODE must be 'docker' or 'metal' (got '$MODE')"; exit 1 ;;
esac
say "Mode: $MODE"

command -v docker >/dev/null || { warn "Docker not found. Install Docker Desktop first."; exit 1; }
docker compose version >/dev/null 2>&1 || { warn "Docker Compose v2 not available."; exit 1; }

# --- 1. Load bundled images, if any ------------------------------------------
# In metal mode we don't actually need the Ollama image, but loading it costs
# only disk I/O if the user already bundled it, so we don't bother filtering.
shopt -s nullglob
tars=(assets/images/*.tar)
shopt -u nullglob

if (( ${#tars[@]} == 0 )); then
  warn "No assets/images/*.tar found. Falling back to network pulls on 'compose up'."
else
  for tar in "${tars[@]}"; do
    refs="$(tar -xOf "$tar" manifest.json 2>/dev/null \
      | grep -o '"RepoTags":\[[^]]*\]' \
      | grep -oE '"[^"]+:[^"]+"' \
      | tr -d '"' || true)"
    all_present=1
    if [[ -z "$refs" ]]; then
      all_present=0
    else
      while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        if ! docker image inspect "$ref" >/dev/null 2>&1; then
          all_present=0
          break
        fi
      done <<<"$refs"
    fi
    if (( all_present )); then
      say "Image(s) from $tar already loaded; skipping."
    else
      say "Loading $tar"
      docker load -i "$tar"
    fi
  done
fi

# --- 2. Backend-specific prep ------------------------------------------------
if [[ "$MODE" == "docker" ]]; then
  if [[ ! -d assets/ollama-data/models ]] || [[ -z "$(ls -A assets/ollama-data/models 2>/dev/null || true)" ]]; then
    warn "assets/ollama-data/models is empty. Run ./bundle.sh on an online machine first,"
    warn "or 'docker compose exec ollama ollama pull qwen2.5-coder:14b' after start."
  fi
  COMPOSE_PROFILES=docker-backend
  EXPECTED_CONTAINERS=(claude-offline-ollama claude-offline-litellm)
else
  # metal mode
  command -v ollama >/dev/null || { warn "Native ollama not installed. Run: brew install ollama"; exit 1; }

  # Make ollama reachable from Docker containers. Default bind is loopback,
  # which host.docker.internal can't reach. launchctl setenv is persistent
  # for the user session.
  if [[ "$(launchctl getenv OLLAMA_HOST 2>/dev/null || true)" != "0.0.0.0:11434" ]]; then
    say "Setting OLLAMA_HOST=0.0.0.0:11434 (so containers can reach host ollama)."
    launchctl setenv OLLAMA_HOST 0.0.0.0:11434
    # If ollama was already running with the old bind, restart.
    brew services list 2>/dev/null | awk '$1=="ollama" && $2=="started" {found=1} END{exit !found}' \
      && { say "Restarting host ollama with new bind."; brew services restart ollama >/dev/null; } \
      || true
  fi

  if ! brew services list 2>/dev/null | awk '$1=="ollama" && $2=="started" {found=1} END{exit !found}'; then
    say "Starting host ollama..."
    brew services start ollama >/dev/null
  fi

  for _ in $(seq 1 30); do
    curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 \
    || { warn "Host ollama not responding on :11434"; exit 1; }
  say "Host ollama is up."

  # Seed ~/.ollama from the bundle if the model isn't on the host yet.
  if ! ollama list | awk '{print $1}' | grep -qx "qwen2.5-coder:14b"; then
    if [[ -d assets/ollama-data/models ]] && [[ -n "$(ls -A assets/ollama-data/models 2>/dev/null)" ]]; then
      say "Seeding ~/.ollama from assets/ollama-data (rsync)..."
      mkdir -p "$HOME/.ollama/models"
      rsync -a assets/ollama-data/models/ "$HOME/.ollama/models/"
      # Newly-rsynced manifests need ollama to re-scan; restart picks them up.
      brew services restart ollama >/dev/null
      for _ in $(seq 1 30); do
        curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
        sleep 1
      done
    else
      warn "Model not on host and no assets/ollama-data bundle to seed from."
      warn "Run: ollama pull qwen2.5-coder:14b"
      exit 1
    fi
  fi
  ollama list | awk '{print $1}' | grep -qx "qwen2.5-coder:14b" \
    || { warn "Model qwen2.5-coder:14b still not visible after seeding."; exit 1; }
  say "Host ollama has qwen2.5-coder:14b."

  COMPOSE_PROFILES=""
  EXPECTED_CONTAINERS=(claude-offline-litellm)
fi

# --- 3. Start the stack ------------------------------------------------------
say "Starting compose stack ($MODE mode)..."
COMPOSE_PROFILES="$COMPOSE_PROFILES" docker compose up -d

say "Waiting for services to report healthy..."
for _ in $(seq 1 60); do
  all_healthy=1
  for c in "${EXPECTED_CONTAINERS[@]}"; do
    h=$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo missing)
    if [[ "$h" != "healthy" ]]; then
      all_healthy=0
      break
    fi
  done
  (( all_healthy )) && break
  sleep 2
done

if ! (( all_healthy )); then
  warn "Services did not become healthy in time."
  for c in "${EXPECTED_CONTAINERS[@]}"; do
    h=$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo missing)
    warn "  $c: $h"
  done
  warn "Inspect with: docker compose logs"
  exit 1
fi

say "Stack is up:  http://127.0.0.1:4000 (litellm)"
[[ "$MODE" == "docker" ]] && say "             http://127.0.0.1:11434 (ollama, in container)"
[[ "$MODE" == "metal"  ]] && say "             http://127.0.0.1:11434 (ollama, host-native, Metal)"
echo
echo "  Use it inside any git repo:"
echo "      $REPO_ROOT/claude-offline"
echo
if [[ "$MODE" == "docker" ]]; then
  echo "  Tear down with:  COMPOSE_PROFILES=docker-backend docker compose down"
else
  echo "  Tear down with:  docker compose down"
  echo "                   (host ollama keeps running; 'brew services stop ollama' to halt it)"
fi
