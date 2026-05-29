#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Status Bar
# ─────────────────────────────────────────────────────────────────────────────
#
# A status bar and nothing else. One line, rendered from the JSON that Claude
# Code pipes to a statusLine command on stdin. No model calls, no hooks, no
# background forks, no writes to your config, no reading of any other tool's
# state. It cannot interfere with anything because it only ever reads stdin and
# prints one line.
#
# Slots (left → right), each collapses when its data is absent:
#   1. Beacon          animated glyph, colour = overall status severity
#   2. Status          one word: ok / elevated / high / critical
#   3. Action          a zero-cost recommended action, derived from the metrics
#   4. Context         used percent + a small bar
#   5. Tokens          up (sent) / down (received), real session totals
#   6. Week            rolling seven-day usage percent + reset countdown
#   7. Branch          current git branch + pull-request number when present
#   8. Model           display name
#
# Install (settings.json):
#   { "statusLine": { "type": "command",
#                     "command": "bash ~/.claude/status.sh",
#                     "refreshInterval": 1 } }   # seconds; 1 keeps it animating
#
# Requires: bash 4+, jq. Optional: git. Honours NO_COLOR and TERM=dumb.

# ── Tunables ─────────────────────────────────────────────────────────────────
WARN=50; HIGH=75; CRIT=90        # severity thresholds (percent)
NARROW_COLS=100                  # below this width, shed low-priority detail

# ── Palette (honours NO_COLOR / TERM=dumb) ───────────────────────────────────
if [ -n "$NO_COLOR" ] || [ "$TERM" = "dumb" ]; then
  R=""; Y=""; G=""; C=""; B=""; D=""; X=""
else
  R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; C=$'\033[36m'
  B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
fi
SEP="  "                         # between top-level groups

# ── Helpers ──────────────────────────────────────────────────────────────────
pct_color() {
  local p=$1
  if   [ "$p" -lt "$HIGH" ]; then [ "$p" -lt "$WARN" ] && printf '%s' "$G" || printf '%s' "$Y"
  else printf '%s' "$R"
  fi
}

bar() {                          # bar <percent> <width> <colour>
  local pct=$1 width=${2:-8} col=$3 s i filled=$(( $1 * ${2:-8} / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width; [ "$filled" -lt 0 ] && filled=0
  s="${col}${B}"; for ((i=0; i<filled; i++)); do s+="▓"; done
  s+="${X}${D}";  for ((i=0; i<width-filled; i++)); do s+="░"; done
  printf '%s%s' "$s" "$X"
}

fmt_k() {                        # 1234 → 1.2k, 1200000 → 1.2M
  awk -v n="$1" 'BEGIN {
    if      (n >= 1000000) printf "%.1fM", n/1000000
    else if (n >= 1000)    printf "%.1fk", n/1000
    else                   printf "%d", n
  }'
}

fmt_until() {                    # seconds → 2d / 3h / 45m / now
  awk -v s="$1" 'BEGIN {
    if      (s <= 0)     printf "now"
    else if (s >= 86400) printf "%dd", int(s/86400)
    else if (s >= 3600)  printf "%dh", int(s/3600)
    else                 printf "%dm", int(s/60)
  }'
}

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
    (.workspace.current_dir // .cwd // ""),
    (.terminal_width // .columns // 0)
  ] | .[]' 2>/dev/null)

MODEL="${CLAUDE_MODEL:-${F[0]:-unknown}}"
CTX_PCT=$(to_int "${F[1]:-0}"); [ "$CTX_PCT" -gt 100 ] && CTX_PCT=100
IN_TOK="${F[2]:-0}"
OUT_TOK="${F[3]:-0}"
WEEK_RAW="${F[4]}"; WEEK_RESET="${F[5]}"; FIVEH_RAW="${F[6]}"
PR_NUM="${F[7]}"
CWD="${F[8]:-$PWD}"
TERM_W="${F[9]:-0}"

# Width: stdin → $COLUMNS → default. (tput is useless here: our output is
# captured, not attached to a terminal.)
[ "${TERM_W:-0}" -le 0 ] && TERM_W="${COLUMNS:-0}"
[ "$TERM_W" -le 0 ] && TERM_W=200
NARROW=0; [ "$TERM_W" -lt "$NARROW_COLS" ] && NARROW=1

# Model: strip "claude-" + a trailing date stamp; keep a [1m] context flag.
SHORT_MODEL=$(printf '%s' "$MODEL" | sed -E 's/^claude-//; s/-[0-9]{8}([^0-9]|$)/\1/')

# ── Rate limits (Pro/Max login only; absent for interface-key users) ─────────
HAVE_WEEK=0; WEEK_PCT=0; WEEK_COL="$G"; WEEK_LEFT=""
if [ -n "$WEEK_RAW" ] && [ "$WEEK_RAW" != "null" ]; then
  HAVE_WEEK=1; WEEK_PCT=$(to_int "$WEEK_RAW"); [ "$WEEK_PCT" -gt 100 ] && WEEK_PCT=100
  WEEK_COL=$(pct_color "$WEEK_PCT")
  [ -n "$WEEK_RESET" ] && [ "$WEEK_RESET" != "null" ] && WEEK_LEFT=$(fmt_until "$(( WEEK_RESET - $(date +%s) ))")
fi
FIVEH_PCT=0
[ -n "$FIVEH_RAW" ] && [ "$FIVEH_RAW" != "null" ] && FIVEH_PCT=$(to_int "$FIVEH_RAW")

# ── Branch (one cheap git call; pull-request number is native) ───────────────
BRANCH_NAME=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$BRANCH_NAME" = "HEAD" ] && BRANCH_NAME="@$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)"

