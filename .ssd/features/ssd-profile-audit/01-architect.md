---
skill: architect
version: 1.2.0
produced_at: 2026-06-11T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-profile-audit
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0010]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — ssd-profile-audit (R9 → v1.20.0)

Design for closing 🔴 P2 / F2: make every sub-skill's stance on `developer_profile` deliberate and
documented. Governing decision: **[ADR-0010](../../../docs/decisions/ADR-0010-profile-aware-subskills.md)**
— a skill branches on profile only when profile changes output *substance*, never tone; and profile
never suppresses gate-critical output. `standard` is the unchanged baseline.

> **Platform note.** This is a markdown skills library — no runtime, no data store, no network.
> The architect deliverables below are adapted to a doctrine/documentation change: the "component
> diagram" is the skill×profile matrix, the "data model" is the documentation schema (table +
> per-skill section), the "API contract" is how the orchestrator and each SKILL.md agree on the
> knobs. `systems-designer` is **N/A** (no deploy surface beyond the tagged release).

## Current Scale Baseline

- **Skills:** 10 (7 in scope here; `ssd`, `ssd-init`, `software-standards` out of scope — the first
  two are orchestrator/bootstrap, the third is adversarial-audit and already profile-neutral).
- **Profiles:** 3 (`novice|standard|expert`).
- **Surface touched:** 4 sub-skill SKILL.md (aware) + 3 sub-skill SKILL.md (invariant note) +
  1 new table in `ssd/SKILL.md`. ~7 files.
- **Runtime scale:** none. **10x target:** N/A — the only growth axis is "more skills," and ADR-0010
  gives each new skill a one-line stance decision at creation, so the design scales by rule, not by
  rework.

## Component Diagram — where the knob lives

```
                       .ssd/project.yml: developer_profile
                                    │ (read once, ADR-0004)
                                    ▼
                          ┌──────────────────┐
                          │   orchestrator   │  tone / surface / confirmations / narration
                          │   (ssd/SKILL.md) │  ── stays here, NOT duplicated downstream
                          └─────────┬────────┘
            passes profile in the invocation context to each sub-skill
                                    │
        ┌───────────────┬───────────┼────────────┬──────────────────────┐
        ▼               ▼           ▼            ▼                      ▼
   INVARIANT        INVARIANT    INVARIANT   PROFILE-AWARE          PROFILE-AWARE …
   architect        methodology  refactor    systems-designer        coder /
   (no branch,      (absolute    (plan is    (checklist depth)       code-reviewer /
    explicit note)   score)       substance)                          codebase-skeptic
                                    │                                    │
                                    └────────── single source of truth ──┘
                                  ssd/SKILL.md § "Profile-aware sub-skill behavior" table
```

## Data Model — the documentation schema

