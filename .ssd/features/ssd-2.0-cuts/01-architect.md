---
skill: architect
version: 1.2.1
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: false
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0012]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: not_applicable
quality_gate_pass: true
---

# Architect Cut-Plan — SSD 2.0 (ADR-0012, issue #15)

> Markdown skills library. `systems-designer` N/A. This spec enumerates the deletions and pins the
> **unconditional defaults** that replace each profile-keyed behavior — the only real design
> decisions; the rest is mechanical removal.

## The governing decision: collapse to `standard`

ADR-0012: *"`standard` is the unchanged baseline — `novice` and `expert` are deltas around it."* So
every profile-keyed behavior collapses to **what `standard` did in v1.x**, and the `novice`/`expert`
deltas are deleted. Progressive disclosure (the no-arg Auto-Detect, already in the spine) is the
replacement for the *guidance* the profile tiers provided; depth-on-demand (the escape-hatch chapters)
is the replacement for `expert` mode. **Removing the mode ≠ removing the capability** (NeXTSTEP).

## Iter A — Pillar 1: remove the profile concept

### Deletions
| File | Cut |
|---|---|
| `ssd/chapters/profile.md` | **delete the file** (whole chapter: profile values, defaults table, profile-aware table, teaching mode, bridge flags) |
| `ssd/SKILL.md` | delete the `## Developer Profile + Teaching Mode` spine stub + chapter-index row; drop profile mentions in the no-arg Auto-Detect prose |
| `ssd/chapters/workstreams.md` | `switch_note_default` per-profile defaults → single default `prompt`; drop `developer_profile: expert` `--promote` clause (keep `--promote` unconditional) |
| `code-reviewer/SKILL.md` | delete `## Profile-Aware Behavior`; unconditional = **MINOR inline, NIT summarized** (standard). BLOCKER/MAJOR + `gate_pass` were always profile-independent — unchanged. |
| `coder/SKILL.md` | delete `## Profile-Aware Behavior`; unconditional = **`# REVIEW:` markers on genuine uncertainties** (standard) |
| `systems-designer/SKILL.md` | delete `## Profile-Aware Behavior`; unconditional = **the standard checklist** (safety-critical gates already apply at every profile — unchanged) |
| `codebase-skeptic/SKILL.md` | delete `## Profile-Aware Behavior`; unconditional = **relevant voices** (today's standard); milestone/pre-release keep full breadth as before |
| `architect`, `methodology`, `refactor` SKILL.md | delete the `> Profile stance: invariant` notes (top) + the changelog "no behavior change" lines — they never branched; nothing to collapse |
| `ssd-init/SKILL.md` | remove `developer_profile`/`teaching_mode` from the `project.yml` template; Step 5 (gitignore migration) + Step 5.5 (hook install) drop profile-conditional suppression → **always propose, user declines** (warnings-not-walls) |
| `docs/decisions/ADR-0004`, `ADR-0010` | mark **Superseded by ADR-0012** (do not delete — ADR record is non-negotiable) |

### Data-model change (`.ssd/project.yml`)
Remove `developer_profile` and the `teaching_mode` block. Keep `switch_note_default` as a plain config
knob (no longer profile-derived; default `prompt`). v1 projects that still carry the removed keys: 2.0
**ignores** them (no crash); iter C adds the guided migration to clean them up.

### `ssd/SKILL.md` § "Profile-aware sub-skill behavior" single-source table
Deleted with the profile chapter. Each sub-skill that pointed back to it loses its pointer when its
`## Profile-Aware Behavior` section is removed.

## Iter B — Pillar 3: single surface + verb collapse
- Delete the dual-surface "perfect parity" doctrine wherever it survives outside the profile chapter
  (e.g., any "no surface hides anything" prose; the parity-test note is already N/A).
- Front-page **Invocation** in the spine collapses to the progressive-disclosure entry plus the few
  everyday verbs; the full phase + lifecycle set stays in `ssd/chapters/{phases,upgrade,workstreams}.md`
  as the retained escape hatch (already relocated by the v1.25.0 split). Commands are a thin alias that
  lowers into the conversational path — explicitly **not** a co-equal surface with its own state.

## Iter C — deprecation path
- `methodology/migrations.yml`: new **guided** entries (`introduced_in: 2.0.0`) — "2.0 removed the
  profile concept; delete `developer_profile`/`teaching_mode` from `project.yml` (now ignored)" and the
  surface/verb deprecations. `/ssd upgrade` re-surfaces them (R3) so v1 projects learn what changed.
- Open the ADR-0011 revisit-aware tracking issue ADR-0012 requires (the deprecation-window ledger).

## API / interface contract
No new commands. The user-facing command *names* are unchanged in iter A (only profile flags/keys go);
iter B reshapes which verbs are taught first. The orchestrator's gate, artifact tree, and rails are
untouched.

## Version plan
Iter A is the first breaking change (project.yml keys removed) → **2.0.0**. Iter B → 2.1.0, iter C →
2.2.0 (or fold C into the 2.0.0 ship if small). `methodology/core.md` may begin citing ADR-0012 once
iter A lands (2.0 has shipped — satisfies the ADR-0012 status note's "until 2.0 ships" condition).

## Risk assessment
| Risk | L | I | Mitigation |
|---|---|---|---|
| **R1 — a profile-keyed behavior is silently dropped, not collapsed** (a sub-skill loses a behavior instead of defaulting to standard) | M | M | Each deletion explicitly states the surviving unconditional default (table above); code-review verifies the standard behavior remains described in the skill body, not just that the section was removed. |
| **R2 — dangling references** to the deleted profile chapter / `developer_profile` (broken `§` cites, ADR links) | M | L | grep gate after each iter: no live ref to `profile.md`, `developer_profile`, `Profile-aware sub-skill behavior` outside `.ssd/`/CHANGELOG history + the superseded ADRs. |
| **R3 — over-cutting a NeXTSTEP capability** (removing an expert escape hatch, not just the mode) | L | H | The verb set is *relocated, not removed* (iter B keeps chapters); only the profile *enum* + tiered deltas die. Code-review checks every v1 manual verb is still invokable. |
| **R4 — `skill-version-sync` drift** from bumping 7 skill banners | L | L | Bump each touched skill's banner + its frontmatter-example in lockstep; the gate rule catches misses. |

## Self-verification
1. Every cut names its surviving unconditional default (no silent behavior loss). ✓
2. ADRs superseded, not deleted (ADR record non-negotiable). ✓
3. NeXTSTEP: capability preserved (escape-hatch chapters), only the mode removed. ✓
4. Iteration boundaries are independently shippable + gated. ✓
