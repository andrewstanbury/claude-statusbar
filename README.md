# claude-statusbar

A portable, **modular** [Claude Code](https://claude.com/claude-code) setup you can drop onto any machine in one command — a rich status bar plus optional quality/workflow **hooks**, **skills**, and global **instructions**. Pick exactly the parts you want, keep each independently versioned, and stay on the latest automatically.

```
⠹ ok  ship the simple version  Context: 12% ▓░░░░░░░  Tokens: ↑182.0k ↓24.0k  Week: 62% (3d)  Branch: feat/x  PR: 42  Model: opus-4-8
```

The status bar reads everything from the metrics Claude Code now passes to a statusLine on stdin — **real** session up/down tokens, weekly rate-limit usage, and the native PR number — so there's no `gh` call, no transcript parsing, and no background processes. The advice slot (`ship the simple version`) is a throttled, context-aware one-liner that nudges you away from scope creep; it disappears when your work is appropriately focused.

## What's in it

Granularity is "medium" — the status bar, the global instructions, five hook groups, and each skill are individually selectable. Installing **everything is recommended** (and the default).

| Component | What it does |
|---|---|
| **Status bar** | Single line, all from native statusLine stdin: animated severity beacon, context % + bar, **real** session up/down tokens, weekly rate-limit usage + reset countdown (Pro/Max login only), branch + PR, model. Plus an **advice slot** — a throttled one-line anti-over-engineering recommendation written by a `Stop` hook. |
| **Global instructions** | `CLAUDE.md` — terse-mode default, quality-gate rules, web standards. (Task-management workflow moved to [claude-task-queue](https://github.com/andrewstanbury/claude-task-queue) as of 2026-05-29.) |
| **Workflow hooks** | `audit-with-rules` (full-project audit on request), `stack-lint` (advisory, stack-aware lint-on-edit). `confirm-intent` is deprecated — see [claude-task-queue](https://github.com/andrewstanbury/claude-task-queue). |
| **Quality guards** | Block debug code / untested components / untracked TODOs / no-expiry skips; plus pre-edit, pre-bash, and pre-read guards. |
| **Web standards** | Block (guard) + nudge on HTML a11y/SEO/semantic-nesting issues. |
| **Dead-code guard** | Block commented-out code blocks; recommend removing unused/duplicated code. |
| **Session / cost** | Session summary, subagent-cost guard, compaction reminder, re-read tracker. |
| **Skills** | `caveman`, `grill-me`, `write-a-skill` (each optional). |

## Install

Two ways: the **plugin** (just the status bar + its advice hook, managed by `/plugin`) or the **installer** (the full modular config — hooks, skills, instructions).

### As a Claude Code plugin (recommended for just the status bar)

```text
/plugin marketplace add andrewstanbury/claude-statusbar
/plugin install statusbar@claude-statusbar
```

Update and remove are first-class:

```text
/plugin update statusbar@claude-statusbar      # pull the latest
/plugin uninstall statusbar@claude-statusbar   # clean removal
```

The plugin ships the status bar (`status.sh`, wired as the statusLine with `refreshInterval: 1`) and the advice `Stop` hook — nothing else. The version is derived from git, so `/plugin update` always lands the latest commit.

> **Note on the statusLine:** a plugin-provided statusLine is honored by recent Claude Code (verify with `/statusline` or by checking your bar after install). If your version doesn't pick it up, use the installer below — it writes the statusLine into `~/.claude/settings.json` directly — or add it yourself: `{ "statusLine": { "type": "command", "command": "bash ~/.claude/status.sh", "refreshInterval": 1 } }`. The advice hook works from the plugin regardless. A user-level statusLine in your own `settings.json` takes precedence over the plugin's.

### As the full modular config (installer)

```bash
# Linux / macOS / WSL — requires bash 4+, git, jq
curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-statusbar/main/install.sh | bash
```

The installer asks **“Install ALL components (recommended)? [Y/n]”** — press Enter for everything, or answer `n` to choose per component. It symlinks the chosen pieces into `~/.claude` and **composes** `~/.claude/settings.json` with only the hooks you selected (plus the status line). Restart Claude Code (or run `/config`) afterwards.

Already have the repo cloned?

```bash
bash install.sh            # interactive install
bash install.sh --status   # installed-vs-latest version of each component
bash install.sh --update   # bring the installed set to latest
bash uninstall.sh          # clean removal
```

## Versioning & updates

Each component's version is **derived from git** — the short hash + date of the last commit that touched its files. `--status` lists installed vs latest and flags `↑ update available`; `--update` (or simply re-running the installer) brings everything current. Staying on the latest is the default. Your selection is remembered in `~/.claude/.claude-statusbar.json`, so updates re-apply exactly the set you chose.

## Uninstall

```bash
bash uninstall.sh
```

Removes **only** the symlinks this project created (it never touches your own files, auth, memory, or unrelated hooks/skills) and restores the `settings.json` it backed up at install time — or removes the composed one if you had no prior settings.

## Requirements

| | bash 4+ | jq | git | curl |
|---|---|---|---|---|
| **Linux** | ✓ default | via pkg mgr | for branch + versioning | ✓ default |
| **macOS** | via Homebrew[^1] | via Homebrew | via Homebrew/Xcode | ✓ default |
| **Windows** | via Git Bash / WSL2 | via Git Bash / WSL2 | ✓ | ✓ |

The status bar itself needs only `bash` + `jq` (git is used for the branch name). The advice hook additionally needs the `claude` CLI on `PATH`.

[^1]: macOS ships bash 3.2; the installer and hooks use bash 4+ features, so install a newer bash via Homebrew.

## Customization

- **Hooks** honor per-feature override env vars (e.g. `CLAUDE_WEB_GUARD_DISABLED=1`, `CLAUDE_STACK_LINT_DISABLED=1`, `CLAUDE_INTENT_CONFIRM_DISABLED=1`) — documented in `claude/CLAUDE.md`.
- **Status bar** tunables (thresholds, colours, narrow-mode width) live at the top of `status.sh`.
- **Advice slot** — generated by `claude/hooks/statusbar-advice.sh` (a throttled Haiku call). Turn it off with `CLAUDE_STATUSBAR_ADVICE_DISABLED=1`; tune cadence with `CLAUDE_STATUSBAR_ADVICE_THROTTLE=<seconds>` (default 180).
- **Components** are defined in `claude/components.sh` — the single source of truth the installer and updater both read.

## License

Released under the terms in [LICENSE](LICENSE).
