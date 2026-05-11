# Configuration Reference

Every tunable in [`status.sh`](../../status.sh). Edit in place at the top of the script.

## Tunables (lines 38-40)

| Variable | Default | Purpose |
|---|---|---|
| `PRICE_IN_PER_MTOK` | `3` | USD cost per 1M input tokens. Default matches Sonnet 4.x rates. |
| `PRICE_OUT_PER_MTOK` | `15` | USD cost per 1M output tokens. Default matches Sonnet 4.x rates. |
| `COST_BAR_MAX_USD` | `5` | Cost bar saturates here. Higher = more sensitive bar. |

If you mostly use Opus or Haiku, override:

```bash
# Opus 4.x rates
PRICE_IN_PER_MTOK=15
PRICE_OUT_PER_MTOK=75

# Haiku 4.x rates
PRICE_IN_PER_MTOK=1
PRICE_OUT_PER_MTOK=5
```

## ANSI colours (lines 43-49)

The script uses standard 8-colour ANSI escapes. Override if your terminal handles them oddly:

| Variable | Default | Used for |
|---|---|---|
| `R` | red | CRITICAL level, expensive cost |
| `Y` | yellow | WARN/HIGH level, moderate cost |
| `G` | green | OK level, cheap |
| `C` | cyan | model name, recommendation chip |
| `B` | bold | section emphasis |
| `D` | dim | separators, secondary text |
| `X` | reset | end of escape sequence |

## Manual-test env vars

The script accepts these env vars as overrides for the JSON payload Claude Code provides on stdin. Useful for testing the bar without launching Claude Code:

| Variable | Purpose |
|---|---|
| `CLAUDE_MODEL` | Override the detected model (e.g., `claude-sonnet-4-6`) |
| `CLAUDE_CONTEXT_TOKENS_USED` | Override the current context-window usage |
| `CLAUDE_MAX_CONTEXT_TOKENS` | Override the model's context-window cap |

Test invocation:

```bash
CLAUDE_MODEL=claude-sonnet-4-6 \
CLAUDE_CONTEXT_TOKENS_USED=80000 \
CLAUDE_MAX_CONTEXT_TOKENS=200000 \
bash status.sh
```

## Recommendation thresholds (further down in the script)

The script picks one recommendation chip per render based on a priority-scored set of conditions: `/compact` when context is high, `commit your changes` when there are uncommitted changes, `git push` when ahead of upstream, `start a new session` when cost is excessive, etc.

To tweak the gates, edit the score thresholds in the `# ── Recommendation ──` section. There's no centralised config block — adjust the literal values inline.

## What's NOT configurable

- **The bar layout.** Sections always appear in the same order: spinner | level | recommendation | model | tokens | cost | git | memory.
- **Section visibility.** All sections render unconditionally; if data is unavailable (e.g., not in a git repo) the section shows `-` or empty bars rather than disappearing.
- **Refresh interval.** The bar re-renders only when Claude Code redraws it (between turns). It's not a live ticker.
