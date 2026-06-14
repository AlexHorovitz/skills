---
skill: brief
version: 2.1.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#c
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-2.0-cuts iter C (the deprecation path)

Third and final iteration of the SSD 2.0 subtraction ([ADR-0012](../../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md),
issue #15). Iter A (Pillar 1, profile removal) shipped as **v2.0.0** (PR #24); iter B (Pillar 3,
single surface + verb collapse) shipped as **v2.1.0** (PR #25). This iteration closes the epic and
targets **2.2.0**. Like A and B it is additive doctrine + manifest work on the v1.x core, not a
rewrite, and ships as its own gated PR. Markdown skills library → **systems-designer N/A**; design
is the architect only.

## The problem iter C names

2.0 removed project-visible conventions (the `developer_profile`/`teaching_mode` keys in iter A) and
reshaped which surface is taught first (iter B). A v1-era project that runs `/ssd upgrade` today
gets **no signal** that these changed — worse, the existing `dev-profile-keys` mechanical migration
(`introduced_in: 1.10.0`) would still tell it to **add** `developer_profile`, the exact key 2.0 now
ignores. ADR-0012 also names a **reversibility obligation**: its § "Revisit when" triggers are
"mirrored on #15 per ADR-0011" (Pillar 4 — every removed verb/flag deprecation is itself a
revisit-aware Issue). Iter C is the deprecation vehicle that makes both true.

## Scope (refines architect cut-plan § "Iter C")

1. **`methodology/migrations.yml` — new `2.0.0` guided entries** so `/ssd upgrade` re-surfaces what
   2.0 changed (R3 re-surfacing) to projects still on v1 conventions:
   - **Profile-concept removal** — guidance: "2.0 removed the profile concept; delete
     `developer_profile` / `teaching_mode` from `project.yml` (now ignored)."
   - **Surface/verb collapse** — guidance: commands are now a thin alias over the conversational
     path; the front-page verb list is no longer canonical (verbs relocated, not removed).
2. **Open / formalize the ADR-0011 revisit-tracking Issue** that ADR-0012 Pillar 4 requires — the
   deprecation-window ledger carrying ADR-0012's four "Revisit when" triggers on #15.

## Open questions for the architect (design phase)

- **OQ-C1 — additive-manifest vs. a "remove" convention.** Every existing `mechanical` entry is
  *additive* (adds keys / rewrites-with-backup; the manifest's stated invariant is "never delete").
  The cut-plan specifies the new entries are **`guided`** (informational; adopted by hand) precisely
  to avoid teaching the manifest to delete project keys. Confirm `guided` is correct, or design a
  safe `mechanical` deletion path (`.bak`-guarded, ADR-0013 R1) if hand-cleanup is judged too weak.
- **OQ-C2 — the stale `dev-profile-keys` entry.** It now recommends adding a key 2.0 ignores. Does
  iter C neutralize it (and how, under append-only ordering — supersede note? `applies_to` flip?
  `deprecated_by` field?), or is the new guided entry's "delete these keys" guidance sufficient to
  override it in the drift report? This is the sharpest design decision in the iteration.
- **OQ-C3 — the ADR-0011 Issue.** ADR-0012 says the triggers already "live on #15." Is the action
  to *verify/formalize* the revisit ledger on #15, or to open a dedicated deprecation-window Issue?
  Resolve before coding (outward-facing `gh` action — stays under explicit human control).
- **OQ-C4 — guided-entry interaction with the contiguous version bump.** Per the upgrade chapter,
  unadopted guided entries pin the recorded version below themselves (R3). Adding `2.0.0` guided
  entries means a caught-up 2.x project must be able to `--adopt` them to record zero drift. Confirm
  the iter-C entries play correctly with iter-B/C `--adopt` + `migration-manifest-current` gate rule.

## Out of scope

- Re-adding any removed capability. **NeXTSTEP guarantee holds:** iter C documents the removals and
  helps v1 projects migrate; it does not reintroduce the profile concept or a co-equal command surface.
- Changing `/ssd upgrade` engine behavior beyond what new manifest rows require (no new flags).

## Acceptance

- `/ssd gate` clean (no BLOCKER/MAJOR); `migration-manifest-current` gate rule green; parity harness green.
- `methodology/migrations.yml` carries the `2.0.0` guided entries; `/ssd upgrade` on a synthetic v1
  project re-surfaces them (R3) and the report no longer pushes the now-ignored profile keys without
  a countervailing "delete them" signal (OQ-C2 resolution verified, not asserted).
- The ADR-0011 revisit-tracking Issue obligation (ADR-0012 Pillar 4) is satisfied and recorded.
- ADR-0013 addendum if the manifest schema gains a field (OQ-C2); otherwise an ADR-delta note explaining
  why no schema change was needed.
- `VERSION` → 2.2.0; CHANGELOG 2.2.0 entry; banners + frontmatter examples in lockstep for any touched
  skill (`skill-version-sync`). With iter C, the **ssd-2.0-cuts epic (#15) is complete** → archive.
