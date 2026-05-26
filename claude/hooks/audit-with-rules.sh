#!/usr/bin/env bash
# UserPromptSubmit hook: when the user asks to audit / review (or similar) a
# project, inject the full claude-statusbar standards checklist so the audit is
# performed against THIS config's rules, not ad-hoc. Complements the
# enforcement hooks (quality-guard, deadcode, web-standards) that gate edits —
# this drives the read-only audit/review pass over an existing codebase.
set -euo pipefail

# Escape hatch (matches the other hooks' override convention).
[ "${CLAUDE_AUDIT_RULES_DISABLED:-0}" = "1" ] && exit 0

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty')"
[ -z "$prompt" ] && exit 0

# Fire only when the prompt reads like an audit/review/assessment request.
# Stems (no trailing \b) catch inflections: auditing, reviewing, evaluating,
# assessment, inspection. Leading \b keeps "preview"/"overview" from matching.
printf '%s' "$prompt" \
  | grep -qiE '\b(audit|review|assess|evaluat|critiqu|apprais|inspect)' \
  || exit 0

msg="This request is a project audit/review. Evaluate the target project against ALL claude-statusbar standards and report each finding as file:line + the rule it breaks + a concrete fix. Checklist:
- Debug code in app code: console.log / console.debug / debugger / global alert(.
- Test-first: any components/*.tsx (new or existing) without a co-located test.
- Untracked TODO / FIXME / HACK / XXX lacking an (owner, date) tag.
- Skipped tests (.skip / xit / xdescribe / t.Skip) with no expiry marker.
- Dead code: commented-out code blocks; tool-confirmed unused imports/vars; heavy line duplication.
- Web standards (HTML/DOM projects ONLY, never React Native <View>/<Text>): <img> without alt; nested interactive controls (<a>/<button> inside each other); clickable <div>/<span> without role; full HTML doc missing <html lang> / <title> / <meta name=description>; more than one <h1>; invalid nesting (block element in <p>, non-<li> children of <ul>/<ol>); inputs without <label>/aria-label; SEO heading order / canonical / Open Graph.
This is read-only: report findings, do not edit unless the user then asks. Skip any check that does not apply to the project's stack (e.g. web standards on a non-web project)."

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $m
  }
}'
