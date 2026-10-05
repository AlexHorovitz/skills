---
name: systems-designer
description: Check whether a feature is safe to run in production. Covers failure modes, observability, security, performance, deployment, and rollback. Use when the user asks for production readiness or /ssd ship needs the systems-designer artifact. Do not use for a line-by-line diff review.
license: See /LICENSE
metadata:
  version: "1.6.0"
---

# Systems Designer Skill

<!-- License: See /LICENSE -->

**Version:** 1.6.0

## Purpose

Decide whether a change is safe to operate, not merely whether it works on a laptop. Reliability, observability, security, performance, deployment, and recovery are the questions. A passing review here is evidence. It is not permission to ship.

## When to use

- Before a feature ships.
- When the user asks for a production-readiness review.
- During an incident post-mortem the user asked for.

Do not start this as a side effect of an ordinary diff review.

## Interface

| | |
|---|---|
| **Input** | `.ssd/features/<slug>/01-architect.md`, or a spec the user named |
| **Output** | `.ssd/features/<slug>/02-systems-designer.md` |
| **Consumed by** | `/ssd ship`, which reads `block_conditions_met` |
| **SSD phase** | `/ssd feature`, `/ssd ship` |

**Required output frontmatter:**

```yaml
---
skill: systems-designer
version: 1.6.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <feature-slug>
consumed_by: [ssd]
machine_checked:
  tests_exist: true
  indexes_declared: true
  flag_wired: true
  migration_reversible: true
block_conditions_met: false
result_status: NOT_RUN
reviewed_snapshot: <git-sha-or-dirty-snapshot>
execution_method: inline
---
```

`result_status` is `PASS`, `FAIL`, `ERROR`, or `NOT_RUN`. A missing tool is `NOT_RUN` or `ERROR`, never `PASS`. `block_conditions_met: true` is a claim you may write only after each block condition below is actually true. The orchestrator does not treat that boolean as a ship grant.

## Phase 0 — input

Read the architect spec. If it is missing, stop and say so. Do not invent the design.

## What the artifact must contain

Cover each heading. Worked examples, log snippets, load-test tables, and the long runbook template live in [references/archive-v2.14.md](references/archive-v2.14.md). Load that file when you need a template. Do not paste it into every reply.

1. **Failure modes.** For each dependency, name how it fails, what the user sees, and the timeout or fallback.
2. **Observability.** Logs carry who, what, context, and result. Errors carry context. Requests carry a trace id.
3. **Security.** Every endpoint states its auth. Secrets are not in the repo. Input is validated.
4. **Performance.** State the load you actually measured, or `NOT_RUN` with the command you did not run.
5. **Deployment safety.** Migration expands then contracts. The feature is behind a flag, off by default. Rollback does not require a heroic data repair.
6. **Operational readiness.** A runbook names symptoms, the first checks, and who is escalated to.
7. **Block conditions.** All of these must be true before `block_conditions_met` is true: tests exist and were run for this snapshot, the flag is wired, a reversible migration plan exists when schema changes, and there is no unowned single point of failure you discovered and left undocumented.

## Three-tier output

- **Machine-checkable.** The frontmatter booleans. False when you did not check.
- **Human review.** The narrative under each heading.
- **Block conditions.** The list above. Any false value means the ship handoff says not ready.

## Do not

- Rewrite the user's tests or acceptance criteria so the checklist turns green.
- Report a checklist item done because a similar system usually does it.
- Start a Feynman audit or a standards audit from this skill.

## Reference

Load [references/archive-v2.14.md](references/archive-v2.14.md) for the v2.14 checklist depth, example analyses, and the production-readiness review template.

## Changelog

- **1.6.0** (2026-10-05) — Entrypoint compacted. Optional result and snapshot fields are documented. The v2.14 text is in the archive.
