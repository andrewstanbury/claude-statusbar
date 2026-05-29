#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Status Bar (v2.1 — audit pass)
# ─────────────────────────────────────────────────────────────────────────────
#
# Single-line, label-based status bar. Sections collapse when their info is at
# "quiet" state. Narrow terminals (<NARROW_COLS) shed low-priority sections.
#
# Column groups (left → right):
#   1. ⠿ spinner+verdict   worst severity across context/cost/dirty/unpushed/mem
#   2. advice        single highest-priority imperative (only when active)
#   3. Context       % + bar (8-cell mini bar)
#   4. Tokens        ↑in ↓out (estimated 65/35 split)
#   5. Cost · Time   real cost from stdin; session elapsed
#   5b. Queue        claude-task-queue: glyph · done/total · mode · current task
#                    (only when the project has a queue; plugin optional)
#   6. Repo          Branch[⎇] · PR · Web · Dirty · Unpushed · Behind · Base↑↓ · Lines · Stash · EAS
#   7. Model         · Mode (non-default) · Style (non-default)
#   8. System        Memory
#
# Install:
#   { "statusLine": { "type": "command", "command": "bash ~/.claude/status.sh" } }
#
# Requires: bash 4+, jq. Optional: git, gh, free.
# Honors NO_COLOR and TERM=dumb (emits plain text).

# ── Tunables ─────────────────────────────────────────────────────────────────
PRICE_IN_PER_MTOK=3        # fallback rates when stdin lacks real cost
PRICE_OUT_PER_MTOK=15
COST_BAR_MAX_USD=5         # cost beyond this saturates the severity scale
CTX_WARN=50; CTX_HIGH=75; CTX_CRIT=90
DIRTY_WARN=5;  DIRTY_HIGH=10; DIRTY_CRIT=20
PUSH_WARN=5;   PUSH_HIGH=10
MEM_CRIT=90
NARROW_COLS=110
PR_CACHE_TTL=300           # seconds before background PR refresh

# ── Palette (honors NO_COLOR / TERM=dumb) ────────────────────────────────────
if [ -n "$NO_COLOR" ] || [ "$TERM" = "dumb" ]; then
  R=""; Y=""; G=""; C=""; B=""; D=""; X=""
else
  R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; C=$'\033[36m'
  B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
fi
GSEP="  "                       # between top-level groups

# ── Helpers ──────────────────────────────────────────────────────────────────
pct_color() {
  local p=$1
  if   [ "$p" -lt 50 ]; then printf '%s' "$G"
  elif [ "$p" -lt 75 ]; then printf '%s' "$Y"
  else                       printf '%s' "$R"
  fi
}

bar() {
  local pct=$1 width=${2:-6} col=$3 s
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  s="${col}${B}"
  for ((i=0; i<filled; i++)); do s+="▓"; done
  s+="${X}${D}"
  for ((i=0; i<width-filled; i++)); do s+="░"; done
  s+="${X}"
  printf '%s' "$s"
}

fmt_k() {
  awk -v n="$1" 'BEGIN {
    if      (n >= 1000000) printf "%.1fM", n/1000000
    else if (n >= 1000)    printf "%.1fk", n/1000
    else                   printf "%d", n
  }'
}

fmt_duration() {
  awk -v ms="$1" 'BEGIN {
    s = int(ms/1000)
    if      (s < 60)   printf "%ds", s
    else if (s < 3600) printf "%dm", int(s/60)
    else               printf "%dh%dm", int(s/3600), int((s%3600)/60)
  }'
}

# Integer with severity color when non-zero, dim "0" otherwise.
# Leading space is part of the output so callers can chain "Label:" + fmt_count.
fmt_count() {
  local n="$1" col="$2" prefix="${3:-}"
  if [ "$n" -eq 0 ]; then printf "${D} %s0${X}" "$prefix"
  else                    printf "${col}${B} %s%s${X}" "$prefix" "$n"
  fi
}

# Highest score wins.
set_advice() {
  local score=$1
  [ "$score" -le "$ADVICE_SCORE" ] && return
  ADVICE=$2; ADVICE_SCORE=$score; ADVICE_COL=$3
}

