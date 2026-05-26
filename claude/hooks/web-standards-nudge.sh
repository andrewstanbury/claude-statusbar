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
warns=""

# Whole-document checks only when this is a full HTML document.
if printf '%s' "$flat" | grep -qiE '<html'; then
  printf '%s' "$flat" | grep -qiE '<html[^>]*[[:space:]]lang=' || warns="${warns}\n  • <html> has no lang attribute (a11y/SEO)"
  printf '%s' "$flat" | grep -qiE '<title>[^<]' || warns="${warns}\n  • no non-empty <title> (SEO)"
  printf '%s' "$flat" | grep -qiE '<meta[^>]+name="description"' || warns="${warns}\n  • no <meta name=\"description\"> (SEO)"
fi

# More than one <h1> (case-sensitive tag).
h1=$(printf '%s' "$flat" | grep -oE '<h1[ >]' | wc -l | tr -d ' ' || true)
[ "${h1:-0}" -gt 1 ] && warns="${warns}\n  • ${h1} <h1> headings — use one per page (SEO/structure)"

# Click handler on a non-interactive element with no role.
if printf '%s' "$flat" | grep -qE '<(div|span)[^>]*[[:space:]]on[Cc]lick' \
   && ! printf '%s' "$flat" | grep -qE '<(div|span)[^>]*[[:space:]]on[Cc]lick[^>]*role='; then
  warns="${warns}\n  • clickable <div>/<span> with no role — prefer <button> for keyboard/a11y"
fi

[ -z "$warns" ] && exit 0

msg="$(printf '🌐 Web standards nudge for %s:%b\n\nAddress before shipping; run html-validate / eslint-plugin-jsx-a11y for a full pass, and Lighthouse in CI. Silence: CLAUDE_WEB_NUDGE_DISABLED=1.' "$file_path" "$warns")"

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $m
  }
}'
