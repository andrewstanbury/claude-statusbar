# Troubleshoot

Expansion of the README's Troubleshooting section. Symptom → cause → fix.

## Status bar doesn't appear at all

1. **Run the script directly to see if it works:**
   ```bash
   bash ~/.claude/status.sh
   ```
   If you see one line of mostly-coloured output, the script is fine.

2. **Check `~/.claude/settings.json` has the `statusLine` block:**
   ```bash
   jq '.statusLine' ~/.claude/settings.json
   ```
   Expected: `{ "type": "command", "command": "bash ~/.claude/status.sh" }` (or similar with absolute path on Windows).

3. **Restart Claude Code.** Settings changes only apply on launch.

4. **Check if Claude Code's status bar is enabled** in your `/config`. Some early versions had it off by default.

## `jq: command not found`

The script depends on `jq` to parse the JSON Claude Code sends on stdin. Install it:

| OS | Command |
|---|---|
| Debian/Ubuntu | `sudo apt install jq` |
| Fedora/RHEL | `sudo dnf install jq` |
| Arch | `sudo pacman -S jq` |
| macOS | `brew install jq` |
| Windows (Chocolatey) | `choco install jq` |
| Windows (Scoop) | `scoop install jq` |
| Windows (manual) | Download `jq.exe` from [jqlang.org/download](https://jqlang.org/download/) and put it on `PATH` |

## `free: command not found` on macOS

Expected. macOS doesn't ship the `free` command. The Mem section will show `?` instead of a percentage. Everything else still works.

If you want a real number on macOS, replace the `MEM_PCT=` line with:

```bash
MEM_PCT=$(top -l 1 -n 0 | awk '/PhysMem/ { print int($8 / ($2 + $4 + $6 + $8) * 100) }')
```

(Untested — adjust to your `top` output format.)

## Branch / commit info shows `-` or empty bars

You're not running Claude Code from inside a git repo, or your branch has no upstream/base to diff against.

The script:
- Detects the repo via `git rev-parse --is-inside-work-tree`.
- Computes the commit bar from the diff against `main` or `master` (whichever exists).
- If neither is found, the diff is empty → empty bar.

Open Claude Code from a repo directory to see git data populate.

## Windows: `bash: ~/.claude/status.sh: No such file or directory`

Git Bash translates `~` to your `%USERPROFILE%`. WSL2 translates it to the WSL home (different filesystem). Whichever environment Claude Code is running in must be the one where you installed.

```bash
# Confirm the file exists in your Git Bash environment:
ls ~/.claude/

# In WSL2, check the actual path:
echo "$HOME/.claude/"
ls "$HOME/.claude/"
```

If Claude Code runs under one and you installed under the other, run the install script under the right shell.

## Spinner doesn't animate

It's not a true animation. The frame is `(epoch_seconds % N)` — it advances only when Claude Code redraws the bar (between turns). If you sit idle, the spinner sits idle too.

If you want a real ticker, you'd need to drive it from outside the script (e.g., a watcher process that touches a file every 100ms and reads the frame from there). Out of scope for this tool.

## Cost shows wildly wrong numbers

The cost is *estimated* — the script doesn't see the real per-message billing. It's based on a 65/35 input/output split applied to total tokens-used, multiplied by the configured per-MTok prices.

Override the prices in the Tunables block at the top of `status.sh` to match your actual model:

```bash
PRICE_IN_PER_MTOK=15     # Opus 4.x
PRICE_OUT_PER_MTOK=75
```

See [`../reference/config.reference.md`](../reference/config.reference.md) for the full price table.

## Recommendation chip is wrong/annoying

The recommendation is the highest-priority item from a small priority-scored set: `/compact`, `commit your changes`, `git push`, `start a new session`, `all clear`. Tweak the score gates inline in the `# ── Recommendation ──` section of `status.sh`.

There's no central config — edit the literals. Common tweaks:

- Less frequent `/compact` reminder: raise the context-percentage threshold.
- Suppress `commit your changes` for big-change branches: lower the diff-line threshold.
- Suppress `git push` if you push infrequently: comment out the unpushed-commits priority block.
