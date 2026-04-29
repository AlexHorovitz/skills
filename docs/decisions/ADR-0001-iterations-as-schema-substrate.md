# ADR-0001: Iterations as schema substrate inside a feature

## Status
Accepted — 2026-04-29 — landed in iteration 2 of the ssd-skill-upgrades epic ([epic plan on disk](../../.ssd/features/ssd-skill-upgrades/01-architect.md)).

## Context

A single SSD "feature" is assumed by `/ssd feature` to be one design → one build → one review → one
deploy. Real working sessions outgrew this in the athena project, where the
`talentos-reimagined-phase3-ui` feature shipped as iterations 3a, 3b, 3c — three PRs over a
fortnight, each with its own brief, code, review (sometimes with multiple rounds), and deploy. The
17 artifacts that accumulated under that single feature directory had names like
`00-brief-3b.md`, `03-coder-status-3c.md`, `04-code-review-3b-round-2.md`. The user invented a
filename convention (`-3b`, `-round-2`) because SSD lacked first-class support for either concept.

Beyond filename ergonomics, the missing iteration concept has downstream consequences:

- The orchestrator can't render "PR 3a, 3b shipped; 3c in coder phase" rollups because there is no
  structure to roll up.
- Carry-over from one iteration to the next (deferred findings, partial work) lives as prose
  bullets in `current.yml`.
- Multi-round gates (P1.2) need somewhere to put `round-N.md` files — without iterations, they go
  back into the feature root and produce the same naming hack, just one level lower.
- The deferred-findings ledger (P1.5) needs a per-iteration locus, not per-feature.

## Decision

Add an opt-in iterations layer to the feature artifact tree:

```
.ssd/features/<slug>/
├── 00-brief.md                       # epic-level brief (single-cycle features stay here)
├── 01-architect.md                   # epic-level design
├── 02-systems-designer.md            # production readiness
├── 03-coder-status.md                # — for single-cycle features only
├── 04-code-review.md                 # — for single-cycle features only
├── 05-deploy.md                      # — for single-cycle features only
└── iterations/                       # OPTIONAL — only for multi-iteration features
    ├── 3a/
    │   ├── brief.md
    │   ├── coder-status.md
    │   ├── code-review/              # multi-round gates land here (iter 3 / P1.2)
    │   │   ├── round-1.md
    │   │   └── round-2.md
    │   ├── deferred.yml              # carry-over ledger (iter 4 / P1.5)
    │   └── deploy.md
    ├── 3b/ ...
    └── 3c/ ...
```

**Iteration-id syntax**: `<slug>#<iter-id>` — for example `talentos-reimagined-phase3-ui#3b`. Both
forms (with and without `#iter`) resolve via the orchestrator. A feature with no `iterations/`
subdirectory continues to use the flat single-cycle layout — back-compat is total.

**Iter-id format**: any string matching `[A-Za-z0-9_-]+`. Suggested conventions: short numeric
suffixes (`3a`, `3b`), descriptive (`auth-flow`, `cleanup`), or sequential (`1`, `2`, `3`). The
orchestrator does not enforce a particular format because real teams will land on different
conventions.

**Resolution rule**: when the orchestrator receives a slug:

1. If slug contains `#`: split into feature-slug + iter-id. Read
   `.ssd/features/<feature-slug>/iterations/<iter-id>/`. If that path doesn't exist and the user is
   in a phase that creates artifacts (e.g., coder), prompt the user to confirm "create new
   iteration <iter-id> under <feature-slug>?" before proceeding.
2. If slug has no `#` and the feature has an `iterations/` subdirectory: the orchestrator surfaces
   active iterations from `.ssd/current.yml` and asks the user which to operate on, or to create a
   new one.
3. If slug has no `#` and the feature has no `iterations/` subdirectory: single-cycle feature —
   read/write the flat layout under `.ssd/features/<feature-slug>/`.

