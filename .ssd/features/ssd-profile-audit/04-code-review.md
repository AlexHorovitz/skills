---
skill: code-reviewer
version: 1.6.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: branch add-ssd-profile-audit vs main (8 SKILL.md + ADR-0010 + feature artifacts)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 1
  suggestion: 1
  nit: 0
gate_pass: true
remediation_mode: false
round: 2
closed_from_previous_round: [MINOR-1, SUGGESTION-1]
---

# Code Review — ssd-profile-audit (R9, v1.20.0)

Feature work, round 1. Reviewed against [01-architect.md](01-architect.md) and
[ADR-0010](../../../docs/decisions/ADR-0010-profile-aware-subskills.md). Diff: 12 files, +527/-14.

## Phase 2 — design/approach

The implementation matches ADR-0010 exactly. The substance-not-tone rule is applied consistently:
the 3 invariant skills (architect, methodology, refactor) only gained a one-line stance note; the 4
aware skills (systems-designer, coder, code-reviewer, codebase-skeptic) each branch on a single
output-substance knob. No skill duplicates the orchestrator's narration/confirmation knob. The
single-source-of-truth pattern (one table in `ssd/SKILL.md`, each skill points back) is the right
call for closing P2 ("scattered, no single source").

## Phase 3 — detailed verification

**(1) 3-invariant / 4-aware split — matches ADR-0010.** ✓ Verified each skill on disk:
architect 1.2.1, methodology 1.6.1, refactor 1.2.2 carry "Profile stance: invariant" notes;
systems-designer 1.4.0, coder 1.3.0, code-reviewer 1.6.0, codebase-skeptic 1.3.0 carry
`## Profile-Aware Behavior` sections.

**(2) Invariant guarantee — present and correct in every aware skill.** ✓ Traced each:
- code-reviewer: "BLOCKER and MAJOR reported inline at *every* profile; `gate_pass` (blocker==0 AND
  major==0) profile-independent" — explicitly marked "normative, overrides the profile delta". Correct.
- codebase-skeptic: "reducing voice count changes *angles*, never the severity of what is found; a
  💀/🔴 a running voice surfaces is reported regardless of profile." Correct.
- systems-designer: "safety-critical gates (rollback, migration safety, observability) required at
  *every* profile." Correct.
- coder: "a genuine blocker — missing feature flag, red build, spec drift — halts handoff at *every*
  profile." Correct.
Plus the global guarantee in the `ssd/SKILL.md` table. The correctness boundary is well-defended.

**(3) codebase-skeptic ≤4-voice cap — carve-out is sufficient (see QUESTION-1).** The
milestone/pre-release full-breadth exception protects the path where a missed angle is
release-blocking. Honest residual: ad-hoc novice reviews do get fewer angles — but that is the
opted-into behavior, and the severity-never-suppressed invariant + the carve-out bound the risk.

**(4) Table ↔ section consistency — verified verbatim.** ✓ Each aware skill's novice/standard/expert
bullets match its row in the `ssd/SKILL.md` table word-for-word in substance (systems-designer
depth, coder marker density, code-reviewer MINOR/NIT, codebase-skeptic voice breadth).

**Mechanical:** `skill-version-sync` PASS (all 8 bumped banners synced to their frontmatter
examples — this very check dogfooding the v1.19.1 rule); `gate-rules --base main` all PASS/SKIP;
`parity-test` 16/16. `standard` baseline unchanged (every aware row + section says so explicitly).

## Findings

- 🟡 **MINOR-1 — profile-delivery mechanism unstated.** Each aware skill now says it "branches on
  `developer_profile`," but neither the new table section nor § "/ssd feature" / "/ssd design"
  states *how* a sub-skill learns the active profile at invocation. The architect spec calls it a
  prose contract ("the profile value is available in context"), which is consistent with this
  library's LLM-interpreted model — but a one-line addition to `ssd/SKILL.md` ("when invoking a
  profile-aware sub-skill, the orchestrator states the active `developer_profile` in the invocation
  context") would close the "how does `coder` know the profile?" gap for the next reader.
  Non-blocking; suggest folding into this PR before ship or as a fast follow.
- 💭 **QUESTION-1 — ad-hoc novice reviews get fewer angles.** A voice that doesn't run can't find
  its issue. Confirmed acceptable by design: novice explicitly trades breadth for focus, the
  milestone/pre-release carve-out forces full breadth where it matters, and severity is never
  suppressed. Answered-by-design; no change required. Recorded so the tradeoff is on the record.
- 💡 **SUGGESTION-1 — global guarantee completeness.** The `ssd/SKILL.md` table's global invariant
  guarantee names only code-reviewer + codebase-skeptic gate-critical output. systems-designer
  safety gates and coder blockers are covered in their own sections; optionally name all four in the
  one global statement for a single complete reference. Optional.

## Gate decision

**PASS** — `blocker == 0 AND major == 0`. The one MINOR is a doc-completeness nicety, not a blocker.
Recommend addressing MINOR-1 inline before tagging v1.20.0 (cheap, and it's the kind of "implementation
ahead of its own docs" gap this very epic exists to prevent), but it does not hold the gate.

---

## Round 2 (inline) — closures

Addressed in the same gate cycle (small remediation, inline per § "Multi-Round Gates"):

- ✅ **MINOR-1 closed.** `ssd/SKILL.md` § "Profile-aware sub-skill behavior" now states the
  profile-delivery contract: the orchestrator states the active `developer_profile` (from
  `.ssd/project.yml`) in the invocation context; ad-hoc invocation defaults to `standard`. Verified
  in the diff.
- ✅ **SUGGESTION-1 closed.** The global invariant guarantee now names all four gate-critical
  surfaces (code-reviewer BLOCKER/MAJOR + gate_pass, codebase-skeptic 💀/🔴, systems-designer safety
  gates, coder blocker-halt). Verified in the diff.
- 💭 QUESTION-1 remains answered-by-design (no change).

Re-verified post-edit: `skill-version-sync` PASS (no banner change — ssd already at 1.20.0 for this
release), `gate-rules --base main` all PASS/SKIP, `parity-test` 16/16. Gate remains **PASS**.
