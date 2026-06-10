---
skill: ssd (orchestrator, /ssd feature)
version: 1.14.0
produced_at: 2026-05-21T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: enable working on multiple SSD features concurrently without per-switch git ceremony
consumed_by: [architect, coder, code-reviewer]
---

# Brief — Parallel Features

## What is being asked

> "I would like to be allowed to work on multiple features at once. Please help me
> restructure the overall project to enable multiple features in flight at the same time."

Today, working on more than one SSD feature simultaneously is *technically* supported by the
schema (`current.yml.active` is a list, the no-arg orchestrator already surfaces multiple
workstreams) but is *operationally* awkward:

- One working tree → one branch → one feature edit at a time. Switching mid-flight requires
  stash/checkout/restore dance, which discourages true parallel work.
- The orchestrator doesn't know which active workstream the current branch corresponds to —
  branch ↔ feature mapping lives only in the user's head.
- No "pause and switch" ergonomics. Handoff notes exist in `current.notes.yml` but there's no
  command to trigger a snapshot when stepping away from feature A to pick up feature B.
- No conflict awareness: two features touching the same files don't surface that overlap until
  rebase time.
- No worktree lifecycle integration. A user who *does* want isolated working dirs has to set
  them up by hand and remember to clean up.

## Goal

Make running 2–4 concurrent feature workstreams a first-class workflow. The user should be able
to:

1. Start feature B while feature A is mid-build, with one orchestrator command that creates the
   branch (and optionally a git worktree), updates `current.yml`, and seeds the artifact tree.
2. Resume any active workstream by name, with the orchestrator handling branch/worktree
   selection and surfacing the last handoff note as starting context.
3. Pause the current workstream and capture a handoff note in one step before switching.
4. See, at a glance, which active workstreams overlap on the same files (for gate-time conflict
   awareness, not as a hard block).
5. Run `/ssd` from inside any worktree and have the orchestrator auto-identify which workstream
   is in scope from the branch name.

## Non-goals

- **Multi-user / multi-machine coordination.** Single-developer workflow only.
- **Replacing git.** No bespoke locking, no Claude-managed branches that bypass `git`. Worktrees
  and branches remain plain git artifacts.
- **Forcing worktrees.** A user who prefers single-tree + stash should still be able to work
  that way. Worktree integration is opt-in per workstream.
- **Cross-feature dependency resolution.** If feature B depends on feature A's API, the user
  still serializes them manually — we surface awareness, not automation.
- **Changing the shippable-state invariant.** Each workstream still ships independently. No
  "two features in one PR" shortcuts.

## Likely deliverables (subject to architect refinement)

- New ADR (ADR-0007): branch + worktree as first-class workstream artifacts.
- New orchestrator commands:
  - `/ssd feature new <slug>` — create branch (and optionally worktree) + brief scaffold +
    `current.yml` entry in one step.
  - `/ssd switch <slug>` — pause the current workstream (capture handoff note), check out the
    target workstream's branch/worktree, render its starting context.
  - `/ssd worktree <slug> add|remove` — explicit worktree lifecycle.
- Schema additions to `current.yml.active[]`:
  - `branch:` — required; the git branch for this workstream.
  - `worktree:` — optional absolute path if the workstream uses a worktree.
  - `touches:` — optional list of file globs the workstream is known to modify (populated by
    architect, used for cross-workstream conflict awareness).
- Auto-detection: branch ↔ slug mapping via convention (`add-<slug>` / `feature/<slug>` etc.) so
  `/ssd` invoked on any branch resolves to the right workstream without flags.
- Updates to SKILL.md sections: "Session Continuity," "/ssd (no-arg) — Auto-Detect," and the
  artifact tree (worktree paths sit outside the repo, but `current.yml` tracks them).
- Updates to `methodology/gate-rules.sh`: nothing to change in the rules themselves, but the
  gate must run against the workstream's branch, not whatever happens to be checked out.

## Acceptance criteria

1. **Two workstreams concurrent test** — Starting feature B while feature A is `phase: code`
   leaves both in `current.yml.active`, each with its own branch, each independently runnable
   through gate + ship.
2. **Switch test** — `/ssd switch feature-b` from feature A's working tree captures a handoff
   note for A, checks out B's branch (or `cd`s to B's worktree), and renders B's last
   `handoff_notes` as starting context. No uncommitted changes lost.
3. **Auto-detect from branch test** — Running `/ssd` (no-arg) on branch `add-feature-b` resolves
   to feature-b without any prompt asking "which workstream?"
4. **Overlap warning test** — Two active workstreams whose architect specs both declare
   `touches: [src/foo.ts]` produce a non-blocking warning at gate time on either workstream.
5. **Worktree opt-in test** — Same flow works whether the user opts into a worktree or stays
   single-tree. No flow forces worktrees.
6. **Schema backward-compat test** — Existing v2 `current.yml` files without `branch:` /
   `worktree:` / `touches:` keys still parse; the orchestrator infers `branch:` lazily on next
   touch.
7. **No-regression test** — Single-workstream flow (the default for novices and small projects)
   is unchanged: no new prompts, no required fields, no new commands surface unless invoked.

## Files in scope (preliminary)

- `ssd/SKILL.md` — new commands, schema fields, branch auto-detection
- `ssd/rails.md` — may add a "pause/switch" annotation step (or explicitly mark it as non-rail)
- New: `docs/decisions/ADR-0007-parallel-features.md`
- New: `ssd/worktree-helpers.sh` (or equivalent) if branch/worktree creation is shelled out
- `methodology/gate-rules.sh` — branch-aware base detection (already mostly there)
- `ssd-init/SKILL.md` — mention concurrent-workstream support in the init narrative

## Open questions for architect

1. **Branch naming convention** — is `add-<slug>` (current `add-adr-0006` style) the canonical
   pattern, or do we want `ssd/<slug>` namespacing? Pick one and codify.
2. **Where do worktrees live by default** — sibling-of-repo (`../skills-<slug>/`) or under a
   parent directory? Allow override via project.yml?
3. **Handoff-note capture on switch** — automated (orchestrator drafts from recent activity) or
   prompt the user? Hybrid?
4. **`touches:` population** — does architect compute it from the spec, or does coder backfill
   it from actual diff at first commit? Both?
5. **Interaction with iterations** — `<slug>#<iter>` already handles in-feature iterations; do
   we ever want parallel iterations of the same feature? (Probably no — out of scope.)

## Out-of-scope (firmly)

- Plan-mode integration
- Cross-project parallelism (multi-repo orchestration)
- Replacing git worktrees with anything bespoke
- Auto-resolving merge conflicts
