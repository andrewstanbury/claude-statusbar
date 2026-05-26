#!/usr/bin/env bash
# PreCompact hook: about to compress conversation context. Emit a
# system reminder so Claude saves load-bearing state (open PRs, in-flight
# decisions, named flags/dates) to memory BEFORE the older transcript
# turns are summarized away.
set -euo pipefail

# Hook fires for both 'manual' (/compact) and 'auto' (context-pressure).
# Manual compacts are user-initiated and usually deliberate — skip the
# reminder; only nag on auto compacts.
payload="$(cat)"
trigger="$(printf '%s' "$payload" | jq -r '.trigger // empty')"

[ "$trigger" = "manual" ] && exit 0

msg="🗜️  About to auto-compact context. Before older turns are summarized, save any load-bearing state to memory: open PR numbers, in-flight decisions, named flags/dates, unresolved blockers. Then proceed."

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PreCompact",
    additionalContext: $m
  }
}'
