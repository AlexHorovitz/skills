# ADR-0010: When a sub-skill branches on `developer_profile`

## Status
**Superseded by [ADR-0012](ADR-0012-ssd-2.0-architecture.md) — 2026-06-14** (SSD 2.0, ssd-2.0-cuts
iter A, v2.0.0). The profile-aware sub-skill boundary rule this ADR set is moot now that the
`developer_profile` concept is removed: the per-skill behaviors collapsed to their former `standard`
defaults (unconditional). Retained as the historical record (it was the precondition that made the
profile subsystem coherent enough to remove surgically — see ADR-0012 Consequences).

Proposed — 2026-06-11 — drove the ssd-profile-audit feature (R9, shipped v1.20.0).
Extends [ADR-0004](ADR-0004-developer-profile-and-teaching-mode.md).

## Context

ADR-0004 introduced `developer_profile` (`novice|standard|expert`) and made the **orchestrator**
profile-aware (surface, confirmations, narration, YAML-editing posture). The **sub-skills** stayed
profile-blind. The post-v1.19 milestone flagged this as 🔴 P2 (Feathers: profile-awareness scattered,
no single source) + F2 (new-hire risk). R9 closes it — but "make every skill profile-aware" would
be over-engineering (Universal Principle 2) and would duplicate the orchestrator's existing
narration/confirmation knobs at seven new sites.

We need a *rule* for which skills branch, so the decision is principled and future skills inherit it.

## Decision

**A sub-skill branches on `developer_profile` only when the profile changes the skill's output
*substance* — which artifacts, markers, findings, voices, or checklist items are produced. Profile
must NOT be used at the skill level to change mere *tone/verbosity/confirmation*; that is the
orchestrator's job (ADR-0004) and duplicating it per-skill is the scatter we're trying to end.**

Two hard guarantees bound every profile-aware skill:

1. **`standard` is the unchanged baseline.** novice and expert are deltas around today's behavior;
   a `standard` user sees zero change.
2. **Profile never suppresses gate-critical output.** A `code-reviewer` BLOCKER/MAJOR and a
   `codebase-skeptic` 💀/🔴 surface at *every* profile. Profile tunes teaching breadth (which MINOR/
   NIT/voices/markers also appear), never correctness or the gate decision.

### Resulting per-skill decisions

| Sub-skill | Decision | Why |
|---|---|---|
| `architect` | **invariant** | Design rigor is absolute — a spec is for the codebase, not the author. ADRs are produced regardless of who asks. |
| `methodology` | **invariant** | `/methodology score` is an absolute self-adherence metric; bending it to the profile makes it meaningless. |
| `refactor` | **invariant** | The plan (what to refactor, which finding it cites) is substance-invariant; only coaching verbosity would differ, and that's the orchestrator's narration knob. |
| `systems-designer` | **profile-aware** — checklist depth | Which deploy-checklist items surface is substance. novice sees the full annotated set; expert sees the core set. |
| `coder` | **profile-aware** — `# REVIEW:` marker density | How many uncertainty markers get emitted is substance. novice flags more (safety net); expert flags only blocking unknowns (signal). |
| `code-reviewer` | **profile-aware** — MINOR/NIT reporting | Which severities surface inline is substance. novice gets MINOR+NIT inline (teaching); expert gets them summarized. BLOCKER/MAJOR always inline. |
| `codebase-skeptic` | **profile-aware** — voice breadth | How many expert voices activate is substance. novice gets a focused subset (≤4, less overwhelming); expert gets all relevant voices. Critical findings surface regardless. |

3 invariant, 4 aware.

## Consequences

- A single rule ("substance, not tone; never suppress gate-critical output") governs current and
  future skills — a new skill declares its profile stance at creation, like it already declares a
  priority rule in § "Resolving Skill Overlap".
- Per-skill knobs are documented in one place: a new § "Profile-aware sub-skill behavior" table in
  `ssd/SKILL.md`, adjacent to the existing orchestrator-defaults table. Each aware skill's SKILL.md
  gets a short "Profile-aware behavior" section pointing back to that table (single source of truth,
  closing P2).
- The three invariant skills get an explicit one-line "profile-invariant, because …" note, so
  "profile-blind" is never again ambiguous with "nobody decided."

## Alternatives rejected

- **Make all 7 profile-aware.** Over-engineering; duplicates the orchestrator's narration knob at
  the skill level for architect/methodology/refactor where only tone would change.
- **Make all 7 invariant, keep profile purely orchestrator-level.** Leaves real substance wins on
  the table (a novice genuinely benefits from more REVIEW markers and a narrower voice set) and
  doesn't close P2's "implementation drifts from ADR-0004's two-audiences intent".
- **Persist profile knobs as a schema field per skill.** Deferred — no need yet; the behavior is
  documented in prose + the ssd table. Revisit if a knob needs to be machine-read.
