# ADR-0003: `rails.md` as the canonical opinionated path

## Status
Accepted — 2026-04-29 — landed in iteration 7 of the ssd-skill-upgrades epic ([epic plan on disk](../../.ssd/features/ssd-skill-upgrades/01-architect.md)).

## Context

SSD has an opinionated default path — the sequence of phases (brief → design → code → review →
gate → deploy → rollout-advance → flag-removal) that produces critic-grade output. Until now, that
sequence existed only as folklore: encoded across `ssd/SKILL.md` § "Phase Playbooks", per-skill
SKILL.md files, and `methodology/core.md`. New users had to reverse-engineer it from how the
orchestrator prompted them.

When iteration 6 (P1.3) introduced no-arg `/ssd` auto-detection, the orchestrator started actively
*proposing* the next step in the sequence. That made the implicit explicit — but the *source* of
the sequence was still scattered. The orchestrator's decision tree in `ssd/SKILL.md` was a
duplication: any change to the rails required syncing the decision tree, the phase playbooks, and
the methodology doctrine.

Beyond the maintainability concern, there was a strategic gap: `code-reviewer` and
`codebase-skeptic` had no first-class object to audit against ("did this feature walk the rails?"
was a question without a programmable answer). And without a named rails document, conversational
and command surfaces had nothing shared to walk — the planned two-surface architecture would
diverge at the first opportunity.

## Decision

Create `ssd/rails.md` as a first-class artifact. It documents:

1. The eight-step canonical sequence (brief → design → code → review → gate → deploy →
   rollout-advance → flag-removal).
2. The eight critic-grade invariants the rails guarantee.
3. The `rail_deviations` logging contract (skipping a step is allowed, but recorded in
   `current.yml.active[].rail_deviations`).
4. The surface-agnostic guarantee: both conversational and command surfaces walk the same rails
   and produce identical artifacts.

`rails.md` is the **single source of truth** for the canonical sequence. The orchestrator's
decision tree, sub-skill cross-references, and review-skill audit checks all cite it. If the
rails change, they change in one place.

A team that wants non-default rails forks `rails.md`, names the variant (e.g., `rails-mobile.md`),
and points `project.yml.rails: rails-mobile.md` at it. The default remains `rails.md` if no
override.

## Rationale

- **Folklore doesn't scale.** Without a named artifact, the rails would continue to drift across
  files. Newcomers would continue to reverse-engineer them from prompts.
- **Auditability.** `code-reviewer` can now flag "this PR adds code outside the rails for step
  X" with a citable reference. `codebase-skeptic` can audit a shipped feature against the eight
  critic-grade invariants programmatically.
- **Two-surface alignment.** The plan's Part II two-surface strategy (P2.B's profile +
  conversational vs command) requires a shared rails source. Without one, surfaces diverge.
- **Forkable.** A team with genuinely different needs can fork `rails.md` and reference the fork
  from `project.yml`. The default doesn't have to suit every consumer.
- **Short and stable.** `rails.md` is intentionally short (~150 lines) so it stays readable and
  changes infrequently. It's the schedule, not the doctrine.

## Consequences

**Easier:**
- New users have one file to read to understand SSD's default flow.
- Auditors and reviewers have a canonical object to cite.
- Conversational and command surfaces share a single source.
- Customization is well-bounded (fork the file, point `project.yml` at the fork).

**Harder:**
- One more file to keep in sync if the rails change. Mitigated by making the file the *only*
  place the sequence lives — other docs reference it rather than duplicating it.
- Teams that adopt forked rails create a divergence the SSD orchestrator must handle.
  `project.yml.rails:` defaults to the standard file; forks are explicit and visible.

**What we give up:**
- The freedom to evolve the rails by editing whichever file was nearest. Now any change goes
  through `rails.md`. This is a feature, not a bug.

## Alternatives Rejected

- **Continue with the rails as folklore.** Status quo. Doesn't scale to teams or to the
  two-surface architecture.
- **Embed the rails inside `ssd/SKILL.md`.** The orchestrator's SKILL.md is already the longest
  in the repo. Adding the rails compounds the readability problem and entangles "how the
  orchestrator works" with "what the canonical sequence is." Separate files separate concerns.
- **Embed the rails inside `methodology/core.md`.** Doctrine ("why ship in small increments") and
  schedule ("steps are: brief, design, ...") are different layers. Conflating them makes both
  harder to evolve.
- **Generate `rails.md` from `ssd/SKILL.md` + sub-skills.** Tempting but premature: 8 steps is not
  enough material to justify a generator. A single hand-edited file is more maintainable until
  the rails get substantively more complex.
- **Make `rail_deviations:` a hard gate** (block the workstream on N+ deviations). Rejected for
  v1.0.0 — deviations are engineering judgment; gating them invites users to lie. The field is a
  signal, not a control. A team that wants enforcement can extend `gate-rules.sh`.

## Future evolution

If the rails change, ADR-0003 stays as the rationale; the change is reflected in `rails.md` itself
and in the per-skill SKILL.md files that cite it. Versioning: `rails.md` carries its own
`Version:` line. A team that forks `rails.md` is on their own version line; the SSD orchestrator
respects whichever rails the project's `project.yml` points at.

The rails are not democracy — they're an opinionated default. Forks are allowed precisely so that
the default can stay opinionated rather than diluted.