# ── Input (single jq fork → mapfile preserves empty fields) ──────────────────
INPUT=""; [ ! -t 0 ] && INPUT=$(cat); [ -z "$INPUT" ] && INPUT="{}"

mapfile -t F < <(printf '%s' "$INPUT" | jq -r '[
    (.model.id // .model.display_name // "unknown"),
    (.context_window.used_tokens // 0),
    (.context_window.used_percentage // 0),
    (.permission_mode // ""),
    (.output_style.name // ""),
    (.cost.total_cost_usd // ""),
    (.cost.total_duration_ms // 0),
    (.workspace.current_dir // .cwd // ""),
    (.terminal_width // .columns // 0)
  ] | .[]' 2>/dev/null)
MODEL_RAW="${F[0]:-unknown}"
TOKENS_USED="${F[1]:-0}"
USED_PCT="${F[2]:-0}"
PERM_MODE="${F[3]}"
OUT_STYLE="${F[4]}"
REAL_COST="${F[5]}"
SESSION_MS="${F[6]:-0}"
CWD="${F[7]}"
TERM_W="${F[8]:-0}"

MODEL="${CLAUDE_MODEL:-${MODEL_RAW:-unknown}}"
TOKENS_USED="${CLAUDE_CONTEXT_TOKENS_USED:-${TOKENS_USED:-0}}"
CWD="${CWD:-$PWD}"

# Width: stdin → $COLUMNS → tput → default. Drives narrow-mode toggle.
[ "${TERM_W:-0}" -le 0 ] && TERM_W="${COLUMNS:-0}"
[ "$TERM_W" -le 0 ] && TERM_W=$(tput cols 2>/dev/null || echo 0)
[ "$TERM_W" -le 0 ] && TERM_W=200
NARROW=0; [ "$TERM_W" -lt "$NARROW_COLS" ] && NARROW=1

# Token max: stdin-derived → env override → 1M when model carries [1m] → 200k.
TOKENS_MAX=0
if [ "${USED_PCT%.*}" -gt 0 ] 2>/dev/null && [ "$TOKENS_USED" -gt 0 ]; then
  TOKENS_MAX=$(awk -v u="$TOKENS_USED" -v p="$USED_PCT" 'BEGIN { printf "%d", u*100/p }')
fi
if [ "$TOKENS_MAX" -le 0 ]; then
  if [ -n "$CLAUDE_MAX_CONTEXT_TOKENS" ]; then TOKENS_MAX="$CLAUDE_MAX_CONTEXT_TOKENS"
  elif [[ "$MODEL" == *"[1m]"* ]];          then TOKENS_MAX=1000000
  else                                           TOKENS_MAX=200000
  fi
fi

# Model: strip "claude-" + trailing date stamp; preserve [1m] (1M-context flag).
SHORT_MODEL=$(printf '%s' "$MODEL" | sed -E 's/^claude-//; s/-[0-9]{8}([^0-9]|$)/\1/')

# ── Context ──────────────────────────────────────────────────────────────────
CTX_PCT=0
[ "$TOKENS_MAX" -gt 0 ] && CTX_PCT=$(( TOKENS_USED * 100 / TOKENS_MAX ))
[ "$CTX_PCT" -gt 100 ] && CTX_PCT=100
CTX_COL=$(pct_color "$CTX_PCT")

# ── Cost (real from stdin; fall back to token-split estimate). One awk each. ─
if [ -n "$REAL_COST" ] && [ "$REAL_COST" != "null" ]; then
  read -r COST_STR COST_PCT <<<"$(awk -v c="$REAL_COST" -v cap="$COST_BAR_MAX_USD" 'BEGIN {
    if (c+0 < 0.01) s="<$0.01"; else s=sprintf("$%.2f", c+0)
    p = (cap > 0) ? c/cap*100 : 0; if (p > 100) p = 100
    printf "%s %d", s, p
  }')"
else
  IN_TOK=$(( TOKENS_USED * 65 / 100 )); OUT_TOK=$(( TOKENS_USED * 35 / 100 ))
  read -r COST_STR COST_PCT <<<"$(awk -v i="$IN_TOK" -v o="$OUT_TOK" \
    -v pi="$PRICE_IN_PER_MTOK" -v po="$PRICE_OUT_PER_MTOK" -v cap="$COST_BAR_MAX_USD" 'BEGIN {
      c = (i*pi + o*po) / 1000000
      if (c < 0.01) s="<$0.01"; else s=sprintf("$%.2f", c)
      p = (cap > 0) ? c/cap*100 : 0; if (p > 100) p = 100
      printf "%s %d", s, p
    }')"
fi
COST_COL=$(pct_color "$COST_PCT")

IN_STR=$(fmt_k "$(( TOKENS_USED * 65 / 100 ))")
OUT_STR=$(fmt_k "$(( TOKENS_USED * 35 / 100 ))")

# Session elapsed (strip fractional ms if upstream sends a float).
SESSION_STR=""; SESSION_MS_INT="${SESSION_MS%.*}"
[ "${SESSION_MS_INT:-0}" -gt 0 ] 2>/dev/null && SESSION_STR=$(fmt_duration "$SESSION_MS_INT")

# ── Git ──────────────────────────────────────────────────────────────────────
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
BRANCH_NAME=""; DIRTY=0; UNPUSHED=0; TO_PULL=0; CONFLICTS=0
AHEAD_BASE=0; BEHIND_BASE=0; BRANCH_LINES=0; STASH_COUNT=0
WORKTREE_MARK=""; PR_NUM=""; EAS_HINT=""; WEB_ISSUES=0

if [ -n "$REPO_ROOT" ]; then
  # branch + upstream ahead/behind + porcelain file list in one call
  GIT_STATUS=$(git -C "$REPO_ROOT" status --porcelain=2 --branch 2>/dev/null)
  BRANCH_NAME=$(awk '/^# branch.head/{print $3; exit}' <<<"$GIT_STATUS")
  if [ "$BRANCH_NAME" = "(detached)" ] || [ -z "$BRANCH_NAME" ]; then
    BRANCH_NAME="@$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null)"
  fi
  read -r AHEAD_UP BEHIND_UP <<<"$(awk '/^# branch.ab/{print $3+0, $4*-1}' <<<"$GIT_STATUS")"
  UNPUSHED="${AHEAD_UP:-0}"
  TO_PULL="${BEHIND_UP:-0}"
  # Dirty excludes unmerged (`u`); conflicts are surfaced separately via advice.
  DIRTY=$(grep -cE '^[12?]' <<<"$GIT_STATUS")
  CONFLICTS=$(grep -cE '^u' <<<"$GIT_STATUS")

  # vs base (origin/HEAD → origin/main → origin/master): line delta + stack depth
  BASE=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
  [ -z "$BASE" ] && git -C "$REPO_ROOT" rev-parse --verify origin/main >/dev/null 2>&1 && BASE=origin/main
  [ -z "$BASE" ] && git -C "$REPO_ROOT" rev-parse --verify origin/master >/dev/null 2>&1 && BASE=origin/master
  if [ -n "$BASE" ]; then
    MB=$(git -C "$REPO_ROOT" merge-base HEAD "$BASE" 2>/dev/null)
    if [ -n "$MB" ]; then
      BRANCH_LINES=$(git -C "$REPO_ROOT" diff --shortstat "$MB"...HEAD 2>/dev/null | \
        awk '{ for(i=1;i<=NF;i++) if($i~/^[0-9]+$/ && ($(i+1)~/insertion/||$(i+1)~/deletion/)) s+=$i } END { print s+0 }')
      read -r BEHIND_BASE AHEAD_BASE <<<"$(git -C "$REPO_ROOT" rev-list --left-right --count "$BASE"...HEAD 2>/dev/null)"
    fi
  fi
  AHEAD_BASE="${AHEAD_BASE:-0}"; BEHIND_BASE="${BEHIND_BASE:-0}"

  # Worktree detection in one rev-parse (git-dir + common-dir on stdout)
  mapfile -t GD_LINES < <(git -C "$REPO_ROOT" rev-parse --git-dir --git-common-dir 2>/dev/null)
  GD="${GD_LINES[0]}"; GCD="${GD_LINES[1]}"
  if [ -n "$GD" ] && [ -n "$GCD" ]; then
    GDR=$(cd "$REPO_ROOT" 2>/dev/null && realpath "$GD" 2>/dev/null)
    GCDR=$(cd "$REPO_ROOT" 2>/dev/null && realpath "$GCD" 2>/dev/null)
    [ -n "$GDR" ] && [ "$GDR" != "$GCDR" ] && WORKTREE_MARK="⎇ "
  fi

  STASH_COUNT=$(git -C "$REPO_ROOT" stash list 2>/dev/null | wc -l | tr -d ' ')

  # PR #: render from cache; refresh in background. "-" sentinel means "no PR".
  if command -v gh &>/dev/null && [[ "$BRANCH_NAME" != "@"* ]]; then
    PR_CACHE="/tmp/claude-pr-$(printf '%s' "$REPO_ROOT$BRANCH_NAME" | md5sum | cut -c1-8)"
    [ -f "$PR_CACHE" ] && PR_NUM=$(cat "$PR_CACHE" 2>/dev/null)
    [ "$PR_NUM" = "-" ] && PR_NUM=""
    CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$PR_CACHE" 2>/dev/null || echo 0) ))
    if [ ! -f "$PR_CACHE" ] || [ "$CACHE_AGE" -gt "$PR_CACHE_TTL" ]; then
      (cd "$REPO_ROOT" && {
        n=$(timeout 5 gh pr view "$BRANCH_NAME" --json number -q .number 2>/dev/null)
        [ -z "$n" ] && n="-"
        printf '%s' "$n"
      } > "$PR_CACHE.tmp" && mv "$PR_CACHE.tmp" "$PR_CACHE") &>/dev/null &
    fi
  fi

  # EAS/Expo project (has eas.json): hint to prefix `eas update` with EXPO_GO=1
  # so the OTA payload loads in Expo Go.
  [ -f "$REPO_ROOT/eas.json" ] && EAS_HINT="EXPO_GO=1"

  # Web-quality degradation — cached + background-refreshed (like the PR check)
  # so a 1s statusLine refresh never rescans web files on the hot path. Counts
  # web-standards violations in web files the active branch has touched.
  WEB_CACHE="/tmp/claude-web-$(printf '%s' "$REPO_ROOT$BRANCH_NAME" | md5sum | cut -c1-8)"
  if [ "$AHEAD_BASE" -gt 0 ] || [ "$DIRTY" -gt 0 ]; then
    [ -f "$WEB_CACHE" ] && WEB_ISSUES=$(cat "$WEB_CACHE" 2>/dev/null)
    WEB_ISSUES="${WEB_ISSUES:-0}"
    WAGE=$(( $(date +%s) - $(stat -c %Y "$WEB_CACHE" 2>/dev/null || echo 0) ))
    if [ ! -f "$WEB_CACHE" ] || [ "$WAGE" -gt 15 ]; then
      ( WS_LIB=""
        for c in "$HOME/.claude/hooks/lib/web-standards-checks.sh" \
                 "$(dirname "${BASH_SOURCE[0]}")/claude/hooks/lib/web-standards-checks.sh"; do
          [ -f "$c" ] && { WS_LIB="$c"; break; }
        done
        cnt=0
        if [ -n "$WS_LIB" ]; then
          . "$WS_LIB" 2>/dev/null
          web_files=$( {
            [ -n "$BASE" ] && git -C "$REPO_ROOT" diff --name-only "$BASE"...HEAD 2>/dev/null
            git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null
            git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null
          } | grep -iE '\.(html?|vue|svelte|astro)$' | sort -u | head -25 )
          if [ -n "$web_files" ] && declare -f ws_doc_findings >/dev/null 2>&1; then
            while IFS= read -r wf; do
              [ -n "$wf" ] && [ -f "$REPO_ROOT/$wf" ] || continue
              n=$(ws_doc_findings "$(tr '\n\t' '  ' < "$REPO_ROOT/$wf")" | grep -oF '•' | wc -l | tr -d ' ')
              cnt=$(( cnt + ${n:-0} ))
            done <<< "$web_files"
          fi
        fi
        printf '%s' "$cnt" > "$WEB_CACHE.tmp" 2>/dev/null && mv "$WEB_CACHE.tmp" "$WEB_CACHE" 2>/dev/null
      ) &>/dev/null &
    fi
  else
    WEB_ISSUES=0; rm -f "$WEB_CACHE" 2>/dev/null
  fi
fi

DIRTY_COL=$(pct_color $(( DIRTY * 5  > 100 ? 100 : DIRTY * 5  )))
PUSH_COL=$( pct_color $(( UNPUSHED*10 > 100 ? 100 : UNPUSHED*10 )))
PULL_COL=$( pct_color $(( TO_PULL*10 > 100 ? 100 : TO_PULL*10 )))
LINES_COL=$(pct_color $(( BRANCH_LINES/5 > 100 ? 100 : BRANCH_LINES/5 )))

# ── System ───────────────────────────────────────────────────────────────────
MEM_PCT=0; MEM_STR=""
if command -v free &>/dev/null; then
  read -r mtotal mused <<<"$(free -m | awk '/^Mem:/{print $2,$3}')"
  if [ "${mtotal:-0}" -gt 0 ]; then MEM_PCT=$(( mused * 100 / mtotal )); MEM_STR="${MEM_PCT}%"; fi
fi
MEM_COL=$(pct_color "$MEM_PCT")

# ── Task queue (claude-task-queue plugin) ────────────────────────────────────
# Surfaces the durable, project-scoped work queue when the plugin is installed
# and this project has a queue. Cheap: one jq fork over a small jsonl file.
# Honors the plugin's CLAUDE_TQ_STATE_DIR override and its sha1(cwd)[:12] key,
# and mirrors its tq_next selection (in_progress first, else first unblocked
# pending) so the bar shows the same "current task" the assistant works on.
TQ_DONE=0; TQ_TOTAL=0; TQ_ID=""; TQ_SUBJ=""; TQ_EST=""
TQ_GLYPH="▶"; TQ_GLYPH_COL="$C"; TQ_MODE=""; TQ_MODE_COL="$D"; TQ_PAUSED=0
if command -v sha1sum &>/dev/null; then
  TQ_DIR="${CLAUDE_TQ_STATE_DIR:-$HOME/.claude/state/task-queue}"
  # Dual-read: claude-task-queue keys its queue by the git repo root (with a
  # cwd fallback). Prefer the repo-root key here, but fall back to a cwd key so
  # we also find pre-existing cwd-keyed queues and stay correct no matter which
  # repo merges its keying change first.
  TQ_KEY=""
  for _tq_base in "${REPO_ROOT:-}" "$CWD"; do
    [ -n "$_tq_base" ] || continue
    _tq_k=$(printf '%s' "$_tq_base" | sha1sum | cut -c1-12)
    if [ -s "$TQ_DIR/$_tq_k.jsonl" ]; then TQ_KEY="$_tq_k"; break; fi
  done
  TQ_FILE="$TQ_DIR/$TQ_KEY.jsonl"
  if [ -n "$TQ_KEY" ] && [ -s "$TQ_FILE" ]; then
    IFS=$'\t' read -r TQ_DONE TQ_TOTAL TQ_ID TQ_SUBJ TQ_EST <<<"$(jq -rs '
        . as $all
        | ($all | map(select(.status=="completed"))            | length) as $done
        | ($all | length)                                                 as $total
        | ($all | map(select(.status=="completed" or .status=="cancelled") | .id)) as $resolved
        | ( ($all | map(select(.status=="in_progress")) | first)
            // ( $all | map(select(.status=="pending"))
                      | map(select((.blockedBy // []) - $resolved | length == 0))
                      | first ) ) as $cur
        | [ $done, $total, ($cur.id // ""), ($cur.subject // ""), ($cur.est // "") ]
        | @tsv' "$TQ_FILE" 2>/dev/null)"
    TQ_DONE="${TQ_DONE:-0}"; TQ_TOTAL="${TQ_TOTAL:-0}"
    if [ -f "$TQ_DIR/$TQ_KEY.pause" ]; then
      TQ_GLYPH="⏸"; TQ_GLYPH_COL="$Y"; TQ_MODE="paused"; TQ_MODE_COL="$Y"; TQ_PAUSED=1
    elif [ -f "$TQ_DIR/$TQ_KEY.autopilot" ]; then
      TQ_MODE="auto"; TQ_MODE_COL="$G"
    fi
  fi
fi

# ── Advice (severity-scored; highest wins) ───────────────────────────────────
ADVICE=""; ADVICE_SCORE=0; ADVICE_COL="$G"

if   [ "$CTX_PCT" -ge "$CTX_CRIT" ]; then set_advice 100 "/compact" "${R}${B}"
elif [ "$CTX_PCT" -ge "$CTX_HIGH" ]; then set_advice 80  "/compact" "$Y"
elif [ "$CTX_PCT" -ge "$CTX_WARN" ]; then set_advice 50  "consider /compact" "$Y"
fi
[ "$COST_PCT" -ge 80 ] && set_advice 70 "new session" "$Y"
[ "$COST_PCT" -ge 50 ] && [ "$COST_PCT" -lt 80 ] && set_advice 40 "watch cost" "$Y"

if   [ "$DIRTY" -ge "$DIRTY_CRIT" ]; then set_advice 75 "break into smaller commits" "$R"
elif [ "$DIRTY" -ge "$DIRTY_HIGH" ]; then set_advice 60 "break into smaller commits" "$R"
elif [ "$DIRTY" -ge "$DIRTY_WARN" ]; then set_advice 45 "commit changes" "$Y"
fi
if   [ "$UNPUSHED" -ge "$PUSH_HIGH" ]; then set_advice 65 "split into multiple PRs" "$Y"
elif [ "$UNPUSHED" -ge "$PUSH_WARN" ]; then set_advice 50 "git push" "$Y"
fi
[ "$CONFLICTS" -gt 0 ]                                    && set_advice 95 "resolve conflicts" "${R}${B}"
[ "$TO_PULL" -ge 1 ]                                      && set_advice 30 "git pull" "$Y"
[ "$MEM_PCT" -ge "$MEM_CRIT" ]                            && set_advice 85 "free memory" "$R"
[ "$WEB_ISSUES" -gt 0 ]                                  && set_advice 78 "fix web a11y/SEO (${WEB_ISSUES})" "$R"
[ "$TQ_PAUSED" -eq 1 ] && [ "$TQ_TOTAL" -gt "$TQ_DONE" ] && set_advice 35 "tq resume" "$Y"

# ── Verdict beacon (worst severity across all axes) ──────────────────────────
WORST=0
for s in "$CTX_PCT" "$COST_PCT" $((DIRTY*5)) $((UNPUSHED*10)) "$MEM_PCT"; do
  [ "$s" -gt "$WORST" ] && WORST=$s
done
[ "$CONFLICTS" -gt 0 ] && WORST=100
[ "$WEB_ISSUES" -gt 0 ] && [ "$WORST" -lt 80 ] && WORST=80
[ "$WORST" -gt 100 ] && WORST=100
if   [ "$WORST" -ge 90 ]; then VERDICT_COL="$R"; VERDICT_TAG="critical"
elif [ "$WORST" -ge 75 ]; then VERDICT_COL="$Y"; VERDICT_TAG="high"
elif [ "$WORST" -ge 50 ]; then VERDICT_COL="$Y"; VERDICT_TAG="medium"
else                           VERDICT_COL="$G"; VERDICT_TAG="ok"
fi

# ── Render ───────────────────────────────────────────────────────────────────
# 1) Verdict beacon — animated braille spinner. The frame is keyed to the wall
#    clock so it advances once per render (cadence = statusLine refreshInterval);
#    colour still encodes the worst severity (ok/medium/high/critical).
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
BEACON="${SPIN[$(( $(date +%s) % ${#SPIN[@]} ))]}"
printf "${VERDICT_COL}${B}%s${X} ${VERDICT_COL}%s${X}${GSEP}" "$BEACON" "$VERDICT_TAG"

# 2) Advice (when active)
[ -n "$ADVICE" ] && printf "${ADVICE_COL}${B}%s${X}${GSEP}" "$ADVICE"

# 3) Context % + bar (bar hidden on narrow)
printf "${D}Context:${X} ${CTX_COL}${B}%d%%${X}" "$CTX_PCT"
[ "$NARROW" -eq 0 ] && printf " %s" "$(bar "$CTX_PCT" 8 "$CTX_COL")"
printf "${GSEP}"

# 4) Tokens
printf "${D}Tokens:${X} ${C}↑${X}${B}${IN_STR}${X} ${C}↓${X}${B}${OUT_STR}${X}${GSEP}"

# 5) Cost · session time (bold cost when no advice is stealing the spotlight)
COST_BOLD=""; [ -z "$ADVICE" ] && COST_BOLD="$B"
printf "${D}Cost:${X} ${COST_COL}${COST_BOLD}%s${X}" "$COST_STR"
[ "$NARROW" -eq 0 ] && [ -n "$SESSION_STR" ] && printf " ${D}Time:${X} ${C}%s${X}" "$SESSION_STR"
printf "${GSEP}"

# 5b) Task queue (claude-task-queue) — glyph · done/total · mode · current task
if [ "$TQ_TOTAL" -gt 0 ]; then
  printf "${D}Queue:${X} ${TQ_GLYPH_COL}${B}%s${X} ${C}${B}%s/%s${X}" "$TQ_GLYPH" "$TQ_DONE" "$TQ_TOTAL"
  [ -n "$TQ_MODE" ] && printf " ${TQ_MODE_COL}%s${X}" "$TQ_MODE"
  if [ "$NARROW" -eq 0 ] && [ -n "$TQ_ID" ]; then
    sub="$TQ_SUBJ"; [ "${#sub}" -gt 28 ] && sub="${sub:0:27}…"
    printf " ${D}·${X} ${C}#%s${X} %s" "$TQ_ID" "$sub"
    [ -n "$TQ_EST" ] && printf " ${D}(%s)${X}" "$TQ_EST"
  fi
  printf "${GSEP}"
fi

# 6) Repo group
if [ -n "$REPO_ROOT" ]; then
  printf "${D}Branch:${X} ${C}${WORKTREE_MARK}${B}%s${X}" "$BRANCH_NAME"
  [ -n "$PR_NUM" ] && printf " ${D}PR:${X} ${C}${B}%s${X}" "$PR_NUM"
  [ "$WEB_ISSUES" -gt 0 ] && printf " ${D}Web:${X} ${R}${B}⚠ %d${X}" "$WEB_ISSUES"
  printf " ${D}Dirty:${X}";    fmt_count "$DIRTY"    "$DIRTY_COL"
  printf " ${D}Unpushed:${X}"; fmt_count "$UNPUSHED" "$PUSH_COL"
  [ "$TO_PULL" -gt 0 ] && { printf " ${D}Behind:${X}"; fmt_count "$TO_PULL" "$PULL_COL"; }
  if [ "$AHEAD_BASE" != "0" ] || [ "$BEHIND_BASE" != "0" ]; then
    printf " ${D}Base:${X} ${C}↑${X}${B}${AHEAD_BASE}${X}${C}↓${X}${B}${BEHIND_BASE}${X}"
  fi
  [ "$NARROW" -eq 0 ] && { printf " ${D}Lines:${X}"; fmt_count "$BRANCH_LINES" "$LINES_COL" "+"; }
  [ "$NARROW" -eq 0 ] && [ "$STASH_COUNT" -gt 0 ] && printf " ${D}Stash: %s${X}" "$STASH_COUNT"
  [ "$NARROW" -eq 0 ] && [ -n "$EAS_HINT" ] && printf " ${D}EAS:${X} ${Y}%s${X}" "$EAS_HINT"
  printf "${GSEP}"
fi

# 7) Model · Mode · Style (mode/style only when non-default; bypass = red)
printf "${D}Model:${X} ${C}%s${X}" "$SHORT_MODEL"
if [ -n "$PERM_MODE" ] && [ "$PERM_MODE" != "default" ] && [ "$PERM_MODE" != "auto" ]; then
  MODE_COL="${Y}${B}"
  [ "$PERM_MODE" = "bypassPermissions" ] && MODE_COL="${R}${B}"
  printf " ${D}Mode:${X} ${MODE_COL}%s${X}" "$PERM_MODE"
fi
if [ -n "$OUT_STYLE" ] && [ "$OUT_STYLE" != "default" ]; then
  printf " ${D}Style:${X} ${C}%s${X}" "$OUT_STYLE"
fi
printf "${GSEP}"

# 8) System (Memory)
if [ -n "$MEM_STR" ]; then printf "${D}Memory:${X} ${MEM_COL}${B}%s${X}" "$MEM_STR"; fi

printf '\n'
