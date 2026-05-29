# Troubleshoot

Symptom → cause → fix.

## Status bar doesn't appear at all

1. **Run the script directly:**
   ```bash
   bash ~/.claude/status.sh < /dev/null
   ```
   One line of mostly-coloured output means the script is fine.

2. **Check the `statusLine` key exists:**
   ```bash
   jq '.statusLine' ~/.claude/settings.json
   ```
   Expected: `{ "type": "command", "command": "bash /…/.claude/status.sh", "refreshInterval": 1 }`.

3. **Restart Claude Code** (or run `/config`). Settings changes apply on launch.

## `jq: command not found`

The script needs `jq` to parse the JSON on stdin. Install it:

| OS | Command |
|---|---|
| Debian/Ubuntu | `sudo apt install jq` |
| Fedora/RHEL | `sudo dnf install jq` |
| Arch | `sudo pacman -S jq` |
| macOS | `brew install jq` |
| Windows (Scoop) | `scoop install jq` |

## Branch slot is missing

You are not running Claude Code from inside a git repository, or `git` is not installed. The branch slot is detected with `git rev-parse` against the working directory and is simply omitted when there is no repo. Everything else still renders.

## Week slot is missing

The seven-day rate-limit figure only exists for **Pro/Max logins**, and only after the first request of a session. Interface-key logins receive no `rate_limits` field, so the Week slot is omitted for them by design — there is no calendar-month figure to show instead.

## The beacon doesn't animate

The frame is `(date +%s) % 10`, so it advances when Claude Code re-runs the script. With `refreshInterval: 1` in the `statusLine` config it advances about once a second even while idle. If yours is frozen, confirm the interval is set:

```bash
jq '.statusLine.refreshInterval' ~/.claude/settings.json   # should print 1
```

## The recommended action is wrong or annoying

The action is chosen by a priority cascade in the `# ── Recommended action ──` block of `status.sh`, gated by `WARN` / `HIGH` / `CRIT` (top of the script). It is empty below `HIGH`. To make it quieter, raise `HIGH`/`CRIT`; to change the wording or order, edit the inline conditions. See [`../reference/config.reference.md`](../reference/config.reference.md).

## Windows: `bash: ~/.claude/status.sh: No such file or directory`

Git Bash and WSL2 resolve `~` to different home directories. Install under the same environment Claude Code runs in:

```bash
ls ~/.claude/            # Git Bash
ls "$HOME/.claude/"      # WSL2
```

## It changed my settings.json — what did it touch?

Only the `statusLine` key. The installer backs the file up to `settings.json.bak` on first install, and the uninstaller runs `jq 'del(.statusLine)'` — your `hooks` and every other key are never read or written. Compare against the backup if you want to confirm:

```bash
diff <(jq 'del(.statusLine)' ~/.claude/settings.json) ~/.claude/settings.json.bak
```
