#!/usr/bin/env bash
# Dead-code / redundancy guard + recommender. ONE script, two modes (so the
# block path and the recommend path can't drift):
#
#   deadcode.sh pre   — PreToolUse: BLOCK a clear-cut introduce (a commented-out
#                       code block being added). Reliable + snippet-detectable.
#   deadcode.sh post  — PostToolUse: threshold-gated. On a substantial app-code
#                       file, run cheap static checks + the project's own linter
#                       (when present) and surface dead/redundant code. Tool-
#                       confirmed dead code (unused imports/vars) → decision:block
#                       (Claude must address it); fuzzier static findings → nudge.
#
# Token-efficient: zero tokens (static + local tools only); the post pass stays
# SILENT unless the file is ≥ CLAUDE_DEADCODE_MIN_LOC (default 150) lines.
#
# Overrides: CLAUDE_DEADCODE_DISABLED=1 (both), CLAUDE_DEADCODE_MIN_LOC=<n>.
set -euo pipefail

mode="${1:-post}"
[ "${CLAUDE_DEADCODE_DISABLED:-0}" = "1" ] && exit 0

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -z "$file_path" ] && exit 0

# Only app source (skip tests/generated/vendored/docs).
case "$file_path" in
  *.test.*|*.spec.*|*/__tests__/*|*/node_modules/*|*/dist/*|*/build/*|*.generated.*) exit 0 ;;
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.go|*.py|*.rb) ;;
  *) exit 0 ;;
esac

# A run of >=4 consecutive comment lines whose stripped body is statement-like
# (ends in ;{}, , or contains =>) — i.e. commented-out CODE, not prose.
commented_code_block() {
  printf '%s' "$1" | awk '
    { line=$0; sub(/^[[:space:]]+/,"",line)
      is_c = (line ~ /^(\/\/|#|\*|--)/)
      body = line; sub(/^(\/\/|#|\*|--)[[:space:]]*/,"",body)
      looks_code = (body ~ /[;{},]$/ || body ~ /=>/ || body ~ /^(const|let|var|function|func|def|return|import|export|class|if|for|while)\b.*[({=]/)
      if (is_c && looks_code) { run++; if (run>=4) { found=1 } } else { run=0 }
    }
    END { exit (found?0:1) }
  '
}

# ── PRE: block a commented-out code block being introduced ──────────────
if [ "$mode" = "pre" ]; then
  content="$(printf '%s' "$payload" | jq -r '
    [ .tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string) ]
    | map(select(. != null)) | join("\n")')"
  [ -z "$content" ] && exit 0
  if commented_code_block "$content"; then
    jq -nc --arg r "Dead-code guard: this edit introduces a block of commented-out code in $file_path. Delete it — version control is the history. Override: CLAUDE_DEADCODE_DISABLED=1." \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  fi
  exit 0
fi

# ── POST: threshold-gated recommend (+ tool-confirmed block) ────────────
[ -f "$file_path" ] || exit 0
loc=$(wc -l < "$file_path" 2>/dev/null || echo 0)
[ "$loc" -lt "${CLAUDE_DEADCODE_MIN_LOC:-150}" ] && exit 0   # quiet on small files

block=""   # tool-confirmed, clear-cut → forces a fix
nudge=""   # heuristic → recommendation

# Tool-confirmed (zero tokens, accurate): run the project's own ESLint on just
# this file when it's a JS/TS file in a project that has ESLint configured.
case "$file_path" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    root="$(dirname "$file_path")"
    while [ "$root" != "/" ] && [ ! -e "$root/package.json" ]; do root="$(dirname "$root")"; done
    if [ -e "$root/package.json" ] && ls "$root"/.eslintrc* "$root"/eslint.config.* >/dev/null 2>&1; then
      unused="$(cd "$root" && timeout 15 npx --no-install eslint --format json "$file_path" 2>/dev/null \
        | jq -r '[.[].messages[]? | select(.ruleId|test("no-unused-vars|unused-imports")) | "L\(.line) \(.message)"] | .[0:5] | join("; ")' 2>/dev/null || true)"
      [ -n "$unused" ] && [ "$unused" != "null" ] && block="unused import/variable (ESLint): $unused"
    fi
    ;;
esac

# Heuristic (static): commented-out code still sitting in the file.
commented_code_block "$(cat "$file_path")" && nudge="${nudge}\n  • commented-out code present — delete it (history is in git)"

# Heuristic (static): copy-paste — many repeated substantial lines.
dups=$(grep -vE '^[[:space:]]*([}{)(\[\];,]|//|\*|#|$)' "$file_path" 2>/dev/null \
  | sed 's/^[[:space:]]*//' | awk 'length>25' | sort | uniq -d | wc -l | tr -d ' ' || true)
[ "${dups:-0}" -ge 5 ] && nudge="${nudge}\n  • ${dups} substantial lines are duplicated — likely copy-paste; consider extracting a helper"

if [ -n "$block" ]; then
  jq -nc --arg r "Dead-code: $file_path has $block. Remove the unused symbols (right-size the file to what it actually uses) before moving on." \
    '{decision:"block", reason:$r}'
  exit 0
fi
if [ -n "$nudge" ]; then
  jq -nc --arg m "$(printf '🧹 Maintainability (%s, %s LOC):%b\n\nKeep LOC matched to real complexity. Silence: CLAUDE_DEADCODE_DISABLED=1.' "$file_path" "$loc" "$nudge")" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
fi
exit 0
