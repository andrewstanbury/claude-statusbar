---
name: write-a-skill
description: Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when user wants to create, write, or build a new skill.
---

# Writing Skills

## Process

1. **Gather requirements** — task/domain, specific use cases, scripts vs instructions only, reference materials.
2. **Draft** — `SKILL.md` (concise); split into `REFERENCE.md`/`EXAMPLES.md` if >100 lines; add `scripts/` if deterministic ops needed.
3. **Review with user** — coverage, gaps, detail level.

## Structure

```
skill-name/
├── SKILL.md         # required, <100 lines
├── REFERENCE.md     # if needed
├── EXAMPLES.md      # if needed
└── scripts/         # deterministic utilities
```

## Description field

The description is the ONLY thing the agent sees when deciding which skill to load. Max 1024 chars, third person.

- First sentence: what it does
- Second sentence: "Use when [specific triggers — keywords, contexts, file types]"

Good: `Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs, forms, or document extraction.`

Bad: `Helps with documents.` (no way to distinguish from siblings)

## When to add scripts

Deterministic ops (validation, formatting), repeated codegen, explicit error handling. Scripts save tokens vs generated code.

## When to split files

`SKILL.md` >100 lines, distinct domains (finance vs sales), rarely-needed advanced features.

## Checklist

- [ ] Description includes triggers ("Use when...")
- [ ] SKILL.md under 100 lines
- [ ] No time-sensitive info
- [ ] Consistent terminology
- [ ] Concrete examples included
- [ ] References one level deep