# ── Overall status (worst severity across context + both rate windows) ───────
WORST="$CTX_PCT"
[ "$WEEK_PCT"  -gt "$WORST" ] && WORST="$WEEK_PCT"
[ "$FIVEH_PCT" -gt "$WORST" ] && WORST="$FIVEH_PCT"
[ "$WORST" -gt 100 ] && WORST=100
if   [ "$WORST" -ge "$CRIT" ]; then STATUS_COL="$R"; STATUS_TAG="critical"
elif [ "$WORST" -ge "$HIGH" ]; then STATUS_COL="$R"; STATUS_TAG="high"
elif [ "$WORST" -ge "$WARN" ]; then STATUS_COL="$Y"; STATUS_TAG="elevated"
else                                STATUS_COL="$G"; STATUS_TAG="ok"
fi

# ── Recommended action (zero-cost heuristic from the metrics; no model) ──────
# Resource-focused, since a status line cannot see your code. Empty when healthy
# so it never nags. Words spelled out — no abbreviations.
ACTION=""
if   [ "$CTX_PCT" -ge "$CRIT" ];   then ACTION="compact the context now"
elif [ "$FIVEH_PCT" -ge "$CRIT" ]; then ACTION="five-hour limit critical — pause"
elif [ "$WEEK_PCT" -ge "$CRIT" ];  then ACTION="weekly limit critical — pause"
elif [ "$CTX_PCT" -ge "$HIGH" ];   then ACTION="consider compacting soon"
elif [ "$FIVEH_PCT" -ge "$HIGH" ]; then ACTION="near five-hour limit — slow down"
elif [ "$WEEK_PCT" -ge "$HIGH" ];  then ACTION="near weekly limit — slow down"
fi

# ── Render ───────────────────────────────────────────────────────────────────
# 1) Beacon — animated glyph keyed to the wall clock (advances once per second
#    when statusLine refreshInterval is 1).
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
BEACON="${SPIN[$(( $(date +%s) % ${#SPIN[@]} ))]}"
printf "${STATUS_COL}${B}%s${X} ${STATUS_COL}%s${X}${SEP}" "$BEACON" "$STATUS_TAG"

# 2) Recommended action (only when there is one)
[ -n "$ACTION" ] && printf "${Y}${B}%s${X}${SEP}" "$ACTION"

# 3) Context percent + bar (bar hidden on narrow terminals)
printf "${D}Context:${X} $(pct_color "$CTX_PCT")${B}%d%%${X}" "$CTX_PCT"
[ "$NARROW" -eq 0 ] && printf " %s" "$(bar "$CTX_PCT" 8 "$(pct_color "$CTX_PCT")")"
printf "${SEP}"

# 4) Tokens — real session up (sent) / down (received)
printf "${D}Tokens:${X} ${C}up${X} ${B}%s${X} ${C}down${X} ${B}%s${X}${SEP}" \
  "$(fmt_k "$IN_TOK")" "$(fmt_k "$OUT_TOK")"

# 5) Week — rolling seven-day usage (only when the login reports it)
if [ "$HAVE_WEEK" -eq 1 ]; then
  printf "${D}Week:${X} ${WEEK_COL}${B}%d%%${X}" "$WEEK_PCT"
  [ "$NARROW" -eq 0 ] && [ -n "$WEEK_LEFT" ] && printf " ${D}(resets %s)${X}" "$WEEK_LEFT"
  printf "${SEP}"
fi

# 6) Branch + pull-request number
if [ -n "$BRANCH_NAME" ]; then
  printf "${D}Branch:${X} ${C}${B}%s${X}" "$BRANCH_NAME"
  [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ] && printf " ${D}pull request${X} ${C}${B}%s${X}" "$PR_NUM"
  printf "${SEP}"
fi

# 7) Model
printf "${D}Model:${X} ${C}%s${X}" "$SHORT_MODEL"

printf '\n'
