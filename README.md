# maude

**Real agentic coding, fully on your laptop.**

<sub>**no cloud** · **no Claude** · **no API key** · **no internet** · **no bill at the end of the month**</sub>

A coding agent that reads, writes, greps, and shells against your codebase
— and never phones home. Open-weight model on your own GPU, structured
tool calls for real file edits, the whole stack in one repo. After the
first asset fetch, the network cable can come out.

- **No cloud.** Nothing leaves the machine. No API rate limits, no
  proxy in front of your code, no trust handed to a vendor's data
  retention policy.
- **No Claude.** No OpenAI. No Gemini. The whole inference pipeline is
  Qwen 3 Coder 30B-A3B running on your own Apple Silicon (or any GPU
  Ollama supports).
- **Offline.** Run `./fetch-assets.sh` once with internet to bundle the
  images and model. After that, `./turnup.sh` boots the whole stack with
  zero outbound calls. No telemetry. No update pings.
- **$0/month.** Hosted coding agents bill per million tokens. maude bills
  electricity. A long refactor session is cents.

It is not Claude Opus. It will not one-shot a multi-file migration on a
new codebase. But for short, well-scoped agentic edits — write this file,
fix this bug, refactor this function, scaffold this test — it is *good
enough that you actually use it*, and it costs nothing to run.

## Features

- **One-command turnup.** `./turnup.sh` brings up the LiteLLM + Ollama
  backend; `./maude` launches OpenCode against the local model.
  `./maude-cpu` and `./maude-gpu` are thin wrappers that preset the backend
  mode.
- **Two backend modes**, picked by `MODE=docker` (default) or `MODE=metal`:
  - `docker` — Ollama runs as a container. Single self-contained stack.
    CPU inference on macOS (Linux containers can't see Apple's Metal GPU).
    Saturates all cores during generation.
  - `metal` — Ollama runs natively on the macOS host with Metal/GPU
    acceleration. Roughly 5–10× faster generation on Apple Silicon and
    keeps the CPU idle. Only LiteLLM lives in compose.
- **OpenAI-compatible endpoint** at `http://127.0.0.1:4000` via LiteLLM,
  so non-agent clients (curl, IDE plugins, custom scripts) work against
  the local model without code changes.
- **Built-in chat UI** at `http://127.0.0.1:3000` via Open WebUI, wired
  directly into LiteLLM as a plain OpenAI provider. Same model, same key,
  no separate config — useful for prompt exploration and quick chats
  alongside agentic editing. Branded `maude`, auth disabled (loopback-only
  bind), offline mode on.
- **Three ways to drive opencode.** Native TUI (`./maude`), browser
  terminal (`http://127.0.0.1:7681`, ttyd serving an xterm.js front-end),
  and the Open WebUI chat at :3000 for non-agentic prompting. The
  browser terminal is a real PTY — same opencode, same tool calls, same
  on-disk edits — just rendered through xterm.js in a tab.
- **Agentic coding via OpenCode**, a single static binary. OpenCode talks
  directly to Ollama's `/v1` endpoint (bypassing LiteLLM — see Architecture
  for why) and uses real structured function-calling: the model can
  `write`, `edit`, `bash`, `read`, `grep`, etc. against your CWD.
- **Reproducible offline turnup.** `./fetch-assets.sh` once on an online
  machine produces a self-contained `./assets/` tree (saved Docker images
  + Ollama model blobs); `./turnup.sh` on the offline machine then never
  touches the network. Idempotent — re-runnable, skips work already done.
- **Pinned versions** end to end — `ollama/ollama:0.4.7` (container image,
  docker mode), LiteLLM main-stable, OpenCode (`anomalyco/tap`), Qwen 3
  Coder 30B-A3B (MoE). Host-side Ollama in metal mode tracks whatever
  Homebrew ships (currently ~0.20.x), since it's a separate install path;
  the model itself is pinned the same way either way, so behaviour doesn't
  shift with the host version.
- **Local-only by design.** Both LiteLLM and Ollama bind to `127.0.0.1`.
  No telemetry, no outbound calls after fetch-assets completes.
- **Healthchecked.** Containers expose proper Docker healthchecks; turnup
  blocks until services report healthy before printing success.
