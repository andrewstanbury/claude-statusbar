#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# claude-statusbar — uninstaller (status bar only)
# ─────────────────────────────────────────────────────────────────────────────
# Reverses exactly what install.sh did and nothing more:
#   1. removes the "statusLine" key from ~/.claude/settings.json (jq, in place)
#   2. removes ~/.claude/status.sh
#
# It NEVER touches "hooks" or any other key, so your other tools are left alone.
#
# Usage: bash uninstall.sh
# Requires: jq
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
DEST="$CLAUDE_DIR/status.sh"
G=$'\033[32m'; B=$'\033[1m'; X=$'\033[0m'
ok() { printf '  %s✓%s %s\n' "$G" "$X" "$1"; }

command -v jq >/dev/null || { printf 'jq not found (required)\n' >&2; exit 1; }

if [ -e "$DEST" ] || [ -L "$DEST" ]; then rm -f "$DEST"; ok "removed $DEST"; fi

if [ -f "$SETTINGS" ]; then
  tmp=$(mktemp)
  jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  ok "removed statusLine from settings.json (everything else left intact)"
fi

printf '\n%sUninstalled.%s Restart Claude Code (or run /config).\n' "$B" "$X"
