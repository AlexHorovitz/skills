---
skill: ssd
version: 1.19.1
produced_at: 2026-06-11T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-profile-audit (refactor R9, post-v1.19 milestone; ships v1.20.0)
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-profile-audit

## Origin

Refactor item **R9** from the post-v1.19 milestone
([refactor-plan.md](../../milestones/2026-06-10-post-v1.19/refactor-plan.md)), deferred out of the
v1.19.1 doctrine-tightening patch because it touches 7 sub-skills and is its own design pass.
Closes the deferred 🔴 finding **P2** (Feathers: profile-awareness prose scattered, no single
source) and forward-finding **F2** (new-hire breaks because most sub-skills are profile-blind). See
[verification.md](../../milestones/2026-06-10-post-v1.19/verification.md) § "Carried forward".

## Problem

`developer_profile` (`novice|standard|expert`, ADR-0004) adjusts orchestrator defaults — surface,
confirmations, narration, YAML-editing posture — but **the sub-skills are profile-blind**. The
profile-aware behavior lives only in `ssd/SKILL.md`'s defaults table; each sub-skill applies the
same behavior regardless of who's driving. That's a drift between the ratified design (ADR-0004,
"two audiences") and the implementation across the skill chain. A novice gets the same terse
code-review and sparse `# REVIEW:` markers an expert gets; an expert gets the same hand-holding a
novice gets.

## Goal

For each of the 7 sub-skills, make a deliberate, documented decision: either
- **(a) profile-invariant** — add an explicit "this skill's behavior does not branch on
  `developer_profile`, because …" note, OR
- **(b) profile-aware** — add real per-profile behavior branches, with the knobs surfaced as new
  columns in `ssd/SKILL.md`'s § "Profile-aware defaults" table.

Every sub-skill ends the epic with one or the other — no skill stays silently profile-blind.

## Per-skill leanings (from the refactor-plan; the architect pass confirms or revises)

| Skill | Plan's leaning | Candidate knob |
|---|---|---|
| `architect` | invariant | ADRs/specs are produced regardless of who asks |
| `methodology` | invariant | `/methodology score` is an absolute metric |
| `systems-designer` | maybe branch | novice gets more deploy-checklist guidance; expert terse |
| `refactor` | maybe branch | budget-hours-warning verbosity |
| `coder` | maybe branch | `# REVIEW:` marker threshold (novice more, expert fewer) |
| `code-reviewer` | maybe branch | MINOR/NIT strictness (novice more called out) |
| `codebase-skeptic` | maybe branch | voice-activation count (novice fewer voices) |

## Constraints

- **No regression for `developer_profile: standard`** — current behavior is the standard baseline;
  branches add novice/expert variants around it.
- Markdown-only change → `systems-designer` is **N/A** for the design phase (architect runs alone).
- New knobs must be consistent between each sub-skill's SKILL.md and the `ssd/SKILL.md` table
  (the very consistency the v1.19.1 `skill-version-sync` rule now guards for versions — keep this
  table/skill agreement honest too).
- Any sub-skill whose banner changes this release re-aligns per the R7 banner-lag note.

## Out of scope

- P1 (ssd/SKILL.md chapter split → v2.0.0).
- Schema changes to persist profile as a skill-level flag (note as a question if the design surfaces
  a need; don't build it here).

## Acceptance

- All 7 sub-skills carry either an explicit invariance note or per-profile branches.
- `ssd/SKILL.md` Profile-aware defaults table gains any new columns introduced.
- `/ssd gate` clean (incl. `skill-version-sync`); ships as v1.20.0.

## Next step

`/ssd design ssd-profile-audit` — architect only (systems-designer N/A).
