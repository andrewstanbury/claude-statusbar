#!/usr/bin/env bash
# Aggregator: PostToolUse on Edit/Write/MultiEdit. Three soft nudges (never block):
#   1. TODO/FIXME/HACK/XXX without owner+date in parens
#   2. Test .skip / xit / xdescribe / t.Skip without "expires" marker nearby
#   3. console.log / debugger / alert( in non-test app code
#
# Each nudge surfaces via `additionalContext` (PostToolUse JSON). Silenceable
# per-nudge via env vars: CLAUDE_{TODO,SKIP,DEBUG}_NUDGE_DISABLED=1.
#
# Best-effort: silent on any error, never blocks the edit.
set -euo pipefail

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"

[ -z "$file_path" ] && exit 0

# ─── Extract written content from the tool payload ──────────────────────
# Edit: new_string. Write: content. MultiEdit: concat edits[].new_string.
case "$tool_name" in
  Write)
    content="$(printf '%s' "$payload" | jq -r '.tool_input.content // ""')"
    ;;
  Edit)
    content="$(printf '%s' "$payload" | jq -r '.tool_input.new_string // ""')"
    ;;
  MultiEdit)
    content="$(printf '%s' "$payload" | jq -r '.tool_input.edits // [] | map(.new_string // "") | join("\n")')"
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$content" ] && exit 0

# Skip docs / binaries / generated / dependency dirs.
case "$file_path" in
  *.md|*.markdown|*.mdx) skip_todo=0 ;;  # md still gets TODO check below
esac
case "$file_path" in
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf|*.ico|*.woff|*.woff2|*.ttf|*.otf|*.lock|*-lock.json) exit 0 ;;
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/.expo/*|*/.git/*|*/vendor/*|*/coverage/*|*/.cache/*) exit 0 ;;
  */generated/*|*.generated.*|*_pb.go|*_pb.ts|*.pb.go) exit 0 ;;
esac

nudges=()

# ─── 1. TODO/FIXME/HACK/XXX without owner+date ──────────────────────────
# A marker is "owned" iff followed by non-empty parens: TODO(@andrew, 2026-06).
# Bare "TODO:" / "TODO " / "FIXME -" / EOL "HACK" all trigger the nudge.
if [ "${CLAUDE_TODO_NUDGE_DISABLED:-0}" != "1" ]; then
  case "$file_path" in
    *.md|*.markdown|*.mdx) ;;  # skip docs — TODO lists in markdown are intentional
    *)
      if printf '%s' "$content" | awk '
        /\<(TODO|FIXME|HACK|XXX)\>/ {
          # If marker is followed by ( with non-empty contents, treat as owned.
          if ($0 ~ /\<(TODO|FIXME|HACK|XXX)\([^)]+\)/) next
          found=1
        }
        END { exit !found }
      '; then
        nudges+=("📝 Unowned TODO/FIXME/HACK in this edit. Add owner+date so it doesn't rot: \`TODO(@you, YYYY-MM): reason\`. Silence: export CLAUDE_TODO_NUDGE_DISABLED=1.")
      fi
      ;;
  esac
fi

# ─── 2. Test skip without expiry marker ─────────────────────────────────
# Skipped tests silently rot. Require a nearby "expires" / date marker.
if [ "${CLAUDE_SKIP_NUDGE_DISABLED:-0}" != "1" ]; then
  case "$file_path" in
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx|*_test.go|*/__tests__/*)
      if printf '%s' "$content" | grep -qE '(\.skip\(|\<xit\(|\<xtest\(|\<xdescribe\(|\<t\.Skip\()'; then
        # Accept any of: "expires", "expiry", "remove after/by", or a 20YY date nearby.
        if ! printf '%s' "$content" | grep -qiE '(expires|expiry|remove (after|by)|unskip|20[0-9]{2}-[0-9]{2})'; then
          nudges+=("⏭️  Test skip added without expiry. Skipped tests rot — add \`// expires YYYY-MM-DD: <reason>\` nearby. Silence: export CLAUDE_SKIP_NUDGE_DISABLED=1.")
        fi
      fi
      ;;
  esac
fi

# ─── 3. console.log / debugger / alert in non-test app code ─────────────
# console.warn/error are legitimate logging; only flag .log/.debug + debugger + alert.
# The alert check uses a negative lookbehind (?<![\w.]) so the browser global
# alert( is flagged but METHOD calls like React Native's Alert.alert( / foo.alert(
# are not. Requires grep -P (GNU/PCRE).
if [ "${CLAUDE_DEBUG_NUDGE_DISABLED:-0}" != "1" ]; then
  case "$file_path" in
    *.test.*|*.spec.*|*/__tests__/*|*/scripts/*|*/tools/*|*/bin/*) ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
      if printf '%s' "$content" | grep -qP '\bconsole\.(log|debug)\(|\bdebugger\b|(?<![\w.])alert\('; then
        nudges+=("🐛 \`console.log\`/\`debugger\`/\`alert(\` slipped into app code. Remove or convert to a proper logger before commit. Silence: export CLAUDE_DEBUG_NUDGE_DISABLED=1.")
      fi
      ;;
  esac
fi

[ ${#nudges[@]} -eq 0 ] && exit 0

msg=$(printf '%s\n' "${nudges[@]}")

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $m
  }
}'
