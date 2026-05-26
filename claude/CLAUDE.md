# Global Instructions

## Caveman mode default

Activate the `caveman` skill behavior by default at the start of every conversation, in every project. Use ultra-terse caveman style (drop articles, filler, pleasantries; keep technical substance exact). Persist across all turns. Disable only when user says "stop caveman" or "normal mode".

## Confirm intent before executing

`confirm-intent.sh` (UserPromptSubmit) injects a reminder on every submitted prompt: before doing anything, restate in one or two terse lines what the request is understood to be asking, and do NOT start executing yet. If the prompt has more than one plausible interpretation, present the options via `AskUserQuestion` (multiple choice) or ask focused follow-up questions — never assume on the user's behalf. Begin the work only after the user confirms. For any non-trivial / multi-step ask it also requires breaking the work into prioritized tasks via `TaskCreate`, each tagged with a complexity + estimated processing time (S/M/L + rough minutes/token size), shown for approval, then worked **one at a time** — pausing before each task to state its estimate and get a go-ahead (no back-to-back execution, so the user can stop when short on time), and always pausing before any destructive/irreversible step. Exception: a prompt that is itself a direct confirmation/answer to a prior clarifying question is treated as confirmed and proceeds without re-echoing. Skips slash-commands (`/foo`) and bang-shell (`!cmd`) lines. Override `CLAUDE_INTENT_CONFIRM_DISABLED=1`.

## Project audits / reviews

`audit-with-rules.sh` (UserPromptSubmit) fires when a prompt reads like an audit/review/assessment request (`audit`, `review`, `assess`, `evaluat*`, `critiqu*`, `apprais*`, `inspect*`). It injects the full claude-statusbar standards checklist so any audit is performed against THIS config's rules, not ad-hoc: debug code in app code; `components/*.tsx` without a co-located test; untracked `TODO/FIXME/HACK/XXX` lacking an `(owner, date)` tag; skipped tests with no expiry marker; dead/commented code + unused imports/vars + heavy duplication; and (web/HTML projects only, never React Native) the web a11y/SEO/semantic-nesting rules. Findings are reported read-only as `file:line` + rule + fix; checks that don't fit the project's stack are skipped. Complements the edit-time enforcement hooks (`quality-guard.sh`, `deadcode.sh`, `web-standards-guard.sh`). Override `CLAUDE_AUDIT_RULES_DISABLED=1`.

## Stack-aware lint-on-edit (advisory)

`stack-lint.sh` (PostToolUse · Edit|Write|MultiEdit) is the "optimize the code over time" layer: when a source file is edited it lints **just that file** for its language and surfaces improvement suggestions inline — incremental, **never a whole-project audit on open**, and it **never blocks** the edit (the hard blocks stay with `quality-guard`/`deadcode`). Local-first: detection is 100% local and costs 0 model tokens via a cascade — **project linter → global linter → in-house heuristic floor** (JS/TS→eslint, Python→ruff/flake8, Go→`go vet`/golangci-lint, Ruby→rubocop, Shell→shellcheck, Rust→heuristics since clippy is CI-grade). Only when local findings exceed `CLAUDE_STACK_LINT_MAX` (default 5) does it spend a cheap **Haiku triage** pass (`claude -p --model haiku`, run with our prompt hooks suppressed) to pick the top 3; on any failure it falls back to raw findings. 0 findings → silent. Overrides: `CLAUDE_STACK_LINT_DISABLED=1`, `CLAUDE_STACK_LINT_TRIAGE=0` (always raw), `CLAUDE_STACK_LINT_MAX=<n>`. For a full-project pass against every rule, ask for an audit (see `audit-with-rules.sh`).

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
