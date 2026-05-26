#!/usr/bin/env bash
# Soft TDD nudge: PostToolUse on Edit/Write/MultiEdit. When a component
# file (app/**/components/*.tsx or components/*.tsx, but NOT a test file
# itself) is touched and no sibling __tests__/<basename>.test.tsx exists,
# emit an `additionalContext` reminder. Does NOT block.
#
# Scoped tight on purpose: nudging every edit would be spam. Only nudges
# on:
#   * .tsx files
#   * paths matching /components/ (case-sensitive)
#   * not already a test file
#   * with no co-located test
set -euo pipefail

[ "${CLAUDE_TDD_NUDGE_DISABLED:-0}" = "1" ] && exit 0

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"

[ -z "$file_path" ] && exit 0

# Only nudge for .tsx component files.
case "$file_path" in
  *.test.tsx|*.test.ts|*.spec.tsx|*.spec.ts) exit 0 ;;
  *__tests__*) exit 0 ;;
  *.tsx) ;;
  *) exit 0 ;;
esac

# Must contain /components/ in path.
case "$file_path" in
  */components/*) ;;
  *) exit 0 ;;
esac

# Check for a sibling test file.
dir="$(dirname "$file_path")"
base="$(basename "$file_path" .tsx)"

if [ -f "$dir/__tests__/${base}.test.tsx" ]; then exit 0; fi
if [ -f "$dir/${base}.test.tsx" ]; then exit 0; fi
if [ -f "$dir/__tests__/${base}.test.ts" ]; then exit 0; fi

# No sibling test — emit a context nudge for the next turn.
msg="🧪 TDD nudge: ${file_path} has no co-located test. Consider adding ${dir}/__tests__/${base}.test.tsx before further edits. See app/(app)/programs/[id]/components/__tests__/mark-complete.test.tsx for the pattern. Silence: export CLAUDE_TDD_NUDGE_DISABLED=1."

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $m
  }
}'
