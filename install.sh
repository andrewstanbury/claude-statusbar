#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Status Bar — installer
# ─────────────────────────────────────────────────────────────────────────────
#
# One-shot installer for status.sh. Downloads the script to ~/.claude/status.sh
# and registers it as the Claude Code statusLine in ~/.claude/settings.json.
#
# Usage:
#   curl -fsSL <RAW_URL_OF_THIS_FILE> | bash
#
# Or, if you've already cloned the repo:
#   bash install.sh
#
# Re-running is safe (idempotent). Existing settings.json is backed up to
# ~/.claude/settings.json.bak before modification.
#
# Requirements: bash 4+, curl, jq.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Raw URL where status.sh is hosted. Override with SCRIPT_URL env var if forking.
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/andrewstanbury/claude-statusbar/main/status.sh}"

# ── Paths ────────────────────────────────────────────────────────────────────
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_DEST="$CLAUDE_DIR/status.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP="$SETTINGS.bak"

# ── Pretty output ────────────────────────────────────────────────────────────
G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[1m'; X=$'\033[0m'
say()  { printf '%s%s%s\n' "$B" "$1" "$X"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$X" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$X" "$1"; }
die()  { printf '%s✗ %s%s\n' "$R" "$1" "$X" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
say "Claude Code status bar installer"

command -v curl >/dev/null || die "curl not found (required to download status.sh)"
command -v jq   >/dev/null || die "jq not found (required to patch settings.json — install it first)"

mkdir -p "$CLAUDE_DIR"
ok "Config dir: $CLAUDE_DIR"

# ── Download script ──────────────────────────────────────────────────────────
if [ -f "$SCRIPT_DEST" ]; then
  cp "$SCRIPT_DEST" "$SCRIPT_DEST.bak"
  warn "Existing status.sh backed up to status.sh.bak"
fi

# If the installer lives next to a local status.sh, prefer that over downloading.
LOCAL_SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  LOCAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  [ -f "$LOCAL_DIR/status.sh" ] && LOCAL_SRC="$LOCAL_DIR/status.sh"
fi

if [ -n "$LOCAL_SRC" ] && [ "$LOCAL_SRC" != "$SCRIPT_DEST" ]; then
  cp "$LOCAL_SRC" "$SCRIPT_DEST"
  ok "Copied status.sh from $LOCAL_SRC"
elif [ -z "$LOCAL_SRC" ]; then
  curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_DEST" \
    || die "Failed to download from $SCRIPT_URL"
  ok "Downloaded status.sh from $SCRIPT_URL"
else
  ok "status.sh already at destination"
fi

chmod +x "$SCRIPT_DEST"
ok "Made executable: $SCRIPT_DEST"

# ── Patch settings.json ──────────────────────────────────────────────────────
NEW_BLOCK=$(jq -n --arg cmd "bash $SCRIPT_DEST" \
  '{statusLine: {type: "command", command: $cmd}}')

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$BACKUP"
  ok "Backed up settings.json to settings.json.bak"

  # Validate existing JSON before merging.
  jq empty "$SETTINGS" 2>/dev/null \
    || die "$SETTINGS is not valid JSON — fix or remove it, then re-run"

  EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  if [ -n "$EXISTING" ] && [ "$EXISTING" != "bash $SCRIPT_DEST" ]; then
    warn "Replacing existing statusLine: $EXISTING"
  fi

  jq --argjson new "$NEW_BLOCK" '. + $new' "$SETTINGS" > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
else
  printf '%s\n' "$NEW_BLOCK" | jq '.' > "$SETTINGS"
  ok "Created $SETTINGS"
fi
ok "Registered statusLine in settings.json"

# ── Done ─────────────────────────────────────────────────────────────────────
say ""
say "Done. Restart Claude Code (or run /config) to see the status bar."
say "To uninstall: remove the .statusLine key from $SETTINGS and delete $SCRIPT_DEST"
