# Global Instructions

## Caveman mode default

Activate the `caveman` skill behavior by default at the start of every conversation, in every project. Use ultra-terse caveman style (drop articles, filler, pleasantries; keep technical substance exact). Persist across all turns. Disable only when user says "stop caveman" or "normal mode".

## Hook denies

When a global PreToolUse hook denies a legitimately-required action, raise the threshold via the corresponding env var (`CLAUDE_BLOAT_THRESHOLD`, `CLAUDE_DOC_CAP_*`, `CLAUDE_BIG_READ_THRESHOLD`, `CLAUDE_REREAD_THRESHOLD`, `CLAUDE_SUBAGENT_MIN_PROMPT`, `CLAUDE_SESSION_STATS_ROTATE`, `CLAUDE_WEB_GUARD_DISABLED`, `CLAUDE_DEBUG_GUARD_DISABLED`, `CLAUDE_TDD_GUARD_DISABLED`, `CLAUDE_TODO_GUARD_DISABLED`, `CLAUDE_SKIP_GUARD_DISABLED`) rather than disabling the hook. Per-commit override for a project's pre-commit bloat guard: `COMMIT_BLOAT_OVERRIDE=1` or `COMMIT_BLOAT_THRESHOLD=<n>`. Reference: [[feedback-hook-denies]].

## Quality gates (blocking)

`quality-guard.sh` (PreToolUse) hard-blocks: debug code (`console.log`/`console.debug`/`debugger`/global `alert(`) in app code; **any** `/components/*.tsx` (new OR existing) with no co-located test (test-first); an untracked `TODO/FIXME/HACK/XXX` (needs an `(owner, date)` tag); a skipped test (`.skip`/`xit`/`xdescribe`/`t.Skip`) with no expiry marker. The debug/TODO/skip checks are introduce-only (inspect just the edit's new content); the test check is file-level (blocks until a sibling test exists). Each has the override env var listed above. Reference: [[feedback-quality-gates]].

## Web quality standards

Applies to web (HTML/DOM) projects only — NOT React Native (`<View>`/`<Text>`). Keep markup semantic, valid, accessible, and SEO-sound as you write:
- **Valid nesting:** no block elements inside `<p>`; never nest `<a>`/`<button>`; `<ul>`/`<ol>` children are `<li>`; `<tr>` holds `<td>`/`<th>`.
- **A11y:** every `<img>` has `alt` (decorative → `alt=""`); inputs have a `<label>`/`aria-label`; interactivity uses `<button>`/`<a>`, not click handlers on `<div>`/`<span>`.
- **SEO:** one `<h1>` per page + ordered headings; `<html lang>`; a `<title>` and `<meta name="description">`; canonical + Open Graph where relevant.
- **Perf/Lighthouse:** lazy-load below-the-fold media, set explicit width/height (avoid CLS), prefer modern formats; target Lighthouse perf/a11y/SEO/best-practices ≥ 90. Run Lighthouse / `@lhci/cli` in CI, never per-edit.

Enforced automatically: `web-standards-guard.sh` (PreToolUse) **blocks** — `<img>` without alt, nested interactive controls, full-HTML-doc missing `lang`/`<title>`/`<meta description>`, 2+ `<h1>` in one edit, and clickable `<div>`/`<span>` without `role`. `web-standards-nudge.sh` (PostToolUse) remains as a whole-file backstop for the same SEO/a11y issues on edits to existing deficient docs. Both skip React Native via case-sensitive lowercase-tag matching; doc-level blocks gate on `<html>` so fragments/components are never flagged. Overrides: `CLAUDE_WEB_GUARD_DISABLED=1`, `CLAUDE_WEB_NUDGE_DISABLED=1`. Reference: [[feedback-web-standards]].
