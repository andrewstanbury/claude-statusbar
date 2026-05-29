#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# statusbar-advice.sh — Stop hook
# ─────────────────────────────────────────────────────────────────────────────
# Writes a ONE-LINE anti-over-engineering recommendation to a cache file that
# status.sh renders in its advice slot. The bar never calls a model; this hook
# is the only thing that does — throttled and backgrounded so the session never
# waits on it.
#
#   generate (here, throttled Haiku)  →  ~/.claude/state/statusbar-advice/<sid>.txt
#   render   (status.sh, every refresh, free)  ←  cat that file
#
# Cost: one cheap Haiku call at most once per throttle window (default 180s) of
# active work. Recursion-safe: the nested `claude -p` runs with this hook (and
# the other prompt hooks) disabled, so it can't trigger itself.
#
# Overrides:
#   CLAUDE_STATUSBAR_ADVICE_DISABLED=1   off entirely (kill switch)
#   CLAUDE_STATUSBAR_ADVICE_THROTTLE=<s> seconds between refreshes (default 180)
#   CLAUDE_STATUSBAR_ADVICE_DIR=<path>   cache dir (must match status.sh)

[ "${CLAUDE_STATUSBAR_ADVICE_DISABLED:-0}" = "1" ] && exit 0
command -v claude >/dev/null 2>&1 || exit 0
command -v jq     >/dev/null 2>&1 || exit 0

THROTTLE="${CLAUDE_STATUSBAR_ADVICE_THROTTLE:-180}"
DIR="${CLAUDE_STATUSBAR_ADVICE_DIR:-$HOME/.claude/state/statusbar-advice}"

INPUT=$(cat); [ -z "$INPUT" ] && exit 0
IFS=$'\t' read -r SID TRANSCRIPT <<<"$(printf '%s' "$INPUT" \
  | jq -r '[(.session_id // ""), (.transcript_path // "")] | @tsv' 2>/dev/null)"
[ -n "$SID" ] || exit 0

OUT="$DIR/$SID.txt"

# Throttle: a fresh advice file (even an empty "on track" one) means skip.
if [ -f "$OUT" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$OUT" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$THROTTLE" ] && exit 0
fi
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
mkdir -p "$DIR" 2>/dev/null || exit 0

# Generate in the background so the Stop hook returns immediately.
(
  # Recent plain-text turns (user + assistant) from the transcript tail.
  # Collapse ALL whitespace (incl. newlines) to spaces BEFORE the global cap,
  # so the prompt is genuinely bounded — a per-line cut would let it balloon and
  # blow the model timeout.
  ctx=$(tail -n 80 "$TRANSCRIPT" 2>/dev/null | jq -rs '
        map(select(.message.content != null)
            | .message.content
            | if type == "array"
              then (map(select(.type == "text") | .text) | join(" "))
              else tostring end)
        | map(select(length > 0)) | .[-8:] | join(" ")' 2>/dev/null \
        | tr -s ' \t\r\n' ' ' | cut -c1-2000)
  [ -n "$ctx" ] || exit 0

  read -r -d '' prompt <<EOF
You watch a developer's coding session for SCOPE CREEP and OVER-ENGINEERING of local changes.

Reply with ONE imperative clause ONLY — max 8 words, no question mark, no period, no quotes — naming the simplest next move. Examples: ship the simple version / commit before adding more / stop gold-plating, one change at a time / split this into smaller PRs.

If the work is already appropriately scoped and focused, reply EXACTLY: on track

Recent session:
$ctx
EOF

  advice=$(CLAUDE_STATUSBAR_ADVICE_DISABLED=1 CLAUDE_INTENT_CONFIRM_DISABLED=1 \
           CLAUDE_AUDIT_RULES_DISABLED=1 CLAUDE_STACK_LINT_DISABLED=1 \
           timeout 45 claude -p "$prompt" --model haiku 2>/dev/null \
           | head -n1 | tr -d '"' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | cut -c1-48)

  case "$(printf '%s' "$advice" | tr '[:upper:]' '[:lower:]')" in
    "" | "on track" | "on-track" | "ontrack")
      : > "$OUT" 2>/dev/null ;;                       # clear slot, refresh mtime
    *)
      printf '%s' "$advice" > "$OUT.tmp" 2>/dev/null && mv "$OUT.tmp" "$OUT" 2>/dev/null ;;
  esac
) >/dev/null 2>&1 &

exit 0
