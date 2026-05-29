#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Status Bar (v3 — native metrics)
# ─────────────────────────────────────────────────────────────────────────────
#
# Single line. Reads everything from the statusLine stdin JSON — no `gh`, no
# transcript parsing, no background forks. Sections collapse when empty; narrow
# terminals shed low-priority detail.
#
# Slots (left → right):
#   1. Beacon + verdict   braille spinner, colour = worst severity
#   2. Advice             one imperative line, written by the advice hook (PR2);
#                         rendered only when the cache file exists
#   3. Context            % + 8-cell bar           (context_window.used_percentage)
#   4. Tokens             ↑in ↓out, REAL totals    (context_window.total_*_tokens)
#   5. Week               7-day rate-limit % + reset countdown  (rate_limits)
#   6. Branch             current branch + PR #     (git + native .pr.number)
#   7. Model              display name              (model.display_name)
#
# Install (settings.json):
#   { "statusLine": { "type": "command",
#                     "command": "bash ~/.claude/status.sh",
#                     "refreshInterval": 1 } }   # seconds
#   refreshInterval keeps the spinner ticking once/sec even while idle.
#
# Requires: bash 4+, jq. Optional: git. Honors NO_COLOR and TERM=dumb.

# ── Tunables ─────────────────────────────────────────────────────────────────
CTX_WARN=50; CTX_HIGH=75; CTX_CRIT=90
WEEK_WARN=50; WEEK_HIGH=75; WEEK_CRIT=90
NARROW_COLS=100
ADVICE_DIR="${CLAUDE_STATUSBAR_ADVICE_DIR:-$HOME/.claude/state/statusbar-advice}"

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
  local pct=$1 width=${2:-8} col=$3 s i
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
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

# Seconds → compact "Nd" / "Nh" / "Nm" / "now".
fmt_until() {
  awk -v s="$1" 'BEGIN {
    if      (s <= 0)    printf "now"
    else if (s >= 86400) printf "%dd", int(s/86400)
    else if (s >= 3600)  printf "%dh", int(s/3600)
    else                 printf "%dm", int(s/60)
  }'
}

# Truncate a possibly-float percentage to a non-negative int.
to_int() { local v="${1%.*}"; [[ "$v" =~ ^-?[0-9]+$ ]] || v=0; [ "$v" -lt 0 ] && v=0; printf '%d' "$v"; }

# ── Input (single jq fork → mapfile preserves empty fields) ──────────────────
INPUT=""; [ ! -t 0 ] && INPUT=$(cat); [ -z "$INPUT" ] && INPUT="{}"

