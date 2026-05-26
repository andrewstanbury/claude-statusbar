#!/usr/bin/env bash
# Re-read tracker: PostToolUse companion for re-read-guard.sh.
#
#   - On a successful Read tool result: append the file_path to the
#     per-session read log so re-read-guard can count occurrences.
#   - On a successful Edit/Write/MultiEdit: clear ALL prior reads of that
#     file from the log (post-edit re-reads are legitimate; the file's
#     contents changed).
#
# Best-effort: silent on any error, never blocks.
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
offset="$(printf '%s' "$payload" | jq -r '.tool_input.offset // empty')"
limit="$(printf '%s' "$payload" | jq -r '.tool_input.limit // empty')"

[ -z "$session_id" ] && exit 0
[ -z "$file_path" ] && exit 0

log="/tmp/claude-reads-${session_id}.txt"

case "$tool" in
  Read)
    # Skip paginated reads from the dup count.
    [ -n "$offset" ] && exit 0
    [ -n "$limit" ] && exit 0
    printf '%s\n' "$file_path" >> "$log" 2>/dev/null || true
    ;;
  Edit|Write|MultiEdit)
    # Drop prior reads for this file — they're now stale.
    [ -f "$log" ] || exit 0
    tmp="${log}.tmp.$$"
    grep -vFx "$file_path" "$log" > "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$log" 2>/dev/null || rm -f "$tmp"
    ;;
esac

exit 0