- **Profile-scoped services.** Ollama lives in the `docker-backend`
  Compose profile so metal mode excludes it cleanly.

## Tech stack

| Layer | Component | Pinned version | Role |
|---|---|---|---|
| Model | [Qwen 3 Coder 30B-A3B](https://ollama.com/library/qwen3-coder) | `qwen3-coder:30b` | MoE coder model — 30 B total / 3.3 B active per token. ~19 GB on disk, 256 k native context, designed for function-calling and agentic tool use. |
| Model server | [Ollama](https://ollama.com) | `ollama/ollama:0.4.7` (container, docker mode) · Homebrew `ollama` (host, metal mode) | Loads the GGUF weights, exposes the Ollama HTTP API on :11434. Metal-aware on host; CPU-only in containers. The container image is pinned for reproducible offline turnup; the host install is whatever `brew install ollama` gives you. |
| OpenAI shim | [LiteLLM](https://github.com/BerriAI/litellm) | `ghcr.io/berriai/litellm:main-stable` | Exposes OpenAI v1 at :4000 for clients that don't need tool calling (curl, IDE plugins, Open WebUI). OpenCode bypasses this and talks to Ollama's `/v1` directly because of a [LiteLLM bug forwarding `tool_calls`](https://github.com/BerriAI/litellm/issues/19742). |
| Chat UI | [Open WebUI](https://github.com/open-webui/open-webui) | `ghcr.io/open-webui/open-webui:main` | Browser chat front-end at :3000. Configured as a LiteLLM client (`OPENAI_API_BASE_URLS=http://litellm:4000/v1`) with Ollama auto-integration off, so all traffic flows through the same canonical path. Auth and signup disabled (loopback bind); `OFFLINE_MODE=True` to suppress update checks and embedding-model downloads. |
| Web terminal | [ttyd](https://github.com/tsl0922/ttyd) + [fzf](https://github.com/junegunn/fzf) + opencode | `ttyd 1.7.7` · `fzf 0.38` (in `maude-webterm:local`) | Single Go binary serving an xterm.js front-end on :7681. Each connection runs `launcher.sh`: maude banner → fzf directory picker over `$WORKSPACE` (git repos first) → `exec opencode`. Bind-mounts `${WORKSPACE:-$HOME}` and runs as the host UID/GID so file edits land owned by the host user. Theme tokens mirror `webui/maude.css`. |
| Agent | [OpenCode](https://opencode.ai) | host: `anomalyco/tap/opencode` · container: `opencode-ai` (npm) | Native static binary in host mode (`./maude`); npm-installed Linux build in `maude-webterm` for the browser terminal. Same `opencode.json` schema, same model, same tool calls — only the baseURL differs (`127.0.0.1`, `ollama`, or `host.docker.internal`) depending on where opencode is running. |
| Orchestration | Docker Compose v2 | n/a | Single `docker-compose.yml`; the `docker-backend` profile gates the in-container Ollama. |
| Glue | Bash scripts | — | `fetch-assets.sh`, `turnup.sh`, `maude`, `maude-cpu`, `maude-gpu`. Tested with `set -euo pipefail`. |
| Asset storage | local filesystem (default) | — | `assets/` is gitignored. Git LFS patterns are pre-declared in `.gitattributes` if you want to vendor them. |

## About the model — Qwen 3 Coder 30B-A3B

**Maker.** [Alibaba Cloud's Qwen team](https://qwenlm.github.io/). The
Qwen 3 series launched in April 2025; the code-specialised
**Qwen3-Coder-30B-A3B-Instruct** variant followed on July 31, 2025.
Apache-2.0 weights via Hugging Face and the Ollama registry.

**Architecture.** Mixture-of-Experts (MoE): **30 B total parameters but
only ~3.3 B activated per token** — 128 experts, 8 selected per token via
a learned router, across 48 transformer layers with Grouped Query
Attention. The MoE design means generation speed roughly matches a dense
3.3 B model while quality matches a much larger dense model.

**Why it replaced Qwen 2.5 Coder here.** Qwen 2.5 Coder didn't reliably
emit structured OpenAI-style `tool_calls` over the Ollama API — it would
write tool invocations as markdown-fenced JSON in the response body, which
OpenCode can't execute. Qwen 3 Coder was designed for "function calls,
browser use, and structured code completion" and works with OpenCode,
Cline, Claude Code, and similar agents out of the box.

**Capabilities.**

- Native **function calling** in the OpenAI tool-use schema — the part
  that makes file-editing agents actually edit files.
- Code generation, completion, repair across many languages.
- 256 k **native** context window (limited to 32 k by `opencode.json` here
  so it fits comfortably in the Docker VM's RAM ceiling).
- "Thinking" and "non-thinking" modes switchable in-prompt — useful for
  multi-step planning vs. fast turn-around.
- Score 20 on the Artificial Analysis Intelligence Index — above average
  for open-weight non-reasoning models of similar size.

### How does it compare to Claude Opus?

Honest answer: it's a different weight class, and the framing depends on
what you're measuring.

| Dimension | Qwen 3 Coder 30B-A3B (local) | Claude Opus 4.7 (hosted) |
|---|---|---|
| Parameters | 30 B total / 3.3 B active per token (MoE, open weights) | not disclosed; orders of magnitude larger |
| Where it runs | Your laptop, offline, no API key | Anthropic API, paid, requires internet |
| Native tool / function calling | Yes (the whole reason it's here) | First-class |
| **SWE-bench Verified** (real GitHub issues, agentic) | Solid for an open model; still well behind frontier hosted | **82.4 %** — current state-of-the-art |
| Long-horizon agentic work, multi-file refactors | Decent on short loops; loses thread on long chains | Strong; what Claude Code is built on |
| Multimodal input (images, PDFs, diagrams) | No | Yes |
| Privacy / data residency | Stays on your disk | Sent to Anthropic's API |
| Latency for short replies | A few seconds local (GPU) | Sub-second typical |
| Cost per token | $0 after install | Hosted pricing |

**The honest framing.** Qwen 3 Coder 30B-A3B is the first open-weight
local model that makes a setup like this *actually agentic* — it can
read, write, grep, run shells through OpenCode without hand-holding. For
short, well-scoped tasks it's genuinely useful. For long-horizon work
across a large codebase, Opus still pulls ahead by a wide margin. Use the
right tool for the size of the task.

### Further reading

- Qwen 3 Coder on Ollama — [ollama.com/library/qwen3-coder](https://ollama.com/library/qwen3-coder)
- Qwen 3 Coder GitHub — [QwenLM/Qwen3-Coder](https://github.com/QwenLM/Qwen3-Coder)
- Hugging Face: Qwen3-30B-A3B — [huggingface.co/Qwen/Qwen3-30B-A3B](https://huggingface.co/Qwen/Qwen3-30B-A3B)
- OpenCode + Qwen3-Coder write-up — [KDnuggets](https://www.kdnuggets.com/seeing-whats-possible-with-opencode-ollama-qwen3-coder)
- Anthropic Claude Opus 4.7 benchmarks — [Vellum write-up](https://www.vellum.ai/blog/claude-opus-4-7-benchmarks-explained)

## Architecture

```mermaid
flowchart LR
    Dev([Developer])
    Browser([Browser])
    Other([curl / IDE plugin / scripts])

    Dev --> OC["OpenCode CLI (host)<br/>./maude — native binary<br/>tools: read/write/edit/bash/grep/…"]
    Browser --> WebUI["Open WebUI<br/>chat @ :3000"]
    Browser --> WebTerm["maude-webterm<br/>ttyd + opencode @ :7681<br/>xterm.js / per-conn PTY"]
    Other --> LiteLLM["LiteLLM proxy<br/>OpenAI v1 @ :4000"]
    WebUI --> LiteLLM

    OC -- "OpenAI v1 + tool_calls<br/>(direct)" --> Ollama
    WebTerm -- "OpenAI v1 + tool_calls<br/>(direct)" --> Ollama
    LiteLLM -- "Ollama API" --> Ollama

    subgraph backend["Ollama"]
        direction LR
        Ollama["MODE=docker → container (CPU)<br/>MODE=metal → host (Metal GPU)<br/>:11434"]
    end

    Ollama --> Model[("qwen3-coder:30b")]

    classDef host fill:#fdf0e6,stroke:#c98140,color:#3a1f08
    classDef container fill:#e8f1fc,stroke:#5a8dc7,color:#0a2540
    class OC host
    class LiteLLM,WebUI,WebTerm container
```

OpenCode talks **directly** to Ollama's OpenAI-compat endpoint
(`:11434/v1`) because LiteLLM currently has a [known bug forwarding
structured `tool_calls`](https://github.com/BerriAI/litellm/issues/19742)
from `ollama_chat`. LiteLLM stays in the stack as the OpenAI-compat
endpoint for everything else that doesn't need tool calling (curl, IDE
plugins, OpenWebUI, custom scripts).

## Prerequisites

- **Docker** Desktop / Engine / OrbStack on macOS, Windows, or Linux, with Compose v2.
- **OpenCode** binary: `brew install anomalyco/tap/opencode`
  (or use the `curl` one-liner from [opencode.ai](https://opencode.ai)).
- For `MODE=metal`: macOS on Apple Silicon and `brew install ollama`.
- ~22 GB free disk for the qwen3-coder:30b bundle (~3 GB images + ~19 GB model).
- 32 GB unified memory recommended:
  - docker mode: large MoE model in CPU on a 32 GB Mac is workable but slow.
  - metal mode: the model lives in unified memory and uses the GPU; this is
    the intended path.

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

1. `docker pull` Ollama and LiteLLM at pinned versions and `docker save`
   each into `assets/images/*.tar` *immediately* after pull (Docker
   Desktop's auto-GC otherwise eats unsaved images during step 2).
2. Spin up a throwaway Ollama with `assets/ollama-data/` mounted and
   `ollama pull qwen3-coder:30b`, so all the model blobs land in the repo.

End state: `assets/` is ~22 GB (~3 GB images + ~19 GB model). The repo's
`.gitignore` skips `assets/` by default; see "Storage notes" below for
options if you want to vendor it.

OpenCode is *not* bundled here — it's a separate native install
(`brew install anomalyco/tap/opencode`). It's a single static binary so
the install footprint is small and avoids the container/UID friction we
had when running Aider in a sidecar.

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

### 3. Use OpenCode against the local model

```bash
# inside any project directory
/path/to/maude/maude                       # interactive TUI (docker mode by default)
/path/to/maude/maude run "your task..."    # non-interactive single-shot

# convenience wrappers
/path/to/maude/maude-cpu                   # MODE=docker (container Ollama, CPU)
/path/to/maude/maude-gpu                   # MODE=metal  (host Ollama, Apple GPU)
```

The launcher ensures the backend is up, sets `OPENCODE_CONFIG` to point
at this repo's `opencode.json`, then `exec`s the `opencode` binary in
your CWD. OpenCode reads and writes files directly on the host — no
container, no UID juggling. Add the launcher to your `PATH` and just type
`maude` (or `maude-gpu`).

### 4. Tear down

```bash
# docker mode — ollama lives in compose, include the profile when stopping
COMPOSE_PROFILES=docker-backend docker compose down

# metal mode — litellm + open-webui in compose; host ollama keeps running
docker compose down
brew services stop ollama   # if you also want to stop host ollama
```

`./webui-data/` and `./assets/` survive `compose down`. Delete them
explicitly to wipe chat history or reclaim the model bundle. The web
terminal has no persistent state of its own — chat/edit history goes
into `$WORKSPACE/.opencode` on the host.

## Usage examples

All screenshots below are real terminal output captured against this stack
running locally — Ollama (`0.4.7` in docker mode, Homebrew host build in
metal mode), LiteLLM main-stable, Qwen 3 Coder 30B-A3B —
rendered with [`charmbracelet/freeze`](https://github.com/charmbracelet/freeze).

### Stack overview — `docker ps`

Healthy compose stack after `./turnup.sh` (metal mode shown — only the
LiteLLM container; in docker mode you'd also see `maude-ollama`).

![docker ps](docs/screenshots/01-docker-ps.png)

### What the model is doing — `ollama ps`

`PROCESSOR` is the headline number. In metal mode the host Ollama loads
the model on the M-series GPU (`100% GPU`); in docker mode it falls back
to `100% CPU` and pegs every core during generation.

![ollama ps](docs/screenshots/02-ollama-ps.png)

### Use the model directly — `curl` the OpenAI-compatible endpoint

Anything that speaks OpenAI v1 works against `http://127.0.0.1:4000`.
Here the model returns a real GCD implementation in response to a chat
completion call.

![curl litellm](docs/screenshots/03-curl.png)

### Agentic editing — `maude-gpu` driving OpenCode

The launcher points OpenCode at this repo's `opencode.json` (which targets
the local LiteLLM endpoint) and then `exec`s `opencode` in your CWD.
OpenCode reads and writes your files directly via structured tool calls —
no container, no UID juggling. Below is `maude-gpu run "..."`, a one-shot
non-interactive invocation that creates a file from scratch.

![maude-gpu](docs/screenshots/04-opencode-session.png)

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

## Web terminal (xterm.js)

`http://127.0.0.1:7681` opens a browser-side terminal connected to a
container that runs `opencode` inside an xterm.js wire (via
[ttyd](https://github.com/tsl0922/ttyd)). It's the same agent as
`./maude`, just rendered in a tab instead of your shell — useful when
you're already in the browser using Open WebUI, or when you want a
fresh agent session on another device on the LAN (firewall permitting;
the port binds to 127.0.0.1 by default — see "Exposing it" below).

### Picking a project on connect

Each WebSocket connection runs `webterm/launcher.sh`, which paints the
maude banner and drops you into an [fzf](https://github.com/junegunn/fzf)
picker over the directories under `$WORKSPACE`. Git repos float to the
top of the list; common noise (`node_modules`, `.venv`, `dist`, …) is
pruned. Type to fuzzy-filter, Enter to confirm, Esc to bail. Once you
pick, `opencode` exec's in that directory.

To skip the picker and jump straight to a known repo, use ttyd's
`--url-arg` syntax:

```
http://127.0.0.1:7681/?arg=Desktop/repos/foo
```

The argument is resolved against `$WORKSPACE` and rejected if it
escapes that root (defence-in-depth for the day the port leaves
loopback).

### Workspace

Set by the `WORKSPACE` env var at turnup time, default `$HOME`:

```bash
./turnup.sh                                    # workspace = $HOME
WORKSPACE=~/Desktop/repos/foo ./turnup.sh      # pin to a single repo
```

The host directory is bind-mounted into the container as `/workspace`
and the container runs as the host UID/GID (auto-detected by `turnup.sh`),
so files edited via the web terminal end up owned by your user — no
chown dance afterwards.

The web terminal does **not** see a `MODE=docker`/`metal` switch — it
always runs in a container. What changes per mode is the baseURL it
uses to reach Ollama (`ollama:11434` vs `host.docker.internal:11434`);
`docker-compose.yml` mounts the right `webterm/opencode.${MODE}.json`.

### State

Opencode writes its history and cache under `$HOME/.opencode` (or
similar). Because the web terminal sets `HOME=/workspace` (= host
`$WORKSPACE`), that state lands in the same place a native `./maude`
session would — which means **don't run a native `./maude` and a
browser session against the same repo simultaneously**, or you'll race
state files.

### Exposing it

Default is loopback-only. If you want to reach it from another machine
on the LAN, override the host bind in a `docker-compose.override.yml`:

```yaml
services:
  webterm:
    ports:
      - "0.0.0.0:7681:7681"
```

ttyd itself accepts only one writer per WebSocket; layer your own auth
(reverse proxy with basic-auth, Tailscale, etc.) before doing this.

## Chat UI (Open WebUI)

After `./turnup.sh`, open <http://127.0.0.1:3000>. The UI is pre-wired to
LiteLLM — `qwen-coder` appears in the model picker with no further
configuration. Auth is disabled (loopback-only bind), so it drops you
straight into a chat.

State (chat history, settings) persists in `./webui-data/`, mounted into
the container.

### Apply the maude theme

Open WebUI takes a one-shot Custom CSS payload via the admin UI; the
project ships the maude-branded payload at [`webui/maude.css`](webui/maude.css).
Paste it in once and it persists in the SQLite at `webui-data/webui.db`:

1. Open <http://127.0.0.1:3000> → **Settings** (top-right) → **Interface**.
2. Scroll to **Custom CSS**, paste the contents of `webui/maude.css`, save.
3. Reload. The header shows `maude`, the accent colour shifts to the
   amber/host-mode tone from the architecture diagram, and the typography
   moves to a mono stack.

To reset, clear the textarea and save again — the data volume keeps it
out of code so you can edit freely without rebuilding the image.

## Layout

```
.
├── docker-compose.yml          # ollama (profile: docker-backend) + litellm + open-webui + webterm
├── litellm/
│   ├── config.docker.yaml      # api_base http://ollama:11434
│   └── config.metal.yaml       # api_base http://host.docker.internal:11434
├── opencode.json               # host opencode config (loopback to local Ollama)
├── webterm/                    # in-container opencode via ttyd
│   ├── Dockerfile              # debian-slim + ttyd 1.7.7 + opencode-ai (npm) + fzf
│   ├── start.sh                # applies maude xterm theme, exec's ttyd launcher.sh
│   ├── launcher.sh             # maude banner + fzf directory picker → exec opencode
│   ├── opencode.docker.json    # baseURL http://ollama:11434/v1
│   └── opencode.metal.json     # baseURL http://host.docker.internal:11434/v1
├── webui/
│   └── maude.css               # maude-branded Custom CSS for Open WebUI (paste once)
├── fetch-assets.sh             # online: pull & save images, prefetch model blobs
├── turnup.sh                   # offline: docker load + compose up (MODE-aware)
├── maude                       # launcher: exec opencode with OPENCODE_CONFIG
├── maude-cpu                   # wrapper: MODE=docker maude …
├── maude-gpu                   # wrapper: MODE=metal  maude …
├── .gitattributes              # LFS patterns (not active unless you enable LFS)
├── webui-data/                 # (gitignored) Open WebUI SQLite, uploads, settings
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
   storage / 1 GB bandwidth per month and the qwen3-coder bundle is ~22 GB).
3. **Host assets elsewhere.** Push `assets/` to S3 / R2 / HuggingFace / a
   GitHub Release. Extend `fetch-assets.sh` with a download path that pulls
   from your bucket when an env var like `MAUDE_ASSETS_URL` is set.

## Troubleshooting

**`no space left on device` during fetch.** The Mac is full, not Docker.
Check `df -h /`. The Ollama image ships ~2 GB of NVIDIA CUDA libraries that
go nowhere useful on Apple Silicon but still need disk to extract. Free
host space, then retry — `fetch-assets.sh` resumes where it left off.

**`model requires more system memory than is available`.** The MoE
qwen3-coder:30b model can exceed the Docker VM's RAM allocation on a
32 GB Mac. Either switch to `MODE=metal` (uses host unified memory
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

- Qwen 3 Coder 30B-A3B is roughly mid-tier on agentic coding benchmarks:
  solid for short loops (write this file, fix this bug, refactor this
  function) and structured tool use; weaker at long-horizon reasoning
  across a large codebase than a hosted frontier model.
- Both LiteLLM and host-mode Ollama bind to `0.0.0.0` internally but only
  the loopback interface is mapped — your macOS firewall still gates any
  inbound traffic; this stack is local-only.
- No telemetry. No outbound calls after `fetch-assets.sh` finishes.

<!-- scc-start -->
## Code Statistics

| Language | Files | Lines | Blanks | Comments | Code | Complexity |
|---|---|---|---|---|---|---|
| Shell | 4 | 455 | 55 | 98 | 302 | 64 |
| BASH | 3 | 45 | 7 | 18 | 20 | 5 |
| JSON | 3 | 69 | 0 | 0 | 69 | 0 |
| YAML | 3 | 166 | 11 | 41 | 114 | 0 |
| Markdown | 2 | 548 | 112 | 0 | 436 | 0 |
| CSS | 1 | 207 | 18 | 37 | 152 | 0 |
| Dockerfile | 1 | 55 | 9 | 17 | 29 | 9 |
| Python | 1 | 0 | 0 | 0 | 0 | 0 |
| **Total** | **18** | **1,545** | **212** | **211** | **1,122** | **78** |

- **Estimated Cost to Develop (organic):** $30,485
- **Estimated Schedule Effort (organic):** 3.65 months
- **Estimated People Required (organic):** 0.74
- **Processed:** 63,678 bytes (0.064 megabytes)

*Generated with [scc](https://github.com/boyter/scc) on 2026-05-23*
<!-- scc-end -->
