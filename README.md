# claude-offline

A fully-offline, agentic coding assistant for macOS (Apple Silicon).

Local model via [Ollama](https://ollama.com) + the [Aider](https://aider.chat)
terminal CLI. No internet, no API keys — everything runs on the machine.

## Setup

```bash
./setup.sh                  # qwen2.5-coder:14b  (fast, ~9 GB)
MODEL_SIZE=32b ./setup.sh   # qwen2.5-coder:32b  (stronger, ~20 GB, needs the RAM)
```

The script is idempotent — safe to re-run. It:

1. Installs Ollama and starts it as a background service.
2. Pulls the coding model.
3. Builds a large-context variant (`num_ctx=32768`, override with `NUM_CTX`)
   so real codebases aren't silently truncated.
4. Installs Aider via `uv` with its own isolated Python 3.12.
   (The Homebrew `aider` formula's bundled Python currently hits a
   `pyexpat`/`libexpat` symbol mismatch on macOS and crashes — `uv` avoids it.)
5. Writes a `./claude-offline` launcher (gitignored — it embeds absolute paths).

## Use

Inside any git repo:

```bash
/path/to/claude-offline/claude-offline
```

Or add the launcher to your `PATH` and just run `claude-offline`.

## Notes

- A local 32B model is roughly an older mid-tier hosted model: good for
  refactors, boilerplate, and well-scoped changes; weaker at long-horizon
  reasoning and large contexts than a hosted frontier model.
- Requirements: macOS, Homebrew, ~10 GB free disk (14b) or ~22 GB (32b),
  and enough free RAM for the model (16 GB+ for 14b, 32 GB for 32b).
