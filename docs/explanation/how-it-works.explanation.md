# How it works

What the script actually does on each invocation. Useful when modifying it.

## Lifecycle

Claude Code calls `bash ~/.claude/status.sh` between turns. The script:

1. **Reads JSON from stdin.** Claude Code passes `{ model, contextTokensUsed, maxContextTokens, ... }`. The script extracts what it needs via `jq`.
2. **Reads env-var overrides.** `CLAUDE_MODEL`, `CLAUDE_CONTEXT_TOKENS_USED`, `CLAUDE_MAX_CONTEXT_TOKENS` win over the JSON values — used for manual testing.
3. **Computes derived values:**
   - Context percentage (`tokens_used / tokens_max * 100`)
   - Cost estimate (`input_tokens * input_price + output_tokens * output_price`)
   - Cost percentage of `COST_BAR_MAX_USD` for the bar fill
   - Git diff line count (vs `main`/`master`)
   - Uncommitted/unpushed change counts
   - Memory usage percentage (Linux/WSL only)
4. **Picks one recommendation** from a priority-scored set.
5. **Renders one line** of ANSI-coloured output to stdout.

Stdout is what Claude Code shows in the status bar. Stderr is silently dropped — failures are graceful (the section shows `?` or `-`).

## Section breakdown

```
⠙  OK     all clear   sonnet-4-6   Tokens: ↑52.0k ↓28.0k   Cost: $0.58   Branch: feat/x   Commit: [██░░░]   Size: [█░░░░]   Mem: 32%
↑  ↑      ↑           ↑            ↑                       ↑             ↑                ↑                  ↑              ↑
1  2      3           4            5                       6             7                8                  9              10
```

| # | Section | Source |
|---|---|---|
| 1 | Spinner frame | `(epoch_seconds % 10)` indexed into a 10-frame braille spinner |
| 2 | Level | `OK` / `WARN` / `HIGH` / `CRITICAL` based on context percentage |
| 3 | Recommendation | Highest-priority chip — see below |
| 4 | Model | Short form, e.g., `sonnet-4-6` from `claude-sonnet-4-6-20251015` |
| 5 | Tokens | `↑input ↓output`, formatted to k/M (input estimated as 65% of total) |
| 6 | Cost | USD estimate based on `PRICE_IN_PER_MTOK` + `PRICE_OUT_PER_MTOK` |
| 7 | Branch | Current git branch, or empty if not in a repo |
| 8 | Commit bar | Uncommitted-changes bar (5 chars, fills based on line-count) |
| 9 | Size bar | Branch size (lines diff vs base), 5 chars |
| 10 | Memory | `(used / total) * 100`, Linux/WSL only via `free` |

## Recommendation priority

The recommendation chip is chosen from a scored set. Roughly (highest priority first):

1. **`start a new session`** — context > 90% AND cost > saturation
2. **`/compact`** — context > 75%
3. **`commit your changes`** — diff > N lines uncommitted
4. **`git push`** — N commits ahead of upstream
5. **`/compact`** (lower threshold) — context > 50%
6. **`all clear`** — fallback when nothing else fires

The score gates are literals inline — see [`how-to/troubleshoot.how-to.md`](../how-to/troubleshoot.how-to.md#recommendation-chip-is-wrongannoying) for tuning.

## Why bash + jq, not Python or Node

- **Cold-start time matters.** The script runs between every turn. Python takes ~50ms to start, Node ~80ms. Bash is ~5ms.
- **Zero deps to manage.** `bash` and `jq` are baseline-installable on every platform Claude Code runs on. No `pip install`, no `npm install`, no version manager dance.
- **Single file.** Easy to inspect, easy to fork.

The trade-off: the script is harder to read than the equivalent Python. Inline `awk`, `sed`, and `printf` for math/formatting. Comments help; the structure is consistent (gather → compute → render).

## Why one file, not modules

Same reason as bash-vs-Python: cold start. Sourcing extra bash files adds milliseconds. Keeping everything in one file is faster and easier to install (one `curl` to a known path).

Trade-off: 200+ lines in one file. Mitigated by clear section dividers (`# ── Section ──`).
