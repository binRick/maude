# maude

A fully-offline, agentic coding assistant — packaged as a Docker Compose stack
that turns up the same way on any machine, with or without internet.

## Features

- **One-command turnup.** `./turnup.sh` brings up the stack; `./maude`
  drops you into Aider against the local model. `./maude-cpu` and
  `./maude-gpu` are thin wrappers that preset the backend mode.
- **Two backend modes**, picked by `MODE=docker` (default) or `MODE=metal`:
  - `docker` — Ollama runs as a container. Single self-contained stack.
    CPU inference on macOS (Linux containers can't see Apple's Metal GPU).
    Saturates all cores during generation.
  - `metal` — Ollama runs natively on the macOS host with Metal/GPU
    acceleration. Roughly 5–10× faster generation on Apple Silicon and
    keeps the CPU idle. Only LiteLLM and Aider live in compose.
- **OpenAI-compatible endpoint** at `http://127.0.0.1:4000` via LiteLLM, so
  anything that speaks OpenAI (Aider, OpenWebUI, IDE plugins, custom
  scripts) just works against the local model.
- **Agentic coding via Aider**, run on demand in a sidecar container with
  the current directory mounted at `/workspace`. Files Aider writes land
  on the host with your UID (the launcher passes `--user $(id -u):$(id -g)`).
- **Reproducible offline turnup.** `./fetch-assets.sh` once on an online
  machine produces a self-contained `./assets/` tree (saved Docker images
  + Ollama model blobs); `./turnup.sh` on the offline machine then never
  touches the network. Idempotent — re-runnable, skips work already done.
- **Pinned versions** end to end — Ollama 0.4.7, LiteLLM main-stable, Aider
  0.69.1, Qwen 2.5 Coder 14B. Mode swaps don't change the model behaviour.
- **Local-only by design.** Both LiteLLM and Ollama bind to `127.0.0.1`.
  No telemetry, no outbound calls after fetch-assets completes.
- **Healthchecked.** Containers expose proper Docker healthchecks; turnup
  blocks until services report healthy before printing success.
- **Profile-scoped services.** Ollama lives in the `docker-backend`
  Compose profile so metal mode excludes it cleanly; Aider lives in the
  `cli` profile so it never runs on its own — only via the launcher.

## Tech stack

