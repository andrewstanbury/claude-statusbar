#!/usr/bin/env bash
# Aggregator: PreToolUse on Edit/Write/MultiEdit. Runs bloat-guard
# (file LOC ceiling) AND docs-bloat-guard (per-doc caps) inline so the
# harness spawns ONE subprocess per Edit instead of two.
#
# Either guard can deny; first deny wins.
set -euo pipefail

LOC_THRESHOLD="${CLAUDE_BLOAT_THRESHOLD:-500}"

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"

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

# ─── 1. docs-bloat-guard ────────────────────────────────────────────────
# These files load EVERY conversation; each extra line costs ~5 tokens
# per turn per session.
basename="$(basename "$file_path")"
case "$basename" in
  AGENTS.md)  doc_cap="${CLAUDE_DOC_CAP_AGENTS:-120}" ;;
  CLAUDE.md)  doc_cap="${CLAUDE_DOC_CAP_CLAUDE:-100}" ;;
  MEMORY.md)  doc_cap="${CLAUDE_DOC_CAP_MEMORY:-200}" ;;
  *)          doc_cap="" ;;
esac
if [ -n "$doc_cap" ] && [ -f "$file_path" ]; then
  current=$(wc -l < "$file_path" 2>/dev/null || echo 0)
  if [ "$current" -ge "$doc_cap" ]; then
    # Write that shrinks under cap is allowed (the prune itself).
    if [ "$tool_name" = "Write" ]; then
      new_loc=$(printf '%s' "$payload" | jq -r '.tool_input.content // ""' | wc -l)
      if [ "$new_loc" -lt "$doc_cap" ]; then
        exit 0
      fi
    fi
    deny "$basename is $current lines (cap $doc_cap). Loads into context EVERY conversation — extra lines cost ~5 tokens × every turn × every session. Prune stale content first. Override: CLAUDE_DOC_CAP_${basename%.md}=<n>."
  fi
fi

# ─── 2. bloat-guard (file-LOC ceiling) ──────────────────────────────────
# Skipped paths: docs, lockfiles, generated artifacts.
[ ! -f "$file_path" ] && exit 0
case "$file_path" in
  *.md|*.markdown|*.mdx) exit 0 ;;
  *.lock|*-lock.json|*.lockb) exit 0 ;;
  *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*bun.lockb|*Cargo.lock|*go.sum|*Pipfile.lock|*poetry.lock|*composer.lock) exit 0 ;;
  *.svg|*.json) exit 0 ;;
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/.expo/*|*/.git/*|*/vendor/*|*/coverage/*|*/.cache/*) exit 0 ;;
  */generated/*|*.generated.*|*_pb.go|*_pb.ts|*.pb.go) exit 0 ;;
esac

loc=$(wc -l < "$file_path" 2>/dev/null || echo 0)
if [ "$loc" -gt "$LOC_THRESHOLD" ]; then
  deny "File $file_path is $loc LOC (threshold $LOC_THRESHOLD). Decompose first — split responsibilities into smaller modules/hooks/components before editing. Override: CLAUDE_BLOAT_THRESHOLD=<n>."
fi

exit 0
