#!/usr/bin/env bash
# UserPromptSubmit hook: before acting on a freshly submitted prompt, have
# Claude restate — in its own words — what it understood the request to be,
# so the user can confirm intent BEFORE any execution. On ambiguity, force
# multiple-choice options / follow-up questions instead of guessing. Goal:
# the user always knows what Claude thinks was asked; no silent assumptions.
set -euo pipefail

# Escape hatch (matches the other hooks' override convention).
[ "${CLAUDE_INTENT_CONFIRM_DISABLED:-0}" = "1" ] && exit 0

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty')"

# Nothing to interpret, or a slash-command (/foo) / bang-shell (!cmd) line the
# user typed deliberately — skip the echo-back to avoid noise.
[ -z "$prompt" ] && exit 0
case "$prompt" in
  /*|!*) exit 0 ;;
esac

msg="Before doing anything else, restate in one or two terse lines what you understand this request to be asking, so the user can confirm you read it right. Do NOT start executing yet. If the request has more than one plausible interpretation, present the options via AskUserQuestion (multiple choice) or ask focused follow-up questions — never pick an interpretation on the user's behalf. For any non-trivial or multi-step ask, after restating use the task tool (TaskCreate) to break the work into tasks ordered by sensible default priority (prerequisites first, then by value/impact), each tagged with a complexity and estimated processing time (S/M/L plus rough minutes or token size), and show the list. Then work through them ONE AT A TIME: before starting each task, state its time estimate and pause for the user's go-ahead — never run tasks back-to-back without a check-in, so the user can stop whenever they are short on time; at each check-in offer the choice to keep going one task at a time or to run all remaining tasks without further pauses (autopilot) — and always pause before any destructive or irreversible step regardless. Begin the actual work only after the user confirms. If a new request arrives while a task queue is already in progress, do not abandon or interrupt the in-flight list — fold the new request into the queue (add or revise tasks) and re-prioritize, so the user can keep submitting requests while existing tasks continue in order. EXCEPTION: if this prompt is itself a direct confirmation or answer to your own previous clarifying question, treat intent as confirmed and proceed without re-echoing."

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $m
  }
}'
