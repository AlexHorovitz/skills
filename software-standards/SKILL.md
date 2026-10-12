---
name: software-standards
description: Adversarial comparison of one or more codebases against eight engineering dimensions, ending in a Hard Truth. Use only when the user explicitly invokes /software-standards for a one-off evaluation. Do not use it for continuous review of a codebase the team owns; that is /codebase-skeptic. Do not start it from an ordinary feature task.
license: See /LICENSE
metadata:
  version: "1.2.0"
disable-model-invocation: true
---

# Software Standards Skill

<!-- License: See /LICENSE -->

**Version:** 1.2.0

## When not to use

`software-standards` and `codebase-skeptic` are mutually exclusive. Do not chain them.

- Owned, active codebase, repeated cadence: `/codebase-skeptic`.
- A pull request: `/code-reviewer`.

If the user points this skill at their own active codebase, ask whether they meant codebase-skeptic and wait for an explicit yes. Do not start either audit while you wait.

This skill is user-invoked. A milestone routine may propose it. Nothing may start it by registering an agent that triggers itself.

## Interface

| | |
|---|---|
| **Input** | One codebase (adversarial single) or two or more (comparative) |
| **Output** | `.ssd/audits/YYYY-MM-DD-<scope>/standards-report.md` |
| **Consumed by** | `architect`, as input to a later human decision |
| **SSD phase** | `/ssd audit` only, and only after the user asks |

**Required output frontmatter:**

```yaml
---
skill: software-standards
version: 1.2.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <codebases>
consumed_by: [architect]
mode: comparative
winner: n/a
hard_truth: "<one sentence>"
reviewed_snapshot: <sha>
execution_method: explicit-invocation
---
```

`mode` is `comparative` or `adversarial_single`. `winner` is a codebase name only in comparative mode; otherwise `n/a`.

## The report

Score eight dimensions, 1–5, with evidence next to the score. The dimension checklists are in [references/archive-v2.14.md](references/archive-v2.14.md). Load that file when you assign scores. The dimensions are:

1. Architectural integrity
2. Code quality and craftsmanship
3. Efficiency and performance
4. Maintainability and evolvability
5. Error handling and resilience
6. Security posture
7. Operational readiness
8. Documentation

Comparative mode names a winner only when the scores and the evidence agree. A tie is allowed. Say so.

## The Hard Truth

Every report includes a `## The Hard Truth` section: one paragraph on the thing the reader most wants not to hear, repeated as `hard_truth` in the frontmatter. Omitting it means the report is not done.

## Do not

- Start from a feature implementation or a diff review.
- Present the scores as a ship decision.
- Hide a missing measurement inside a high score. Use `NOT_RUN` in the evidence cell.

## Reference

Load [references/archive-v2.14.md](references/archive-v2.14.md) for the v2.14 per-dimension questions, the comparative summary template, and the evidence-log appendix.

## Changelog

- **1.2.0** (2026-10-05) — Entrypoint compacted. Invocation is explicit and mutually exclusive with codebase-skeptic. The v2.14 text is in the archive.
