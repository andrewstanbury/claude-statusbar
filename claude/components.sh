#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Component registry — the single source of truth for the installer + updater.
# ─────────────────────────────────────────────────────────────────────────────
# Sourced (never executed) by install.sh and the update/status path so the two
# can't drift. Defines, per optional component:
#   • a human label (shown in the interactive menu)
#   • the repo-relative paths it symlinks into ~/.claude
#   • the settings.json contributions (statusLine and/or hook entries)
#
# Granularity = "medium": the status bar, the global instructions, five hook
# groups, and each skill. Default install = ALL of these (recommended).
#
# Hook spec line format (one per line in COMPONENT_HOOKS):
#   EVENT::MATCHER::SCRIPT_AND_ARGS::TIMEOUT
# MATCHER is blank for events that take none (UserPromptSubmit/Stop/PreCompact).
# SCRIPT_AND_ARGS is relative to ~/.claude/hooks (may carry an arg, e.g.
# "deadcode.sh post"); the installer renders it as `bash $HOME/.claude/hooks/<it>`.
# "::" is the field delimiter so a MATCHER like "Edit|Write|MultiEdit" is safe.
# ─────────────────────────────────────────────────────────────────────────────

# Install order + menu order (prerequisites/most-valuable first).
COMPONENT_ORDER=(
  statusbar
  instructions
  workflow
  quality-guards
  web-standards
  dead-code
  session-cost
  skill-caveman
  skill-grill-me
  skill-write-a-skill
)

declare -A COMPONENT_LABEL=(
  [statusbar]="Status bar (status.sh + statusLine)"
  [instructions]="Global instructions (CLAUDE.md)"
  [workflow]="Workflow hooks — audit-with-rules, stack-lint (confirm-intent deprecated: see github.com/andrewstanbury/claude-task-queue)"
  [quality-guards]="Quality guards — quality-guard + pre-edit/bash/read guards"
  [web-standards]="Web standards — guard (blocks) + nudge"
  [dead-code]="Dead-code guard (pre block + post recommend)"
  [session-cost]="Session/cost — summary, subagent cost, compact reminder, re-read"
  [skill-caveman]="Skill: caveman"
  [skill-grill-me]="Skill: grill-me"
  [skill-write-a-skill]="Skill: write-a-skill"
)

# Repo-relative paths to symlink into ~/.claude (space-separated).
declare -A COMPONENT_PATHS=(
  [statusbar]="status.sh claude/hooks/statusbar-advice.sh"
  [instructions]="claude/CLAUDE.md"
  [workflow]="claude/hooks/audit-with-rules.sh claude/hooks/stack-lint.sh"
  [quality-guards]="claude/hooks/quality-guard.sh claude/hooks/pre-edit-guards.sh claude/hooks/pre-bash-guards.sh claude/hooks/pre-read-guards.sh"
  [web-standards]="claude/hooks/web-standards-guard.sh claude/hooks/web-standards-nudge.sh claude/hooks/lib/web-standards-checks.sh"
  [dead-code]="claude/hooks/deadcode.sh"
  [session-cost]="claude/hooks/session-summary.sh claude/hooks/subagent-cost-guard.sh claude/hooks/pre-compact-reminder.sh claude/hooks/re-read-track.sh"
  [skill-caveman]="claude/skills/caveman"
  [skill-grill-me]="claude/skills/grill-me"
  [skill-write-a-skill]="claude/skills/write-a-skill"
)

# settings.json hook entries contributed by each component (blank = none).
declare -A COMPONENT_HOOKS=(
  [statusbar]="Stop::::statusbar-advice.sh::5"
  [workflow]="UserPromptSubmit::::audit-with-rules.sh::5
PostToolUse::Edit|Write|MultiEdit::stack-lint.sh::45"
  [quality-guards]="PreToolUse::Edit|Write|MultiEdit::quality-guard.sh::5
PreToolUse::Edit|Write|MultiEdit::pre-edit-guards.sh::5
PreToolUse::Bash::pre-bash-guards.sh::5
PreToolUse::Read::pre-read-guards.sh::5"
  [web-standards]="PreToolUse::Edit|Write|MultiEdit::web-standards-guard.sh::5
PostToolUse::Edit|Write|MultiEdit::web-standards-nudge.sh::5"
  [dead-code]="PreToolUse::Edit|Write|MultiEdit::deadcode.sh pre::5
PostToolUse::Edit|Write|MultiEdit::deadcode.sh post::20"
  [session-cost]="Stop::::session-summary.sh::10
PreToolUse::Agent::subagent-cost-guard.sh::5
PreCompact::::pre-compact-reminder.sh::5
PostToolUse::Read|Edit|Write|MultiEdit::re-read-track.sh::5"
)

# Components that contribute the statusLine block (space-separated).
COMPONENT_STATUSLINE="statusbar"
