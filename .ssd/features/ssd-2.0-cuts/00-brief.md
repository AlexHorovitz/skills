---
skill: brief
version: 2.0.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-2.0-cuts (SSD 2.0: the subtraction)

The accepted [ADR-0012](../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md) cuts. 2.0 is
**subtraction on the v1.x core**, not a rewrite. Multi-iteration epic; each iteration is a separate
gated PR.

## Iterations (ADR-0012 pillars)

- **Iter A — Pillar 1: remove the profile *concept*.** Delete `ssd/chapters/profile.md` + its spine
  stub; remove the per-skill profile-aware sections (4 skills) + invariant-stance notes (3 skills),
  collapsing each profile-keyed behavior to its **unconditional default (= the v1.x `standard`
  baseline)**; strip `developer_profile`/`teaching_mode` from `ssd-init`'s `project.yml` template and
  its profile-conditional Step-5/5.5 logic (→ unconditional propose-and-decline). Supersede ADR-0004 +
  ADR-0010. **First breaking change → 2.0.0.**
- **Iter B — Pillar 3: single surface + verb collapse.** Remove the dual-surface "perfect parity"
  doctrine (bridge flags already gone with the profile chapter). Front-page Invocation collapses to the
  progressive-disclosure entry (`/ssd` + a few); the full verb set is retained as a discoverable
  escape hatch in `ssd/chapters/` (already there post-split), just not taught first. Commands = thin
  alias, not a co-equal surface.
- **Iter C — deprecation path.** Register the removed conventions as `/ssd upgrade` **guided** manifest
  entries (warnings-not-walls: "2.0 ignores `developer_profile`/`teaching_mode`; remove them") so a v1
  project degrades gracefully; open the ADR-0011 revisit-aware tracking issue ADR-0012 requires.

## Invariants held (ADR-0012 "Non-negotiable")

The committed `.ssd/features/` trail, the BLOCKER/MAJOR gate (loud signal, per Pillar 5), "never
silently advance a phase," and the ADR record survive untouched. **NeXTSTEP guarantee:** 2.0 removes
the expert *mode*, never the expert *capability* — every v1 manual verb stays invokable (escape-hatch
chapters); the system just leads more gently by default.

## Acceptance

Per iteration: `/ssd gate` clean; parity green; the removed concept leaves no dangling reference
(grep-verified); `methodology/core.md` may now cite ADR-0012 once iter A lands (2.0 has shipped).
