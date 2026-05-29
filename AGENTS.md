# AGENTS.md — codebase context for AI agents

Tiny standalone repo. One bash script that renders a status bar, plus a surgical installer/uninstaller. Nothing else.

## What it is

A single-line status bar for [Claude Code](https://claude.com/claude-code). It reads the status-line JSON on stdin and prints one ANSI-coloured line. It is **only** a status bar: no model calls, no hooks, no background forks, and the only config it writes is one `statusLine` key. This scope is deliberate — it must never interfere with other tools (e.g. claude-task-queue).

## File layout

```
status.sh       ← the status-bar script (bash + jq + awk)
install.sh      ← surgical installer: places status.sh + merges ONLY statusLine
uninstall.sh    ← removes status.sh + deletes ONLY the statusLine key
README.md       ← user-facing install/update/uninstall
docs/           ← reference / how-to / explanation
LICENSE
AGENTS.md       ← this file
```

## Conventions

- **Bash + jq + awk only.** No Python, no Node, no extra dependencies. Cold start matters.
- **Single file (`status.sh`).** Don't split into sourced modules — sourcing is slow and one file installs cleanly.
- **Section dividers** (`# ── Name ──`) for readability.
- **Graceful failure.** Every external call (`git`, etc.) is wrapped so a missing tool or a non-repo directory drops the slot rather than crashing.
- **No persistent state.** The script runs fresh each render; the only cross-render value is the beacon frame, derived from `date +%s`.
- **Reads stdin, writes one line.** It must never write files, call a model, or fork background work. Keeping that contract is what makes it safe alongside other tools.

## The installer's contract (do not break)

`install.sh` and `uninstall.sh` must touch **only** the `statusLine` key in `~/.claude/settings.json` (via `jq`) and the `~/.claude/status.sh` file. They must never read or write `.hooks` or any other key — that is the whole point of the rewrite. Test any change with a throwaway `CLAUDE_CONFIG_DIR` that already contains hooks, and confirm the hooks survive.

## Common tasks

| Task | Where |
|---|---|
| Change thresholds / colours | tunables + palette block at the top of `status.sh` |
| Re-tune the recommended action | `# ── Recommended action ──` block (inline gates) |
| Add / change a slot | `# ── Render ──` block |
| Test without Claude Code | `echo '{...}' \| NO_COLOR=1 bash status.sh` |

## Don'ts

- **Don't add dependencies** beyond `bash`, `jq`, `awk`, `sed`, `printf`, `git`.
- **Don't make the installer compose the whole settings.json.** Merge only `statusLine`.
- **Don't read another tool's state** (queue files, caches, etc.) — that re-couples the bar to things it should be independent of.
- **Don't add a config file.** Tunables are inline at the top of `status.sh`.

## Where to look

- Tunables → [`docs/reference/config.reference.md`](./docs/reference/config.reference.md)
- What the script does each render → [`docs/explanation/how-it-works.explanation.md`](./docs/explanation/how-it-works.explanation.md)
- Failure modes → [`docs/how-to/troubleshoot.how-to.md`](./docs/how-to/troubleshoot.how-to.md)
