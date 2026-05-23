#!/usr/bin/env bash
#
# Per-connection entry point inside maude-webterm.
#
# Paints the maude banner, then drops the user into a hierarchical fzf
# picker rooted at $WORKSPACE. Each fzf invocation shows the dirs in the
# current level plus two control items:
#
#   ▸ open this directory   — bail out of the picker and exec opencode here
#   ↑ parent                — cd .. and re-list (omitted at the WORKSPACE root)
#
# Subdirs with a .git child are tagged with a "●" so it's easy to spot
# repos as you walk down. ttyd's --url-arg path is still honoured: if a
# directory comes in as $1 we skip the picker entirely.

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
WORKSPACE_REAL=$(realpath "$WORKSPACE")
cd "$WORKSPACE_REAL"

# --- Palette (matches webterm/start.sh's xterm theme + webui/maude.css) ---
ACCENT=$'\033[38;2;201;129;64m'    # #c98140
SOFT=$'\033[38;2;253;240;230m'     # #fdf0e6
DIM=$'\033[38;2;185;168;144m'      # --maude-fg-dim
MUTE=$'\033[38;2;123;106;85m'      # --maude-fg-mute
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Dirs to never list as children — pruned at every level. Mostly macOS
# protected dirs (read through the bind mount they raise EPERM) and
# heavy/noisy package-manager caches.
SKIP_REGEX='^(\.git|node_modules|\.venv|__pycache__|dist|build|target|\.next|\.cache|Library|\.Trash|\.cargo|\.rbenv|\.pyenv|\.nvm|go|\.docker|\.gem|\.npm|\.local|\.bun|\.deno)$'

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

# --- URL-arg fast path: ?arg=path skips the picker entirely ---------------
if [[ $# -gt 0 && -n "${1:-}" ]]; then
  TARGET="$1"
  [[ "$TARGET" = /* ]] || TARGET="$WORKSPACE_REAL/$TARGET"
  TARGET_REAL=$(realpath -m "$TARGET")
  case "$TARGET_REAL" in
    "$WORKSPACE_REAL"|"$WORKSPACE_REAL"/*) ;;
    *) printf '  %s!%s  outside workspace: %s\n\n' "$ACCENT" "$RESET" "$TARGET"; exit 1 ;;
  esac
  if [[ ! -d "$TARGET_REAL" ]]; then
    printf '  %s!%s  not a directory: %s\n\n' "$ACCENT" "$RESET" "$TARGET_REAL"; exit 1
  fi
  cd "$TARGET_REAL"
  clear
  printf '\n  %s▸%s  %sopencode%s  %s@%s  %s\n\n' "$ACCENT" "$RESET" "$BOLD" "$RESET" "$MUTE" "$RESET" "$TARGET_REAL"
  exec opencode
fi

# --- Helpers --------------------------------------------------------------

display_path() {
  # $WORKSPACE_REAL → '~'; everything else → '~/<rel>'.
  if [[ "$1" == "$WORKSPACE_REAL" ]]; then
    printf '~'
  else
    printf '~/%s' "${1#$WORKSPACE_REAL/}"
  fi
}

build_entries() {
  # Writes one entry per line into $2 for the dir at $1.
  # Lines are prefixed with a sentinel so we can route the choice back
  # in the case-statement without ambiguity:
  #   "▸ open this directory"
  #   "↑ parent"
  #   "● <name>"   — subdirectory that contains .git
  #   "· <name>"   — subdirectory that doesn't
  local cur="$1" out="$2" d name

  : > "$out"
  printf '▸ open this directory\n' >> "$out"
  if [[ "$cur" != "$WORKSPACE_REAL" ]]; then
    printf '↑ parent\n' >> "$out"
  fi

  # find can EPERM on macOS-protected dirs read through the bind mount;
  # don't let that knock us out. Sort case-insensitively, dotfiles last.
  local tmp_dirs
  tmp_dirs=$(mktemp)
  set +e
  find "$cur" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | sort -f > "$tmp_dirs"
  set -e

  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    name=$(basename "$d")
    [[ "$name" =~ $SKIP_REGEX ]] && continue
    if [[ -d "$d/.git" ]]; then
      printf '● %s\n' "$name" >> "$out"
    else
      printf '· %s\n' "$name" >> "$out"
    fi
  done < "$tmp_dirs"
  rm -f "$tmp_dirs"
}

# --- Picker loop ----------------------------------------------------------

entries_file=$(mktemp)
trap 'rm -f "$entries_file"' EXIT

current="$WORKSPACE_REAL"

while true; do
  build_entries "$current" "$entries_file"

  # If there's nothing here besides "open here" / "parent", still show the
  # picker so the user can choose what to do.
  pick=$(
    fzf \
      --prompt="$(display_path "$current") ▶ " \
      --pointer='▶' \
      --marker='■' \
      --height=100% \
      --layout=reverse \
      --info=inline \
      --border=rounded \
      --border-label=' navigate · ● = git repo · ↑ = up · enter = select ' \
      --border-label-pos=3 \
      --header="$(display_path "$current")" \
      --no-mouse \
      --color='fg:#f4e9d8,bg:#0e0a06,hl:#c98140,fg+:#fdf0e6,bg+:#18120b,hl+:#fdf0e6,info:#c98140,border:#c98140,prompt:#c98140,pointer:#fdf0e6,marker:#9fbb6e,header:#7b6a55,gutter:#0e0a06,label:#c98140' \
      < "$entries_file"
  ) || {
    printf '\n  %scancelled%s — refresh the page to pick again\n\n' "$MUTE" "$RESET"
    exit 0
  }

  case "$pick" in
    '▸ open this directory')
      break
      ;;
    '↑ parent')
      current=$(dirname "$current")
      ;;
    '● '*)
      name="${pick#● }"
      current="$current/$name"
      ;;
    '· '*)
      name="${pick#· }"
      current="$current/$name"
      ;;
    *)
      # Shouldn't fire — fall through as a literal subdir name just in case.
      current="$current/$pick"
      ;;
  esac
done

cd "$current"
clear
printf '\n  %s▸%s  %sopencode%s  %s@%s  %s\n\n' "$ACCENT" "$RESET" "$BOLD" "$RESET" "$MUTE" "$RESET" "$current"

exec opencode