**Promotion to multi-iteration**: a feature is "promoted" the first time `<slug>#<iter>` is
referenced in a `/ssd` invocation. The orchestrator creates `iterations/` and the named iteration
subdirectory. Existing flat-layout artifacts (`00-brief.md`, `01-architect.md`, etc.) stay at the
feature root and are treated as epic-level material that all iterations share. They are NOT moved
into the first iteration — that would be a destructive operation that re-shapes the feature's
existing history without explicit consent.

## Rationale

- **Filename conventions are a code smell.** Athena's `-3b`, `-round-2` suffixes were the user
  doing the orchestrator's job. Making iterations a real concept removes the pressure to invent
  conventions.
- **Opt-in.** Single-cycle features are still the common case. Forcing every feature into
  `iterations/1/` would be ceremony for no benefit. Promotion happens only when the user actually
  splits work.
- **Forward-compatible with later iterations.** P1.2 (multi-round gates) and P1.5 (deferred
  ledger) both consume the `iterations/<id>/` substrate. Without this ADR, both have to invent
  alternate landing spots and the schema gets messier.
- **Total back-compat.** Athena's existing flat-layout features keep working. The `iteration` field
  in `current.yml` v2 (added in iter-1 / ADR-0002) was already nullable specifically for this
  case.

## Consequences

**Easier:**
- Multi-PR features have a real home for per-iteration artifacts.
- Orchestrator can render "iteration 3a shipped, 3b in review, 3c in coder" status from
  `current.yml` field reads.
- Deferred ledger (P1.5) and multi-round gates (P1.2) plug in naturally.

**Harder:**
- Two layouts in the wild (flat single-cycle vs nested multi-iteration). The orchestrator must
  detect and handle both. Document this clearly in `ssd/SKILL.md`.
- Slug-with-`#` syntax requires escaping in shells that interpret `#` (most don't, but `zsh` with
  `extended_glob` might). Document the recommended quoting (`/ssd code 'foo#3b'`).
- Iteration-id collisions: two features each wanting `#3a` is fine because the iter-id namespace is
  scoped to the feature path (`features/<slug>/iterations/<id>/`). Within a feature, the orchestrator
  refuses to create a duplicate iter-id.

**What we give up:**
- The clean "one feature → one cycle" model. The model wasn't actually true in practice — this
  ADR formalizes what was already happening.

## Alternatives Rejected

- **Force every feature to use iterations from day one** (auto-create `iterations/1/` on feature
  start). Rejected: ceremony for the common case. Most features ship in one cycle; making them
  pretend otherwise adds folder depth for no benefit.
- **Iterations as a flat naming convention** (e.g., `<slug>__3a/` as a sibling feature directory).
  Rejected: loses the parent-child relationship. Epic-level briefs and architect docs would have
  to be duplicated or symlinked.
- **A single `iteration: 3a` field in current.yml with no on-disk subtree.** Rejected: the
  artifacts still need somewhere to live. This is exactly the failure mode of the v1 status quo.
- **Migrate flat-layout features into `iterations/0/` automatically the moment a `#1` is requested.**
  Rejected: destructive without consent. The flat artifacts are existing history; rearranging them
  changes git blame, breaks editor bookmarks, and violates the "no silent rewrites" principle from
  ADR-0002.

## Promotion ergonomics

The first time a user references `<slug>#<iter>` for a feature that's currently flat-layout:

```
/ssd code talentos-reimagined-phase3-ui#3b
   ↓
detected: feature 'talentos-reimagined-phase3-ui' is currently flat-layout
          (no iterations/ subdirectory).
proposing: create iterations/3b/ under this feature?
           epic-level artifacts (00-brief.md, 01-architect.md, …) stay at the
           feature root; per-iteration artifacts go in iterations/3b/.
   ↓ confirm
.ssd/features/talentos-reimagined-phase3-ui/iterations/ created
.ssd/features/talentos-reimagined-phase3-ui/iterations/3b/ created
.ssd/current.yml updated: active[].iteration = "3b"
```

Subsequent iterations (`#3c`, `#3d`) skip the prompt.

A user who wants to "regret" the promotion can manually delete the empty `iterations/` directory
and continue flat-layout. The orchestrator never deletes user content.
