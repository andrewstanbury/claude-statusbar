# Global Instructions

## Caveman mode default

Activate the `caveman` skill behavior by default at the start of every conversation, in every project. Use ultra-terse caveman style (drop articles, filler, pleasantries; keep technical substance exact). Persist across all turns. Disable only when user says "stop caveman" or "normal mode".

## Confirm intent before executing

> **Deprecated 2026-05-29** in favor of [claude-task-queue](https://github.com/andrewstanbury/claude-task-queue). `confirm-intent.sh` was a per-prompt instructional hook — every prompt carried ~400 words asking Claude to restate, decompose, and pace itself. claude-task-queue replaces that pattern with a real durable orchestrator (jsonl queue, Haiku triage for auto-decomposition, pause-resumable autopilot CLI, and a PreToolUse gate that always pauses on destructive ops). Migrate: `curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-task-queue/main/install.sh | bash`, then remove the confirm-intent entry from `~/.claude/settings.json`. The hook file is kept here for backward compatibility; silence it with `CLAUDE_INTENT_CONFIRM_DISABLED=1` if you're still on the old install path.

## Project audits / reviews

`audit-with-rules.sh` (UserPromptSubmit) fires when a prompt reads like an audit/review/assessment request (`audit`, `review`, `assess`, `evaluat*`, `critiqu*`, `apprais*`, `inspect*`). It injects the full claude-statusbar standards checklist so any audit is performed against THIS config's rules, not ad-hoc: debug code in app code; `components/*.tsx` without a co-located test; untracked `TODO/FIXME/HACK/XXX` lacking an `(owner, date)` tag; skipped tests with no expiry marker; dead/commented code + unused imports/vars + heavy duplication; and (web/HTML projects only, never React Native) the web a11y/SEO/semantic-nesting rules. Findings are reported read-only as `file:line` + rule + fix; checks that don't fit the project's stack are skipped. Complements the edit-time enforcement hooks (`quality-guard.sh`, `deadcode.sh`, `web-standards-guard.sh`). Override `CLAUDE_AUDIT_RULES_DISABLED=1`.

## Stack-aware lint-on-edit (advisory)

`stack-lint.sh` (PostToolUse · Edit|Write|MultiEdit) is the "optimize the code over time" layer: when a source file is edited it lints **just that file** for its language and surfaces improvement suggestions inline — incremental, **never a whole-project audit on open**, and it **never blocks** the edit (the hard blocks stay with `quality-guard`/`deadcode`). Local-first: detection is 100% local and costs 0 model tokens via a cascade — **project linter → global linter → in-house heuristic floor** (JS/TS→eslint, Python→ruff/flake8, Go→`go vet`/golangci-lint, Ruby→rubocop, Shell→shellcheck, Rust→heuristics since clippy is CI-grade). Only when local findings exceed `CLAUDE_STACK_LINT_MAX` (default 5) does it spend a cheap **Haiku triage** pass (`claude -p --model haiku`, run with our prompt hooks suppressed) to pick the top 3; on any failure it falls back to raw findings. 0 findings → silent. Overrides: `CLAUDE_STACK_LINT_DISABLED=1`, `CLAUDE_STACK_LINT_TRIAGE=0` (always raw), `CLAUDE_STACK_LINT_MAX=<n>`. For a full-project pass against every rule, ask for an audit (see `audit-with-rules.sh`).

## Status bar advice (advisory)

`statusbar-advice.sh` (Stop) keeps the status bar's **advice slot** current: after a response it generates ONE imperative line that steers away from scope creep / over-engineering of local changes, and writes it to `~/.claude/state/statusbar-advice/<session>.txt`; `status.sh` just renders that cache (the bar never calls a model). Throttled (one cheap `claude -p --model haiku` call at most once per `CLAUDE_STATUSBAR_ADVICE_THROTTLE` seconds, default 180) and backgrounded so the Stop hook returns immediately. Recursion-safe: the nested `claude -p` runs with this hook and the other prompt hooks suppressed. When the work is appropriately focused the model replies `on track`, which clears the slot (no nag). Overrides: `CLAUDE_STATUSBAR_ADVICE_DISABLED=1` (off entirely), `CLAUDE_STATUSBAR_ADVICE_THROTTLE=<seconds>`, `CLAUDE_STATUSBAR_ADVICE_DIR=<path>` (must match `status.sh`).

## Hook denies

When a global PreToolUse hook denies a legitimately-required action, raise the threshold via the corresponding env var (`CLAUDE_BLOAT_THRESHOLD`, `CLAUDE_DOC_CAP_*`, `CLAUDE_BIG_READ_THRESHOLD`, `CLAUDE_REREAD_THRESHOLD`, `CLAUDE_SUBAGENT_MIN_PROMPT`, `CLAUDE_SESSION_STATS_ROTATE`, `CLAUDE_WEB_GUARD_DISABLED`, `CLAUDE_DEBUG_GUARD_DISABLED`, `CLAUDE_TDD_GUARD_DISABLED`, `CLAUDE_TODO_GUARD_DISABLED`, `CLAUDE_SKIP_GUARD_DISABLED`, `CLAUDE_DEADCODE_DISABLED`) rather than disabling the hook. Per-commit override for a project's pre-commit bloat guard: `COMMIT_BLOAT_OVERRIDE=1` or `COMMIT_BLOAT_THRESHOLD=<n>`. Reference: [[feedback-hook-denies]].

## Quality gates (blocking)

`quality-guard.sh` (PreToolUse) hard-blocks: debug code (`console.log`/`console.debug`/`debugger`/global `alert(`) in app code; **any** `/components/*.tsx` (new OR existing) with no co-located test (test-first); an untracked `TODO/FIXME/HACK/XXX` (needs an `(owner, date)` tag); a skipped test (`.skip`/`xit`/`xdescribe`/`t.Skip`) with no expiry marker. The debug/TODO/skip checks are introduce-only (inspect just the edit's new content); the test check is file-level (blocks until a sibling test exists). Each has the override env var listed above. Reference: [[feedback-quality-gates]].

`deadcode.sh` (one script, two modes) keeps LOC matched to real complexity: **pre** blocks introducing a commented-out code block; **post** is threshold-gated (silent under `CLAUDE_DEADCODE_MIN_LOC`, default 150 LOC) and on substantial app files runs static checks + the project's own ESLint — tool-confirmed unused imports/vars → `decision:block`, commented-out code / heavy line duplication → recommendation. Zero token cost (static + local tools). Override `CLAUDE_DEADCODE_DISABLED=1`.

## Web quality standards

Applies to web (HTML/DOM) projects only — NOT React Native (`<View>`/`<Text>`). Keep markup semantic, valid, accessible, and SEO-sound as you write:
- **Valid nesting:** no block elements inside `<p>`; never nest `<a>`/`<button>`; `<ul>`/`<ol>` children are `<li>`; `<tr>` holds `<td>`/`<th>`.
- **A11y:** every `<img>` has `alt` (decorative → `alt=""`); inputs have a `<label>`/`aria-label`; interactivity uses `<button>`/`<a>`, not click handlers on `<div>`/`<span>`.
- **SEO:** one `<h1>` per page + ordered headings; `<html lang>`; a `<title>` and `<meta name="description">`; canonical + Open Graph where relevant.
- **Perf/Lighthouse:** lazy-load below-the-fold media, set explicit width/height (avoid CLS), prefer modern formats; target Lighthouse perf/a11y/SEO/best-practices ≥ 90. Run Lighthouse / `@lhci/cli` in CI, never per-edit.

Enforced automatically: `web-standards-guard.sh` (PreToolUse) **blocks** — `<img>` without alt, nested interactive controls, full-HTML-doc missing `lang`/`<title>`/`<meta description>`, 2+ `<h1>` in one edit, and clickable `<div>`/`<span>` without `role`. `web-standards-nudge.sh` (PostToolUse) remains as a whole-file backstop for the same SEO/a11y issues on edits to existing deficient docs. Both skip React Native via case-sensitive lowercase-tag matching; doc-level blocks gate on `<html>` so fragments/components are never flagged. Overrides: `CLAUDE_WEB_GUARD_DISABLED=1`, `CLAUDE_WEB_NUDGE_DISABLED=1`. Reference: [[feedback-web-standards]].
