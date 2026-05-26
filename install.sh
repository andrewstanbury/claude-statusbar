#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# claude-statusbar — unified, component-aware installer
# ─────────────────────────────────────────────────────────────────────────────
# Modular install of the portable Claude Code config: status bar, global
# instructions, hook groups, and skills. Pick what you want — installing
# everything is the recommended default. Symlinks chosen component files into
# ~/.claude and COMPOSES a real ~/.claude/settings.json (statusLine + the hooks
# of the selected components) from claude/components.sh.
#
# Local:   bash install.sh
# Remote:  curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-statusbar/main/install.sh | bash
#          (no local repo → clones to ~/.cache/claude-statusbar)
#
# No TTY (e.g. CI): installs ALL components. Idempotent: existing real files are
# backed up to <file>.bak before linking; settings.json is recomposed each run.
#
# Requires: bash 4+, git, jq.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL="${CSB_REPO_URL:-https://github.com/andrewstanbury/claude-statusbar.git}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE="$CLAUDE_DIR/.claude-statusbar.json"

MODE=install
case "${1:-}" in
  --status|status) MODE=status ;;
  --update|update) MODE=update ;;
  -h|--help) printf 'Usage: install.sh [--status | --update]\n  (no args) interactive install   --update keep installed set at latest   --status show versions\n'; exit 0 ;;
  "") ;;
  *) printf 'unknown arg: %s (try --help)\n' "$1" >&2; exit 2 ;;
esac

G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[1m'; X=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$G" "$X" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$X" "$1"; }
die()  { printf '%s✗ %s%s\n' "$R" "$1" "$X" >&2; exit 1; }

command -v git >/dev/null || die "git not found (required)"
command -v jq  >/dev/null || die "jq not found (required)"

# ── Locate the repo: local clone preferred; else clone to a cache ────────────
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
  [ -n "$d" ] && [ -f "$d/claude/components.sh" ] && SRC="$d"
fi
if [ -z "$SRC" ]; then
  CACHE="${CSB_CACHE:-$HOME/.cache/claude-statusbar}"
  if [ -d "$CACHE/.git" ]; then git -C "$CACHE" pull --ff-only -q 2>/dev/null || true
  else mkdir -p "$(dirname "$CACHE")"; git clone -q "$REPO_URL" "$CACHE" || die "clone failed: $REPO_URL"; fi
  SRC="$CACHE"
fi
[ -f "$SRC/claude/components.sh" ] || die "components.sh not found under $SRC"
# Keep-to-latest: when updating from a real clone, pull before composing.
[ "$MODE" = update ] && [ -d "$SRC/.git" ] && git -C "$SRC" pull --ff-only -q 2>/dev/null || true
# shellcheck source=/dev/null
. "$SRC/claude/components.sh"

# Git-derived version of a component = short hash + date of the last commit
# touching any of its paths. Run in a subshell so cwd is untouched.
comp_version() { ( cd "$SRC" && git log -1 --format='%h %cs' -- ${COMPONENT_PATHS[$1]} 2>/dev/null ) || true; }

if [ "$MODE" = status ]; then
  [ -f "$STATE" ] || die "claude-statusbar not installed (no $STATE)"
  printf '%-22s  %-20s  %-20s  %s\n' COMPONENT INSTALLED LATEST STATUS
  while IFS= read -r c; do
    inst=$(jq -r --arg k "$c" '.components[$k] // "?"' "$STATE")
    cur=$(comp_version "$c"); cur=${cur:-unknown}
    st="up-to-date"; [ "$inst" != "$cur" ] && st="↑ update available"
    printf '%-22s  %-20s  %-20s  %s\n' "$c" "$inst" "$cur" "$st"
  done < <(jq -r '.components|keys[]' "$STATE")
  exit 0
fi

printf '%sclaude-statusbar installer%s  (source: %s)\n\n' "$B" "$X" "$SRC"

# ── Choose components (interactive via /dev/tty; default = ALL/recommended) ──
SELECTED=()
if [ "$MODE" = update ] && [ -f "$STATE" ]; then
  while IFS= read -r c; do [ -n "$c" ] && SELECTED+=("$c"); done < <(jq -r '.components|keys[]' "$STATE")
  printf 'Updating installed components to latest: %s\n' "${SELECTED[*]}"
elif { true >/dev/tty; } 2>/dev/null; then
  printf 'Install ALL components (recommended)? [Y/n] ' > /dev/tty
  read -r ans < /dev/tty || ans=""
  case "$ans" in
    n|N)
      for c in "${COMPONENT_ORDER[@]}"; do
        printf '  • %s? [Y/n] ' "${COMPONENT_LABEL[$c]}" > /dev/tty
        read -r a < /dev/tty || a=""
        case "$a" in n|N) ;; *) SELECTED+=("$c") ;; esac
      done ;;
    *) SELECTED=("${COMPONENT_ORDER[@]}") ;;
  esac
