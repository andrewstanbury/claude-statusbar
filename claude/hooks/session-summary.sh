#!/usr/bin/env bash
# Stop hook — session summary printed when Claude stops a turn.
# Reads the transcript JSONL, sums token usage, and surfaces the top
# token-burn vectors (largest reads, biggest bash outputs) so the user has
# a feedback loop to fix wasteful habits.
#
# Output goes to stdout as a `systemMessage` JSON so the harness renders it
# in the UI without ending the turn unexpectedly.
set -euo pipefail

payload="$(cat)"
transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"

[ -z "$transcript" ] && exit 0
[ ! -f "$transcript" ] && exit 0

# Aggregate token usage across all assistant messages in this session.
sums="$(jq -s '
  map(select(.type == "assistant" and (.message.usage // null) != null) | .message.usage)
  | {
      input:       (map(.input_tokens // 0)               | add // 0),
      output:      (map(.output_tokens // 0)              | add // 0),
      cache_read:  (map(.cache_read_input_tokens // 0)    | add // 0),
      cache_write: (map(.cache_creation_input_tokens // 0)| add // 0),
      turns:       (length)
    }
' < "$transcript" 2>/dev/null || echo '{"input":0,"output":0,"cache_read":0,"cache_write":0,"turns":0}')"

input=$(printf '%s' "$sums" | jq -r '.input')
output=$(printf '%s' "$sums" | jq -r '.output')
cread=$(printf '%s' "$sums" | jq -r '.cache_read')
cwrite=$(printf '%s' "$sums" | jq -r '.cache_write')
turns=$(printf '%s' "$sums" | jq -r '.turns')

# Bail silently on a brand-new session with no usage yet.
[ "$turns" = "0" ] && exit 0

# Top 5 largest file reads (by byte length of the result) — and the single largest's tool_use_id (resolved to a file path below).
top_reads_json="$(jq -sc '
  [ .[]
    | select(.type == "user")
    | .message.content // []
    | (if type == "array" then .[] else . end)
    | select(type == "object" and .type == "tool_result")
    | select((.content // "") | type == "string")
    | {bytes: ((.content // "") | length), id: (.tool_use_id // "")}
  ] | sort_by(-.bytes) | .[0:5]
' < "$transcript" 2>/dev/null || echo '[]')"

top_reads="$(printf '%s' "$top_reads_json" | jq '[.[].bytes] | add // 0')"
biggest_id="$(printf '%s' "$top_reads_json" | jq -r '.[0].id // ""')"
biggest_bytes="$(printf '%s' "$top_reads_json" | jq -r '.[0].bytes // 0')"

# Resolve biggest_id → originating tool name + file path (Read/Bash/etc.) for diagnostic.
biggest_path=""
if [ -n "$biggest_id" ]; then
  biggest_path="$(jq -rs --arg id "$biggest_id" '
    [ .[]
      | select(.type == "assistant")
      | .message.content // []
      | (if type == "array" then .[] else . end)
      | select(type == "object" and .type == "tool_use" and .id == $id)
      | (.input.file_path // .input.command // "")
    ] | .[0] // ""
  ' < "$transcript" 2>/dev/null || echo "")"
  # Truncate excessively long commands for the status line.
  if [ ${#biggest_path} -gt 60 ]; then
    biggest_path="${biggest_path:0:57}..."
  fi
fi

# Top tool counts.
tool_counts="$(jq -rs '
  [ .[]
    | select(.type == "assistant")
    | .message.content // []
    | (if type == "array" then .[] else . end)
    | select(type == "object" and .type == "tool_use")
    | .name
  ]
  | group_by(.) | map({name: .[0], count: length})
  | sort_by(-.count) | .[0:5]
  | map("\(.name)=\(.count)") | join(", ")
' < "$transcript" 2>/dev/null || echo "")"

human() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000;
    else if (n >= 1000) printf "%.1fk", n/1000;
    else printf "%d", n
  }'
}

in_h=$(human "$input")
out_h=$(human "$output")
cr_h=$(human "$cread")
cw_h=$(human "$cwrite")
tr_h=$(human "$top_reads")

# Cache hit ratio — high % = good (cheap input). Low % = drift / re-reading.
total_in=$((input + cread))
if [ "$total_in" -gt 0 ]; then
  hit_pct=$((cread * 100 / total_in))
else
  hit_pct=0
fi

msg="📊 session: ${turns} turn(s) · in ${in_h} · out ${out_h} · cache r/w ${cr_h}/${cw_h} (${hit_pct}% hit) · top-5 tool-result bytes ${tr_h}"
if [ -n "$biggest_path" ] && [ "${biggest_bytes:-0}" -gt 0 ]; then
  bb_h=$(human "$biggest_bytes")
  msg="${msg} · biggest ${bb_h}: ${biggest_path}"
fi
if [ -n "$tool_counts" ]; then
  msg="${msg} · tools: ${tool_counts}"
fi

# Persist one JSON line PER SESSION (last-wins) for trend analysis.
# Stop fires after every turn, so without dedupe the log grows once per
# turn — useless for cross-session trends. Strategy: build the new entry,
# then rewrite the log keeping every OTHER session's last-known line
# plus our new line.
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
stats_log="${HOME}/.claude/session-stats.jsonl"
ROTATE_AT="${CLAUDE_SESSION_STATS_ROTATE:-1000}"

if [ -n "$session_id" ]; then
  new_line="$(jq -nc \
    --arg sid "$session_id" \
    --arg cwd "$cwd" \
    --arg ts "$(date -u +%FT%TZ)" \
    --argjson turns "$turns" \
    --argjson input "$input" \
    --argjson output "$output" \
    --argjson cread "$cread" \
    --argjson cwrite "$cwrite" \
    --argjson hit_pct "$hit_pct" \
    --argjson top_reads "$top_reads" \
    --arg tools "$tool_counts" \
    '{ts:$ts, session_id:$sid, cwd:$cwd, turns:$turns, input:$input, output:$output, cache_read:$cread, cache_write:$cwrite, hit_pct:$hit_pct, top_read_bytes:$top_reads, tools:$tools}')"

  tmp="${stats_log}.tmp.$$"
  if [ -f "$stats_log" ]; then
    # Keep only the LAST entry per session_id (other sessions), drop our
    # session_id's prior entries — `$new_line` replaces them. AWK keeps
    # final-occurrence semantics across the file.
    awk -v sid="$session_id" '
      {
        # Naive session_id extraction — matches `"session_id":"<sid>"`.
        match($0, /"session_id":"[^"]*"/)
        if (RSTART > 0) {
          curr = substr($0, RSTART+14, RLENGTH-15)
        } else {
          curr = ""
        }
        if (curr == sid) next            # drop our prior entries
        line_by_sid[curr] = $0
        order[++n] = curr
      }
      END {
        seen[""] = 0
        for (i = 1; i <= n; i++) {
          k = order[i]
          if (k != "" && !(k in seen)) {
            seen[k] = 1
          }
        }
        # Emit in original first-seen order but with the final value.
        for (i = 1; i <= n; i++) {
          k = order[i]
          if (k != "" && k in line_by_sid) {
            print line_by_sid[k]
            delete line_by_sid[k]
          }
        }
      }
    ' "$stats_log" > "$tmp" 2>/dev/null || cp "$stats_log" "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s\n' "$new_line" >> "$tmp"

  # Rotate if too long: keep only the last $ROTATE_AT lines.
  total=$(wc -l < "$tmp" 2>/dev/null || echo 0)
  if [ "$total" -gt "$ROTATE_AT" ]; then
    tail -n "$ROTATE_AT" "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"
  fi
  mv -f "$tmp" "$stats_log" 2>/dev/null || rm -f "$tmp"
fi

# Cleanup orphaned re-read logs from old sessions. The current session's
# log stays; anything older than 24h is purged.
find /tmp -maxdepth 1 -name 'claude-reads-*.txt' -mmin +1440 -delete 2>/dev/null || true

jq -nc --arg m "$msg" '{systemMessage: $m, suppressOutput: true}'