**(a) New subsection in `ssd/SKILL.md`**, immediately after the existing § "Profile-aware defaults"
table (which stays as-is — it's the *orchestrator* knobs). Title: **"Profile-aware sub-skill
behavior."** One row per sub-skill:

| Sub-skill | novice | standard (baseline) | expert |
|---|---|---|---|
| `architect` | *profile-invariant* — design rigor is absolute | | |
| `methodology` | *profile-invariant* — `/methodology score` is absolute | | |
| `refactor` | *profile-invariant* — refactor plan is substance, verbosity is the orchestrator's | | |
| `systems-designer` | full annotated checklist — every item + the "why" | standard checklist | terse: core items only |
| `coder` | more `# REVIEW:` markers — flag every uncertainty | markers on genuine uncertainties | minimal — only blocking unknowns |
| `code-reviewer` | MINOR **and** NIT inline (teaching) | MINOR inline, NIT summarized | MINOR/NIT summarized; focus on BLOCKER/MAJOR |
| `codebase-skeptic` | focused voice subset (≤4 most relevant) | relevant voices (today's behavior) | all relevant voices |

Followed by the **invariant guarantee** stated once below the table:

> Profile tunes teaching breadth, never correctness. `code-reviewer` BLOCKER/MAJOR and
> `codebase-skeptic` 💀/🔴 findings surface at **every** profile and the `gate_pass` computation is
> profile-independent. `standard` behavior is unchanged from pre-v1.20.0.

**(b) Per-skill SKILL.md additions:**
- **Aware skills** (systems-designer, coder, code-reviewer, codebase-skeptic): a short
  `## Profile-Aware Behavior` section stating the knob and the novice/expert delta, with a pointer:
  "single source of truth: `ssd/SKILL.md` § Profile-aware sub-skill behavior." Bump banner + changelog.
- **Invariant skills** (architect, methodology, refactor): a one-line note near the top —
  *"Profile stance: invariant. This skill's output does not branch on `developer_profile` (see
  [ADR-0010]); rationale: …."* Bump banner + changelog (the skill changed — a note was added).

## API / Interface Contract

- **Profile source:** unchanged — `developer_profile` is read from `.ssd/project.yml` by the
  orchestrator (ADR-0004). No new field, no schema bump to `current.yml`/`project.yml`.
- **Orchestrator → sub-skill:** the orchestrator already invokes sub-skills with project context in
  scope; the profile value is available. Each aware skill reads it and selects its row from the
  table. No new machine interface — this is prose contract, like the rest of the methodology.
- **Consistency contract:** each aware skill's `## Profile-Aware Behavior` section MUST match its row
  in the `ssd/SKILL.md` table. (There is no mechanical check for this in v1.20.0 — see Risk R3.)

## Integration Contract
N/A — no queues, events, retries, or cross-service calls. Documentation change.

## Decision Log
- **[ADR-0010](../../../docs/decisions/ADR-0010-profile-aware-subskills.md)** — the substance-not-tone
  boundary rule + the two hard guarantees + the 3-invariant/4-aware split. This is the load-bearing
  decision; the coder implements its table verbatim.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **R1 — A profile branch suppresses a real finding** (e.g. expert mode hides a MINOR that was actually a MAJOR; novice voice-subset drops the voice that would've caught a 💀) | M | H | ADR-0010 guarantee #2 is normative: gate-critical output (BLOCKER/MAJOR, 💀/🔴) surfaces at every profile. Coder adds an explicit "always surfaced regardless of profile" line to each aware skill. code-reviewer verifies it in the gate. |
| **R2 — Scope creep / over-engineering** (branching skills that should stay invariant) | M | M | ADR-0010 fixes the 3/4 split; coder does not branch architect/methodology/refactor. Any new branch proposal needs an ADR-0010 amendment. |
| **R3 — Table/skill drift** (the new ssd table and a skill's section disagree over time) | M | M | Single-source-of-truth pointer in each skill section. Note for a future milestone: extend `skill-version-sync`-style checking to table/section agreement (logged, not built here). |
| **R4 — `ssd/SKILL.md` grows further** (already flagged P1 monolith) | H | L | The new table is ~10 rows; net add small. The v2.0.0 chapter split (P1) will move profile content into `profiles.md` — this table is authored to lift out cleanly. |

**Top 3:** R1 (correctness — the one that must not regress), R2 (discipline), R3 (future drift).

## Feature Flag Plan
N/A — documentation-only change with no runtime. It "ships" atomically as the v1.20.0 tagged release;
there is no flag to stage. (Rollout = the single PR + tag, per the R7 tag-after-merge step.) The
`standard`-is-baseline guarantee is the de-facto safety mechanism: existing users see no change.

## Implementable spec for the coder (build order)

1. **`ssd/SKILL.md`** — add § "Profile-aware sub-skill behavior" (table above + guarantee) right
   after the existing "Profile-aware defaults" table. Bump banner 1.19.1 → 1.20.0 + changelog.
2. **Invariant notes** (architect, methodology, refactor): add the one-line profile-stance note +
   bump each banner + changelog entry. (Banners: architect 1.2.0→1.2.1, methodology 1.6.0→1.6.1,
   refactor 1.2.1→1.2.2 — minor, doc-only. Keep each skill's frontmatter `version:` example in sync
   per the v1.19.1 `skill-version-sync` rule.)
3. **Aware sections** (systems-designer, coder, code-reviewer, codebase-skeptic): add
   `## Profile-Aware Behavior` (knob + novice/expert delta + "always-surfaced" guarantee line +
   single-source pointer) + bump banner + changelog. (systems-designer 1.3.0→1.4.0, coder
   1.2.0→1.3.0, code-reviewer 1.5.0→1.6.0, codebase-skeptic 1.2.1→1.3.0 — minor feature each.)
4. **VERSION/CHANGELOG**: library 1.19.1 → 1.20.0 at release time.
5. Each touched skill: keep its required-frontmatter `version:` example == new banner (gate enforces).

**Gate expectations:** `skill-version-sync` PASS (all bumped banners synced to examples);
`adr-delta` — diff is `.md`-only so it SKIPs, but ADR-0010 exists anyway as the design record;
docs-only so no feature-flag/test rules apply.

## Self-verification
1. Every deliverable section has real content (baseline, diagram, schema, contract, ADR, risk, flag-plan rationale). ✓
2. Adapted to the actual stack (markdown library), not copy-pasted web/runtime defaults. ✓
3. `systems-designer` correctly scoped N/A for the design phase; its *own* profile-aware behavior (checklist depth) is still specified for when it IS used on a real project. ✓
4. ADR-0010 authored in `docs/decisions/`. ✓
5. Scale baseline uses real counts (10 skills, 3 profiles, ~7 files), not placeholders. ✓
