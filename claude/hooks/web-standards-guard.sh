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

# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/web-standards-checks.sh"

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

# Shared document-level SEO/a11y checks (full-<html> lang/title/meta, 2+ <h1>,
# clickable <div>/<span> without role) — see lib/web-standards-checks.sh.
errors="${errors}$(ws_doc_findings "$flat")"

[ -z "$errors" ] && exit 0

reason="$(printf 'Web standards guard blocked this edit — egregious HTML/a11y error(s):%b\n\nFix the markup, or set CLAUDE_WEB_GUARD_DISABLED=1 to override.' "$errors")"

jq -nc --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
