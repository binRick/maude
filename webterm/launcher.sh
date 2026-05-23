#!/usr/bin/env bash
#
# Per-connection entry point inside maude-webterm: paint the maude banner,
# let the user pick a directory under $WORKSPACE (or accept one supplied via
# ttyd's `?arg=` URL parameter), then exec `opencode` there.
#
# Why the picker:
#   - ./maude is run from inside a project repo; the web terminal has no
#     equivalent "where I'm cd'd" signal at connection time.
#   - $WORKSPACE defaults to $HOME, which is a lot of dirs. fzf with a
#     git-repos-first list turns "land in $HOME and run opencode" into
#     "land in $HOME and pick the repo I actually want".

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
cd "$WORKSPACE"

# --- Palette (matches webterm/start.sh's xterm theme + webui/maude.css) ----
ACCENT=$'\033[38;2;201;129;64m'    # #c98140 — host stroke
SOFT=$'\033[38;2;253;240;230m'     # #fdf0e6 — host fill
DIM=$'\033[38;2;185;168;144m'      # --maude-fg-dim
MUTE=$'\033[38;2;123;106;85m'      # --maude-fg-mute
DEEP=$'\033[38;2;58;31;8m'         # #3a1f08 — host text on accent
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear
printf '\n'
printf '  %s╭──────────────────────────────────────────────╮%s\n' "$ACCENT" "$RESET"
printf '  %s│%s  %s%smaude%s  %s·%s  %sweb terminal%s                  %s│%s\n' \
       "$ACCENT" "$RESET" "$BOLD" "$ACCENT" "$RESET" "$MUTE" "$RESET" "$SOFT" "$RESET" "$ACCENT" "$RESET"
printf '  %s│%s  %soffline · local · no cloud%s                  %s│%s\n' \
       "$ACCENT" "$RESET" "$MUTE" "$RESET" "$ACCENT" "$RESET"
printf '  %s╰──────────────────────────────────────────────╯%s\n' "$ACCENT" "$RESET"
printf '\n'
printf '  %sworkspace%s  %s\n' "$MUTE" "$RESET" "$WORKSPACE"
printf '\n'

# --- URL-arg fast path -----------------------------------------------------
# ttyd's --url-arg pipes ?arg=foo into the spawned command's $1. If the user
# passes a directory that way, skip the picker.
if [[ $# -gt 0 && -n "${1:-}" ]]; then
  TARGET="$1"
  [[ "$TARGET" = /* ]] || TARGET="$WORKSPACE/$TARGET"

  # Enforce containment in $WORKSPACE — defence-in-depth in case the port is
  # ever bound off loopback.
  WORKSPACE_REAL=$(realpath "$WORKSPACE")
  TARGET_REAL=$(realpath -m "$TARGET")
  case "$TARGET_REAL" in
    "$WORKSPACE_REAL"|"$WORKSPACE_REAL"/*) ;;
    *) printf '  %s!%s  outside workspace: %s\n\n' "$ACCENT" "$RESET" "$TARGET"; exit 1 ;;
  esac
  if [[ ! -d "$TARGET_REAL" ]]; then
    printf '  %s!%s  not a directory: %s\n\n' "$ACCENT" "$RESET" "$TARGET_REAL"; exit 1
  fi
  TARGET="$TARGET_REAL"
else
  # --- Picker path -------------------------------------------------------
  printf '  %spick a directory%s  · type to filter · enter to confirm · esc to bail\n' "$DIM" "$RESET"
  printf '\n'

  candidates=$(mktemp)
  trap 'rm -f "$candidates"' EXIT

  # Pass 1: git repos under WORKSPACE (high signal — the dirs you actually
  # want to run opencode in).
  find "$WORKSPACE" -maxdepth 6 -type d -name .git \
    -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null \
    | while read -r gitdir; do dirname "$gitdir"; done \
    | sort -u > "$candidates"

  # Pass 2: any directory up to depth 3 that wasn't already a git repo.
  find "$WORKSPACE" -maxdepth 3 -type d \
    \( -name .git -o -name node_modules -o -name .venv \
       -o -name __pycache__ -o -name dist -o -name build \
       -o -name target -o -name .next -o -name .cache \
       -o -name 'Library' \) -prune \
    -o -type d -print 2>/dev/null \
    | sort -u \
    | grep -vxFf "$candidates" >> "$candidates" || true

  if ! [[ -s "$candidates" ]]; then
    printf '  %s!%s  no directories found under %s\n\n' "$ACCENT" "$RESET" "$WORKSPACE"
    exit 1
  fi

  TARGET=$(
    fzf \
      --prompt='▶ ' \
      --pointer='▶' \
      --marker='■' \
      --height=100% \
      --layout=reverse \
      --info=inline \
      --border=rounded \
      --border-label=' directories · git repos first ' \
      --border-label-pos=3 \
      --header="$WORKSPACE" \
      --color='fg:#f4e9d8,bg:#0e0a06,hl:#c98140,fg+:#fdf0e6,bg+:#18120b,hl+:#fdf0e6,info:#c98140,border:#c98140,prompt:#c98140,pointer:#fdf0e6,marker:#9fbb6e,header:#7b6a55,gutter:#0e0a06,label:#c98140' \
      < "$candidates"
  ) || { printf '\n  %scancelled%s — refresh the page to pick again\n\n' "$MUTE" "$RESET"; exit 0; }
fi

cd "$TARGET"
clear
printf '\n  %s▸%s  %sopencode%s  %s@%s  %s\n\n' "$ACCENT" "$RESET" "$BOLD" "$RESET" "$MUTE" "$RESET" "$TARGET"

exec opencode
