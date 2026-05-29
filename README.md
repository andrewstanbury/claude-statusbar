# claude-statusbar

A single-line status bar for [Claude Code](https://claude.com/claude-code) — and **nothing else**. It reads the JSON that Claude Code pipes to a status-line command and prints one coloured line. It makes **no model calls**, runs **no hooks**, forks nothing in the background, and writes nothing to your config beyond a single `statusLine` key. It cannot interfere with other tools (such as [claude-task-queue](https://github.com/andrewstanbury/claude-task-queue)) because all it ever does is read standard input and print a line.

```
⠹ ok  Context: 22% ▓░░░░░░░  Tokens: up 48.2k down 12.0k  Week: 31% (resets 2d)  Branch: feat/x pull request 42  Model: Opus 4.8 [1m]
```

## What it shows

Left → right; each slot collapses when its data is absent, and a narrow terminal sheds the lower-priority detail (the bar and the reset countdown):

| Slot | Meaning |
|---|---|
| **Beacon** | An animated glyph that advances once a second; its colour is the overall status severity. |
| **Status** | One word — `ok` / `elevated` / `high` / `critical` — the worst of context and rate-limit usage. |
| **Action** | A recommended action, shown only when something needs attention (e.g. *consider compacting soon*). Derived purely from the metrics — zero cost, no model call. |
| **Context** | Context-window used percent plus a small bar. |
| **Tokens** | Real session totals — `up` (sent) and `down` (received). |
| **Week** | Rolling seven-day usage percent and a reset countdown. (Shown only for Pro/Max logins, which report rate limits.) |
| **Branch** | Current git branch, plus the pull-request number when Claude Code reports one. |
| **Model** | The model display name. |

> **Note on the "billing cycle".** Claude Code does not expose a calendar-month figure. The **Week** slot is the rolling seven-day rate-limit window, which is the meaningful budget number for Pro/Max plans. Interface-key logins receive no rate-limit fields, so the Week slot is simply omitted for them.

## Install

Requires **bash 4+** and **jq**; **git** is optional (used only for the Branch slot).

```bash
git clone https://github.com/andrewstanbury/claude-statusbar.git
cd claude-statusbar
bash install.sh
```

The installer does exactly two things and nothing else:

1. places `status.sh` at `~/.claude/status.sh` (symlinked from your clone, so edits go live immediately), and
2. merges a single `statusLine` key into `~/.claude/settings.json`.

It backs up `settings.json` to `settings.json.bak` once, and **never reads or writes your `hooks`** (or any other key). Restart Claude Code (or run `/config`) afterwards.

Prefer to do it by hand? Copy `status.sh` to `~/.claude/status.sh` and add this to `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "bash ~/.claude/status.sh", "refreshInterval": 1 }
```

(`refreshInterval` is in **seconds**; `1` keeps the beacon animating while idle.)

## Update

It is a single script. From your clone:

```bash
git pull
```

Because the installer symlinks `status.sh`, a pull is the whole update — no re-install needed. (If you installed without a clone, re-run `bash install.sh` to refresh the copied script.)

## Uninstall

```bash
bash uninstall.sh
```

Removes `~/.claude/status.sh` and deletes **only** the `statusLine` key from `settings.json`. Everything else — your hooks, environment, and other keys — is left exactly as it was.

## Customize

Tunables live at the top of `status.sh`:

- `WARN` / `HIGH` / `CRIT` — the severity thresholds (percent) that drive the status word, the action, and the colours.
- `NARROW_COLS` — terminal width below which the bar and reset countdown are hidden.

It honours `NO_COLOR` and `TERM=dumb` (plain text, no ANSI codes).

## Distribution note

Claude Code plugins **cannot** ship a `statusLine` — it only takes effect from user or project `settings.json`. So there is no way to "install" a status bar without that one settings entry; this repo keeps that entry as small and surgical as possible.

## License

Released under the terms in [LICENSE](LICENSE).
