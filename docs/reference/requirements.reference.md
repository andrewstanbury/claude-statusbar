# claude-statusbar — Requirements Reference

> **Purpose.** This is a complete, build-from-scratch specification of the
> `claude-statusbar` project. It is written so that a competent agent (or human)
> given **only this file** can recreate the entire repository — the status bar,
> every hook, every skill, the installer/uninstaller, the global instructions,
> and the docs — with behaviour-faithful fidelity.
>
> **How to use it.** Read §1–§4 for context and constraints, then build
> component-by-component using §5–§13 as the contract for each. §14 is the
> acceptance checklist. **Appendix A is an ordered "build playbook" of prompts**
> you can paste into Claude one at a time to construct the repo end-to-end.
>
> Where a value is a default that the user can override, it is given as
> `NAME (default: X)`. All env-var names are normative.

---

## 1. Project overview & goals

`claude-statusbar` is a **portable, modular [Claude Code](https://claude.com/claude-code) setup** that can be dropped onto any machine in one command. It delivers:

- a rich single-line **status bar**,
- a set of optional **quality / workflow hooks**,
- a few optional **skills**, and
- a global **instructions** file (`CLAUDE.md`).

Design goals, in priority order:

1. **One-command install** over `curl | bash`, with a local clone path too.
2. **Modularity** — "medium" granularity: the status bar, the global
   instructions, five hook groups, and each skill are individually selectable.
   Installing **everything is the recommended default**.
3. **Non-destructive** — the installer only ever symlinks its own files into
   `~/.claude`, composes `settings.json` from the selected pieces, and on
   uninstall restores exactly what it found. It never touches the user's auth,
   memory, or unrelated hooks/skills.
4. **Self-updating** — each component's version is derived from git; `--status`
   shows installed-vs-latest and `--update` brings everything current.
5. **Zero runtime dependencies beyond a baseline** — bash 4+, `jq`, `git`;
   `gh` and `free` are optional and degrade gracefully.
6. **Token-frugal** — hooks are local-first (static checks + local linters),
   spending model tokens only as a last resort (a single cheap Haiku triage).

Example rendered status line:

```
● ok  Context: 12%  ▓░░░░░░░  Tokens: ↑52.0k ↓28.0k  Cost: $0.58  Branch: feat/x  PR: 42  Web: ⚠ 2  Dirty: 3  Model: sonnet-4-6  Memory: 32%
```

---

## 2. Repository layout

```
claude-statusbar/
├── README.md                       # user-facing install/usage
├── AGENTS.md                       # agent-facing repo overview & conventions
├── LICENSE
├── .gitignore                      # must ignore local-only agents, caches, OS cruft
├── install.sh                      # unified, component-aware installer (entry point)
├── uninstall.sh                    # removes only what install.sh created
├── status.sh                       # the status-bar script (bash + jq)
├── claude/
│   ├── CLAUDE.md                   # the global-instructions file that gets installed
│   ├── components.sh               # component registry (sourced by install.sh)
│   ├── install.sh                  # deprecated shim → forwards to root install.sh
│   ├── settings.json               # BASE settings template (statusLine+hooks are composed in)
│   ├── hooks/
│   │   ├── confirm-intent.sh
│   │   ├── audit-with-rules.sh
│   │   ├── stack-lint.sh
│   │   ├── quality-guard.sh
│   │   ├── deadcode.sh             # one script, two modes (pre|post via $1)
│   │   ├── web-standards-guard.sh
│   │   ├── web-standards-nudge.sh
│   │   ├── pre-edit-guards.sh
│   │   ├── pre-bash-guards.sh
│   │   ├── pre-read-guards.sh
│   │   ├── re-read-track.sh
│   │   ├── subagent-cost-guard.sh
│   │   ├── session-summary.sh
│   │   ├── pre-compact-reminder.sh
│   │   └── lib/
│   │       └── web-standards-checks.sh   # shared by guard + nudge
│   └── skills/
│       ├── caveman/SKILL.md
│       ├── grill-me/SKILL.md
│       └── write-a-skill/SKILL.md
└── docs/                           # Diátaxis: reference / how-to / explanation
    ├── README.md
    ├── reference/
    │   ├── config.reference.md
    │   └── requirements.reference.md   # ← this file
    ├── how-to/
    │   └── troubleshoot.how-to.md
    └── explanation/
        └── how-it-works.explanation.md
```

---

## 3. Technical constraints & design principles

- **Languages/tools:** Everything is **bash + `jq` + `awk`/`sed`/`printf`**. No
  Python, Node, or compiled deps. Rationale: cold-start time (bash ~5 ms vs
  Python ~50 ms vs Node ~80 ms) and universal availability.
- **`status.sh` is a single file**, organised by `# ── Section ──` dividers — no
  sourced modules (sourcing adds cold-start ms, and one file installs with one
  `curl`).
- **Hooks are independent scripts** under `claude/hooks/`, each reading the hook
  JSON payload on **stdin** and emitting its decision/context on **stdout**.
- **Graceful degradation everywhere:** if `git`/`gh`/`free`/`jq` are missing,
  not in a repo, etc., the relevant output is omitted rather than erroring.
- **No persistent state in the status bar** beyond `/tmp` caches; hook state
  lives in `/tmp/claude-*` (per-session) or `~/.claude/` (stats/selection).
- **Honour `NO_COLOR` / `TERM=dumb`** — emit plain text when set.
- **Token-frugality is a feature.** Hooks prefer static analysis and locally
  installed linters; only `stack-lint` may spend tokens, and only on a single
  cheap Haiku triage call when findings exceed a threshold.

### Hook I/O contract (Claude Code)

Each hook is wired in `settings.json` under an **event key** with an optional
**tool matcher**, e.g.:

```json
{ "matcher": "Edit|Write|MultiEdit",
  "hooks": [ { "type": "command", "command": "bash $HOME/.claude/hooks/X.sh", "timeout": 5 } ] }
```

Events used by this project: `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PreCompact`, `Stop`.

**Decision/output shapes** (emitted as JSON on stdout):

- **Advisory (inject context):**
  ```json
  { "hookSpecificOutput": { "hookEventName": "<Event>", "additionalContext": "<text>" } }
  ```
- **Block a PreToolUse action (deny):**
  ```json
  { "hookSpecificOutput": { "hookEventName": "PreToolUse",
      "permissionDecision": "deny", "permissionDecisionReason": "<text>" } }
  ```
- **Block at PostToolUse (force a correction):**
  ```json
  { "decision": "block", "reason": "<text>" }
  ```
- **Silent / allow:** print nothing and `exit 0`.

A hook that wants to stay silent simply prints nothing. Every hook should
`exit 0` on any internal error (never break the user's tool call).

---

## 4. Cross-platform & dependencies

| | bash 4+ | jq | git | curl | gh | free |
|---|---|---|---|---|---|---|
| **Required** | ✓ | ✓ | ✓ (install + git segments) | for `curl\|bash` install | optional (PR segment) | optional (memory segment) |
| **Linux** | default | pkg mgr | pkg mgr | default | pkg mgr | default |
| **macOS** | Homebrew | Homebrew | Homebrew/Xcode | default | brew | n/a → memory omitted |
| **Windows** | Git Bash / WSL2 | Git Bash / WSL2 | ✓ | ✓ | optional | WSL2 only |

`install.sh` hard-requires `git` and `jq` (dies with a clear message if
missing). `status.sh` treats `gh` and `free` as optional and omits their
segments when absent.

---

## 5. Component model (`claude/components.sh`)

`components.sh` is the **single source of truth** for what can be installed. It
defines four parallel bash associative-array structures keyed by component id:

- `COMPONENT_ORDER` — ordered list of component ids (drives menu + install order).
- `COMPONENT_LABEL[id]` — human-readable label for the interactive menu.
- `COMPONENT_PATHS[id]` — space-separated repo-relative paths to symlink.
- `COMPONENT_HOOKS[id]` — newline-separated hook specs (blank if none).

**Hook spec line format** (parsed by the installer):

```
EVENT::MATCHER::SCRIPT_AND_ARGS::TIMEOUT
```

- `EVENT` ∈ {UserPromptSubmit, PreToolUse, PostToolUse, PreCompact, Stop}
- `MATCHER` = tool matcher (e.g. `Edit|Write|MultiEdit`) or blank for
  event types that take no matcher.
- `SCRIPT_AND_ARGS` = path relative to `~/.claude/hooks` (may include args,
  e.g. `deadcode.sh pre`).
- `TIMEOUT` = integer seconds.

### The 10 components

| id | Label | Paths | Hooks |
|---|---|---|---|
| `statusbar` | Status bar (status.sh + statusLine) | `status.sh` | — (contributes the `statusLine` block) |
| `instructions` | Global instructions (CLAUDE.md) | `claude/CLAUDE.md` | — |
| `workflow` | Workflow hooks — confirm-intent, audit-with-rules, stack-lint | `claude/hooks/confirm-intent.sh`, `claude/hooks/audit-with-rules.sh`, `claude/hooks/stack-lint.sh` | 3 |
| `quality-guards` | Quality guards — quality-guard + pre-edit/bash/read | `claude/hooks/quality-guard.sh`, `claude/hooks/pre-edit-guards.sh`, `claude/hooks/pre-bash-guards.sh`, `claude/hooks/pre-read-guards.sh` | 4 |
| `web-standards` | Web standards — guard (blocks) + nudge | `claude/hooks/web-standards-guard.sh`, `claude/hooks/web-standards-nudge.sh`, `claude/hooks/lib/web-standards-checks.sh` | 2 |
| `dead-code` | Dead-code guard (pre block + post recommend) | `claude/hooks/deadcode.sh` | 2 |
| `session-cost` | Session/cost — summary, subagent cost, compact reminder, re-read | `claude/hooks/session-summary.sh`, `claude/hooks/subagent-cost-guard.sh`, `claude/hooks/pre-compact-reminder.sh`, `claude/hooks/re-read-track.sh` | 4 |
| `skill-caveman` | Skill: caveman | `claude/skills/caveman` | — |
| `skill-grill-me` | Skill: grill-me | `claude/skills/grill-me` | — |
| `skill-write-a-skill` | Skill: write-a-skill | `claude/skills/write-a-skill` | — |

### Full hook wiring table (what the installer composes)

| Component | Event | Matcher | Script (+args) | Timeout |
|---|---|---|---|---|
| workflow | UserPromptSubmit | — | `confirm-intent.sh` | 5 |
| workflow | UserPromptSubmit | — | `audit-with-rules.sh` | 5 |
| workflow | PostToolUse | `Edit\|Write\|MultiEdit` | `stack-lint.sh` | 45 |
| quality-guards | PreToolUse | `Edit\|Write\|MultiEdit` | `quality-guard.sh` | 5 |
| quality-guards | PreToolUse | `Edit\|Write\|MultiEdit` | `pre-edit-guards.sh` | 5 |
| quality-guards | PreToolUse | `Bash` | `pre-bash-guards.sh` | 5 |
| quality-guards | PreToolUse | `Read` | `pre-read-guards.sh` | 5 |
| web-standards | PreToolUse | `Edit\|Write\|MultiEdit` | `web-standards-guard.sh` | 5 |
| web-standards | PostToolUse | `Edit\|Write\|MultiEdit` | `web-standards-nudge.sh` | 5 |
| dead-code | PreToolUse | `Edit\|Write\|MultiEdit` | `deadcode.sh pre` | 5 |
| dead-code | PostToolUse | `Edit\|Write\|MultiEdit` | `deadcode.sh post` | 20 |
| session-cost | Stop | — | `session-summary.sh` | 10 |
| session-cost | PreToolUse | `Agent` | `subagent-cost-guard.sh` | 5 |
| session-cost | PreCompact | — | `pre-compact-reminder.sh` | 5 |
| session-cost | PostToolUse | `Read\|Edit\|Write\|MultiEdit` | `re-read-track.sh` | 5 |

---

## 6. Status bar (`status.sh`) — exhaustive spec

### 6.1 Input (stdin JSON)

Claude Code pipes a statusline JSON object on stdin. The script falls back to
`{}` if stdin is empty, and extracts these fields with a **single `jq -r`** call
(array-indexed, `// default` for each):

| jq path | Fallbacks | Meaning |
|---|---|---|
| `.model.id` | `.model.display_name`, `"unknown"` | model id |
| `.context_window.used_tokens` | `0` | tokens used |
| `.context_window.used_percentage` | `0` | used % (used to derive max) |
| `.permission_mode` | `""` | permission mode |
| `.output_style.name` | `""` | output style |
| `.cost.total_cost_usd` | `""` | real cost if present |
| `.cost.total_duration_ms` | `0` | session elapsed ms |
| `.workspace.current_dir` | `.cwd`, `$PWD` | working dir |
| `.terminal_width` | `.columns`, `$COLUMNS`, `tput cols`, `200` | width |

**Env overrides** (win over stdin): `CLAUDE_MODEL`, `CLAUDE_CONTEXT_TOKENS_USED`,
`CLAUDE_MAX_CONTEXT_TOKENS`.

**Context-max derivation:** if stdin gives `used_percentage > 0` and tokens > 0,
back-compute max from the ratio; else use `CLAUDE_MAX_CONTEXT_TOKENS`; else if the
model id contains `[1m]` use `1000000`; else default `200000`.

### 6.2 Tunables (top of script)

| Var | Default | Purpose |
|---|---|---|
| `PRICE_IN_PER_MTOK` | 3 | USD per Mtok input (Sonnet 4.x) |
| `PRICE_OUT_PER_MTOK` | 15 | USD per Mtok output |
| `COST_BAR_MAX_USD` | 5 | cost severity saturation |
| `CTX_WARN` / `CTX_HIGH` / `CTX_CRIT` | 50 / 75 / 90 | context % bands |
| `DIRTY_WARN` / `DIRTY_HIGH` / `DIRTY_CRIT` | 5 / 10 / 20 | dirty-file bands |
| `PUSH_WARN` / `PUSH_HIGH` | 5 / 10 | unpushed-commit bands |
| `MEM_CRIT` | 90 | memory critical band |
| `NARROW_COLS` | 110 | width below which low-priority segments hide |
| `PR_CACHE_TTL` | 300 | PR cache seconds |

Colour palette (empty strings when `NO_COLOR` set or `TERM=dumb`): `R` red,
`Y` yellow, `G` green, `C` cyan, `B` bold, `D` dim, `X` reset. Group separator
`GSEP` = two spaces.

### 6.3 Helper functions

- `pct_color(n)` → green `<50`, yellow `50–74`, red `≥75`.
- `fmt_k(n)` → `%.1fM` ≥1e6, `%.1fk` ≥1e3, else integer (e.g. `52.0k`).
- `fmt_duration(s)` → `Xs` <60, `Xm` <3600, else `XhYm`.
- `fmt_count(n[,prefix])` → dim ` 0` when zero; coloured-bold ` N` otherwise.
- 8-cell bar builder: filled `▓` = `ceil(pct*width/100)` capped at width, empty
  `░` for the rest; filled bold+coloured, empty dim.

### 6.4 Segments (left → right)

All segments are joined by `GSEP`; the line ends with a newline.

1. **Verdict beacon + severity tag.** A 10-frame braille spinner
   (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`, index = `epoch % 10`) followed by `ok`/`medium`/`high`/`critical`.
   Severity = `WORST = max(CTX_PCT, COST_PCT, DIRTY×5, UNPUSHED×10, MEM_PCT)`;
   `CONFLICTS>0 → 100`; `WEB_ISSUES>0 and WORST<80 → 80`; cap 100. Tag: `≥90`
   critical (red+bold), `≥75` high, `≥50` medium (yellow+bold), else `ok` (green).
2. **Advice** (conditional — single highest-priority imperative). Scored set,
   highest score wins:
   - CTX ≥90 → `/compact` (100); ≥75 → `/compact` (80); ≥50 → `consider /compact` (50)
   - COST% ≥80 → `new session` (70); 50–79 → `watch cost` (40)
   - DIRTY ≥20/≥10 → `break into smaller commits` (75/60); ≥5 → `commit changes` (45)
   - UNPUSHED ≥10 → `split into multiple PRs` (65); ≥5 → `git push` (50)
   - CONFLICTS>0 → `resolve conflicts` (95)
   - TO_PULL ≥1 → `git pull` (30)
   - MEM ≥90 → `free memory` (85)
   - WEB_ISSUES>0 → `fix web a11y/SEO (N)` (78)
3. **Context** — `Context: NN%` (banded colour) + 8-cell mini-bar (bar hidden in
   narrow mode).
4. **Tokens** — `Tokens: ↑IN ↓OUT` (cyan arrows), split 65% in / 35% out of
   tokens-used, each via `fmt_k`.
5. **Cost + Time** — `Cost: $X.XX` (or `<$0.01`), coloured by
   `COST_PCT = real_or_estimate / COST_BAR_MAX_USD × 100`. Real cost from stdin if
   present, else estimated from the 65/35 split × prices. Cost is bold only when
   advice is empty. `Time: <fmt_duration>` shown when duration>0 and not narrow.
6. **Repo group** (only if inside a git repo). One `git status --porcelain=2
   --branch` call drives most fields:
   - `Branch:` name (or `@<short-sha>` if detached); prefixed `⎇ ` if in a
     worktree (git-dir ≠ common-dir).
   - `PR:` number — via `gh`, cached in `/tmp/claude-pr-<hash>` (TTL `PR_CACHE_TTL`,
     refreshed in background, `-` sentinel = no PR).
   - `Web: ⚠ N` — count of web-standards violations across changed web files
     (`*.html/*.vue/*.svelte/*.astro`, max 25 files) via
     `ws_doc_findings`, cached in `/tmp/claude-web-<hash>` (TTL 15s, only when
     ahead-of-base or dirty).
   - `Dirty: N` — porcelain lines `^[12?]`, coloured `pct_color(DIRTY×5)`.
   - `Unpushed: N` — ahead count, coloured `pct_color(UNPUSHED×10)`.
   - `Behind: N` — only when behind > 0.
   - `Base: ↑A ↓B` — ahead/behind vs base branch (origin/HEAD → origin/main →
     origin/master).
   - `Lines: +N` — insertions+deletions vs merge-base (hidden when narrow).
   - `Stash: N` — `git stash list | wc -l` (hidden when narrow, omitted if 0).
   - `EAS: EXPO_GO=1` — shown (not narrow) when `eas.json` exists in repo root.
7. **Model · Mode · Style.** `Model:` short name (strip `claude-` prefix and a
   trailing `-YYYYMMDD` date; keep `[1m]`). `Mode:` only when permission_mode is
   non-empty and not `default`/`auto` (red+bold for `bypassPermissions`, else
   yellow+bold). `Style:` only when output style non-empty and not `default`.
8. **Memory.** `Memory: N%` from `free -m` (`used*100/total`), coloured by
   `pct_color`. Omitted entirely if `free` is unavailable (e.g. macOS).

### 6.5 Degradation & caching

- jq/git/gh/free missing, or not a repo → the dependent segment(s) are omitted.
- PR and web caches are file-based in `/tmp`, written atomically (temp + `mv`),
  refreshed in a background subshell so the status line never blocks.
- `NO_COLOR`/`TERM=dumb` → all ANSI codes become empty strings.

---

## 7. Hooks — exhaustive per-hook spec

> Convention below: **Event / Matcher**, **Trigger**, **Mode** (BLOCK or
> ADVISORY), **Env vars (default)**, **Message gist**. All block messages name
> the override env var. All hooks `exit 0` on internal error.

### 7.1 `confirm-intent.sh` — UserPromptSubmit (workflow)
- **Trigger:** any submitted prompt. Exits silently if prompt empty, or starts
  with `/` (slash-command) or `!` (bang-shell).
- **Mode:** ADVISORY → injects `additionalContext`.
- **Env:** `CLAUDE_INTENT_CONFIRM_DISABLED` (default 0).
- **Injected behaviour:** Before executing, restate the request in 1–2 terse
  lines; do not start yet. If >1 plausible interpretation, ask via
  `AskUserQuestion` or focused follow-ups — never assume. For non-trivial /
  multi-step asks: break into `TaskCreate` items ordered by priority
  (prerequisites first, then value/impact), each tagged with complexity + time
  (S/M/L + minutes/tokens); show the list; work **one at a time**, pausing
  before each to state its estimate and get a go-ahead; at each check-in offer
  "continue one-at-a-time vs autopilot"; always pause before
  destructive/irreversible steps. A mid-queue request folds into the list and is
  re-prioritised (never interrupts in-flight work). The queue is durable across
  interruptions and `/clear` (resume, never delete unless asked). **Exception:**
  a prompt that is itself a confirmation/answer to a prior clarifying question
  proceeds without re-echoing.

### 7.2 `audit-with-rules.sh` — UserPromptSubmit (workflow)
- **Trigger:** prompt matches (case-insensitive, leading word boundary)
  `\b(audit|review|assess|evaluat|critiqu|apprais|inspect)`. Otherwise silent.
- **Mode:** ADVISORY → injects the full standards checklist as `additionalContext`.
- **Env:** `CLAUDE_AUDIT_RULES_DISABLED` (default 0).
- **Injected checklist (report read-only as `file:line` + rule + fix; skip
  checks that don't fit the stack):** debug code in app code; `components/*.tsx`
  without a co-located test; untracked `TODO/FIXME/HACK/XXX` lacking `(owner,
  date)`; skipped tests without an expiry marker; dead/commented code + unused
  imports/vars + heavy duplication; and (web/HTML only, never React Native) the
  a11y/SEO/semantic-nesting rules.

### 7.3 `stack-lint.sh` — PostToolUse · Edit|Write|MultiEdit (workflow)
- **Trigger:** reads `.tool_input.file_path`; exits if empty or file missing;
  skips generated/vendored paths
  (`node_modules/dist/build/.next/.expo/vendor/*.generated.*/*.min.js`).
- **Mode:** ADVISORY (never blocks). 0 findings → silent.
- **Env:** `CLAUDE_STACK_LINT_DISABLED` (0), `CLAUDE_STACK_LINT_MAX` (5),
  `CLAUDE_STACK_LINT_TRIAGE` (1).
- **Linter cascade per language** (project linter → global linter → in-house
  heuristic floor):

  | Lang | Ext | Primary | Fallback | Heuristic floor |
  |---|---|---|---|---|
  | JS/TS | ts,tsx,js,jsx,mjs,cjs | eslint (project→global) | — | `console.log/debug`, `debugger` |
  | Python | py | ruff | flake8 | `breakpoint()`, `pdb.set_trace()`, bare `except:` |
  | Go | go | golangci-lint | `go vet` | `fmt.Print*` |
  | Ruby | rb | rubocop | — | `binding.pry`, `byebug`, `puts` |
  | Shell | sh,bash | shellcheck | — | (none — too noisy) |
  | Rust | rs | (clippy too slow) | — | `dbg!`, `todo!`, `unimplemented!`, `println!` |

  Findings formatted `L<line> <rule> — <msg>`, capped 40 collected.
- **Haiku triage:** when `count > MAX` and triage enabled and `claude` available,
  call `claude -p "<top-3 prompt>" --model haiku` (timeout 25s) **with this
  project's own prompt hooks suppressed** (`CLAUDE_INTENT_CONFIRM_DISABLED=1
  CLAUDE_AUDIT_RULES_DISABLED=1 CLAUDE_STACK_LINT_DISABLED=1`) to pick the top 3;
  on any failure fall back to raw findings (cap 5). Final hard cap 10.
- **Message gist:** `🔎 Stack-lint — advisory (not blocking), <file>:` + bullets
  + `Silence: CLAUDE_STACK_LINT_DISABLED=1.`

### 7.4 `quality-guard.sh` — PreToolUse · Edit|Write|MultiEdit (quality-guards)
- **Mode:** BLOCK (deny). Four independent checks:
  1. **Debug code** (introduce-only; app code only — excludes
     `*.test.*/*.spec.*/__tests__/scripts/tools/bin`, only `.ts/.tsx/.js/.jsx/.mjs/.cjs`):
     blocks `console.log(`, `console.debug(`, `debugger`, global `alert(`
     (negative lookbehind excludes `X.alert(`). `console.warn/error` allowed.
     Env `CLAUDE_DEBUG_GUARD_DISABLED` (0).
  2. **TDD / component test-first** (file-level): any `*/components/*.tsx`
     (new or existing) with no sibling test
     (`__tests__/<base>.test.tsx`, `<base>.test.tsx`, `__tests__/<base>.test.ts`)
     is blocked. Env `CLAUDE_TDD_GUARD_DISABLED` (0).
  3. **Untracked TODO** (introduce-only; skips markdown): a comment-marker
     `TODO/FIXME/HACK/XXX` without an `(owner, date)`-style `(...)` tag is
     blocked. Env `CLAUDE_TODO_GUARD_DISABLED` (0).
  4. **Skipped test without expiry** (introduce-only; test files only):
     `.skip(`/`xit(`/`xdescribe(`/`t.Skip(` without an expiry marker
     (`expires|expire|YYYY-MM-DD`) is blocked. Env `CLAUDE_SKIP_GUARD_DISABLED` (0).

### 7.5 `deadcode.sh` — pre (PreToolUse) + post (PostToolUse) · Edit|Write|MultiEdit (dead-code)
- **Mode arg** `$1` = `pre` or `post` (default post). Global skip: empty path,
  test/generated/vendored, non-source (`.ts/.tsx/.js/.jsx/.mjs/.cjs/.go/.py/.rb`).
- **Env:** `CLAUDE_DEADCODE_DISABLED` (0), `CLAUDE_DEADCODE_MIN_LOC` (150).
- **pre (BLOCK):** denies an edit that introduces a **commented-out code block** —
  a run of ≥4 consecutive comment lines whose bodies look like code
  (`//`/`#`/`*`/`--` prefix; body ends `;{},` or matches `=>`/a
  `const|let|var|function|func|def|return|import|export|class|if|for|while` lead).
- **post (threshold-gated):** silent under `CLAUDE_DEADCODE_MIN_LOC` (default 150).
  On substantial files: (a) **tool-confirmed** unused imports/vars via the
  project's ESLint (`timeout 15 npx --no-install eslint --format json`, filtered
  to `no-unused-vars|unused-imports`, ≤5) → **BLOCK** (`decision:block`); (b)
  heuristic commented-out blocks and (c) ≥5 duplicate substantial lines →
  ADVISORY nudge (`🧹 Maintainability`).

### 7.6 `web-standards-guard.sh` — PreToolUse · Edit|Write|MultiEdit (web-standards)
- **Trigger:** inspects only introduced text, for files
  `.html/.htm/.jsx/.tsx/.vue/.svelte/.astro`. **React Native is excluded** by
  matching **lowercase** tags only (`<Image>/<View>/<Text>` never match).
- **Mode:** BLOCK (deny) — egregious, high-confidence errors only:
  - `<img>` with no `alt` (allows `alt=""`, `aria-hidden="true"`,
    `role="presentation"`, JSX spreads).
  - Nested interactive controls (`<a>…<a>`, `<button>…<button>`).
  - Full `<html>` doc missing `lang`, or missing non-empty `<title>`, or missing
    `<meta name="description">` (doc-level checks gate on `<html>` so
    fragments/components are never flagged).
  - 2+ `<h1>` in one edit.
  - Clickable `<div>`/`<span>` with `onClick` but no `role`.
- **Env:** `CLAUDE_WEB_GUARD_DISABLED` (0).

### 7.7 `web-standards-nudge.sh` — PostToolUse · Edit|Write|MultiEdit (web-standards)
- **Trigger:** `.html/.htm` always; `.jsx/.tsx/.vue/.svelte/.astro` only when the
  file actually contains lowercase DOM tags (React Native skipped).
- **Mode:** ADVISORY whole-file backstop for the same doc-level SEO/a11y issues
  as the guard. `🌐 Web standards nudge for <file>:` + bullets.
- **Env:** `CLAUDE_WEB_NUDGE_DISABLED` (0).

### 7.8 `lib/web-standards-checks.sh` — shared library
- Exposes `ws_doc_findings <flat_content>` returning `\n  • <finding>` bullets:
  full `<html>` doc missing `lang`; missing non-empty `<title>`; missing
  `<meta name="description">`; >1 `<h1>`; clickable `<div>`/`<span>` with
  `onClick` but no `role`. Used by the guard, the nudge, and the status-bar
  `Web:` segment.

### 7.9 `pre-edit-guards.sh` — PreToolUse · Edit|Write|MultiEdit (quality-guards)
Two inline guards, first deny wins:
- **docs-bloat-guard:** caps the context-loaded docs only — `AGENTS.md`,
  `CLAUDE.md`, `MEMORY.md`. Env caps `CLAUDE_DOC_CAP_AGENTS` (120),
  `CLAUDE_DOC_CAP_CLAUDE` (100), `CLAUDE_DOC_CAP_MEMORY` (200). Blocks a write
  that would leave LOC ≥ cap (a write that shrinks under cap is allowed).
- **bloat-guard:** all source files except `*.md/*.markdown/*.mdx`, lockfiles,
  SVG/JSON, and generated/vendored dirs. Env `CLAUDE_BLOAT_THRESHOLD` (500 LOC);
  blocks editing a file already over threshold (decompose first).

### 7.10 `pre-bash-guards.sh` — PreToolUse · Bash (quality-guards)
Quote-aware command splitting on `;`/`|`/`||`/`&&`; two guards:
- **search-noise-guard:** `grep -r/-R` without `--exclude-dir`/`--exclude` (and
  not already targeting a generated dir) → rewrite suggestion; `find .`/`find
  <path>` without `-prune`/`-not -path`/`-maxdepth` → rewrite suggestion. `rg`
  is allowed (honours `.gitignore`).
- **bash-quiet-guard** (each rule independent): bare `git log` (no
  `--oneline/--format/--pretty/--stat/--name-only/--shortstat/-p/-N`);
  `npm install` without `--silent/--quiet/--no-progress/-s`; `pnpm` install/add
  without `--silent/--reporter=silent|append-only`; `yarn` install/add/upgrade
  without `--silent/--no-progress/-s`; `ls -l`/`ls -la`; `gh api` without `--jq`;
  `gh pr view` without `--json/--jq`; `gh pr|run|issue list` without
  `--limit/-L`; `gh run view` without `--json/--jq/--log-failed`; `docker logs`
  without `--tail/-n/--since`; `tree` without `-L/-d/--filelimit`.

### 7.11 `pre-read-guards.sh` — PreToolUse · Read (quality-guards)
Two guards:
- **big-read-guard:** blocks unpaginated Read of a text file over
  `CLAUDE_BIG_READ_THRESHOLD` (2000 LOC). Binary types (`png/jpg/.../woff*`) and
  `.ipynb` skipped; a Read with `offset` or `limit` bypasses the check.
- **re-read-guard:** blocks reading a file already fully read
  ≥ `CLAUDE_REREAD_THRESHOLD` (3) times this session without an intervening edit
  (suggest `grep -n` or `{offset,limit}`). Backed by `re-read-track.sh` +
  `/tmp/claude-reads-<session_id>.txt`.

### 7.12 `re-read-track.sh` — PostToolUse · Read|Edit|Write|MultiEdit (session-cost)
Non-blocking tracker: on a successful **Read** (without `offset`/`limit`), append
`file_path` to `/tmp/claude-reads-<session_id>.txt`; on a successful
**Edit/Write/MultiEdit**, remove all prior reads of that path (contents changed →
re-reads legitimate). Logs older than 24h are reaped by `session-summary.sh`.

### 7.13 `subagent-cost-guard.sh` — PreToolUse · Agent (session-cost)
- **Mode:** BLOCK. Denies a subagent spawn only when **all** hold: the
  `subagent_type` is the generic `Explore`/`general-purpose` (specialised agents
  exempt); the `prompt` is shorter than `CLAUDE_SUBAGENT_MIN_PROMPT` (300 chars);
  and the prompt lacks multi-step markers (`across|multiple|each|every|all
  the/of|cross-file|several|throughout|audit|survey|map|catalog|trace|follow|chain|graph`).
  Rationale: subagents cost ~2–5k tokens of system-prompt load; single lookups
  are cheaper done directly.

### 7.14 `session-summary.sh` — Stop (session-cost)
Non-blocking. Aggregates the transcript and prints a one-line
`📊 session:` summary (turns; in/out tokens; cache read/write + hit %; top-5
tool-result bytes; biggest read resolved to its path; top tool counts). Appends a
per-session entry to `~/.claude/session-stats.jsonl` with **last-wins dedupe by
`session_id`** and **rotation** keeping the newest `CLAUDE_SESSION_STATS_ROTATE`
(1000) entries. Also reaps `/tmp/claude-reads-*.txt` older than 24h.

### 7.15 `pre-compact-reminder.sh` — PreCompact (session-cost)
Advisory; fires only on **auto** compaction (skips manual `/compact` via the
`.trigger` field). Reminds: before older turns are summarised, save load-bearing
state to memory (open PR numbers, in-flight decisions, named flags/dates,
unresolved blockers).

### 7.16 Env var quick-reference (all hooks)

| Env var | Default | Effect |
|---|---|---|
| `CLAUDE_INTENT_CONFIRM_DISABLED` | 0 | disable confirm-intent |
| `CLAUDE_AUDIT_RULES_DISABLED` | 0 | disable audit checklist |
| `CLAUDE_STACK_LINT_DISABLED` | 0 | disable stack-lint |
| `CLAUDE_STACK_LINT_MAX` | 5 | findings before Haiku triage |
| `CLAUDE_STACK_LINT_TRIAGE` | 1 | 0 = never call Haiku |
| `CLAUDE_DEBUG_GUARD_DISABLED` | 0 | disable debug-code block |
| `CLAUDE_TDD_GUARD_DISABLED` | 0 | disable component test-first |
| `CLAUDE_TODO_GUARD_DISABLED` | 0 | disable TODO-tag rule |
| `CLAUDE_SKIP_GUARD_DISABLED` | 0 | disable skip-expiry rule |
| `CLAUDE_DEADCODE_DISABLED` | 0 | disable dead-code guard |
| `CLAUDE_DEADCODE_MIN_LOC` | 150 | post-mode LOC floor |
| `CLAUDE_WEB_GUARD_DISABLED` | 0 | disable web block |
| `CLAUDE_WEB_NUDGE_DISABLED` | 0 | disable web nudge |
| `CLAUDE_DOC_CAP_AGENTS` | 120 | AGENTS.md LOC cap |
| `CLAUDE_DOC_CAP_CLAUDE` | 100 | CLAUDE.md LOC cap |
| `CLAUDE_DOC_CAP_MEMORY` | 200 | MEMORY.md LOC cap |
| `CLAUDE_BLOAT_THRESHOLD` | 500 | source-file LOC cap |
| `CLAUDE_BIG_READ_THRESHOLD` | 2000 | unpaginated Read LOC cap |
| `CLAUDE_REREAD_THRESHOLD` | 3 | re-reads before block |
| `CLAUDE_SUBAGENT_MIN_PROMPT` | 300 | min subagent prompt chars |
| `CLAUDE_SESSION_STATS_ROTATE` | 1000 | session-stats entries kept |
| `COMMIT_BLOAT_OVERRIDE` / `COMMIT_BLOAT_THRESHOLD` | — | per-commit bloat override |

**Doctrine:** when a guard denies a legitimately-required action, **raise the
threshold via its env var — never disable the hook.**

---

## 8. Skills

Each skill is a directory under `claude/skills/<name>/` containing `SKILL.md`
with YAML frontmatter (`name`, `description` — third person, ≤1024 chars, whose
second sentence begins "Use when …" listing triggers) and a short body (<100
lines).

- **`caveman`** — ultra-terse communication mode (~75% fewer tokens). Drop
  articles/filler/pleasantries/hedging; fragments OK; abbreviate (DB, auth,
  config…); arrows for causality; keep technical terms, code, and error quotes
  exact. **Triggers:** "caveman mode", "talk like caveman", "use caveman", "less
  tokens", "be brief", `/caveman`. Persists until "stop caveman"/"normal mode".
  Temporarily relax for security warnings, irreversible-action confirmations, and
  multi-step sequences where terseness risks misreading.
- **`grill-me`** — relentless interview to stress-test a plan/design: one
  question at a time, recommend an answer each time, resolve each branch of the
  decision tree; explore the codebase instead of asking when it can answer.
  **Triggers:** "grill me", wanting to stress-test a plan.
- **`write-a-skill`** — authoring guide: gather requirements → draft
  `SKILL.md` (<100 lines) + optional `REFERENCE.md`/`EXAMPLES.md`/`scripts/` →
  review. Description must include "Use when …" triggers; references one level
  deep; concrete examples; no time-sensitive info. **Triggers:** create/write/
  build a new skill.

---

## 9. Global instructions (`claude/CLAUDE.md`)

The installed `CLAUDE.md` documents the behaviours the hooks enforce, so the
model and the hooks agree. Sections:

1. **Caveman mode default** — activate caveman terse style at the start of every
   conversation; persist; disable only on "stop caveman"/"normal mode".
2. **Confirm intent before executing** — describes the `confirm-intent.sh`
   workflow (restate → tasks → per-task pacing/autopilot → durable queue).
3. **Project audits / reviews** — describes `audit-with-rules.sh` and its
   checklist; findings reported read-only as `file:line` + rule + fix.
4. **Stack-aware lint-on-edit (advisory)** — describes `stack-lint.sh`, the
   local-first cascade, and the Haiku-triage budget.
5. **Hook denies** — the doctrine: raise the threshold env var, don't disable.
6. **Quality gates (blocking)** — `quality-guard.sh` + `deadcode.sh` behaviour.
7. **Web quality standards** — the nesting/a11y/SEO/Lighthouse rules and that
   `web-standards-guard.sh` blocks while `web-standards-nudge.sh` nudges; both
   skip React Native; Lighthouse runs in CI, never per-edit.

Keep this file **under its own 100-line cap** (it is policed by docs-bloat-guard).

---

## 10. Installer (`install.sh`)

Single, component-aware entry point. Modes via `$1`: (none)=install,
`--status|status`, `--update|update`, `-h|--help`.

**Bootstrap:** require `git` and `jq` (die otherwise). When run via
`curl | bash`, clone `CSB_REPO_URL`
(default `https://github.com/andrewstanbury/claude-statusbar.git`) into
`CSB_CACHE` (default `~/.cache/claude-statusbar`); when run from a local clone in
`--update`, `git pull --ff-only -q` first. Source `claude/components.sh`
(die if not found). Config dir = `CLAUDE_CONFIG_DIR` (default `~/.claude`).

**Selection:**
- `--update` with an existing state file → re-apply the previously selected set.
- Interactive (TTY): prompt `Install ALL components (recommended)? [Y/n] `; on `n`
  loop each component with `  • <label>? [Y/n] ` (anything but n/N selects it).
- No TTY (CI) → select all. Die if nothing selected.

**Symlinking** (`link <src> <dest>`): create parent dirs; if dest is already the
right symlink, no-op; if it's a different symlink, replace; if it's a real file,
move to `<dest>.bak` with a warning; then `ln -s`. Make `.sh`/`lib/*` files
executable. Map `claude/<path>` → `~/.claude/<path>` (strip the leading
`claude/`; `status.sh` → `~/.claude/status.sh`). Warn (don't die) on a path
missing in the repo. Print `  ✓ linked: <label>`.

**Settings composition** (rebuilt every run, never merged incrementally):
1. BASE = `claude/settings.json` with `statusLine` and `hooks` keys removed.
2. STATUSLINE = the `statusLine` block **iff** `statusbar` was selected.
3. HOOKS = parse the `COMPONENT_HOOKS` specs of all selected components
   (`EVENT::MATCHER::SCRIPT::TIMEOUT`) and reduce them with `jq` into the nested
   `{ EVENT: [ {matcher?, hooks:[{type,command,timeout}]} ] }` structure, with
   `command` = `bash $HOME/.claude/hooks/<script+args>`.
4. Merge `BASE + STATUSLINE + {hooks}` with `jq -n`; pretty-print to
   `~/.claude/settings.json`. If a pre-existing real `settings.json` is present
   on first install (no state file yet), back it up to `settings.json.bak` first;
   if it was an old-style symlink, remove it. Print
   `  ✓ composed settings.json (N components)`.

**Versioning:** `comp_version(id)` = `git log -1 --format='%h %cs' -- <paths>`
(short hash + ISO date of the last commit touching any of the component's paths).

**State file** `~/.claude/.claude-statusbar.json`:
```json
{ "components": { "statusbar": "<hash> <date>", "workflow": "<hash> <date>", … } }
```
Written after install with each selected component's current version.

**`--status`:** require the state file (else die "not installed"); print a table
`COMPONENT  INSTALLED  LATEST  STATUS`, marking `↑ update available` when the
installed version ≠ the current git version.

**`--update`:** re-apply the saved selection at latest versions (after a
`git pull --ff-only` when local), recompose settings, rewrite state.

**Closing message:** `Done. Restart Claude Code (or run /config) to load.` plus a
one-line hint for `--status` / `--update` / `uninstall.sh`.

**`claude/install.sh`** is a deprecated shim that simply forwards to the root
`install.sh` (kept for older instructions/links).

---

## 11. Uninstaller (`uninstall.sh`)

- Walk the specific paths the installer creates — `~/.claude/status.sh`,
  `~/.claude/CLAUDE.md`, `~/.claude/hooks/*.sh`, `~/.claude/hooks/lib/*.sh`,
  `~/.claude/skills/*` — and remove **only symlinks whose target contains
  `claude-statusbar`**. Count and report.
- Remove an old-style `settings.json` symlink if its target is in this repo.
- Restore `settings.json`: if `settings.json.bak` exists, move it back; else if
  `settings.json` is a real (installer-composed) file, remove it. Never delete a
  user-authored settings file.
- Remove the state file `~/.claude/.claude-statusbar.json`.
- `rmdir` the now-empty `hooks/lib`, `hooks`, `skills` dirs (ignore errors).
- **Never touches** auth, memory, agents, or unrelated hooks/skills.

---

## 12. Base settings template (`claude/settings.json`)

The committed BASE (the installer strips and re-adds `statusLine`/`hooks`).
Representative shape:

```json
{
  "theme": "dark",
  "skipAutoPermissionPrompt": true,
  "includeGitInstructions": false,
  "skillListingMaxDescChars": 600,
  "fileCheckpointingEnabled": false,
  "cleanupPeriodDays": 7,
  "permissions": { "…": "…" },
  "skillOverrides": { "…": "…" }
}
```

After composition, `statusLine`:
```json
"statusLine": { "type": "command", "command": "bash $HOME/.claude/status.sh", "refreshInterval": 1 }
```
and a `hooks` object built from the selected components per §10.

---

## 13. Documentation (Diátaxis)

`docs/` follows Diátaxis. New docs go in the right bucket:

| Type | Folder | Naming | Answers |
|---|---|---|---|
| Reference | `docs/reference/` | `*.reference.md` | "what are all the options?" |
| How-to | `docs/how-to/` | `*.how-to.md` | "how do I fix/do X?" |
| Explanation | `docs/explanation/` | `*.explanation.md` | "what does it actually do & why?" |
| Agent context | repo root | `AGENTS.md` | entry point for AI agents |

- **`config.reference.md`** — every `status.sh` tunable (`PRICE_IN_PER_MTOK` 3,
  `PRICE_OUT_PER_MTOK` 15, `COST_BAR_MAX_USD` 5; alt tunings for Opus 15/75,
  Haiku 1/5), the ANSI colour roles, the manual-test env vars, and where the
  recommendation thresholds live (inline literals in the `# ── Recommendation ──`
  section).
- **`how-it-works.explanation.md`** — the per-invocation lifecycle (read stdin →
  env overrides → compute → pick advice → render), the segment breakdown, the
  scored advice priority, and the "why bash+jq" / "why one file" rationale.
- **`troubleshoot.how-to.md`** — symptom→fix for: status bar missing; `jq`
  missing; `free` missing on macOS; branch/PR shows `-`; Windows shell path; the
  spinner only advancing between turns; cost being an estimate; advice chip
  tuning.
- **`AGENTS.md`** — repo structure, conventions (bash+jq+awk only, single file,
  section dividers, graceful failure, no persistent state), common tasks, and
  don'ts (no deps, no real animation, no config file).
- **`README.md`** — user-facing install/update/uninstall + requirements table.

---

## 14. Acceptance criteria

The recreation is complete when:

- [ ] `bash status.sh < sample.json` renders the segments of §6 in order, and
      degrades cleanly with `NO_COLOR=1`, outside a git repo, and without
      `gh`/`free`.
- [ ] `bash install.sh` (TTY) offers "ALL (recommended)?" then per-component
      selection; non-TTY installs all; both compose a valid `settings.json` and
      write `~/.claude/.claude-statusbar.json`.
- [ ] `install.sh --status` prints installed-vs-latest and flags updates;
      `--update` re-applies the saved selection at latest versions.
- [ ] `uninstall.sh` removes only this project's symlinks, restores/removes
      `settings.json` correctly, and leaves auth/memory/unrelated files untouched.
- [ ] Every hook in §7 binds to the correct event/matcher, blocks-vs-advises as
      specified, honours its override env var(s), and `exit 0`s on error.
- [ ] `quality-guard` / `deadcode` / `web-standards-guard` block their target
      anti-patterns; `stack-lint` / nudges / session-summary never block.
- [ ] Each skill's `SKILL.md` is <100 lines with a triggers-bearing description.
- [ ] `CLAUDE.md` stays under its 100-line cap and matches the hook behaviour.
- [ ] Docs exist in the correct Diátaxis buckets.

---

## Appendix A — Build playbook (ordered prompts)

Paste these into Claude **one at a time**, verifying each before moving on. Each
prompt references the section above that defines its contract.

**Phase 0 — scaffold**
1. "Create the repo skeleton from §2: empty `status.sh`, `install.sh`,
   `uninstall.sh`, `claude/{CLAUDE.md,components.sh,install.sh,settings.json}`,
   `claude/hooks/` (+`lib/`), `claude/skills/`, `docs/` Diátaxis dirs, plus
   `README.md`, `AGENTS.md`, `LICENSE`, `.gitignore`. The `.gitignore` must
   ignore local-only agent dirs, caches, and OS cruft."

**Phase 1 — status bar (independently runnable)**
2. "Implement `status.sh` to the §6 spec: stdin JSON parse (single `jq`), env
   overrides, context-max derivation, the tunables block (§6.2), helper
   functions (§6.3), and the eight segments in order (§6.4) with the graceful
   degradation and `/tmp` caching of §6.5. Honour `NO_COLOR`/`TERM=dumb`."
3. "Write `docs/reference/config.reference.md`,
   `docs/explanation/how-it-works.explanation.md`, and
   `docs/how-to/troubleshoot.how-to.md` per §13, and `docs/README.md` indexing
   them."

**Phase 2 — shared web-standards library**
4. "Implement `claude/hooks/lib/web-standards-checks.sh` exposing
   `ws_doc_findings` per §7.8 (used by guard, nudge, and the status bar)."

**Phase 3 — hooks (each reads stdin JSON, emits the §3 decision shapes)**
5. "Implement the workflow hooks: `confirm-intent.sh` (§7.1), `audit-with-rules.sh`
   (§7.2), `stack-lint.sh` (§7.3 — full cascade + Haiku triage)."
6. "Implement the quality guards: `quality-guard.sh` (§7.4, four checks),
   `pre-edit-guards.sh` (§7.9), `pre-bash-guards.sh` (§7.10), `pre-read-guards.sh`
   (§7.11)."
7. "Implement `deadcode.sh` with `pre`/`post` modes (§7.5)."
8. "Implement `web-standards-guard.sh` (§7.6) and `web-standards-nudge.sh` (§7.7)
   on top of the shared library."
9. "Implement the session/cost hooks: `re-read-track.sh` (§7.12),
   `subagent-cost-guard.sh` (§7.13), `session-summary.sh` (§7.14),
   `pre-compact-reminder.sh` (§7.15). Verify all env defaults match §7.16."

**Phase 4 — skills & global instructions**
10. "Create the three skills (§8) and `claude/CLAUDE.md` (§9), keeping CLAUDE.md
    under 100 lines and each SKILL.md under 100 lines."

**Phase 5 — install system**
11. "Write `claude/components.sh` as the §5 registry (the 10 components and the
    full hook-wiring table)."
12. "Write `claude/settings.json` as the §12 BASE template."
13. "Implement `install.sh` to §10 (modes, selection, symlinking, settings
    composition, git-derived versioning, state file) and `uninstall.sh` to §11.
    Add the `claude/install.sh` deprecation shim."

**Phase 6 — verify**
14. "Run the §14 acceptance checklist: render `status.sh` against a sample JSON
    and `NO_COLOR=1`; do a dry-run install into a temp `CLAUDE_CONFIG_DIR`;
    confirm `--status`/`--update`; confirm `uninstall.sh` removes only its own
    symlinks. Fix anything that fails."
15. "Write `README.md` (§13) with the install/update/uninstall instructions and
    the requirements table."
