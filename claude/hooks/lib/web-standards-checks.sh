#!/usr/bin/env bash
# Shared web-standards detection — sourced by web-standards-guard.sh (PreToolUse,
# blocks) and web-standards-nudge.sh (PostToolUse, recommends) so the two can't
# drift. Not executed directly; no shebang behaviour relied on.
#
# ws_doc_findings <flat_content>
#   <flat_content>: the markup with newlines/tabs already collapsed to spaces.
#   Echoes a string of "\n  • <finding>" bullets (empty if none); the caller
#   renders it with printf %b. Covers the document-level SEO/a11y checks both
#   hooks share:
#     * a full <html> doc missing lang / <title> / <meta name=description>
#     * more than one <h1>
#     * clickable <div>/<span> with no role
#   <h1> is matched case-sensitively, so React Native (<View>/<Text>) is unaffected.
ws_doc_findings() {
  local flat="$1" out=""
  if printf '%s' "$flat" | grep -qiE '<html'; then
    printf '%s' "$flat" | grep -qiE '<html[^>]*[[:space:]]lang='   || out="${out}\n  • <html> has no lang attribute (a11y/SEO)"
    printf '%s' "$flat" | grep -qiE '<title>[^<]'                  || out="${out}\n  • no non-empty <title> (SEO)"
    printf '%s' "$flat" | grep -qiE '<meta[^>]+name="description"' || out="${out}\n  • no <meta name=\"description\"> (SEO)"
  fi
  local h1
  h1=$(printf '%s' "$flat" | grep -oE '<h1[ >]' | wc -l | tr -d ' ' || true)
  [ "${h1:-0}" -gt 1 ] && out="${out}\n  • ${h1} <h1> headings — use a single <h1> per page (SEO/structure)"
  if printf '%s' "$flat" | grep -qE '<(div|span)[^>]*[[:space:]]on[Cc]lick' \
     && ! printf '%s' "$flat" | grep -qE '<(div|span)[^>]*[[:space:]]on[Cc]lick[^>]*role='; then
    out="${out}\n  • clickable <div>/<span> with no role — use <button> for keyboard/a11y"
  fi
  printf '%s' "$out"
}
