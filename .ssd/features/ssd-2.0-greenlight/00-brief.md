---
skill: brief
version: 1.25.1
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-greenlight
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-2.0-greenlight (accept ADR-0012 + README refresh)

A docs/decision workstream bundling two non-breaking changes the user requested together.

## 1. Accept ADR-0012 (greenlight SSD 2.0)

Flip [ADR-0012](../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md) **Proposed → Accepted**
(issue #15). The 2.0 direction is now a committed decision and the cuts may begin. **Accepted ≠
shipped** is preserved explicitly: the prerequisites done so far are the additive de-riskers (`/ssd
upgrade` #17, the chapter-split P1 v1.25.0); `methodology/core.md` keeps citing ADR-0011, not
ADR-0012, until the 2.0 cuts land. The NeXTSTEP guarantee (preserve expert capability while
simplifying for the newcomer — Pillar 1) is reaffirmed in the accepted status note.

## 2. README command-list + epics refresh (doc currency)

The README drifted: command lists omitted `/ssd upgrade` and the v1.16+ workstream commands
(`/ssd feature new`/`switch`/`worktree`); the dogfood epics list stopped at `ssd-commit-split` (v1.19).
Add the missing commands to both lists, add the three missing epics (`ssd-profile-audit`,
`ssd-upgrade`, `ssd-skill-chapter-split`).

## Out of scope

- **The 2.0 cuts themselves** (deleting `chapters/profile.md` + bridge flags + verb collapse) — that's
  the next workstream (`ssd-2.0-cuts`), now unblocked by this acceptance. Accepting the ADR is the
  decision; the cuts are the implementation.

## Acceptance

- ADR-0012 Status = Accepted, with the accepted-≠-shipped note intact.
- README command lists include `/ssd upgrade` + the three workstream commands; epics list current
  through v1.25.
- `VERSION` → 1.25.1; CHANGELOG entry. `/ssd gate` clean.
