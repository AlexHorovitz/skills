---
skill: brief
version: 2.0.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#b
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-2.0-cuts iter B (Pillar 3: single surface + verb collapse)

Second iteration of the SSD 2.0 subtraction ([ADR-0012](../../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md),
issue #15). Iter A (Pillar 1, profile removal) shipped as **v2.0.0** (PR #24). This iteration is
**Pillar 3** and targets **2.1.0**. Like iter A it is subtraction on the v1.x core, not a rewrite,
and ships as its own gated PR. Markdown skills library → **systems-designer N/A**; design is the
architect only.

## The problem 2.0 Pillar 3 names

SSD v1.x presents two parallel doctrines about *surfaces*:

1. A **dual-surface "perfect parity"** doctrine — the idea that the conversational path and the
   explicit `/ssd <verb>` command path are co-equal surfaces that must mirror each other so "no
   surface hides anything." With the profile chapter (and its bridge flags) deleted in iter A, this
   doctrine now survives only as scattered prose.
2. A **front-loaded verb list.** The spine's `## Invocation` teaches the full phase + lifecycle verb
   set first, competing with the no-arg Auto-Detect (the progressive-disclosure entry the spine
   already declares as the default path).

Pillar 3 collapses these to **one surface, progressively disclosed**: the conversational/no-arg path
is primary; commands are a thin alias that lowers into it, not a co-equal stateful surface.

## Scope (refines architect cut-plan § "Iter B")

- **Collapse the spine's front-page `## Invocation`** to the progressive-disclosure entry (`/ssd`
  no-arg Auto-Detect) plus the few everyday verbs. The **full** phase + lifecycle verb set is
  **retained, not removed** — it already lives in `ssd/chapters/{phases,upgrade,workstreams}.md`
  after the v1.25.0 split, and stays there as the discoverable escape hatch.
- **Delete the dual-surface "perfect parity" doctrine** wherever it still survives outside the
  (already-deleted) profile chapter — spine prose and any `methodology/core.md` clause that frames
  commands as a co-equal surface requiring parity.
- **Reframe commands as a thin alias** that lowers into the conversational path — explicitly *not* a
  surface with its own independent state.

## Out of scope

- Iter C (deprecation path: `/ssd upgrade` guided entries + ADR-0011 revisit issue) — stays on #15.
- Removing or renaming any verb. **NeXTSTEP guarantee:** every v1 manual verb stays invokable; this
  iteration changes *what is taught first*, never *what is reachable*.

## Acceptance

- `/ssd gate` clean (no BLOCKER/MAJOR); parity harness green.
- **No dangling references** (grep-verified): no live prose still asserts dual-surface parity or
  points the reader at a removed front-page verb listing as canonical.
- **NeXTSTEP check (R-relocate):** every verb dropped from the front-page Invocation is still present
  and reachable via `ssd/chapters/`. Code-review confirms relocation, not deletion.
- Banners + frontmatter examples bumped in lockstep for any touched skill (`skill-version-sync`
  gate rule); `VERSION` → 2.1.0; CHANGELOG 2.1.0 entry marking the surface-doctrine change.
