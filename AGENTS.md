# AGENTS.md — codebase context for AI agents

Tiny standalone repo. One bash script, one installer, one README.

## What it is

A single-line status bar for [Claude Code](https://claude.com/claude-code). Reads JSON from stdin, computes context-window usage / cost / git state / memory %, picks a recommendation chip, renders one ANSI-coloured line.

## File layout

```
status.sh           ← the actual script (~200 lines)
install.sh          ← idempotent installer
README.md           ← user-facing docs (install/configure/uninstall/troubleshoot)
docs/               ← deeper reference + how-to + explanation
LICENSE             ← MIT
AGENTS.md           ← this file
```

## Conventions

- **Bash + jq + awk only.** No Python, no Node. Cold-start matters — see [`docs/explanation/how-it-works.explanation.md`](./docs/explanation/how-it-works.explanation.md).
- **Single file (`status.sh`).** Don't split into sourced modules; sourcing is slow.
- **Section dividers** (`# ── Name ──`) for readability since the file is long.
- **Graceful failure.** Every external command (`free`, `git`, etc.) is wrapped so missing tools show `?` or `-` rather than crash.
- **No persistent state.** The script is invoked fresh each render. Anything cross-render is computed from `epoch_seconds` (e.g., spinner frame).

## Common tasks

| Task | Where |
|---|---|
| Change colours | `# ── ANSI colours ──` block at top of `status.sh` |
| Adjust cost prices | `PRICE_IN_PER_MTOK` / `PRICE_OUT_PER_MTOK` near top of `status.sh` |
| Re-tune recommendation chip | `# ── Recommendation ──` block, score gates are inline |
| Test without Claude Code | `CLAUDE_MODEL=... CLAUDE_CONTEXT_TOKENS_USED=... bash status.sh` |
| Update install script | `install.sh` — must remain idempotent |

## Don'ts

- **Don't add dependencies.** Anything beyond `bash`, `jq`, `awk`, `sed`, `printf`, `git`, `free` (Linux), `top` (macOS) is too much.
- **Don't make it animate.** It only redraws between Claude Code turns. Trying to fake animation in a per-render script is the wrong shape.
- **Don't add a config file.** Tunables are inline at the top of `status.sh` — that's the install model. Adding a `~/.claude/statusbar.config` makes install/uninstall harder for no real benefit.

## Where to look

- For tunable details → [`docs/reference/config.reference.md`](./docs/reference/config.reference.md)
- For "what does the script actually do?" → [`docs/explanation/how-it-works.explanation.md`](./docs/explanation/how-it-works.explanation.md)
- For specific failure modes → [`docs/how-to/troubleshoot.how-to.md`](./docs/how-to/troubleshoot.how-to.md)
- For user-facing install/configure → [`README.md`](./README.md)
