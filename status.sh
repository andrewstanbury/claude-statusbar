#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Status Bar
# ─────────────────────────────────────────────────────────────────────────────
#
# A single-line status bar for Claude Code that surfaces:
#   • spinner + level (OK / WARN / HIGH / CRITICAL — driven by context usage)
#   • highest-priority recommendation (e.g. /compact, commit, push)
#   • model, token usage (in/out), session cost estimate
#   • current git branch, uncommitted-changes bar, branch-size bar
#   • system memory %
#
# ── Install ──────────────────────────────────────────────────────────────────
#   1. Save this file somewhere, e.g. ~/.claude/status.sh
#   2. chmod +x ~/.claude/status.sh
#   3. Wire it up in ~/.claude/settings.json:
#
#        {
#          "statusLine": {
#            "type": "command",
#            "command": "bash ~/.claude/status.sh"
#          }
#        }
#
#   4. Restart Claude Code (or run /config) to reload.
#
# ── Requirements ─────────────────────────────────────────────────────────────
#   bash 4+, jq, awk, git (optional — only used inside repos), free (optional,
#   Linux only — falls back to "?" for memory on macOS/BSD).
#
# ── Manual test ──────────────────────────────────────────────────────────────
#   CLAUDE_MODEL=claude-sonnet-4-6 CLAUDE_CONTEXT_TOKENS_USED=80000 \
#     CLAUDE_MAX_CONTEXT_TOKENS=200000 bash status.sh
#
# ── Tunables ─────────────────────────────────────────────────────────────────
# Adjust per-MTok prices to match the model you use most. Defaults are Sonnet
# 4.x rates ($3 input / $15 output per 1M tokens). Cost bar saturates at $5.
PRICE_IN_PER_MTOK=3
PRICE_OUT_PER_MTOK=15
COST_BAR_MAX_USD=5

# ── ANSI colours ──────────────────────────────────────────────────────────────
R=$'\033[31m'
Y=$'\033[33m'
G=$'\033[32m'
C=$'\033[36m'
B=$'\033[1m'
D=$'\033[2m'
X=$'\033[0m'

SEP="${X} ${D}|${X} "

# ── Inputs ────────────────────────────────────────────────────────────────────
# Claude Code passes a JSON payload on stdin. Env vars are kept as overrides for
# manual testing (see CLAUDE_MODEL=… bash status.sh in settings).
INPUT=""
if [ ! -t 0 ]; then INPUT=$(cat); fi
[ -z "$INPUT" ] && INPUT="{}"

MODEL=$(echo "$INPUT" | jq -r '.model.id // .model.display_name // empty' 2>/dev/null)
MODEL="${CLAUDE_MODEL:-${MODEL:-unknown}}"

