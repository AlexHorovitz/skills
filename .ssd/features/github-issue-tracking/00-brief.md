---
skill: ssd
version: 2.2.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: feature github-issue-tracking
consumed_by: [architect, coder, code-reviewer]
---

# Brief — github-issue-tracking

## Ledger
To be tracked on a GitHub **epic** issue authored alongside this feature's ADR, per the
[ADR-0011](../../../docs/decisions/ADR-0011-decision-record-doctrine.md) decision-record doctrine.
This feature is **self-referential**: it defines the ADR↔epic / task↔issue convention, so its own
tracking issue is the first instance of the convention it ships (bootstrap). Issue creation is an
outward-facing action and stays under explicit human confirmation — the brief does not auto-open it.

## Problem
SSD workstream state lives entirely in `.ssd/current.yml` (active workstreams, `phase`, `gate_rounds`,
`adrs_authored`, archive summaries). That state is **invisible to anyone not sitting at the
developer's checkout** — a teammate, a reviewer, or future-self browsing GitHub sees no live picture
of what's in-flight, what phase it's at, or how the ADRs decompose into shippable tasks.

The repo *already* reaches for GitHub issues to fill this gap, but **by hand and inconsistently**:
issue [#15](https://github.com/AlexHorovitz/skills/issues/15) is the SSD 2.0 epic with a manually
maintained revisit ledger; [#17](https://github.com/AlexHorovitz/skills/issues/17) tracks
`ssd-upgrade`. There is no convention for how an ADR, its tasks, and its workstream map onto issues,
and nothing keeps those issues in sync as phases advance or closes them when work completes. The
mapping is folklore, the upkeep is manual, and it drifts.

## Goal
Let a developer **opt in** (a `project.yml` toggle) to having SSD treat GitHub issues as a live,
auto-maintained mirror of workstream state, structured as a two-level hierarchy:

- **ADR → Epic issue.** Each accepted ADR is represented by a GitHub issue labeled `epic`. The epic
  is the durable home for the decision and its revisit ledger (extends ADR-0011 doctrine onto GitHub).
- **Task → Task issue.** The concrete tasks that implement an ADR (typically one per workstream /
  iteration) are issues linked to the epic (sub-issue / tracked-task relationship), each carrying the
  workstream's live `phase` and `gate_rounds`.
- **Auto-sync on phase advance.** Every `/ssd` phase transition (brief → design → code → review →
  gate → deploy → …) updates the corresponding task issue. No manual sync step.
- **Lifecycle close-up.** As a workstream reaches `done`, `/ssd` closes its task issue. When **all**
  task issues under an epic are closed, `/ssd` closes the epic.

Authority is **one-way**: local `.ssd/` state is the source of truth and *drives* GitHub (create,
update, close). SSD does not read issue state back to mutate workstreams in this scope — that keeps
the model conflict-free and shippable. (Bidirectional sync is explicitly out of scope; see below.)

## What shipping this looks like
A developer sets `integrations.github.issue_tracking: on` (off by default). On the next `/ssd`
phase advance, SSD ensures the workstream's task issue exists and reflects the current phase, and
that its parent epic issue (the ADR) exists. When the workstream is archived, the task issue closes;
when the last task under an epic closes, the epic closes. With the toggle off, behavior is byte-for-byte
unchanged from today (the safety property that lets this ship without a flag-gated rollout risk).

## Scope decisions (user-ratified 2026-06-14)
- **Hierarchy:** ADR = epic issue; implementing tasks = task issues tied to the epic. ✅
- **Trigger:** automatic on every phase advance. ✅
- **Granularity:** one task issue per workstream (mirrors the ADR-0007 parallel-workstream model),
  nested under the ADR's epic. ✅
- **Authority:** SSD → GitHub only (create / update / close). ✅

## Out of scope (deliberately, to stay shippable)
- **Bidirectional sync** — reading issue state back to drive workstream changes (close issue →
  archive workstream). Needs conflict resolution; defer to a follow-up iteration if wanted.
- **Backfilling** existing archived workstreams into issues.
- **Non-GitHub trackers** (GitLab, Jira). The toggle is GitHub-specific for now.

## Design sketch (the architect resolves; do not pre-decide)
- **State binding:** new optional fields on `current.yml.active[]` — `issue:` (task issue number)
  and `epic:` (parent epic issue number, derived from the workstream's `adrs_authored`). Lazily
  backfilled, exactly like the `branch:` field (ADR-0007 precedent).
- **Sync mechanism:** the orchestrator shells out to `gh` (already the SSD-sanctioned GitHub CLI).
  Idempotent: "ensure issue exists / matches", never "create blindly". Must degrade cleanly when
  `gh` is absent or unauthenticated, and when `issue_tracking: off` (skip entirely).
- **ADR↔epic resolution:** how an ADR maps to exactly one epic issue, and how a task discovers its
  epic. Candidate: a `tracking:` block in the ADR front matter, or a lookup by `epic` label +
  ADR id in the title.
- **Outward-action safety:** per SSD doctrine (`/ssd ship` tagging precedent), automatic issue
  *creation* touches the remote — the architect must decide whether first-time creation prompts once
  vs. is fully automatic under the toggle. Closing an epic is the highest-stakes auto-action.
- **Gate interaction:** whether a new gate rule (`issue-sync-current`) should warn when tracking is
  on but the issue diverged from local state — analogous to `migration-manifest-current`.
- **Dogfood:** this repo flips the toggle on and this very feature becomes the first ADR-epic +
  task-issue pair created by the system.

## Success criteria
1. `integrations.github.issue_tracking: off` (default) → zero behavior change, zero network calls.
2. With it on, advancing a workstream's phase creates/updates a task issue and its parent epic
   idempotently (re-running a phase does not duplicate issues).
3. Archiving a workstream closes its task issue; closing the last task under an epic closes the epic.
4. Graceful degradation when `gh` is missing/unauthenticated (warn, never crash a phase).
5. An ADR documents the convention; the feature is itself tracked under that convention (dogfood).
