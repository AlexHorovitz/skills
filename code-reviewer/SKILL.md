---
name: code-reviewer
description: Review a diff or pull request for defects, security issues, and maintainability. Use when the user asks to review a change, a PR, or specific files. Findings use BLOCKER, MAJOR, MINOR, QUESTION, SUGGESTION, or NIT. Do not use for a whole-codebase architectural audit or an epistemic claim audit.
license: See /LICENSE
metadata:
  version: "1.9.0"
---

# Code Reviewer Skill

<!-- License: See /LICENSE -->

**Version:** 1.9.0

## Purpose

Find defects in a change before they ship. Be specific and constructive. A clean review means no qualifying findings in the examined scope. It is not proof the application has no defects.

## When to use

- The user asks for a diff, PR, or file review.
- `/ssd gate` or `/ssd feature` reaches the review phase.

Do not expand an ordinary diff into a codebase-skeptic pass or a Feynman audit. Propose those only when the user is at a milestone, verify, audit, or pre-ship point, and do not start them.

## Interface

| | |
|---|---|
| **Input** | The diff or files in scope, the requirements, and test evidence. Not the coder's status narrative, on the first pass. |
| **Output** | `.ssd/features/<slug>/04-code-review.md` (round 1), `04-code-review-round-N.md`, or `iterations/<iter>/code-review/round-N.md` |
| **Consumed by** | `/ssd gate`. Blocking counts come from validated findings. A `gate_pass` boolean in this file is not the gate. |
| **You do not** | Edit source, write gate state, or touch another workstream. |

**Required output frontmatter:**

```yaml
---
skill: code-reviewer
version: 1.9.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <branch|commit-range|files>
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 0
gate_pass: false
remediation_mode: false
round: 1
closed_from_previous_round: []
reviewed_snapshot: <sha-or-dirty-id>
execution_method: isolated
result_status: NOT_RUN
---
```

`execution_method` is `isolated` only when the review ran in the restricted executor. Inline review is `inline` and means reduced independence. Do not label inline work as isolated.

`gate_pass` remains because older artifacts and `rails-walked` read it. Set it to mirror the finding counts for that legacy reader. Certification ignores it and recomputes from findings plus the runner record.

## How to review

1. Read the requirements and the diff. Name the snapshot you reviewed.
2. On a remediation round, read the previous review and say which findings closed. Load [references/archive-v2.14.md](references/archive-v2.14.md) for the prior-review procedure.
3. Look for correctness, security, and missing tests before style.
4. For a bug-fix, ask what new edge the fix introduces.
5. Write findings. Each finding has an id, severity, location, impact, evidence, and `verification_status` of `confirmed`, `unverified`, or `suggestion`.

## Severity

| Level | Meaning |
|---|---|
| BLOCKER | Incorrect, unsafe, or data-losing in the examined scope. Blocks the gate. |
| MAJOR | Likely defect or missing test for a behavior the change claims. Blocks the gate. |
| MINOR | Real issue that can ship behind a note. |
| QUESTION | You could not verify. Not a pass and not a confirmed defect. |
| SUGGESTION | Optional improvement. |
| NIT | Taste. Does not block. |

A confirmed BLOCKER or MAJOR blocks. An unverified concern stays visible and does not become a pass. A suggestion does not block.

## Findings the reader can use

Lead with the finding, the consequence, the location, and the evidence. Separate confirmed defects, unverified concerns, and suggestions. If a test could not be run, say `NOT_RUN` and why. Do not describe that as a clean result.

## Scope

Review the diff you were given. Cross-workstream overlap is a check when two active workstreams touch the same files; the procedure is in the archive. Load it when `current.yml` lists more than one active workstream. Do not fan out into a milestone audit.

## Self-check before you emit

- Every blocking finding has a location and evidence.
- `finding_counts` matches the findings you wrote.
- `reviewed_snapshot` is the tree you read.
- You did not edit the tree.
- You did not copy the coder's conclusion into the findings.

## Reference

Load [references/archive-v2.14.md](references/archive-v2.14.md) for the long checklist, red-flag examples, multi-round gate narrative, and the v2.14 cross-workstream procedure.

## Changelog

- **1.9.0** (2026-10-05) — Entrypoint compacted. Findings require location, evidence, and verification status. `gate_pass` is a legacy mirror. The v2.14 text is in the archive.
