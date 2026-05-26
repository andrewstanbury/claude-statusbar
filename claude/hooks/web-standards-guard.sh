#!/usr/bin/env bash
# Web standards guard: PreToolUse on Edit|Write|MultiEdit. BLOCKS an edit that
# introduces an egregious, high-confidence HTML/JSX validity or a11y error:
#   * <img> with no alt attribute (decorative alt="" is fine)
#   * a nested interactive control on one source line: <a>…<a, <button>…<button>
# Softer / document-level issues are advisory only (see web-standards-nudge.sh).
#
# Only inspects the text THIS edit introduces, and only for web-markup file
# extensions. Tag names are matched case-sensitively, so capitalized components
# (React Native <Image>/<Pressable>, Next.js <Image>) never match — RN is
# unaffected.
#
# Override (let the edit through): CLAUDE_WEB_GUARD_DISABLED=1
set -euo pipefail

[ "${CLAUDE_WEB_GUARD_DISABLED:-0}" = "1" ] && exit 0

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -z "$file_path" ] && exit 0

case "$file_path" in
  *.html|*.htm|*.jsx|*.tsx|*.vue|*.svelte|*.astro) ;;
  *) exit 0 ;;
esac

# Text this edit would introduce: Write.content, Edit.new_string, or each
# MultiEdit edit's new_string.
content="$(printf '%s' "$payload" | jq -r '
  [ .tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string) ]
  | map(select(. != null)) | join("\n")')"
[ -z "$content" ] && exit 0

# Flatten newlines so multi-line tags are matched as a unit.
flat="$(printf '%s' "$content" | tr '\n\t' '  ')"
errors=""

# <img> with no alt (case-sensitive tag → excludes <Image>; skip JSX spread and
# explicitly-decorative/hidden images).
while IFS= read -r tag; do
  [ -z "$tag" ] && continue
  case "$tag" in *"{..."*) continue ;; esac
  printf '%s' "$tag" | grep -qiE 'alt=' && continue
  printf '%s' "$tag" | grep -qiE 'aria-hidden="true"|role="presentation"' && continue
  errors="${errors}\n  • <img> with no alt text:  ${tag}"
done < <(printf '%s' "$flat" | grep -oE '<img[^>]*>' || true)

# Nested interactive controls on one source line (invalid HTML).
if printf '%s' "$content" | grep -qE '<a[ >][^>]*>[^<]*<a[ >]'; then
  errors="${errors}\n  • nested <a> inside <a> (invalid; breaks a11y + SEO)"
fi
if printf '%s' "$content" | grep -qE '<button[ >][^>]*>[^<]*<button[ >]'; then
  errors="${errors}\n  • nested <button> inside <button> (invalid)"
fi

# Document-level SEO essentials — only when this edit writes a FULL HTML document
# (content contains <html>), so HTML fragments / JSX components are never flagged.
if printf '%s' "$flat" | grep -qiE '<html'; then
  printf '%s' "$flat" | grep -qiE '<html[^>]*[[:space:]]lang=' || errors="${errors}\n  • <html> has no lang attribute (a11y/SEO)"
  printf '%s' "$flat" | grep -qiE '<title>[^<]'                || errors="${errors}\n  • no non-empty <title> (SEO)"
  printf '%s' "$flat" | grep -qiE '<meta[^>]+name="description"' || errors="${errors}\n  • no <meta name=\"description\"> (SEO)"
fi

# More than one <h1> introduced by THIS edit (case-sensitive → ignores RN/components).
h1=$(printf '%s' "$flat" | grep -oE '<h1[ >]' | wc -l | tr -d ' ' || true)
if [ "${h1:-0}" -gt 1 ]; then
  errors="${errors}\n  • ${h1} <h1> headings in one edit — use a single <h1> per page (SEO/structure)"
fi

# Click handler on a non-interactive element with no role (introduce-only).
if printf '%s' "$content" | grep -qE '<(div|span)[^>]*[[:space:]]on[Cc]lick' \
   && ! printf '%s' "$content" | grep -qE '<(div|span)[^>]*[[:space:]]on[Cc]lick[^>]*role='; then
  errors="${errors}\n  • clickable <div>/<span> with no role — use <button> for keyboard/a11y"
fi

[ -z "$errors" ] && exit 0

reason="$(printf 'Web standards guard blocked this edit — egregious HTML/a11y error(s):%b\n\nFix the markup, or set CLAUDE_WEB_GUARD_DISABLED=1 to override.' "$errors")"

jq -nc --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
