#!/usr/bin/env bash
# Subagent-cost guard: PreToolUse on Agent (Task) calls. Subagent spawns
# load their own system prompt (~2-5k tokens) before doing any work. If the
# delegated task looks trivial (single search, single file lookup, short
# prompt), the direct Read/Grep/Bash equivalent is far cheaper.
#
# Heuristic: deny when ALL of:
#   * subagent_type is "Explore" or "general-purpose" (i.e. not a
#     specialized agent that brings unique tooling)
#   * prompt is short (under MIN_PROMPT_CHARS)
#   * prompt does NOT contain multi-step language (across, then, multiple,
#     audit, cross-file, etc.)
set -euo pipefail

MIN_PROMPT_CHARS="${CLAUDE_SUBAGENT_MIN_PROMPT:-300}"

payload="$(cat)"
agent_type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty')"
prompt="$(printf '%s' "$payload" | jq -r '.tool_input.prompt // empty')"

[ -z "$prompt" ] && exit 0

# Only check generic agents — specialized ones (code-reviewer, Plan,
# statusline-setup, claude-code-guide, etc.) are presumed to bring value
# proportionate to the spawn cost.
case "$agent_type" in
  ""|Explore|general-purpose) ;;
  *) exit 0 ;;
esac

prompt_len=${#prompt}

# Long prompts implicitly justify the subagent: their length signals
# context-protection (offloading large reasoning) rather than a triviality.
if [ "$prompt_len" -ge "$MIN_PROMPT_CHARS" ]; then
  exit 0
fi

# Multi-step / breadth markers — if any present, the task likely warrants
# a subagent.
if printf '%s' "$prompt" | grep -iqE '(across|multiple|each|every|all (the|of)|cross-file|several|throughout|audit|survey|map|catalog|trace|follow|chain|graph)'; then
  exit 0
fi

reason="Subagent spawn for a short ($prompt_len-char) prompt without multi-step language. Subagents cost ~2-5k tokens just to load their system prompt before any work. Use Read / Grep / Glob / Bash directly for single lookups, or expand the prompt to reflect actual breadth. Threshold: $MIN_PROMPT_CHARS chars — override via CLAUDE_SUBAGENT_MIN_PROMPT."
jq -nc --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'

exit 0
