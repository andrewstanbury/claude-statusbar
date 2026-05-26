#!/usr/bin/env bash
# Aggregator: PreToolUse on Read. Runs big-read-guard (>N LOC w/o
# pagination) AND re-read-guard (same file read 4+ times w/o edit) inline.
set -euo pipefail

BIG_THRESHOLD="${CLAUDE_BIG_READ_THRESHOLD:-2000}"
REREAD_THRESHOLD="${CLAUDE_REREAD_THRESHOLD:-3}"

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
offset="$(printf '%s' "$payload" | jq -r '.tool_input.offset // empty')"
limit="$(printf '%s' "$payload" | jq -r '.tool_input.limit // empty')"

[ -z "$file_path" ] && exit 0

deny() {
  jq -nc --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Paginated reads bypass both checks — fetching a specific window is the
# correct response to either guard.
if [ -n "$offset" ] || [ -n "$limit" ]; then
  exit 0
fi

[ ! -f "$file_path" ] && exit 0

# ─── 1. big-read-guard (file >N LOC, no pagination) ─────────────────────
case "$file_path" in
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf|*.ico|*.woff|*.woff2|*.ttf|*.otf) ;;  # skip binary
  *.ipynb) ;;                                                                  # skip notebooks
  *)
    loc=$(wc -l < "$file_path" 2>/dev/null || echo 0)
    if [ "$loc" -gt "$BIG_THRESHOLD" ]; then
      deny "Read on $file_path ($loc LOC) without offset/limit. Pass {offset:<N>, limit:<N>} to paginate — slurping burns ~$((loc * 5)) input tokens. Threshold $BIG_THRESHOLD."
    fi
    ;;
esac

# ─── 2. re-read-guard (Nth full read without edit) ──────────────────────
if [ -n "$session_id" ]; then
  log="/tmp/claude-reads-${session_id}.txt"
  if [ -f "$log" ]; then
    count=$(grep -cFx "$file_path" "$log" 2>/dev/null) || count=0
    if [ "$count" -ge "$REREAD_THRESHOLD" ]; then
      deny "You've already read $file_path $count times this session without editing it. Grep for the section you need: 'grep -n <pattern> $file_path' or pass {offset, limit} to read a specific window. Override: CLAUDE_REREAD_THRESHOLD=<n>."
    fi
  fi
fi

exit 0
