---
skill: architect
version: 1.3.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#b
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: false
  data_model: not_applicable
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0012]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: not_applicable
quality_gate_pass: true
---

# Architect Cut-Plan — SSD 2.0 iter B (Pillar 3: single surface + verb collapse)

> Markdown skills library — no runtime, no data model, no scale baseline. `systems-designer` N/A.
> This is subtraction + reframing on the v1.x spine, governed by an already-accepted ADR
> ([ADR-0012](../../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md) Pillar 3); **no new ADR**
> (the surface decision is already recorded). Ships as **2.1.0**.

## The governing decision (ADR-0012 Pillar 3)

> *"Kill the dual-surface parity doctrine and the bridge flags. The command path is a power-user
> shorthand, explicitly not a co-equal surface with its own state."*

Two things this pillar names; their status after iter A:

1. **The dual-surface "perfect parity" doctrine** — the claim that the conversational path and the
   `/ssd <verb>` command path are co-equal surfaces that must mirror each other. **Already removed
   from all live prose by iter A** (it lived in `chapters/profile.md`, deleted, and in ADR-0004,
   superseded). A grep across live files (`-v .ssd/ -v CHANGELOG`) finds it *only* in the superseded
   ADR-0004, the governing ADR-0012, and `.ssd/` history — all immutable. **Nothing live to delete.**
   Iter B's job here is to *verify* this holds (R2), not to cut.
2. **The front-loaded verb list** — the spine's `## Invocation` block teaches the full 13-verb set
   first, competing with the no-arg Auto-Detect that the spine already declares as the default. **This
   is the one real edit in iter B.**

## The single live edit: collapse `ssd/SKILL.md` § "Invocation" (lines 45–64)

Replace the flat 13-verb table + framing with a progressive-disclosure block: the bare `/ssd` as the
headline everyday path, and the full verb set **relocated** into an intent→verb→chapter pointer table
(the per-verb docs already live in the chapters after the v1.25.0 split — this is relocation of the
*index*, not removal of capability).

### Target text (exact)

```markdown
## Invocation

SSD has **one surface, progressively disclosed.** The everyday path is the bare command — it reads
your project state and proposes the next action, naming the explicit step it's taking so you never
have to memorize the verb set:

\```
/ssd               — auto-detect state and propose the next action (the path you use)
/ssd start         — bootstrap a new project (Walking Skeleton) when there's no state to detect yet
\```

That is all most sessions need; `/ssd` walks the canonical rails for you.

The **full verb set** stays a first-class escape hatch — every phase, audit, and lifecycle command
is still directly invokable, just documented in the chapters rather than taught first:

| To… | Verb(s) | Chapter |
|---|---|---|
| force a specific phase | `start` · `feature` · `design` · `milestone` · `verify` · `audit` · `gate` · `ship` | [`chapters/phases.md`](chapters/phases.md) |
| migrate a project to the latest SSD conventions | `upgrade` | [`chapters/upgrade.md`](chapters/upgrade.md) |
| run parallel workstreams | `feature new` · `switch` · `worktree` | [`chapters/workstreams.md`](chapters/workstreams.md) |

The command path is a **thin alias** that lowers into the conversational path — a power-user
shorthand, **not** a co-equal surface with its own state. Everything a command does, `/ssd` can
propose; nothing is reachable only by command ([ADR-0012](../docs/decisions/ADR-0012-ssd-2.0-architecture.md)
Pillar 3).
```

(The `\``` fences above are escaped only for this spec; the coder writes a real nested code block.)

### Why this shape

- **Discoverability preserved.** The intent→chapter table keeps every verb one hop away and tells
  the reader *which chapter* owns it — better than the old flat list, which named verbs but not where
  they're documented.
- **Redundancy retired, not duplicated.** The spine *already* has dedicated sections lower down
  ("Explicit phase commands" → `chapters/phases.md`; "Workstream Lifecycle Commands" →
  `chapters/workstreams.md`; "/ssd upgrade" → `chapters/upgrade.md`). The old Invocation table
  duplicated those pointers; the collapsed table subsumes the duplication.
- **Doctrine stated once.** The "thin alias, not a co-equal surface" sentence is the single live
  home of Pillar 3's surface doctrine going forward.

## API / interface contract

**No command added, removed, or renamed.** Every v1 verb (`start`, `feature`, `design`, `milestone`,
`verify`, `audit`, `gate`, `ship`, `upgrade`, `feature new`, `switch`, `worktree`) stays invokable
with identical behavior. The orchestrator's gate, artifact tree, rails, and no-arg Auto-Detect logic
are untouched. The only change is *what the front page teaches first*.

## Files touched

| File | Change |
|---|---|
| `ssd/SKILL.md` | collapse § "Invocation" (above); bump `**Version:**` banner → 2.1.0 |
| `VERSION` | `2.0.0` → `2.1.0` |
| `CHANGELOG.md` | 2.1.0 entry: surface-doctrine collapse (Pillar 3) |

**Not touched (verified):** `methodology/core.md` (its only ADR cite is ADR-0011 decision-record-doctrine
— correct, unrelated to surfaces); the 4 sub-skill SKILL.md files (no profile/surface prose left after
iter A); the chapters (already hold the full verb docs — they are the relocation *target*, unchanged).
This corrects the iter-B touch-guess in `current.yml`/notes that anticipated a `core.md` edit.

## Version plan

Iter B → **2.1.0** (minor: doctrine/teaching change, no breaking key removal — v1 invocations all still
work). `skill-version-sync` requires the `ssd` banner and its frontmatter example move together.

## Risk assessment

| Risk | L | I | Mitigation |
|---|---|---|---|
| **R1 — collapse drops a verb's discoverability** (a reader can no longer find, e.g., `/ssd milestone`) | M | M | The intent→chapter table lists **every** verb and routes to its chapter; code-review confirms each of the 12 v1 verbs appears in the table and its chapter documents it. |
| **R2 — residual live parity prose** survives outside the deleted profile chapter | L | L | grep gate (live files, excl. `.ssd/`/CHANGELOG): `perfect parity\|dual.?surface\|co-equal\|no surface hides` returns only superseded ADR-0004 + governing ADR-0012. Code-review re-runs and confirms zero spine/core hits. |
| **R3 — NeXTSTEP over-cut** (a verb is *removed*, not relocated) | L | H | No verb deleted; only the front-page index changes. Code-review checks every v1 verb is still invokable + documented in a chapter. |
| **R4 — `skill-version-sync` drift** from the banner bump | L | L | Bump `ssd` banner + its frontmatter example in lockstep with `VERSION`; the gate rule catches a miss. |

## Self-verification

1. Every cut/reframe names what survives (full verb set relocated to chapters, doctrine stated once). ✓
2. No new ADR needed — the decision is recorded in ADR-0012 Pillar 3; cite, don't duplicate. ✓
3. NeXTSTEP: capability fully preserved (every verb invokable + chapter-documented); only teaching-order changes. ✓
4. Scope is independently shippable + gated (single live file + VERSION + CHANGELOG). ✓
5. Standard architect deliverables (data model, scale baseline, integration contract) correctly N/A for a markdown library — not stubbed. ✓