| Layer | Component | Pinned version | Role |
|---|---|---|---|
| Model | [Qwen 2.5 Coder 14B](https://ollama.com/library/qwen2.5-coder) | `qwen2.5-coder:14b` | Code-tuned 14B-parameter LLM. ~9 GB on disk, ~10 GiB resident. |
| Model server | [Ollama](https://ollama.com) | `ollama/ollama:0.4.7` | Loads the GGUF weights, exposes the Ollama HTTP API on :11434. Metal-aware on host; CPU-only in containers. |
| OpenAI shim | [LiteLLM](https://github.com/BerriAI/litellm) | `ghcr.io/berriai/litellm:main-stable` | Translates OpenAI `/v1/chat/completions` to Ollama's API. One LiteLLM config per backend mode (`config.docker.yaml`, `config.metal.yaml`). |
| Agent | [Aider](https://aider.chat) | `aider-chat==0.69.1` | Agentic git-aware editor. Runs in a `python:3.12-slim` sidecar built locally. |
| Orchestration | Docker Compose v2 | n/a | Single `docker-compose.yml`; services gated by profiles (`docker-backend`, `cli`) and the `MODE` env var. |
| Glue | Bash scripts | — | `fetch-assets.sh`, `turnup.sh`, `maude`, `maude-cpu`, `maude-gpu`. Tested with `set -euo pipefail`. |
| Asset storage | local filesystem (default) | — | `assets/` is gitignored. Git LFS patterns are pre-declared in `.gitattributes` if you want to vendor them. |

## Architecture

```mermaid
flowchart LR
    Dev([Developer]) --> Aider

    subgraph compose["Docker Compose stack"]
        direction LR
        Aider["Aider CLI<br/>on-demand sidecar<br/>profile: cli"]
        LiteLLM["LiteLLM proxy<br/>OpenAI v1 @ :4000"]
        Aider -- "OpenAI v1" --> LiteLLM
    end

    LiteLLM -. "MODE=docker" .-> OllamaC["Ollama container<br/>(CPU)"]
    LiteLLM -. "MODE=metal<br/>host.docker.internal" .-> OllamaH["Ollama on host<br/>(Metal GPU)"]

    OllamaC --> Model[("qwen2.5-coder:14b")]
    OllamaH --> Model

    classDef container fill:#e8f1fc,stroke:#5a8dc7,color:#0a2540
    classDef host fill:#fdf0e6,stroke:#c98140,color:#3a1f08
    class Aider,LiteLLM,OllamaC container
    class OllamaH host
```

## Prerequisites

- **Docker** Desktop (macOS, Windows) or Docker Engine (Linux), with Compose v2.
- For `MODE=metal`: macOS on Apple Silicon and `brew install ollama`.
- ~12 GB free disk for the 14b bundle.
- Enough free RAM for the model:
  - 16 GB+ for docker mode (CPU keeps weights in container memory).
  - 16 GB+ for metal mode (Metal shares unified memory with the CPU).

## Deployment guide

### 1. One-time asset fetch (needs internet)

The repo ships only code. Run the fetch script once on a machine with
internet to populate `./assets/`:

```bash
git clone git@github.com:binRick/maude.git
cd maude
./fetch-assets.sh
```

This will:

1. `docker pull` Ollama and LiteLLM at pinned versions, `docker build` Aider,
   and `docker save` each into `assets/images/*.tar` *immediately* after pull
   (Docker Desktop's auto-GC otherwise eats unsaved images during step 2).
2. Spin up a throwaway Ollama with `assets/ollama-data/` mounted and
   `ollama pull qwen2.5-coder:14b`, so all the model blobs land in the repo.

End state: `assets/` is ~11 GB (2.9 GB images + 8.4 GB model). The repo's
`.gitignore` skips `assets/` by default; see "Storage notes" below for
options if you want to vendor it.

### 2. Bring the stack up

```bash
./turnup.sh                  # docker mode (default, CPU on Mac)
MODE=metal ./turnup.sh       # metal mode (Apple GPU)
```

`turnup.sh` is idempotent:

- Loads any `assets/images/*.tar` not already in Docker (`docker load`).
- In docker mode: starts the `docker-backend` compose profile (ollama +
  litellm).
- In metal mode: sets `OLLAMA_HOST=0.0.0.0:11434` via `launchctl setenv`
  so containers can reach the host, starts `brew services ollama`,
  rsync-seeds `~/.ollama` from `assets/ollama-data/` if the model isn't
  already on the host, then starts just litellm.
- Waits for healthchecks before reporting success.

### 3. Use Aider against the local model

```bash
# inside any git repo — default (docker mode, CPU)
/path/to/maude/maude

# convenience wrappers
/path/to/maude/maude-cpu        # MODE=docker (container Ollama)
/path/to/maude/maude-gpu        # MODE=metal  (host Ollama, Apple GPU)
```

The launcher starts the backend if it isn't running, then runs Aider in a
one-shot container with the current directory mounted at `/workspace`.
Add the launcher to your `PATH` and just type `maude` (or `maude-gpu`).

### 4. Tear down

```bash
# docker mode — ollama lives in compose, include the profile when stopping
COMPOSE_PROFILES=docker-backend docker compose down

# metal mode — only litellm is in compose; host ollama keeps running
docker compose down
brew services stop ollama   # if you also want to stop host ollama
```

## OpenAI-compatible endpoint

LiteLLM exposes one model name, `qwen-coder`, at `http://127.0.0.1:4000`.
Use it from anything that speaks OpenAI:

```bash
curl -sS http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-maude-local" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen-coder","messages":[{"role":"user","content":"hi"}]}'
```

The `sk-maude-local` key is set in `litellm/config.*.yaml`. The
proxy is bound to `127.0.0.1` only; the key is defence-in-depth, not a
secret.

## Layout

```
.
├── docker-compose.yml          # ollama (profile: docker-backend) + litellm + aider (profile: cli)
├── litellm/
│   ├── config.docker.yaml      # api_base http://ollama:11434
│   └── config.metal.yaml       # api_base http://host.docker.internal:11434
├── aider/Dockerfile            # python:3.12-slim + pinned aider-chat
├── fetch-assets.sh             # online: pull & save images, prefetch model blobs
├── turnup.sh                   # offline: docker load + compose up (MODE-aware)
├── maude                       # launcher: docker compose run --rm aider …
├── maude-cpu                   # wrapper: MODE=docker maude …
├── maude-gpu                   # wrapper: MODE=metal  maude …
├── .gitattributes              # LFS patterns (not active unless you enable LFS)
└── assets/                     # (gitignored by default)
    ├── images/*.tar
    └── ollama-data/
```

## Storage notes

`assets/` is gitignored by default because plain git doesn't handle multi-GB
blobs and GitHub's free LFS quota is 1 GB. Three options if you want a
truly clone-and-run repo:

1. **Re-run `./fetch-assets.sh` on each new machine.** Default. Needs internet
   on first turnup; cheap and simple.
2. **Enable Git LFS.** `.gitattributes` already lists the right patterns
   (`assets/images/*.tar`, `assets/ollama-data/models/blobs/**`). Run
   `git lfs install`, remove the `assets/` line from `.gitignore`, then add
   and commit. Needs paid GitHub LFS for any real use (free quota is 1 GB
   storage / 1 GB bandwidth per month and a 14b bundle is ~11 GB).
3. **Host assets elsewhere.** Push `assets/` to S3 / R2 / HuggingFace / a
   GitHub Release. Extend `fetch-assets.sh` with a download path that pulls
   from your bucket when an env var like `MAUDE_ASSETS_URL` is set.

## Troubleshooting

**`no space left on device` during fetch.** The Mac is full, not Docker.
Check `df -h /`. The Ollama image ships ~2 GB of NVIDIA CUDA libraries that
go nowhere useful on Apple Silicon but still need disk to extract. Free
host space, then retry — `fetch-assets.sh` resumes where it left off.

**`model requires more system memory than is available`.** The 14b model
at large context windows can exceed the Docker VM's RAM allocation
(~30 GiB on a 32 GB Mac). Either switch to `MODE=metal` (uses host memory
directly) or raise Docker Desktop → Settings → Resources → Memory.

**Generation feels glacial in docker mode.** Expected — Linux containers
can't reach the Apple GPU. Switch to `MODE=metal`.

**Container ollama isn't visible to `docker compose down`.** It's
profile-scoped. Either `COMPOSE_PROFILES=docker-backend docker compose down`
or `docker rm -f maude-ollama`.

**LiteLLM in metal mode can't reach the host.** `turnup.sh` sets
`OLLAMA_HOST=0.0.0.0:11434` via `launchctl setenv` and restarts the brew
service so it picks up the new bind. If you started Ollama some other way,
make sure it's not bound to loopback only.

## Notes

- The 14b model is roughly an older mid-tier hosted model: solid for
  refactors, boilerplate, and well-scoped changes; weaker at long-horizon
  reasoning than a hosted frontier model.
- Both LiteLLM and host-mode Ollama bind to `0.0.0.0` internally but only
  the loopback interface is mapped — your macOS firewall still gates any
  inbound traffic; this stack is local-only.
- No telemetry. No outbound calls after `fetch-assets.sh` finishes.
