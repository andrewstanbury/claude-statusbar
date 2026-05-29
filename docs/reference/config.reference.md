# Configuration Reference

Every tunable in [`status.sh`](../../status.sh). Edit in place at the top of the script.

## Tunables

| Variable | Default | Purpose |
|---|---|---|
| `WARN` | `50` | Percent at/above which status becomes `elevated` (yellow). |
| `HIGH` | `75` | Percent at/above which status becomes `high` (red) and the recommended action appears. |
| `CRIT` | `90` | Percent at/above which status becomes `critical` and the action escalates (e.g. *pause*). |
| `NARROW_COLS` | `100` | Terminal width (columns) below which low-priority detail — the context bar and the week reset countdown — is hidden. |

The three thresholds apply to all three measured signals: context-window usage, the rolling five-hour rate-limit window, and the rolling seven-day window. The overall status is the worst of them.

## ANSI colours

Standard 8-colour ANSI escapes. Override if your terminal handles them oddly. They become empty strings when `NO_COLOR` is set or `TERM=dumb`.

| Variable | Default | Used for |
|---|---|---|
| `R` | red | high / critical severity |
| `Y` | yellow | elevated severity, the recommended action |
| `G` | green | ok severity |
| `C` | cyan | labels' values (tokens, branch, model) |
| `B` | bold | emphasis |
| `D` | dim | slot labels and separators |
| `X` | reset | end of an escape sequence |

## Manual testing

The script reads its data from the JSON on stdin, so pipe a sample object to test any state without launching Claude Code:

```bash
echo '{"model":{"display_name":"Opus 4.8 [1m]"},
       "context_window":{"used_percentage":82,"total_input_tokens":900000,"total_output_tokens":140000},
       "rate_limits":{"seven_day":{"used_percentage":60,"resets_at":1900000000},"five_hour":{"used_percentage":30}},
       "pr":{"number":42}}' | bash status.sh
```

`CLAUDE_MODEL` is the one env override still honoured (it wins over the model in the JSON); everything else comes from stdin.

## Recommended-action gates

The action string is chosen by a small priority cascade in the `# ── Recommended action ──` block — context-critical first, then the rate-limit windows, then the "soon" tier at `HIGH`. There is no separate config block; adjust the inline conditions there if you want different wording or ordering. The action is empty when everything is healthy, so it never nags.

## What is NOT configurable

- **The slot order.** Beacon · status · action · context · tokens · week · branch · model, always in that order.
- **A config file.** All tuning is inline at the top of `status.sh` by design — it keeps install and uninstall to one file and one settings key.
- **A live ticker.** The bar re-renders when Claude Code redraws it; with `refreshInterval: 1` that is about once a second, which is what animates the beacon.
