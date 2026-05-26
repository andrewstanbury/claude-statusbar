#!/usr/bin/env bash
# Aggregator: PreToolUse on Bash. Runs search-noise-guard (recursive
# grep/find without excludes) AND bash-quiet-guard (verbose forms of
# common commands) inline. First deny wins.
set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"

[ -z "$cmd" ] && exit 0

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

# Split on top-level && / ; / | (quote-aware) for segment-level checks.
# A command like `git commit -m "see npm install"` has 'git commit' as the
# only segment; the embedded string in the -m arg is NOT a separate segment.
segments_raw="$(printf '%s' "$cmd" | awk '
  BEGIN { in_sq=0; in_dq=0; seg="" }
  {
    s=$0
    for (i=1; i<=length(s); i++) {
      c=substr(s,i,1)
      if (c=="\x27" && !in_dq) { in_sq=!in_sq; seg=seg c; continue }
      if (c=="\"" && !in_sq)   { in_dq=!in_dq; seg=seg c; continue }
      if (!in_sq && !in_dq) {
        if (c==";")            { print seg; seg=""; continue }
        if (c=="|") {
          next_c = substr(s,i+1,1)
          if (next_c=="|") { i++ }
          print seg; seg=""; continue
        }
        if (c=="&" && substr(s,i+1,1)=="&") { i++; print seg; seg=""; continue }
      }
      seg=seg c
    }
    print seg
  }
')"

while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$seg" ] && continue

  # ─── search-noise: recursive grep -r / -R ─────────────────────────────
  if printf '%s' "$seg" | grep -qE '^grep[[:space:]]+[^|]*-[rR]([[:space:]]|$)'; then
    # Targeting a generated dir explicitly → intentional → allow.
    if ! printf '%s' "$seg" | grep -qE '(node_modules|/dist/|/build/|\.next|\.expo|\.git/|coverage|vendor)' \
       && ! printf '%s' "$seg" | grep -qE -- '(--exclude-dir|--exclude=)'; then
      deny "Recursive grep -r without excluding generated dirs (node_modules/dist/build/.next/.expo/.git/coverage/vendor) — burns tokens on irrelevant matches. Rewrite: grep -r --exclude-dir={node_modules,dist,build,.next,.expo,.git,coverage,vendor} <pattern> <path>"
    fi
  fi

  # ─── search-noise: find . without prune ───────────────────────────────
  # -maxdepth bounds the walk (e.g. -maxdepth 1 = no recursion), so excludes
  # aren't needed — exempt it.
  if printf '%s' "$seg" | grep -qE '^find([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE '(node_modules|/dist/|/build/|\.next|\.expo|\.git/|coverage|vendor)' \
       && ! printf '%s' "$seg" | grep -qE -- '(-prune|-not[[:space:]]+-path|-maxdepth)'; then
      deny "Recursive find without excluding generated dirs — burns tokens on irrelevant matches. Rewrite: find . -type f -not -path \"*/node_modules/*\" -not -path \"*/dist/*\" -not -path \"*/.next/*\" -not -path \"*/.expo/*\" -not -path \"*/.git/*\" ..."
    fi
  fi

  # rg is allowed (respects .gitignore by default).

  # ─── bash-quiet: git log ──────────────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+log([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--oneline|--format=|--pretty=|--stat|--name-only|--shortstat|-p[[:space:]]|-p$|-[0-9]+([[:space:]]|$))'; then
      deny "Use 'git log --oneline' (or --format=) — bare 'git log' dumps ~5 lines per commit × N commits. Add --oneline for one-line summaries, or -10 for last 10 commits."
    fi
  fi

  # ─── bash-quiet: npm install / npm i ──────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^npm[[:space:]]+(install|i)([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--silent|--quiet|--no-progress|-s[[:space:]]|-s$)'; then
      deny "npm install is extremely verbose (~hundreds of lines). Append --silent (or --no-progress + --no-fund) to suppress non-error output."
    fi
  fi

  # ─── bash-quiet: pnpm install / pnpm add ──────────────────────────────
  if printf '%s' "$seg" | grep -qE '^pnpm[[:space:]]+(install|i|add)([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--silent|--reporter[= ]silent|--reporter[= ]append-only)'; then
      deny "pnpm install/add is verbose (progress bars + per-package lines). Append --reporter=silent (or --reporter=append-only for compact output)."
    fi
  fi

  # ─── bash-quiet: yarn / yarn add / yarn install ───────────────────────
  if printf '%s' "$seg" | grep -qE '^yarn([[:space:]]+(add|install|upgrade))?([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--silent|--no-progress|-s[[:space:]]|-s$|--version)'; then
      deny "yarn install/add prints per-package progress. Append --silent (or --no-progress for compact output)."
    fi
  fi

  # ─── bash-quiet: ls -l / ls -la ───────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^ls[[:space:]]+-[a-zA-Z]*l[a-zA-Z]*([[:space:]]|$)'; then
    deny "Use plain 'ls' (or 'ls -1' for one-per-line) — '-l' / '-la' adds permissions/dates/sizes which are rarely useful for code work and inflate token cost ~5×."
  fi

  # ─── bash-quiet: gh api ───────────────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^gh[[:space:]]+api([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--jq)'; then
      deny "gh api returns raw JSON (often KB of fields you don't need). Append --jq '<selector>' (e.g. gh api repos/owner/repo/pulls --jq '.[].number')."
    fi
  fi

  # ─── bash-quiet: gh pr view ───────────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^gh[[:space:]]+pr[[:space:]]+view([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--json|--jq)'; then
      deny "gh pr view dumps full PR body + all comments. Use --json <fields> --jq '<selector>' (e.g. --json title,state,reviews --jq '.title')."
    fi
  fi

  # ─── bash-quiet: gh pr list / gh run list / gh issue list ─────────────
  if printf '%s' "$seg" | grep -qE '^gh[[:space:]]+(pr|run|issue)[[:space:]]+list([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--limit|-L[[:space:]])'; then
      deny "gh <pr|run|issue> list defaults to 30 results × multiple columns. Add --limit <n> (and --json <fields> --jq '...' for narrow output)."
    fi
  fi

  # ─── bash-quiet: gh run view ──────────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^gh[[:space:]]+run[[:space:]]+view([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--json|--jq|--log-failed)'; then
      deny "gh run view dumps the full workflow output. Use --log-failed (only failures), or --json <fields> --jq '<selector>'."
    fi
  fi

  # ─── bash-quiet: docker logs ──────────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^docker[[:space:]]+logs([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(--tail|-n[[:space:]]|--since)'; then
      deny "docker logs without --tail dumps the entire container history. Use --tail <n> (e.g. --tail 100) or --since <duration>."
    fi
  fi

  # ─── bash-quiet: tree ─────────────────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '^tree([[:space:]]|$)'; then
    if ! printf '%s' "$seg" | grep -qE -- '(-L[[:space:]]|-d[[:space:]]|-d$|--filelimit)'; then
      deny "tree without -L <depth> recurses unbounded — node_modules etc. blow up. Add -L 2 (or -L 3) and consider -I 'node_modules|dist|.git'."
    fi
  fi
done <<< "$segments_raw"

exit 0
