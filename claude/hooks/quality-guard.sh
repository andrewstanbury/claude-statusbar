#!/usr/bin/env bash
# Quality guard: PreToolUse on Edit|Write|MultiEdit. BLOCKS an edit that
# INTRODUCES a violation of the established quality/design patterns — the goal is
# to keep change quality high, optimize token spend, and minimise tech debt.
#
# Only the text THIS edit introduces is inspected (Write.content / Edit.new_string
# / MultiEdit.edits[].new_string), so pre-existing issues in untouched code are
# never blocked. Each check has its own override env var (raise-the-bar, don't
# disable — see CLAUDE.md "Hook denies").
#
#   1. Debug code  console.log/console.debug/debugger/global alert( in app code
#                  → CLAUDE_DEBUG_GUARD_DISABLED=1
#   2. TDD         a NEW /components/*.tsx with no co-located test (test-first)
#                  → CLAUDE_TDD_GUARD_DISABLED=1
#   3. TODO        TODO/FIXME/HACK/XXX comment without an (owner, date) tag
#                  → CLAUDE_TODO_GUARD_DISABLED=1
#   4. Skip        .skip/xit/xdescribe/t.Skip in a test without an expiry marker
#                  → CLAUDE_SKIP_GUARD_DISABLED=1
set -euo pipefail

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -z "$file_path" ] && exit 0

deny() {
  jq -nc --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Text this edit would introduce.
content="$(printf '%s' "$payload" | jq -r '
  [ .tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string) ]
  | map(select(. != null)) | join("\n")')"

# Is this an app source file (not a test / script / tooling)?
is_app_code=0
case "$file_path" in
  *.test.*|*.spec.*|*/__tests__/*|*/scripts/*|*/tools/*|*/bin/*) ;;
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) is_app_code=1 ;;
esac

# ─── 1. Debug code (app code only) ──────────────────────────────────────
# console.warn/error are legitimate; the alert lookbehind excludes method calls
# like React Native's Alert.alert(. Requires grep -P (GNU/PCRE).
if [ "${CLAUDE_DEBUG_GUARD_DISABLED:-0}" != "1" ] && [ "$is_app_code" = "1" ] && [ -n "$content" ]; then
  if printf '%s' "$content" | grep -qP '\bconsole\.(log|debug)\(|\bdebugger\b|(?<![\w.])alert\('; then
    deny "Quality guard: this edit introduces debug code (console.log/console.debug/debugger/alert) into app code ($file_path). Remove it or use a real logger — console.warn/error are allowed. Override: CLAUDE_DEBUG_GUARD_DISABLED=1."
  fi
fi

# ─── 3. Untracked TODO/FIXME/HACK/XXX (any non-doc source) ──────────────
# Only flags real comment markers; requires a KEYWORD(owner, date) tag.
if [ "${CLAUDE_TODO_GUARD_DISABLED:-0}" != "1" ] && [ -n "$content" ]; then
  case "$file_path" in
    *.md|*.markdown|*.mdx) ;;
    *)
      todo_lines="$(printf '%s' "$content" | grep -E '(//|/\*|^[[:space:]]*\*|#|<!--)[[:space:]]*(TODO|FIXME|HACK|XXX)\b' || true)"
      if [ -n "$todo_lines" ] && printf '%s' "$todo_lines" | grep -qvE '(TODO|FIXME|HACK|XXX)\([^)]+\)'; then
        deny "Quality guard: TODO/FIXME/HACK/XXX without an owner+date tag in $file_path. Use e.g. \`TODO(andrew, 2026-05-26): …\` so the debt is tracked, not lost. Override: CLAUDE_TODO_GUARD_DISABLED=1."
      fi
      ;;
  esac
fi

# ─── 4. Skipped test without an expiry marker (test files) ──────────────
if [ "${CLAUDE_SKIP_GUARD_DISABLED:-0}" != "1" ] && [ -n "$content" ]; then
  case "$file_path" in
    *.test.*|*.spec.*|*/__tests__/*)
      if printf '%s' "$content" | grep -qE '\.skip\(|\bxit\(|\bxdescribe\(|\bt\.Skip\('; then
        if ! printf '%s' "$content" | grep -qiE 'expires|expire|[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
          deny "Quality guard: skipped test (.skip/xit/xdescribe/t.Skip) without an expiry marker in $file_path. Add e.g. \`// expires 2026-06-30: <reason>\` so it can't silently rot. Override: CLAUDE_SKIP_GUARD_DISABLED=1."
        fi
      fi
      ;;
  esac
fi

# ─── 2. Component without a co-located test (test-first) ────────────────
# ANY /components/*.tsx — new OR existing — with no co-located test. Editing an
# untested component is blocked until a test exists alongside it. (Override per
# project/edit if touching legacy: CLAUDE_TDD_GUARD_DISABLED=1.)
if [ "${CLAUDE_TDD_GUARD_DISABLED:-0}" != "1" ]; then
  case "$file_path" in
    *.test.tsx|*.spec.tsx|*/__tests__/*) ;;
    */components/*.tsx)
      dir="$(dirname "$file_path")"
      base="$(basename "$file_path" .tsx)"
      if [ ! -f "$dir/__tests__/${base}.test.tsx" ] \
         && [ ! -f "$dir/${base}.test.tsx" ] \
         && [ ! -f "$dir/__tests__/${base}.test.ts" ]; then
        deny "Quality guard (TDD): component $file_path has no co-located test. Write $dir/__tests__/${base}.test.tsx first (test-first), then edit the component. Override: CLAUDE_TDD_GUARD_DISABLED=1."
      fi
      ;;
  esac
fi

exit 0
