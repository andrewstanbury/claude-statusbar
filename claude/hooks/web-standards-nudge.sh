#!/usr/bin/env bash
# Web standards nudge: PostToolUse on Edit|Write|MultiEdit. After a web-markup
# file is written, scans it for softer, document-level SEO/a11y issues and emits
# a non-blocking additionalContext reminder. Mirrors the TDD nudge. Hard
# validity errors are caught (and blocked) by web-standards-guard.sh.
#
# Scoped to real web markup: .html/.htm always; .jsx/.tsx/.vue/.svelte/.astro
# only when the file contains lowercase DOM tags — so React Native (<View>/
# <Text>/<Image>) is never nudged.
#
# Silence: CLAUDE_WEB_NUDGE_DISABLED=1
set -euo pipefail

[ "${CLAUDE_WEB_NUDGE_DISABLED:-0}" = "1" ] && exit 0

# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/web-standards-checks.sh"

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')"
[ -z "$file_path" ] && exit 0
[ -f "$file_path" ] || exit 0

case "$file_path" in
  *.html|*.htm) ;;
  *.jsx|*.tsx|*.vue|*.svelte|*.astro)
    grep -qE '<(div|span|p|a|img|ul|ol|li|button|section|main|nav|header|footer|h[1-6]|form|input|label)[ >/]' "$file_path" || exit 0
    ;;
  *) exit 0 ;;
esac

flat="$(tr '\n\t' '  ' < "$file_path")"
# Shared document-level SEO/a11y checks — see lib/web-standards-checks.sh.
warns="$(ws_doc_findings "$flat")"

[ -z "$warns" ] && exit 0

msg="$(printf '🌐 Web standards nudge for %s:%b\n\nAddress before shipping; run html-validate / eslint-plugin-jsx-a11y for a full pass, and Lighthouse in CI. Silence: CLAUDE_WEB_NUDGE_DISABLED=1.' "$file_path" "$warns")"

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $m
  }
}'