mapfile -t F < <(printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // .model.id // "unknown"),
    (.context_window.used_percentage // 0),
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.pr.number // ""),
    (.session_id // ""),
    (.workspace.current_dir // .cwd // ""),
    (.terminal_width // .columns // 0)
  ] | .[]' 2>/dev/null)

MODEL="${F[0]:-unknown}"
CTX_PCT=$(to_int "${F[1]:-0}")
IN_TOK="${F[2]:-0}"
OUT_TOK="${F[3]:-0}"
WEEK_RAW="${F[4]}"
WEEK_RESET="${F[5]}"
FIVEH_RAW="${F[6]}"
PR_NUM="${F[7]}"
SESSION_ID="${F[8]}"
CWD="${F[9]:-$PWD}"
TERM_W="${F[10]:-0}"

# Allow env overrides (parity with prior versions).
MODEL="${CLAUDE_MODEL:-$MODEL}"

# Width: stdin → $COLUMNS → tput → default. Drives narrow-mode toggle.
[ "${TERM_W:-0}" -le 0 ] && TERM_W="${COLUMNS:-0}"
[ "$TERM_W" -le 0 ] && TERM_W=$(tput cols 2>/dev/null || echo 0)
[ "$TERM_W" -le 0 ] && TERM_W=200
NARROW=0; [ "$TERM_W" -lt "$NARROW_COLS" ] && NARROW=1

[ "$CTX_PCT" -gt 100 ] && CTX_PCT=100
CTX_COL=$(pct_color "$CTX_PCT")

# Model: strip "claude-" + trailing date stamp; preserve [1m] (1M-context flag).
SHORT_MODEL=$(printf '%s' "$MODEL" | sed -E 's/^claude-//; s/-[0-9]{8}([^0-9]|$)/\1/')

# ── Week / rate limit (Pro/Max login only; absent for API-key users) ─────────
HAVE_WEEK=0; WEEK_PCT=0; WEEK_COL="$G"; WEEK_LEFT=""
if [ -n "$WEEK_RAW" ] && [ "$WEEK_RAW" != "null" ]; then
  HAVE_WEEK=1
  WEEK_PCT=$(to_int "$WEEK_RAW")
  [ "$WEEK_PCT" -gt 100 ] && WEEK_PCT=100
  WEEK_COL=$(pct_color "$WEEK_PCT")
  if [ -n "$WEEK_RESET" ] && [ "$WEEK_RESET" != "null" ]; then
    WEEK_LEFT=$(fmt_until "$(( WEEK_RESET - $(date +%s) ))")
  fi
fi
# The 5-hour window is the soonest throttle — fold it into severity even though
# we only display the weekly figure.
FIVEH_PCT=0
[ -n "$FIVEH_RAW" ] && [ "$FIVEH_RAW" != "null" ] && FIVEH_PCT=$(to_int "$FIVEH_RAW")

# ── Branch (cheap: one git call; no PR fetch — .pr.number is native) ─────────
BRANCH_NAME=""
BRANCH_NAME=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$BRANCH_NAME" = "HEAD" ]; then
  BRANCH_NAME="@$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)"
fi
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)

# ── Task queue (claude-task-queue plugin) ────────────────────────────────────
# Surfaces the durable, project-scoped work queue when the plugin is installed
# and this project has a queue. Cheap: one jq fork over a small jsonl file.
# Honors the plugin's CLAUDE_TQ_STATE_DIR override and its sha1(key)[:12] file,
# and mirrors its tq_next selection (in_progress first, else first unblocked
# pending) so the bar shows the same "current task" the assistant works on.
TQ_DONE=0; TQ_TOTAL=0; TQ_ID=""; TQ_SUBJ=""; TQ_EST=""
TQ_GLYPH="▶"; TQ_GLYPH_COL="$C"; TQ_MODE=""; TQ_MODE_COL="$D"; TQ_PAUSED=0
if command -v sha1sum &>/dev/null; then
  TQ_DIR="${CLAUDE_TQ_STATE_DIR:-$HOME/.claude/state/task-queue}"
  # Dual-read: claude-task-queue keys its queue by git repo root (with a cwd
  # fallback). Prefer the repo-root key, but fall back to a cwd key so we find
  # cwd-keyed queues too (v0.1.1 keys by cwd) — correct no matter which wins.
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

# ── Advice (rendered from cache; written by the advice hook — PR2) ───────────
ADVICE=""
if [ -n "$SESSION_ID" ] && [ -f "$ADVICE_DIR/$SESSION_ID.txt" ]; then
  IFS= read -r ADVICE < "$ADVICE_DIR/$SESSION_ID.txt" 2>/dev/null
fi

# ── Verdict beacon (worst severity across context + rate limits) ─────────────
WORST="$CTX_PCT"
[ "$WEEK_PCT"  -gt "$WORST" ] && WORST="$WEEK_PCT"
[ "$FIVEH_PCT" -gt "$WORST" ] && WORST="$FIVEH_PCT"
[ "$WORST" -gt 100 ] && WORST=100
if   [ "$WORST" -ge "$CTX_CRIT" ]; then VERDICT_COL="$R"; VERDICT_TAG="critical"
elif [ "$WORST" -ge "$CTX_HIGH" ]; then VERDICT_COL="$Y"; VERDICT_TAG="high"
elif [ "$WORST" -ge "$CTX_WARN" ]; then VERDICT_COL="$Y"; VERDICT_TAG="elevated"
else                                    VERDICT_COL="$G"; VERDICT_TAG="ok"
fi

# ── Render ───────────────────────────────────────────────────────────────────
# 1) Verdict beacon — braille spinner keyed to the wall clock so it advances
#    once per render (drive cadence with statusLine refreshInterval:1000).
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
BEACON="${SPIN[$(( $(date +%s) % ${#SPIN[@]} ))]}"
printf "${VERDICT_COL}${B}%s${X} ${VERDICT_COL}%s${X}${GSEP}" "$BEACON" "$VERDICT_TAG"

# 2) Advice (when the hook has written one)
[ -n "$ADVICE" ] && printf "${C}${B}%s${X}${GSEP}" "$ADVICE"

# 3) Context % + bar (bar hidden on narrow)
printf "${D}Context:${X} ${CTX_COL}${B}%d%%${X}" "$CTX_PCT"
[ "$NARROW" -eq 0 ] && printf " %s" "$(bar "$CTX_PCT" 8 "$CTX_COL")"
printf "${GSEP}"

# 4) Tokens — real session up/down
printf "${D}Tokens:${X} ${C}↑${X}${B}%s${X} ${C}↓${X}${B}%s${X}${GSEP}" \
  "$(fmt_k "$IN_TOK")" "$(fmt_k "$OUT_TOK")"

# 5) Week (7-day rate-limit usage) — only when the API reported it
if [ "$HAVE_WEEK" -eq 1 ]; then
  printf "${D}Week:${X} ${WEEK_COL}${B}%d%%${X}" "$WEEK_PCT"
  [ "$NARROW" -eq 0 ] && [ -n "$WEEK_LEFT" ] && printf " ${D}(%s)${X}" "$WEEK_LEFT"
  printf "${GSEP}"
fi

# 6) Branch + PR #
if [ -n "$BRANCH_NAME" ]; then
  printf "${D}Branch:${X} ${C}${B}%s${X}" "$BRANCH_NAME"
  [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ] && printf " ${D}PR:${X} ${C}${B}%s${X}" "$PR_NUM"
  printf "${GSEP}"
fi

# 6b) Task queue (claude-task-queue) — ALWAYS shown (queue-first workflow): the
# queue is a permanent fixture so it's visible even when empty. Populated:
# glyph · done/total · mode · current task. Empty: a dim "idle".
if [ "$TQ_TOTAL" -gt 0 ]; then
  printf "${D}Queue:${X} ${TQ_GLYPH_COL}${B}%s${X} ${C}${B}%s/%s${X}" "$TQ_GLYPH" "$TQ_DONE" "$TQ_TOTAL"
  [ -n "$TQ_MODE" ] && printf " ${TQ_MODE_COL}%s${X}" "$TQ_MODE"
  if [ "$NARROW" -eq 0 ] && [ -n "$TQ_ID" ]; then
    sub="$TQ_SUBJ"; [ "${#sub}" -gt 28 ] && sub="${sub:0:27}…"
    printf " ${D}·${X} ${C}#%s${X} %s" "$TQ_ID" "$sub"
    [ -n "$TQ_EST" ] && printf " ${D}(%s)${X}" "$TQ_EST"
  fi
else
  printf "${D}Queue:${X} ${D}idle${X}"
fi
printf "${GSEP}"

# 7) Model
printf "${D}Model:${X} ${C}%s${X}" "$SHORT_MODEL"

printf '\n'
