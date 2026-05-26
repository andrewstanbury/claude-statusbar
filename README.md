# claude-statusbar

A portable, **modular** [Claude Code](https://claude.com/claude-code) setup you can drop onto any machine in one command — a rich status bar plus optional quality/workflow **hooks**, **skills**, and global **instructions**. Pick exactly the parts you want, keep each independently versioned, and stay on the latest automatically.

```
● ok  Context: 12%  ▓░░░░░░░  Tokens: ↑52.0k ↓28.0k  Cost: $0.58  Branch: feat/x  PR: 42  Web: ⚠ 2  Dirty: 3  Model: sonnet-4-6  Memory: 32%
```

## What's in it

Granularity is "medium" — the status bar, the global instructions, five hook groups, and each skill are individually selectable. Installing **everything is recommended** (and the default).

| Component | What it does |
|---|---|
| **Status bar** | Single line: context %, tokens, cost/time, git (branch · PR · web-degradation flag · dirty · unpushed · base · lines · stash), model/mode, memory. |
| **Global instructions** | `CLAUDE.md` — terse-mode default, quality-gate rules, web standards, and the confirm-intent task-management workflow (restate → prioritized tasks with time estimates → per-task approval/pacing). |
| **Workflow hooks** | `confirm-intent`, `audit-with-rules` (full-project audit on request), `stack-lint` (advisory, stack-aware lint-on-edit). |
| **Quality guards** | Block debug code / untested components / untracked TODOs / no-expiry skips; plus pre-edit, pre-bash, and pre-read guards. |
| **Web standards** | Block (guard) + nudge on HTML a11y/SEO/semantic-nesting issues. |
| **Dead-code guard** | Block commented-out code blocks; recommend removing unused/duplicated code. |
| **Session / cost** | Session summary, subagent-cost guard, compaction reminder, re-read tracker. |
| **Skills** | `caveman`, `grill-me`, `write-a-skill` (each optional). |

## Install

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

| | bash 4+ | jq | git | curl | free (optional) |
|---|---|---|---|---|---|
| **Linux** | ✓ default | via pkg mgr | for branch/PR + versioning | ✓ default | ✓ default |
| **macOS** | via Homebrew[^1] | via Homebrew | via Homebrew/Xcode | ✓ default | n/a (memory shows nothing) |
| **Windows** | via Git Bash / WSL2 | via Git Bash / WSL2 | ✓ | ✓ | WSL2 only |

[^1]: macOS ships bash 3.2; the installer and hooks use bash 4+ features, so install a newer bash via Homebrew.

## Customization

- **Hooks** honor per-feature override env vars (e.g. `CLAUDE_WEB_GUARD_DISABLED=1`, `CLAUDE_STACK_LINT_DISABLED=1`, `CLAUDE_INTENT_CONFIRM_DISABLED=1`) — documented in `claude/CLAUDE.md`.
- **Status bar** tunables (thresholds, colours, narrow-mode width) live at the top of `status.sh`.
- **Components** are defined in `claude/components.sh` — the single source of truth the installer and updater both read.

## License

Released under the terms in [LICENSE](LICENSE).
