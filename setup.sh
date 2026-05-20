#!/usr/bin/env bash
#
# claude-offline — set up a fully-offline, agentic coding assistant on macOS.
#
# Installs Ollama (local model runtime), pulls a coding model, gives it a
# large context window, and installs Aider (git-aware agentic CLI).
#
# Safe to re-run: every step is idempotent.
#
# Usage:
#   ./setup.sh              # default: qwen2.5-coder:14b
#   MODEL_SIZE=32b ./setup.sh   # stronger, slower (~20 GB, needs the RAM headroom)
#
set -euo pipefail

MODEL_SIZE="${MODEL_SIZE:-14b}"
BASE_MODEL="qwen2.5-coder:${MODEL_SIZE}"
CTX_MODEL="qwen2.5-coder-${MODEL_SIZE}-32k"   # our large-context variant
NUM_CTX="${NUM_CTX:-32768}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# --- 0. Sanity checks --------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "This script targets macOS. Continuing anyway, but paths may differ."
fi

if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found. Install it first: https://brew.sh"
  exit 1
fi

RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
say "Detected ${RAM_GB} GB RAM. Target model: ${BASE_MODEL}"
if [[ "$MODEL_SIZE" == "32b" && "$RAM_GB" -lt 28 ]]; then
  warn "32b model wants ~20 GB; ${RAM_GB} GB is tight. Consider MODEL_SIZE=14b."
fi

# --- 1. Ollama ---------------------------------------------------------------
if ! command -v ollama >/dev/null 2>&1; then
  say "Installing Ollama..."
  brew install ollama
else
  say "Ollama already installed."
fi

# Start the Ollama server as a background service if it isn't responding.
if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  say "Starting Ollama service..."
  brew services start ollama
  for _ in $(seq 1 30); do
    curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 1
  done
fi
curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 \
  && say "Ollama server is up." \
  || { warn "Ollama server not responding on :11434. Run 'ollama serve' manually."; exit 1; }

# --- 2. Pull the base model --------------------------------------------------
if ollama list | awk '{print $1}' | grep -qx "$BASE_MODEL"; then
  say "Model ${BASE_MODEL} already pulled."
else
  say "Pulling ${BASE_MODEL} (this can take a while)..."
  ollama pull "$BASE_MODEL"
fi

# --- 3. Build a large-context variant ---------------------------------------
# Local models default to a small context (~2-8k). Bump it so Aider can feed
# real codebases without silent truncation.
if ollama list | awk '{print $1}' | grep -qx "${CTX_MODEL}:latest"; then
  say "Large-context model ${CTX_MODEL} already exists."
else
  say "Creating ${CTX_MODEL} with num_ctx=${NUM_CTX}..."
  TMP_MODELFILE="$(mktemp)"
  cat > "$TMP_MODELFILE" <<EOF
FROM ${BASE_MODEL}
PARAMETER num_ctx ${NUM_CTX}
EOF
  ollama create "$CTX_MODEL" -f "$TMP_MODELFILE"
  rm -f "$TMP_MODELFILE"
fi

# --- 4. Aider (agentic coding CLI) ------------------------------------------
# Install via uv with its own managed Python. The Homebrew `aider` formula
# pins Homebrew's python@3.12, which on current macOS hits a pyexpat/libexpat
# symbol mismatch and crashes on startup. uv ships an isolated CPython build
# that sidesteps it (also Aider's officially recommended install path).
if ! command -v uv >/dev/null 2>&1; then
  say "Installing uv..."
  brew install uv
else
  say "uv already installed."
fi

UV_BIN="$HOME/.local/bin"
export PATH="$UV_BIN:$PATH"

if uv tool list 2>/dev/null | grep -qi '^aider-chat '; then
  say "Aider already installed via uv."
else
  say "Installing Aider (uv tool, isolated Python 3.12)..."
  uv tool install --python 3.12 aider-chat
fi

AIDER_BIN="$UV_BIN/aider"
if [[ ! -x "$AIDER_BIN" ]]; then
  warn "Aider binary not found at ${AIDER_BIN}; check 'uv tool list'."
  exit 1
fi
"$AIDER_BIN" --version >/dev/null 2>&1 \
  && say "Aider runs OK ($("$AIDER_BIN" --version))." \
  || { warn "Aider installed but fails to run. Inspect: $AIDER_BIN --version"; exit 1; }

# --- 5. Launcher -------------------------------------------------------------
LAUNCHER="$(cd "$(dirname "$0")" && pwd)/claude-offline"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# Launch the offline agentic coding assistant in the current git repo.
set -euo pipefail
export OLLAMA_API_BASE=http://127.0.0.1:11434
exec "${AIDER_BIN}" --model "ollama_chat/${CTX_MODEL}:latest" "\$@"
EOF
chmod +x "$LAUNCHER"

say "Done."
echo
echo "  Run it inside any git repo:"
echo "      ${LAUNCHER}"
echo
echo "  Or add it to your PATH and just type:  claude-offline"
echo
echo "  Switch model tiers by re-running:  MODEL_SIZE=32b ./setup.sh"