else
  SELECTED=("${COMPONENT_ORDER[@]}")
fi
[ "${#SELECTED[@]}" -gt 0 ] || die "nothing selected"

# ── Symlink the chosen components' files ─────────────────────────────────────
link() {  # link <src-abs> <dest-abs>
  local s="$1" d="$2"
  mkdir -p "$(dirname "$d")"
  if [ -L "$d" ]; then [ "$(readlink "$d")" = "$s" ] && return 0; rm -f "$d"
  elif [ -e "$d" ]; then mv "$d" "$d.bak"; warn "backed up $d → $d.bak"; fi
  ln -s "$s" "$d"
}
for c in "${SELECTED[@]}"; do
  for p in ${COMPONENT_PATHS[$c]}; do
    [ -e "$SRC/$p" ] || { warn "missing in repo: $p"; continue; }
    case "$p" in */lib/*) ;; *.sh) chmod +x "$SRC/$p" 2>/dev/null || true ;; esac
    link "$SRC/$p" "$CLAUDE_DIR/${p#claude/}"
  done
  ok "linked: ${COMPONENT_LABEL[$c]}"
done

# ── Compose settings.json: base (static keys) + statusLine + selected hooks ──
BASE='{}'
[ -f "$SRC/claude/settings.json" ] && BASE=$(jq 'del(.statusLine, .hooks)' "$SRC/claude/settings.json")

STATUSLINE='null'
case " ${SELECTED[*]} " in *" statusbar "*)
  STATUSLINE='{"statusLine":{"type":"command","command":"bash $HOME/.claude/status.sh","refreshInterval":1}}' ;;
esac

specs=""
for c in "${SELECTED[@]}"; do [ -n "${COMPONENT_HOOKS[$c]:-}" ] && specs+="${COMPONENT_HOOKS[$c]}"$'\n'; done
HOOKS='{}'
if printf '%s' "$specs" | grep -q '[^[:space:]]'; then
  HOOKS=$(printf '%s\n' "$specs" | grep -vE '^[[:space:]]*$' | awk -F'::' '{
      printf "{\"event\":\"%s\",\"matcher\":\"%s\",\"command\":\"bash $HOME/.claude/hooks/%s\",\"timeout\":%s}\n",$1,$2,$3,$4
    }' | jq -s '
      reduce .[] as $h ({}; .[$h.event][$h.matcher] += [{type:"command", command:$h.command, timeout:$h.timeout}])
      | with_entries(.value |= (to_entries | map(if .key=="" then {hooks:.value} else {matcher:.key, hooks:.value} end)))')
fi

SETTINGS=$(jq -n --argjson base "$BASE" --argjson sl "$STATUSLINE" --argjson hooks "$HOOKS" \
  '$base + (if $sl==null then {} else $sl end) + (if ($hooks|length)>0 then {hooks:$hooks} else {} end)')

mkdir -p "$CLAUDE_DIR"
if [ -L "$CLAUDE_DIR/settings.json" ]; then rm -f "$CLAUDE_DIR/settings.json"
elif [ -f "$CLAUDE_DIR/settings.json" ] && [ ! -f "$STATE" ]; then
  # First install over a pre-existing user settings.json — back it up ONCE.
  cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak"; warn "backed up settings.json → settings.json.bak"
fi
printf '%s\n' "$SETTINGS" | jq '.' > "$CLAUDE_DIR/settings.json"
ok "composed settings.json (${#SELECTED[@]} components)"

# ── Record installed state (versions added by the updater) ───────────────────
state_json='{"components":{}}'
for c in "${SELECTED[@]}"; do
  state_json=$(printf '%s' "$state_json" | jq --arg k "$c" --arg v "$(comp_version "$c")" '.components[$k]=$v')
done
printf '%s\n' "$state_json" | jq '.' > "$STATE"

printf '\n%sDone.%s Restart Claude Code (or run /config) to load.\n' "$B" "$X"
printf 'Status: bash %s/install.sh --status  ·  Update to latest: bash %s/install.sh --update  ·  Uninstall: bash %s/uninstall.sh\n' "$SRC" "$SRC" "$SRC"
