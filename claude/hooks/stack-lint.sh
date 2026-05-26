#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit) ADVISORY stack-aware linter. When you edit a
# source file, run the right linter for its language on JUST that file and surface
# improvement suggestions — incremental (never a whole-project audit), and it
# NEVER blocks the edit. This is the "optimize the code over time" layer.
#
# Local-first / token-frugal: detection is 100% local (project linter → global
# linter → in-house heuristic floor) and costs 0 model tokens. Only when local
# findings are heavy (more than MAX) does it spend a cheap Haiku pass to triage
# down to the few highest-value fixes. 0 findings → silent.
#
# Complements (does NOT replace): quality-guard (hard blocks debug/TODO/skip),
# deadcode (dead/commented code), web-standards-nudge (HTML a11y/SEO). Those keep
# their existing blocking behaviour; this layer is purely advisory.
#
# Overrides:
#   CLAUDE_STACK_LINT_DISABLED=1   off entirely
#   CLAUDE_STACK_LINT_TRIAGE=0     never call Haiku; always surface raw findings
#   CLAUDE_STACK_LINT_MAX=<n>      triage threshold (default 5)
set -euo pipefail

[ "${CLAUDE_STACK_LINT_DISABLED:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# Skip tests / generated / vendored — advice there is noise.
case "$file" in
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/.expo/*|*/vendor/*|*.generated.*|*.min.js) exit 0 ;;
esac

MAX="${CLAUDE_STACK_LINT_MAX:-5}"
dir="$(dirname "$file")"

# Nearest ancestor dir containing any marker; prints it, or nothing.
find_root() {
  local d="$1"; shift
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    local m; for m in "$@"; do [ -e "$d/$m" ] && { printf '%s' "$d"; return 0; }; done
    [ "$d" = "." ] && break
    d="$(dirname "$d")"
  done
  return 0
}

# Each linter fn echoes up to ~40 lines of "L<line> <rule> — <message>".
lint_js() {
  local root raw
  root="$(find_root "$dir" package.json)"
  if [ -n "$root" ] && ls "$root"/.eslintrc* "$root"/eslint.config.* >/dev/null 2>&1; then
    raw="$( ( cd "$root" && timeout 20 npx --no-install eslint --format json "$file" ) 2>/dev/null || true)"
  elif command -v eslint >/dev/null 2>&1; then
    raw="$(timeout 20 eslint --format json "$file" 2>/dev/null || true)"
  fi
  if [ -n "${raw:-}" ]; then
    printf '%s' "$raw" | jq -r '[.[].messages[]? | "L\(.line) \(.ruleId // "eslint") — \(.message)"] | .[0:40] | join("\n")' 2>/dev/null || true
    return 0
  fi
  grep -nE 'console\.(log|debug|trace)\(|^[[:space:]]*debugger\b' "$file" 2>/dev/null \
    | sed -E 's/^([0-9]+):.*/L\1 no-debug — debug logging\/debugger left in source/' | head -20 || true
}

lint_py() {
  local root out
  root="$(find_root "$dir" pyproject.toml setup.cfg .git)"
  if command -v ruff >/dev/null 2>&1; then
    out="$( ( cd "${root:-$dir}" && timeout 20 ruff check --quiet --output-format=concise "$file" ) 2>/dev/null || true)"
  elif command -v flake8 >/dev/null 2>&1; then
    out="$( ( cd "${root:-$dir}" && timeout 20 flake8 "$file" ) 2>/dev/null || true)"
  fi
  if [ -n "${out:-}" ]; then
    printf '%s' "$out" | sed -E 's#^[^:]+:([0-9]+):[0-9]+:[[:space:]]*([A-Z][0-9]+)?[[:space:]]*(.*)#L\1 \2 — \3#' | head -40 || true
    return 0
  fi
  grep -nE 'breakpoint\(\)|pdb\.set_trace\(|^[[:space:]]*except[[:space:]]*:' "$file" 2>/dev/null \
    | sed -E 's/^([0-9]+):.*/L\1 smell — debugger\/bare-except — remove or narrow/' | head -20 || true
}

