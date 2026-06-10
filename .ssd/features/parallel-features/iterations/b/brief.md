---
skill: ssd (orchestrator, /ssd feature, iteration b)
version: 1.15.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features iteration B — the three new orchestrator commands
consumed_by: [architect, coder, code-reviewer]
---

# Brief — Iteration B: Parallel-features commands

## What is being asked

Implement the three new orchestrator commands fully designed in iteration A's architect doc:

- `/ssd feature new <slug> [--branch <name>] [--worktree] [--from <ref>]`
- `/ssd switch <slug> [--no-note | --auto-note]`
- `/ssd worktree <slug> add|remove [--path <path>]`

Plus the supporting documentation updates the architect spec already enumerated:

- `ssd-init/SKILL.md` — mention concurrent-workstream support and write the four new
  `project.yml.ssd.*` defaults at init time.
- `ssd/rails.md` — brief annotation that `/ssd switch` and the pause behavior are intentionally
  non-rail (workflow ergonomics, not a methodology step).

## What does NOT ship in this iteration

- **Cross-workstream overlap warning** at gate time — iteration C.
- **Coder-pass `touches:` backfill** on gate runs — iteration C.
- **`methodology/gate-rules.sh` workstream-aware base-branch detection** — iteration C.

## What this means for "markdown library" commands

This is a markdown skills library — there's no runtime, no compiled commands. The orchestrator
(`/ssd`) is invoked by Claude Code when a user types `/ssd <verb>`, and the *documentation* in
`ssd/SKILL.md` is what tells the LLM how to execute each verb. "Implementing" the three new
commands means:

1. Writing precise behavior specs for each command in `ssd/SKILL.md` (under a new "Workstream
   Lifecycle Commands" sub-section per the iter-A architect spec).
2. Including for each: exact arg syntax, ordered steps, git shell-out invocations, side effects
   on `current.yml` / `current.notes.yml` / artifact tree, every failure mode (FM-1 through
   FM-10 already enumerated in iter A's architect spec).
3. Cross-referencing from the existing `/ssd` (no-arg) decision tree so an LLM reading the
   orchestrator skill can choose the right verb.

No bash scripts, no Python, no compiled artifacts. The "code" is markdown that the LLM reads.

## Acceptance criteria (from ADR-0007's iter B acceptance test plan)

1. **Two-workstream concurrent test** — starting feature B via `/ssd feature new feature-b`
   while feature A is `phase: code` leaves both in `current.yml.active`, each with its own
   branch, each independently runnable through gate + ship.
2. **Switch test** — `/ssd switch feature-b` from feature A's tree captures a handoff note for A
   (per the `switch_note_default` profile-aware behavior), checks out B's branch (or `cd`s to
   B's worktree), and renders B's last `handoff_notes` as starting context.
3. **Worktree opt-in test** — same flow works whether the user opts into a worktree or stays
   single-tree.
4. **No-regression test** — single-workstream flow unchanged: no new prompts, no required
   fields, no new commands surface unless invoked.
5. **Novice walkthrough** — a novice profile user invokes `/ssd feature new` and is walked
   through with confirmations on each destructive step.
6. **Expert walkthrough** — an expert profile user invokes `/ssd switch foo --auto-note` and
   gets silent draft-accept.

## Files in scope

| File | Change | Source spec |
|---|---|---|
| `ssd/SKILL.md` | NEW § "Workstream Lifecycle Commands" between `/ssd ship` and `/Developer Profile`; updates to `/ssd` (no-arg) Step 0 to cross-reference the new commands; version banner 1.15.0 → 1.16.0; changelog entry | iter A architect § "API Contract — New Orchestrator Commands" |
| `ssd-init/SKILL.md` | Two new behaviors: (1) mention concurrent-workstream support in the prerequisite-check narrative, (2) write the four `project.yml.ssd.*` keys with default values at init time | iter A architect § "Files in scope" |
| `ssd/rails.md` | One paragraph noting that `/ssd switch` and `/ssd worktree` are intentionally non-rail (workflow ergonomics) | iter A architect § "Files in scope" |
| `CHANGELOG.md` | v1.16.0 entry | per release convention |
| `VERSION` | 1.15.0 → 1.16.0 | per release convention |

## Out-of-scope (firmly)

- Coder-pass `touches:` diff backfill (iter C)
- Cross-workstream overlap warning (iter C)
- Gate-rules base-branch awareness (iter C)
- Any user-facing `/ssd workstream adopt` or `/ssd workstream set-branch` commands (iter D,
  only if real friction emerges)
- Per-iteration branch-naming convention (e.g., `add-<slug>-<iter>`) — iteration A's
  architect spec didn't address this, and the active workstream's `branch:` field is a free
  string so the orchestrator can record whatever the user picks. Defer formalization.
