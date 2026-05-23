#!/usr/bin/env bash
#
# Entry point inside maude-webterm. ttyd is just a thin xterm.js↔WebSocket
# bridge; this script picks the workspace, applies the maude xterm theme
# (mirrors webui/maude.css), then exec's ttyd with `opencode` as the
# per-connection command.

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
cd "$WORKSPACE"

export OPENCODE_CONFIG="${OPENCODE_CONFIG:-/etc/maude/opencode.json}"
export TERM="${TERM:-xterm-256color}"

# Theme tokens — keep in sync with webui/maude.css so the web terminal and
# the chat UI share one palette. Single-line JSON so ttyd's --client-option
# parser doesn't have to deal with embedded newlines.
THEME='{"background":"#0e0a06","foreground":"#f4e9d8","cursor":"#c98140","cursorAccent":"#0e0a06","selectionBackground":"#1f1810","black":"#18120b","red":"#d96b4d","green":"#9fbb6e","yellow":"#c98140","blue":"#5a8dc7","magenta":"#b07cc9","cyan":"#6cbeb2","white":"#f4e9d8","brightBlack":"#7b6a55","brightRed":"#e58a6f","brightGreen":"#b9d28c","brightYellow":"#fdf0e6","brightBlue":"#7daadd","brightMagenta":"#c89fd6","brightCyan":"#8fd7cb","brightWhite":"#fdf0e6"}'

exec ttyd \
  --writable \
  --interface 0.0.0.0 \
  --port 7681 \
  --client-option "titleFixed=maude · web terminal" \
  --client-option "fontFamily=ui-monospace, JetBrains Mono, Menlo, Consolas, monospace" \
  --client-option "fontSize=14" \
  --client-option "theme=$THEME" \
  --client-option "disableLeaveAlert=true" \
  --client-option "cursorBlink=true" \
  opencode
