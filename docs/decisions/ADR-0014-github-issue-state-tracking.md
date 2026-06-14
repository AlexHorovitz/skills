# ADR-0014: GitHub issue state tracking (ADR = epic, workstream = feature issue)

## Status
Proposed — 2026-06-14. Drives the `github-issue-tracking` feature
([01-architect.md](../../.ssd/features/github-issue-tracking/01-architect.md)). Recorded under the
[ADR-0011](ADR-0011-decision-record-doctrine.md) decision-record doctrine. **Self-referential:** this
ADR is the first epic the convention describes — its own epic issue + this workstream's feature issue
are the dogfood instance (see § "Bootstrap").

## Context
SSD workstream state lives only in `.ssd/current.yml` — invisible to anyone not at the developer's
checkout. The repo already reaches for GitHub issues to fill the gap, but by hand and inconsistently
(#15 = SSD 2.0 epic with a hand-maintained revisit ledger; #17 = `ssd-upgrade`). There is no
convention for how an ADR, its implementing tasks, and the workstream map onto issues, and nothing
keeps them in sync as phases advance or closes them when work completes.

Constraints:
- This is a **markdown skills library with no runtime**. The "mechanism" is orchestrator + skill prose
  + a bash helper, following the `gate-rules.sh` / `migrate.sh` precedent — not application code.
- Outward-facing remote actions (issue create/close send notifications) must stay under the SSD
  safety doctrine: the same doctrine that keeps `/ssd ship` release-tagging human-gated.
- The default-off path must be **byte-for-byte identical to today** — zero network calls, zero
  behavior change — so the feature ships without rollout risk.
- `gh` (GitHub CLI) is already the SSD-sanctioned GitHub tool and is present + authenticated in this
  repo's environment.

## Decision
Introduce an **opt-in** (`integrations.github.issue_tracking: on`, default `off`) mode in which SSD
treats GitHub issues as a **one-way, auto-maintained mirror** of workstream state, structured as a
two-level hierarchy:

1. **ADR → Epic issue.** Each ADR is represented by one GitHub issue labeled **`ssd:epic`**, titled
   `[ADR-NNNN] <decision title>`. The epic is the durable GitHub home for the decision and its
   revisit ledger (extends ADR-0011 onto GitHub).
2. **Workstream → Feature issue.** Each workstream (the tasks implementing an ADR) is one issue
   labeled **`ssd:feature`**, linked to its epic, carrying a **`ssd:phase/<phase>`** label that
   tracks the live `current.yml` phase.
3. **Auto-sync on phase advance.** Every `/ssd` phase transition ensures the feature issue exists,
   re-labels its `ssd:phase/*`, and refreshes a machine-managed body block. The epic is ensured to
   exist whenever its ADR is authored.
4. **Lifecycle close-up.** When a workstream reaches `done`, SSD closes its feature issue. When the
   **last** feature issue under an epic closes, SSD closes the epic.

**Authority is one-way:** local `.ssd/` state is the source of truth and drives GitHub (create /
update / close). SSD does **not** read issue state back to mutate workstreams in this scope.
Bidirectional sync is explicitly deferred.

### Resolution of the three open design questions (from the brief)

**Q1 — ADR↔epic resolution.** *Title + label is the discovery key; `current.yml` caches the binding.*
- The workstream's existing `adrs_authored:` list names its ADR(s). The epic is discovered by
  `gh issue list --label ssd:epic --search "[ADR-NNNN] in:title"`.
- The resolved epic issue number is cached in a new `epic:` field on the workstream entry (lazy
  backfill, exactly the `branch:` precedent from ADR-0007). The feature issue number is cached in a
  new `issue:` field. Caching makes steady-state sync a single `gh issue edit`, no search.
- Rejected: storing the binding *inside* the ADR markdown front matter. ADRs are human-authored prose
  records; threading a machine-mutated `epic_issue:` field into them invites merge churn and couples
  the immutable decision record to mutable remote state. The title convention is enough to rediscover
  the binding if the `current.yml` cache is ever lost.

**Q2 — outward-action safety (create prompt vs fully automatic).** *The toggle is the consent for
additive actions; destructive/notifying actions are gated.*
- **Create + update** (issue create, label change, body refresh) are **automatic** under the toggle —
  they are additive and low-stakes; turning `issue_tracking: on` is the durable authorization.
- **Close** (feature issue, and especially the epic) is gated behind a sub-toggle
  `integrations.github.auto_close` (default `false` → **prompt once per close**). Closing an epic
  fans out notifications and is the highest-stakes auto-action; SSD's "outward + hard-to-reverse →
  confirm" principle applies. Reopening is cheap, so the gate is a prompt, not a hard block.
- This mirrors the `/ssd ship` tagging precedent: the orchestrator never silently performs an
  outward action the user didn't either pre-authorize (toggle) or confirm in-session.

**Q3 — `issue-sync-current` gate rule.** *Yes, but informational and SKIP-by-default, staged to iter B.*
- A new gate rule `issue-sync-current` checks, when `issue_tracking: on`, that each active
  workstream's cached `issue:` is open and its `ssd:phase/*` label matches `current.yml.phase`.
- It **SKIPs cleanly** when tracking is off, `gh` is unavailable/unauthenticated, or the repo has no
  `issue:` bindings (i.e. every project except an opted-in one) — the `migration-manifest-current`
  precedent.
- It FAILs only on a *hard* inconsistency (recorded issue is closed while the workstream is active,
  or phase-label mismatch) — consistent with "the issue is a mirror, not a source of truth." Deferred
  to **iteration B** to keep iter A's surface tight.

## Rationale
- **Reuses existing substrate.** `adrs_authored:` already exists; `epic:`/`issue:` follow the proven
  optional-field + lazy-backfill pattern (`branch:`, ADR-0007). No schema-version bump.
- **Idempotent by construction.** "Ensure issue exists / matches" (search-or-create, edit-in-place)
  never duplicates on re-run — the same property `migrate.sh` relies on.
- **Default-off = zero blast radius.** The entire feature is dormant until a project opts in, so it
  ships on the 1.x line with no rollout risk and no migration for existing projects.
- **One-way authority sidesteps the hard problem.** No conflict resolution, no "issue edited on
  GitHub vs locally" reconciliation — the thing that would have made bidirectional sync a multi-week
  feature. SSD already treats local `.ssd/` as canonical.

## Consequences
**Easier:** teammates/reviewers/future-self see live workstream state on GitHub; ADRs gain a durable,
linkable home with their implementing tasks tracked beneath; the #15/#17 hand-maintenance becomes a
convention the tooling upholds.

**Harder / costs:** SSD now has an outward-facing side effect on phase advance (mitigated: opt-in,
additive-only auto, gated close, graceful `gh`-absent degradation). A new bash helper
(`methodology/issue-sync.sh`) joins `gate-rules.sh`/`migrate.sh` as maintained infrastructure. Label
taxonomy (`ssd:epic`, `ssd:feature`, `ssd:phase/*`) becomes part of the public convention.

**Give up:** bidirectional sync (issue → workstream) and non-GitHub trackers — both explicitly out of
scope, revisitable in a follow-up.

## Bootstrap (dogfood)
The convention is applied to itself immediately, by hand, before the helper exists:
- **Epic issue** `[ADR-0014] GitHub issue state tracking`, label `ssd:epic`.
- **Feature issue** for the `github-issue-tracking` workstream, label `ssd:feature` +
  `ssd:phase/design`, linked to the epic, with `epic:`/`issue:` cached in `current.yml`.
This is the first instance the convention produces and the live test fixture for the helper built in
the Code phase.

## Alternatives Rejected
- **Bidirectional sync** — reading issue state back to drive workstreams. Needs conflict resolution;
  multiplies scope; defer.
- **Binding stored in ADR front matter** (vs `current.yml` cache + title discovery) — couples
  immutable decision records to mutable remote state; merge churn. Rejected (Q1).
- **Fully-automatic close (no gate)** — violates the outward-action safety doctrine for the
  highest-stakes, notification-fanning action. Rejected (Q2); gated behind `auto_close`.
- **A single project dashboard issue** (vs one issue per workstream) — loses per-feature discussion
  threads and the natural epic→task hierarchy; doesn't match the ADR-0007 parallel-workstream model.
  Rejected at brief time by the user.
- **Custom GitHub API client** instead of `gh` — re-implements auth/pagination SSD already gets free
  from the sanctioned CLI. Rejected (Boring Technology Wins).