lint_go() {
  local root out
  root="$(find_root "$dir" go.mod)"
  [ -z "$root" ] && { command -v go >/dev/null 2>&1 || return 0; }
  if command -v golangci-lint >/dev/null 2>&1 && [ -n "$root" ]; then
    out="$( ( cd "$root" && timeout 25 golangci-lint run "$dir/..." ) 2>/dev/null || true)"
  elif command -v go >/dev/null 2>&1 && [ -n "$root" ]; then
    out="$( ( cd "$root" && timeout 20 go vet "./$(realpath --relative-to="$root" "$dir")" ) 2>&1 || true)"
  fi
  if [ -n "${out:-}" ]; then
    printf '%s' "$out" | grep -E '\.go:[0-9]+:' | sed -E 's#.*\.go:([0-9]+):[0-9]*:?[[:space:]]*(.*)#L\1 vet — \2#' | head -40 || true
    return 0
  fi
  grep -nE 'fmt\.Print(ln|f)?\(' "$file" 2>/dev/null \
    | sed -E 's/^([0-9]+):.*/L\1 debug — fmt.Print* left in source; use a logger or remove/' | head -20 || true
}

lint_rb() {
  if command -v rubocop >/dev/null 2>&1; then
    timeout 20 rubocop --format emacs "$file" 2>/dev/null \
      | sed -E 's#^[^:]+:([0-9]+):[0-9]+:[[:space:]]*[A-Z]:[[:space:]]*(.*)#L\1 rubocop — \2#' | head -40 || true
    return 0
  fi
  grep -nE 'binding\.pry|byebug|^[[:space:]]*puts[[:space:]]' "$file" 2>/dev/null \
    | sed -E 's/^([0-9]+):.*/L\1 smell — debugger\/puts left in source/' | head -20 || true
}

lint_sh() {
  if command -v shellcheck >/dev/null 2>&1; then
    timeout 20 shellcheck -f gcc "$file" 2>/dev/null \
      | sed -E 's#^[^:]+:([0-9]+):[0-9]+:[[:space:]]*[a-z]+:[[:space:]]*(.*)#L\1 shellcheck — \2#' | head -40 || true
  fi
  # No heuristic floor for shell — too noisy without shellcheck.
}

lint_rs() {
  # clippy compiles the whole crate (CI-grade, too slow per-edit) — heuristics only.
  grep -nE 'dbg!\(|todo!\(|unimplemented!\(|println!\(' "$file" 2>/dev/null \
    | sed -E 's/^([0-9]+):.*/L\1 smell — dbg!\/todo!\/println! left in source/' | head -20 || true
}

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) findings="$(lint_js)" ;;
  *.py)                              findings="$(lint_py)" ;;
  *.go)                              findings="$(lint_go)" ;;
  *.rb)                              findings="$(lint_rb)" ;;
  *.sh|*.bash)                       findings="$(lint_sh)" ;;
  *.rs)                              findings="$(lint_rs)" ;;
  *) exit 0 ;;
esac

findings="$(printf '%s' "${findings:-}" | sed '/^[[:space:]]*$/d')"
[ -z "$findings" ] && exit 0
count="$(printf '%s\n' "$findings" | grep -c . || true)"

# Heavy + triage enabled + claude available → cheap Haiku triage to the top few.
# Suppress our own prompt hooks in the nested call so they don't derail triage.
if [ "${count:-0}" -gt "$MAX" ] && [ "${CLAUDE_STACK_LINT_TRIAGE:-1}" != "0" ] && command -v claude >/dev/null 2>&1; then
  prompt="$(printf 'Lint findings for %s (one per line). List ONLY the 3 highest-value fixes, each as "L<line> — <one-line fix>". No preamble, no extra text.\n\n%s' "$file" "$findings")"
  triaged="$(CLAUDE_INTENT_CONFIRM_DISABLED=1 CLAUDE_AUDIT_RULES_DISABLED=1 CLAUDE_STACK_LINT_DISABLED=1 \
    timeout 25 claude -p "$prompt" --model haiku 2>/dev/null || true)"
  [ -n "${triaged:-}" ] && findings="$(printf '%s' "$triaged" | sed '/^[[:space:]]*$/d' | head -5)"
fi

# Bound the surfaced list so a noisy file can't balloon context (token guard).
findings="$(printf '%s' "$findings" | head -10)"

msg="$(printf '🔎 Stack-lint — advisory (not blocking), %s:\n%s\n\nSuggestions only; address what is worthwhile. Silence: CLAUDE_STACK_LINT_DISABLED=1.' \
  "$file" "$(printf '%s' "$findings" | sed 's/^/  • /')")"
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
