#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Portable Claude Code config — installer
# ─────────────────────────────────────────────────────────────────────────────
#
# Symlinks this repo's Claude Code config into ~/.claude so a freshly-formatted
# machine gets the same global setup. The repo is the source of truth: edits you
# make live in ~/.claude flow back to the repo through the symlinks, so committing
# from here keeps the portable copy current.
#
# Usage (after cloning the repo):
#   bash claude/install.sh
#
# Idempotent and safe to re-run. An existing real file/dir at a destination is
# backed up to <dest>.bak before being replaced with a symlink.
#
# Links (repo → ~/.claude):
#   claude/settings.json   → ~/.claude/settings.json
#   claude/CLAUDE.md       → ~/.claude/CLAUDE.md
#   claude/hooks/*.sh      → ~/.claude/hooks/<name>
#   claude/skills/<name>   → ~/.claude/skills/<name>
#   status.sh (repo root)  → ~/.claude/status.sh
#
# NOTE: project-specific agents are intentionally NOT kept in this public repo,
# so they are not restored here — add them back by hand.
#
# Requirements: bash 4+. Restart Claude Code (or run /config) afterwards.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../claude
REPO_ROOT="$(cd "$SRC_DIR/.." && pwd)"                    # repo root (status.sh lives here)

G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; X=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$G" "$X" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$X" "$1"; }

# link <source-abs> <dest-abs>: back up an existing real file/dir, then symlink.
link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$src" ]; then ok "already linked: $dest"; return; fi
    rm "$dest"
  elif [ -e "$dest" ]; then
    mv "$dest" "$dest.bak"
    warn "backed up $dest → $dest.bak"
  fi
  ln -s "$src" "$dest"
  ok "$dest → $src"
}

printf '%sLinking Claude config%s\n  from %s\n  into %s\n\n' "$B" "$X" "$REPO_ROOT" "$CLAUDE_DIR"

link "$SRC_DIR/settings.json" "$CLAUDE_DIR/settings.json"
link "$SRC_DIR/CLAUDE.md"     "$CLAUDE_DIR/CLAUDE.md"

chmod +x "$REPO_ROOT/status.sh"
link "$REPO_ROOT/status.sh"   "$CLAUDE_DIR/status.sh"

for h in "$SRC_DIR"/hooks/*.sh; do
  chmod +x "$h"
  link "$h" "$CLAUDE_DIR/hooks/$(basename "$h")"
done

for s in "$SRC_DIR"/skills/*/; do
  s="${s%/}"
  link "$s" "$CLAUDE_DIR/skills/$(basename "$s")"
done

printf '\n%sDone.%s Restart Claude Code (or run /config) to load settings + hooks.\n' "$B" "$X"
printf 'If a tool later replaces a symlink with a regular file (atomic write), just re-run this script to re-link.\n'
