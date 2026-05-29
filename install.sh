#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# claude-statusbar — installer (status bar only)
# ─────────────────────────────────────────────────────────────────────────────
# Installs ONE thing: the status bar. It does exactly two writes to your
# Claude Code config and nothing else —
#   1. places status.sh at ~/.claude/status.sh
#   2. merges a single "statusLine" key into ~/.claude/settings.json
#
# It NEVER reads or writes your "hooks" (or any other key), so it cannot
# disturb claude-task-queue, confirm-intent, or anything else you run.
#
# Local clone:  bash install.sh            (symlinks status.sh → live edits)
# No clone:     curl -fsSL .../install.sh | bash   (clones to a cache, copies)
#
# Requires: bash 4+, jq, git (only when there is no local clone).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL="${CSB_REPO_URL:-https://github.com/andrewstanbury/claude-statusbar.git}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
DEST="$CLAUDE_DIR/status.sh"

G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[1m'; X=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$G" "$X" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$X" "$1"; }
die()  { printf '%s✗ %s%s\n' "$R" "$1" "$X" >&2; exit 1; }

command -v jq >/dev/null || die "jq not found (required)"

# ── Locate status.sh: local clone preferred; otherwise clone to a cache ───────
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
  [ -n "$d" ] && [ -f "$d/status.sh" ] && SRC="$d"
fi
LINK_OK=1
if [ -z "$SRC" ]; then
  command -v git >/dev/null || die "git not found (needed to fetch the script)"
  CACHE="${CSB_CACHE:-$HOME/.cache/claude-statusbar}"
  if [ -d "$CACHE/.git" ]; then git -C "$CACHE" pull --ff-only -q 2>/dev/null || true
  else mkdir -p "$(dirname "$CACHE")"; git clone -q "$REPO_URL" "$CACHE" || die "clone failed: $REPO_URL"; fi
  SRC="$CACHE"; LINK_OK=0          # a cache may be cleared — copy, don't link
fi
[ -f "$SRC/status.sh" ] || die "status.sh not found under $SRC"

mkdir -p "$CLAUDE_DIR"
chmod +x "$SRC/status.sh" 2>/dev/null || true

# ── Place status.sh (symlink from a local clone, copy from a cache) ──────────
[ -e "$DEST" ] || [ -L "$DEST" ] && rm -f "$DEST"
if [ "$LINK_OK" -eq 1 ]; then ln -s "$SRC/status.sh" "$DEST"; ok "linked status.sh → $SRC/status.sh"
else cp "$SRC/status.sh" "$DEST"; ok "copied status.sh → $DEST"; fi

# ── Merge ONLY the statusLine key (back up settings.json once) ────────────────
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
[ -f "$SETTINGS.bak" ] || { cp "$SETTINGS" "$SETTINGS.bak"; warn "backed up settings.json → settings.json.bak"; }

CMD="bash $DEST"
tmp=$(mktemp)
jq --arg cmd "$CMD" \
  '.statusLine = {type:"command", command:$cmd, refreshInterval:1}' \
  "$SETTINGS" > "$tmp" || die "failed to update settings.json (left untouched)"
mv "$tmp" "$SETTINGS"
ok "set statusLine in settings.json (hooks and everything else untouched)"

printf '\n%sDone.%s Restart Claude Code (or run /config) to load the status bar.\n' "$B" "$X"
printf 'Uninstall: bash %s/uninstall.sh\n' "$SRC"
