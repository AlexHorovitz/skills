# ADR-0011: Decisions are recorded as an ADR + a revisit-aware GitHub Issue

## Status
Accepted — 2026-06-13. Adopted in practice immediately; dogfooded on
[issue #15](https://github.com/AlexHorovitz/skills/issues/15) (the SSD 2.0 epic), whose own
decision to exist is recorded under this pattern.

## Context

SSD already commits ADRs (`docs/decisions/`) — they capture *why* a decision was made, durably and
versioned in the diff. But ADRs have two gaps:

1. **They are invisible to people who depend on the repo without cloning it.** A downstream consumer
   of the skills library can't watch `docs/decisions/` the way they can watch a GitHub Issue list.
2. **They are static.** An ADR records the decision at a point in time; it does not surface *under
   what future conditions the decision should reopen.*

SSD tried to capture that second thing — "when do we revisit?" — with the deferred-revisit items
(`NOTES-PF-1`, `NOTES-CSP-1`) carrying `review_window` dates. They rotted: they live in
`current.notes.yml`, which is gitignored and which nobody rereads on schedule. The mechanism existed;
the *surfacing* didn't.

We want every consequential decision to answer three questions, transparently, for everyone who
depends on the codebase: **what happened, why, and under what conditions we'd revisit it.**

## Decision

Every consequential decision is recorded in **two cross-linked places**, each owning a different
question:

| Layer | Lives | Owns the question | Lifespan |
|---|---|---|---|
| **ADR** | committed `docs/decisions/` | **why** (context, alternatives, consequences) | durable / versioned |
| **GitHub Issue** | the project's issue tracker (public) | **what happened** (timeline) + **when to revisit** | live / time-aware / multi-party |

- The ADR links its tracking Issue; the Issue links the ADR. **The ADR is source-of-truth for
  *why*; the Issue is source-of-truth for *current status and reopen conditions*.** Neither
  duplicates the other.
- Every such Issue carries a mandatory **`Revisit when:`** section — a list of *falsifiable*
  reopen-triggers ("reopen this if X happens"). This is the load-bearing new primitive: **no
  decision is a black box; each states the evidence that would overturn it.**
- **The supersession loop:** when a `Revisit when:` trigger fires → reopen the Issue → author a new
  ADR that supersedes the old → mark the old ADR `Superseded by ADR-NNNN` (never delete it). The
  history of *what changed and why* stays auditable end to end.
- **Privacy boundary:** artifacts that are intentionally gitignored (audit reports under
  `.ssd/audits/`, machine state) stay local. The Issue carries the *summary and verdict*, not the
  gitignored artifact. (Learned while dogfooding on #15: the 2.0 audit is local; its verdict lives
  in an issue comment.)

**`Revisit when:` is also the reversibility contract for hard cuts.** When a decision *removes*
something (a subsystem, a command, a guarantee), its triggers state the criteria under which it
returns. That turns a one-way door into a falsifiable, reversible decision — the Wozniak-elegant
property that nothing is removed on faith.

## Scope and degradation

- Applies to **consequential** decisions — the same bar that already earns an ADR (the architect
  skill's "always-ADR" list, plus anything a future engineer would ask "why?" about). Routine work
  does not need an Issue.
- **GitHub is the ledger, never the gate.** `gate-rules.sh`, the overlap check, and the artifact
  tree do not depend on the issue tracker; they remain local and offline-capable.
- **Projects without GitHub** degrade cleanly: the ADR carries the `Revisit when:` section inline,
  and the surfacing is whatever tracker the project uses (or none). The pattern is "ADR + a
  revisit-aware, watchable record"; GitHub Issues are the default instrument, not a hard dependency.

## Consequences

- Decisions become transparent to dependents who never clone the repo.
- Hard cuts become reversible-by-stated-criteria instead of bets.
- The rotting `NOTES-*` revisit items get promoted from buried YAML to surfaced, dated Issues that
  the tracker actually resurfaces.
- New cost: a lightweight per-decision Issue and the discipline of writing falsifiable triggers.
  This is the practice the `ssd-github-issues` feature later automates (its sharpened iter-A scope).

## Alternatives rejected

- **ADR-only (status quo).** Keeps *why* but leaves *when-to-revisit* uncaptured and the record
  invisible to non-cloners. The gap this ADR exists to close.
- **Notes-file revisit windows.** Already tried (`NOTES-PF-1/CSP-1`); rots in gitignored YAML. Proven
  insufficient.
- **Issue-only.** Loses the durable, diff-versioned *why* and couples the decision record to a
  single vendor. The ADR must remain the authoritative, in-repo source of reasoning.
