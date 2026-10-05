---
name: ssd-init
description: Prepare a project for SSD. Inspect the tree and present every file that would be created or edited, the storage mode, and the discovered test command before writing. Use only when the user invokes /ssd-init. Re-running is idempotent. Do not enable optional integrations unless the user agrees.
license: See /LICENSE
metadata:
  version: "1.15.0"
disable-model-invocation: true
---

# SSD Init Skill

<!-- License: See /LICENSE -->

**Version:** 1.15.0

## Purpose

First-run housekeeping for Shippable States Development. Create `.ssd/`, gitignore discipline, project-shape detection, and prerequisite checks so later `/ssd` phases have a known foundation.

**Inspect before writing.** Run `python3 methodology/ssd_cli.py setup-plan --project <root>` (library path, not a search from the project) and show the change set, the storage mode, the discovered test command, and the optional permissions. Write only after the user approves. Do not execute a discovered test command; confirmation comes first.

## When to use

Invoke only when the user types `/ssd-init` or explicitly asks to initialize SSD. Do not run it because `.ssd/` is missing during some other task; propose it and wait.

Do not use it mid-feature, and do not use it to catch an already-initialized project up. That is `/ssd upgrade`.

## Interface

| | |
|---|---|
| **Input** | Project root, plus any platform clarification the user gives |
| **Output** | `.ssd/` tree, `.gitignore` mode, `.ssd/project.yml`, `.ssd/gate.yml`, `.ssd/init-log.md` |
| **Consumed by** | Every later SSD phase |
| **Persisted artifact** | The files above. This skill does not write a numbered feature artifact, so it has no feature-schema. |

## Rules that always apply

1. **Never overwrite existing files.** If `.ssd/project.yml` exists, read it. The user edits it; you do not replace it.
2. **Never delete** existing files or directories. No `rm` of user content.
3. **Preserve** existing `CLAUDE.md`, `AGENTS.md`, a project `verify` skill, settings, git hooks, and project source. Merge only a consented block marked `<!-- ssd:managed id=... -->`.
4. **Idempotent.** A second run presents an empty or keep-only change set and appends to `.ssd/init-log.md` instead of rewriting it.
5. **Storage mode** is one of `selective` (default), `blanket`, or `private`. Detect the existing sentinel before appending another gitignore block. An explicit `gitignore_mode: private` is a user decision, not drift. Patterns come from `methodology/selective.gitignore` and `methodology/private.gitignore`. Load [references/archive-v2.14.md](references/archive-v2.14.md) when you need the exact template text.
6. **Optional integrations stay off** until the user agrees: pre-commit hook, private store, GitHub issue mirror. Refusing one leaves the project usable.
7. **Discovered test command** is a candidate for `.ssd/gate.yml` `test_command`. Show it. Do not run it as part of setup.
8. A malformed `.ssd/project.yml` is corrupt state. Ask the user to fix it. Do not treat it as a fresh project and do not auto-repair it.

## Workflow

Resolve the project root, the worktree root, and the library root separately (`python3 methodology/ssd_cli.py paths`). Do not hunt for scripts with a model.

1. Locate the project root (git toplevel, or the directory the user named).
2. Report git state. A repo with no remote still proceeds.
3. Present the change set from `setup-plan`. Stop until the user approves.
4. Create missing `.ssd/` directories only. Do not recreate files that exist.
5. Write `.ssd/README.md` from the template in the archive when it is absent.
6. Update `.gitignore` for the chosen mode, checking the sentinel first.
7. Offer, do not install, the private artifact store and the pre-commit hook. If `.git/hooks/pre-commit` already exists and is not the SSD symlink, explain coexistence and leave it.
8. Detect stack, framework, and platform. If several languages qualify and the user has not picked one, ask.
9. Write `.ssd/project.yml` and `.ssd/gate.yml` only if absent. `test_command` is commented until the user confirms a candidate. `production_runtime` defaults are in the archive.
10. Write `.ssd/current.yml` schema v2 and `.ssd/current.notes.yml` only if absent.
11. If `CLAUDE.md` or `AGENTS.md` is absent, offer the shared instruction block from `ssd-init/references/project-instructions.md`. If one exists, merge the managed block only after consent. Never replace the file.
12. Run prerequisite checks (CI, tests, flags, deploy) as a report. BLOCKER gaps are listed. MAJOR gaps are noted and do not stop `/ssd` from being proposed later.
13. Append `.ssd/init-log.md`. Recommend the next command, usually `/ssd`.

## Failure modes

| Symptom | What to do |
|---|---|
| Cannot locate a project root | Ask the user to name it. Do not create `.ssd/` in the library checkout by guessing. |
| `.gitignore` is not writable | Report it. Do not work around it. |
| `project.yml` is malformed | Stop. Do not reinitialize. |
| Several stacks, no primary | Ask. |
| Existing instructions conflict | Show the conflict. Do not overwrite. |

## Quality checklist

Project root confirmed. Change set shown before writes. `.ssd/project.yml` and `.ssd/gate.yml` present. Gitignore mode matches the user's choice. Init log appended. No existing file overwritten. No optional integration enabled silently. A second run changes nothing except a new init-log section.

## Reference

Load [references/archive-v2.14.md](references/archive-v2.14.md) for the v2.14 templates (project.yml, current.yml, init log, hook snippet) when you are about to write one of those files. Load [references/project-instructions.md](references/project-instructions.md) when installing the shared instruction block.

Init-log frontmatter example (the banner above is the version):

```yaml
---
skill: ssd-init
version: 1.15.0
produced_at: <ISO-8601>
---
```

Load [references/verify-template.md](references/verify-template.md) when offering an optional project `verify` skill. Do not overwrite an existing one.

## Changelog

- **1.15.0** (2026-10-05) — Entrypoint compacted under 400 lines. Frontmatter is first. Invocation is explicit. The v2.14 text is in `references/archive-v2.14.md`.
