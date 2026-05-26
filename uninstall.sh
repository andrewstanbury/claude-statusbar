#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# claude-statusbar — uninstaller
# ─────────────────────────────────────────────────────────────────────────────
# Removes only what this project installed: symlinks in ~/.claude that point at
# a claude-statusbar checkout (status.sh, CLAUDE.md, hooks/*, skills/*), then
# restores settings.json from the .bak the installer made (or removes the
# composed one if there was no prior settings). Never touches your own files,
# auth, memory, or non-claude-statusbar hooks/skills.
#
# Usage: bash uninstall.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
G=$'\033[32m'; B=$'\033[1m'; X=$'\033[0m'
ok() { printf '  %s✓%s %s\n' "$G" "$X" "$1"; }

n=0
for d in "$CLAUDE_DIR/status.sh" "$CLAUDE_DIR/CLAUDE.md" \
         "$CLAUDE_DIR"/hooks/*.sh "$CLAUDE_DIR"/hooks/lib/*.sh "$CLAUDE_DIR"/skills/*; do
  [ -L "$d" ] || continue
  case "$(readlink "$d")" in
    *claude-statusbar*) rm -f "$d"; n=$((n+1)) ;;
  esac
done
ok "removed $n claude-statusbar symlink(s)"

# Old symlink-style install: drop a settings.json that points at claude-statusbar.
if [ -L "$CLAUDE_DIR/settings.json" ]; then
  case "$(readlink "$CLAUDE_DIR/settings.json")" in
    *claude-statusbar*) rm -f "$CLAUDE_DIR/settings.json"; ok "removed settings.json symlink" ;;
  esac
fi

# settings.json: prefer restoring the installer's backup; else drop the composed file.
if [ -f "$CLAUDE_DIR/settings.json.bak" ]; then
  mv "$CLAUDE_DIR/settings.json.bak" "$CLAUDE_DIR/settings.json"
  ok "restored settings.json from settings.json.bak"
elif [ -f "$CLAUDE_DIR/settings.json" ] && [ ! -L "$CLAUDE_DIR/settings.json" ]; then
  rm -f "$CLAUDE_DIR/settings.json"
  ok "removed composed settings.json"
fi

rm -f "$CLAUDE_DIR/.claude-statusbar.json"
# Tidy now-empty dirs we may have created (ignore if non-empty / absent).
rmdir "$CLAUDE_DIR/hooks/lib" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/skills" 2>/dev/null || true

printf '\n%sUninstalled.%s Restart Claude Code (or run /config).\n' "$B" "$X"
