# How it works

What the script actually does on each invocation. Useful when modifying it.

## Lifecycle

Claude Code runs `bash ~/.claude/status.sh` whenever it redraws the status line — and, because the install sets `refreshInterval: 1`, roughly once a second while idle (that is what animates the beacon). The script:

1. **Reads JSON from stdin.** Claude Code pipes a status-line object containing `model`, `context_window`, `rate_limits`, `pr`, `workspace`, and more. Everything is extracted in a **single `jq` call**, with `// default` per field; an empty stdin falls back to `{}`.
2. **Applies the one env override.** `CLAUDE_MODEL` wins over the model in the JSON (handy for testing).
3. **Computes derived values:** context percent (clamped to 100), the worst severity across context and both rate-limit windows, the seven-day reset countdown, the short model name, and the current git branch.
4. **Picks one recommended action** from a small priority cascade (empty when healthy).
5. **Renders one line** of ANSI-coloured output to stdout.

Stdout is the status line. There is no stderr handling to worry about because the script never calls anything risky — a missing `git` or a non-repo directory just drops the branch slot.

## Slot breakdown

```
⠹ ok  consider compacting soon  Context: 78% ▓▓▓▓▓▓░░  Tokens: up 52.0k down 28.0k  Week: 31% (resets 2d)  Branch: feat/x pull request 42  Model: sonnet-4-6
↑ ↑   ↑                         ↑                       ↑                            ↑                      ↑
1 2   3                         4                       5                            6                      7
```

| # | Slot | Source |
|---|---|---|
| 1 | Beacon | `(date +%s) % 10` indexed into a 10-frame braille spinner; colour = overall severity |
| 2 | Status | `ok` / `elevated` / `high` / `critical` from the worst signal |
| 3 | Action | The recommended action (only when one fires) |
| 4 | Context | `context_window.used_percentage` + an 8-cell bar |
| 5 | Tokens | `context_window.total_input_tokens` / `total_output_tokens`, formatted to k/M |
| 6 | Week | `rate_limits.seven_day.used_percentage` + reset countdown (Pro/Max only) |
| 7 | Branch + model | `git rev-parse` + native `pr.number`; `model.display_name` |

## Severity and the recommended action

Severity is `max(context%, five_hour%, seven_day%)`, banded by `WARN` / `HIGH` / `CRIT`. The action is a single string chosen by priority: context-critical → rate-limit-critical → context-high → rate-limit-high, and empty below `HIGH`. Because a status line cannot see your code, the action is **resource-focused** (compact, slow down, pause) rather than code-aware — there is no model call, so it costs nothing and adds no latency.

## Why bash + jq, not Python or Node

- **Cold-start time matters.** The script runs about once a second. Bash starts in ~5 ms; Python ~50 ms; Node ~80 ms.
- **Zero dependencies to manage.** `bash` and `jq` are baseline on every platform Claude Code runs on.
- **Single file.** Easy to inspect, easy to fork, installs to one known path.

## Why it is only a status bar

Earlier versions of this project also installed hooks, skills, and global instructions, and the installer recomposed your whole `settings.json`. That made the status bar capable of disturbing other tools (it could drop another tool's hooks on update). The rewrite removed all of that: the script only reads stdin and prints a line, and the installer only ever touches the `statusLine` key. The narrow scope is the feature — it is what makes the bar safe to run alongside anything else.
