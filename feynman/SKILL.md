---
name: feynman
description: Epistemic audit that builds a claim ledger and grades what the project believes about itself against evidence. Use only when the user explicitly invokes /feynman. Do not start it because a release is near, a build is green, or confidence seems high.
license: See /LICENSE
metadata:
  version: "1.2.0"
disable-model-invocation: true
---

# Feynman

<!-- License: See /LICENSE -->

**Version:** 1.2.0

> "The first principle is that you must not fool yourself — and you are the easiest person to fool."

**Source doctrine:** [Fooling Yourself: Feynman's Cargo Cult Science](https://insanelygreat.com/fooling-yourself.html)

## Purpose

Test claims the project makes about itself. Not "is the code stylish" — "is what we believe true." A person must invoke this skill. An orchestrator may propose it at milestone, verify, audit, or pre-ship. It must not start the audit on its own, and a workflow or agent with another name must not bypass that.

## When to use

The user typed `/feynman` or named this audit in the same turn. Declining a proposal is recorded, not silence.

## When not to use

- Ordinary implementation or diff review. Use `/code-reviewer`.
- A milestone architecture critique. Use `/codebase-skeptic` if the user asked.
- Because you are curious. Propose it. Wait.

## Interface

| | |
|---|---|
| **Input** | The claims in README, CI, status reports, ADRs, and the user's framing |
| **Output** | `.ssd/features/<slug>/feynman.md` or `.ssd/milestones/<topic>/feynman.md` |
| **Consumed by** | the `feynman-clean` gate rule |
| **Persisted** | yes, the claim ledger |

**Required output frontmatter:**

```yaml
---
skill: feynman
version: 1.2.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <what was examined>
consumed_by: [ssd]
claim_counts:
  supported: 0
  contradicted: 0
  theater: 0
  unexamined: 0
posture: sound
gate_pass: false
not_examined: []
reviewed_snapshot: <sha>
execution_method: explicit-invocation
---
```

`gate_pass` is a legacy mirror of "zero contradicted and zero theater". The gate rule reads `contradicted` and `theater`. Do not set those to zero because the narrative sounds fine.

## Phases

1. **Scope.** Say what you will and will not examine. The user can narrow it. You cannot widen it into the whole company without being asked.
2. **Claim ledger.** List claims the project actually makes. Each claim has a source.
3. **Grade each claim** `supported`, `contradicted`, `theater`, or `unexamined`. Run the check yourself when it is a command. Record collected, passed, skipped, and deselected, not only an exit code. Command patterns are in [references/archive-v2.14.md](references/archive-v2.14.md). Load that file when you are about to run a grading command.
4. **Cargo-cult inventory.** Name rituals that imitate evidence (a green badge that does not run the tests it implies).
5. **Asymmetric scrutiny.** Spend more time on the claims the project is proudest of.
6. **Verdict.** `posture` is `sound`, `drifting`, `at-risk`, or `self-deceiving`. Contradicted or theater claims make the gate rule fail. That failure is loud. It is not a wall, and there is no `--force`.
7. **Lean over backwards.** Include the evidence that would change your mind. A short ledger of what you did not examine is required.

## Do not

- Start because `/ssd milestone` mentioned you. The proposal is the milestone's job; the audit waits for the user.
- Treat a missing tool as a supported claim.
- Edit the code under audit to make a claim true.

## Reference

Load [references/archive-v2.14.md](references/archive-v2.14.md) for the v2.14 field kit, grading examples, and cargo-cult inventory. The entrypoint above is the procedure.

## Changelog

- **1.2.0** (2026-10-05) — Entrypoint compacted. Invocation is explicit. There is no `--force`. The v2.14 text is in the archive.
