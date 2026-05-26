# Claude Code Status Bar

A single-line status bar for [Claude Code](https://claude.com/claude-code) that shows what you actually need at a glance:

```
⠙ OK | all clear | sonnet-4-6 | Tokens: ↑52.0k ↓28.0k | Cost: $0.58 | Branch: feat/x | Commit: [██░░░] | Size: [█░░░░] | Mem: 32%
```

- **Spinner + level** — `OK` / `WARN` / `HIGH` / `CRITICAL`, driven by context window usage
- **Recommendation** — highest-priority actionable nudge: `/compact`, `commit your changes`, `git push`, `start a new session`, etc.
- **Model**, **token usage**, **session cost estimate**
- **Git** — current branch, uncommitted-changes bar, branch-size bar (lines vs base)
- **System memory %**

---

## Requirements

| | bash 4+ | jq | curl | git (optional) | free (optional) |
|---|---|---|---|---|---|
| **Linux** | ✓ default | install via pkg mgr | ✓ default | for branch info | ✓ default |
| **macOS** | install via Homebrew[^1] | install via Homebrew | ✓ default | for branch info | n/a (memory shows `?`) |
| **Windows** | via Git Bash / WSL2 | via Git Bash / WSL2 | ✓ in both | for branch info | WSL2 only |

[^1]: macOS ships bash 3.2. The script *mostly* works on 3.2 but bash 4+ is recommended.

---

## Install

### Linux

```bash
# 1. install jq if you don't have it
sudo apt install jq           # Debian/Ubuntu
sudo dnf install jq           # Fedora/RHEL
sudo pacman -S jq             # Arch

# 2. one-liner install
curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-statusbar/main/install.sh | bash
```

### macOS

```bash
# 1. install bash 4+ and jq via Homebrew
brew install bash jq

# 2. one-liner install
curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-statusbar/main/install.sh | bash
```

### Windows

**Option A — Git Bash** (recommended if you already use it):

1. Open **Git Bash** (ships with [Git for Windows](https://git-scm.com/download/win)).
2. Install `jq`:
   - Easiest: download [jq.exe](https://jqlang.org/download/) and place in your `PATH`.
   - Or via [Chocolatey](https://chocolatey.org/): `choco install jq`
   - Or via [Scoop](https://scoop.sh/): `scoop install jq`
3. Run the installer:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-statusbar/main/install.sh | bash
   ```
4. The status bar writes to `%USERPROFILE%\.claude\settings.json`, which Claude Code on Windows reads.

**Option B — WSL2** (if Claude Code runs inside WSL):

```bash
sudo apt install jq
curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-statusbar/main/install.sh | bash
```

> The installer is idempotent and backs up any existing `status.sh` and `settings.json` before changing them.

---

## Manual install (any platform)

If you'd rather not pipe a script to bash:

1. Download [`status.sh`](./status.sh) to `~/.claude/status.sh`.
2. `chmod +x ~/.claude/status.sh`
3. Add to `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/status.sh"
     }
   }
   ```
4. Restart Claude Code (or run `/config`).

On Windows, replace `~/.claude/` with `%USERPROFILE%\.claude\` and use forward slashes in the JSON (`bash /c/Users/you/.claude/status.sh` for Git Bash).

---

## Configuration

Open `~/.claude/status.sh` and edit the **Tunables** block near the top:

```bash
PRICE_IN_PER_MTOK=3      # input price per million tokens (USD)
PRICE_OUT_PER_MTOK=15    # output price per million tokens (USD)
COST_BAR_MAX_USD=5       # cost bar saturates here
```

Defaults match Sonnet 4.x rates. Adjust to match the model you use most.

The advice thresholds (when to suggest `/compact`, `commit`, etc.) live further down in the **Recommendation** section — tweak the score gates to taste.

For the full list of tunables (including price tables for Opus/Haiku, ANSI colour overrides, and manual-test env vars) see [`docs/reference/config.reference.md`](./docs/reference/config.reference.md).

---

## Portable Claude config

The [`claude/`](./claude) directory is a portable bundle of global Claude Code customizations, so a freshly-formatted machine can be brought back to the same setup with one command:

```bash
git clone https://github.com/andrewstanbury/claude-statusbar.git
bash claude-statusbar/claude/install.sh
```

`install.sh` **symlinks** the bundle into `~/.claude` (backing up any existing files to `*.bak`), so the repo stays the source of truth — edits you make live in `~/.claude` flow back here through the links. It's idempotent; re-run any time. If a tool ever replaces a symlink with a regular file, just re-run it.

What's included:

| Bundle path | Linked to | What it is |
|---|---|---|
| `claude/settings.json` | `~/.claude/settings.json` | permissions, theme, status line, hook wiring |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | global instructions |
| `claude/hooks/*.sh` | `~/.claude/hooks/` | quality/bloat/web-standards guards + nudges, stack-aware lint-on-edit, prompt intent/audit hooks |
| `claude/skills/<name>` | `~/.claude/skills/` | custom skills |
| `status.sh` | `~/.claude/status.sh` | this status bar |

> This repo is **public**, so it deliberately contains no secrets and no project-specific/proprietary agents — those stay local-only (see `.gitignore`).

---

## Uninstall

```bash
# remove the statusLine entry from settings.json (preserves other keys)
jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json

# delete the script
rm ~/.claude/status.sh
```

Restart Claude Code.

---

## Troubleshooting

**Status bar doesn't appear.** Run `bash ~/.claude/status.sh` manually — if you see output, the script is fine. Check `~/.claude/settings.json` has the `statusLine` block, then restart Claude Code.

**`jq: command not found`.** See requirements above for your platform.

**`free: command not found` on macOS.** Expected — memory shows `?` on macOS. The bar still works.

**Branch / commit info shows `-` or empty bars.** You're not in a git repo, or there's no upstream/base branch to diff against. Open Claude Code from a repo dir to see git data.

**Windows: `bash: ~/.claude/status.sh: No such file or directory`.** Git Bash translates `~` to your `%USERPROFILE%`. Confirm with `ls ~/.claude/` in Git Bash. If using WSL2, the path is the WSL home, not Windows home — install must be done inside the same environment Claude Code runs in.

**Spinner doesn't animate.** It only advances when Claude Code redraws the status bar (between turns). It's not a true animation — it's a per-render frame index based on epoch seconds.

---

## License

MIT — do whatever, no warranty.