TOKENS_USED=$(echo "$INPUT" | jq -r '
  .context_window.used_tokens //
  ((.context_window.used_percentage // 0) * 2000 | floor) //
  empty
' 2>/dev/null)
TOKENS_USED="${CLAUDE_CONTEXT_TOKENS_USED:-${TOKENS_USED:-0}}"

TOKENS_MAX=$(echo "$INPUT" | jq -r '
  if (.context_window.used_percentage // 0) > 0 and (.context_window.used_tokens // 0) > 0
  then (.context_window.used_tokens * 100 / .context_window.used_percentage | floor)
  else empty end
' 2>/dev/null)
TOKENS_MAX="${CLAUDE_MAX_CONTEXT_TOKENS:-${TOKENS_MAX:-200000}}"

SHORT_MODEL=$(echo "$MODEL" | sed 's/claude-//;s/-[0-9]\{8\}$//')

# ── Progress bar ──────────────────────────────────────────────────────────────
bar() {
  local pct=$1 width=${2:-5} col=$3
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local s="${col}${B}"
  for ((i=0; i<filled; i++)); do s+="█"; done
  s+="${X}${D}"
  for ((i=0; i<empty; i++)); do s+="░"; done
  s+="${X}"
  printf '%s' "$s"
}

pct_color() {
  local p=$1
  if   [ "$p" -lt 50 ]; then printf '%s' "$G"
  elif [ "$p" -lt 75 ]; then printf '%s' "$Y"
  else                        printf '%s' "$R"
  fi
}

# ── Context window ────────────────────────────────────────────────────────────
CTX_PCT=0
[ "$TOKENS_MAX" -gt 0 ] && CTX_PCT=$(( TOKENS_USED * 100 / TOKENS_MAX ))
CTX_COL=$(pct_color "$CTX_PCT")

# ── Cost estimate (rates configured at top of file) ──────────────────────────
IN_TOK=$(( TOKENS_USED * 65 / 100 ))
OUT_TOK=$(( TOKENS_USED * 35 / 100 ))
COST_STR=$(awk -v i="$IN_TOK" -v o="$OUT_TOK" -v pi="$PRICE_IN_PER_MTOK" -v po="$PRICE_OUT_PER_MTOK" 'BEGIN {
  c = (i*pi + o*po) / 1000000
  if (c < 0.01) print "<$0.01"
  else           printf "$%.2f", c
}')
COST_PCT=$(awk -v i="$IN_TOK" -v o="$OUT_TOK" -v pi="$PRICE_IN_PER_MTOK" -v po="$PRICE_OUT_PER_MTOK" -v cap="$COST_BAR_MAX_USD" 'BEGIN {
  c = (i*pi + o*po) / 1000000
  p = (cap > 0) ? c / cap * 100 : 0
  if (p > 100) p = 100
  printf "%d", p
}')
COST_COL=$(pct_color "$COST_PCT")

fmt_k() {
  awk -v n="$1" 'BEGIN { if (n >= 1000) printf "%.1fk", n/1000; else printf "%d", n }'
}
IN_STR=$(fmt_k "$IN_TOK")
OUT_STR=$(fmt_k "$OUT_TOK")

# ── Git: uncommitted + unpushed + branch size for the current repo ───────────
DIRTY=0
UNPUSHED=0
BRANCH_LINES=0
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
CWD="${CWD:-$PWD}"
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
BRANCH_NAME="-"
if [ -n "$REPO_ROOT" ]; then
  DIRTY=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  UNPUSHED=$(git -C "$REPO_ROOT" log @{u}.. --oneline 2>/dev/null | wc -l | tr -d ' ')
  BRANCH_NAME=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -z "$BRANCH_NAME" ] || [ "$BRANCH_NAME" = "HEAD" ] && BRANCH_NAME="detached"
  BASE=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
  [ -z "$BASE" ] && BASE=$(git -C "$REPO_ROOT" rev-parse --verify origin/main 2>/dev/null >/dev/null && echo origin/main)
  [ -z "$BASE" ] && BASE=$(git -C "$REPO_ROOT" rev-parse --verify origin/master 2>/dev/null >/dev/null && echo origin/master)
  if [ -n "$BASE" ]; then
    MB=$(git -C "$REPO_ROOT" merge-base HEAD "$BASE" 2>/dev/null)
    if [ -n "$MB" ]; then
      BRANCH_LINES=$(git -C "$REPO_ROOT" diff --shortstat "$MB"...HEAD 2>/dev/null | \
        awk '{ for(i=1;i<=NF;i++) if($i~/^[0-9]+$/ && ($(i+1)~/insertion/||$(i+1)~/deletion/)) s+=$i } END { print s+0 }')
    fi
  fi
fi

DIRTY_PCT=$(( DIRTY * 5 ));    [ "$DIRTY_PCT" -gt 100 ] && DIRTY_PCT=100
PUSH_PCT=$(( UNPUSHED * 10 )); [ "$PUSH_PCT"  -gt 100 ] && PUSH_PCT=100
BRANCH_PCT=$(( BRANCH_LINES / 5 )); [ "$BRANCH_PCT" -gt 100 ] && BRANCH_PCT=100
DIRTY_COL=$(pct_color "$DIRTY_PCT")
PUSH_COL=$(pct_color "$PUSH_PCT")
BRANCH_COL=$(pct_color "$BRANCH_PCT")

# ── System memory ─────────────────────────────────────────────────────────────
MEM_PCT=0; MEM_STR="?"
if command -v free &>/dev/null; then
  read -r mtotal mused <<< "$(free -m | awk '/^Mem:/{print $2,$3}')"
  if [ "${mtotal:-0}" -gt 0 ]; then
    MEM_PCT=$(( mused * 100 / mtotal ))
    MEM_STR="${MEM_PCT}%"
  fi
fi
MEM_COL=$(pct_color "$MEM_PCT")

# ── Recommendation: highest-priority actionable message ──────────────────────
# Scored by severity (higher = more urgent). Only the top one is shown.
ADVICE=""
ADVICE_SCORE=0
ADVICE_COL="$G"

# Context pressure (checked first — most urgent, affects this session directly)
if   [ "$CTX_PCT" -ge 90 ]; then
  ADVICE="/compact"
  ADVICE_SCORE=100; ADVICE_COL="${R}${B}"
elif [ "$CTX_PCT" -ge 75 ]; then
  ADVICE="/compact"
  ADVICE_SCORE=80; ADVICE_COL="$Y"
elif [ "$CTX_PCT" -ge 50 ]; then
  ADVICE="consider /compact"
  ADVICE_SCORE=50; ADVICE_COL="$Y"
fi

# Cost pressure
COST_SCORE=0
if   [ "$COST_PCT" -ge 80 ]; then COST_SCORE=70
elif [ "$COST_PCT" -ge 50 ]; then COST_SCORE=40
fi
if [ "$COST_SCORE" -gt "$ADVICE_SCORE" ]; then
  ADVICE="start a new session"
  ADVICE_SCORE=$COST_SCORE; ADVICE_COL="$Y"
fi

# Uncommitted changes (large = risky, many = PR will be huge)
DIRTY_SCORE=0
if   [ "$DIRTY" -ge 20 ]; then DIRTY_SCORE=75
elif [ "$DIRTY" -ge 10 ]; then DIRTY_SCORE=60
elif [ "$DIRTY" -ge 5  ]; then DIRTY_SCORE=45
elif [ "$DIRTY" -ge 1  ]; then DIRTY_SCORE=20
fi
if [ "$DIRTY_SCORE" -gt "$ADVICE_SCORE" ]; then
  if [ "$DIRTY" -ge 10 ]; then
    ADVICE="break into smaller commits"
  else
    ADVICE="commit your changes"
  fi
  ADVICE_SCORE=$DIRTY_SCORE
  [ "$DIRTY" -ge 10 ] && ADVICE_COL="${R}" || ADVICE_COL="${Y}"
fi

# Unpushed commits (stacking up = PR will be hard to review)
PUSH_SCORE=0
if   [ "$UNPUSHED" -ge 10 ]; then PUSH_SCORE=65
elif [ "$UNPUSHED" -ge 5  ]; then PUSH_SCORE=50
elif [ "$UNPUSHED" -ge 1  ]; then PUSH_SCORE=15
fi
if [ "$PUSH_SCORE" -gt "$ADVICE_SCORE" ]; then
  if [ "$UNPUSHED" -ge 10 ]; then
    ADVICE="split into multiple PRs"
  else
    ADVICE="git push"
  fi
  ADVICE_SCORE=$PUSH_SCORE
  [ "$UNPUSHED" -ge 5 ] && ADVICE_COL="${Y}" || ADVICE_COL="${D}"
fi

# Memory pressure
if [ "$MEM_PCT" -ge 90 ] && [ 90 -gt "$ADVICE_SCORE" ]; then
  ADVICE="free up system memory"
  ADVICE_SCORE=85; ADVICE_COL="${R}"
fi

# All clear
if [ -z "$ADVICE" ]; then
  ADVICE="all clear"
  ADVICE_COL="${D}"
fi

# ── Level indicator (driven by context window, the session-scoped resource) ───
SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPIN="${SPIN_FRAMES[$(( $(date +%s) % 10 ))]}"
if   [ "$CTX_PCT" -lt 50 ]; then LEVEL="${G}${B}${SPIN} OK${X}"
elif [ "$CTX_PCT" -lt 75 ]; then LEVEL="${Y}${B}! WARN${X}"
elif [ "$CTX_PCT" -lt 90 ]; then LEVEL="${Y}${B}! HIGH${X}"
else                              LEVEL="${R}${B}! CRITICAL${X}"
fi

# ── Assemble ──────────────────────────────────────────────────────────────────
printf '%s' "${LEVEL}${SEP}"
printf '%s' "${ADVICE_COL}${ADVICE}${X}${SEP}"
printf '%s' "${B}${C}${SHORT_MODEL}${X}${SEP}"
printf '%s' "Tokens: ${C}↑${B}${IN_STR}${X} ${C}↓${B}${OUT_STR}${X}${SEP}"
printf '%s' "Cost: ${COST_COL}${B}${COST_STR}${X}${SEP}"
printf '%s' "Branch: ${B}${C}${BRANCH_NAME}${X}${SEP}"
printf '%s' "Commit: [$(bar "$DIRTY_PCT" 5 "$DIRTY_COL")]${SEP}"
printf '%s' "Size: [$(bar "$BRANCH_PCT" 5 "$BRANCH_COL")]${SEP}"
printf '%s' "Mem: ${MEM_COL}${B}${MEM_STR}${X}"
printf '\n'
