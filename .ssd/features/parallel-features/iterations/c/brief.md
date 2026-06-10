---
skill: ssd (orchestrator, /ssd feature, iteration c)
version: 1.16.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features iteration C — consume the touches field at gate time
consumed_by: [architect, coder, code-reviewer]
---

# Brief — Iteration C: parallel-features overlap detection

## What is being asked

Make iteration A's `touches:` field load-bearing by consuming it at `/ssd gate` time. Three
deliverables, all designed in iter A's architect spec under "Overlap Warning":

1. **Coder-pass `touches:` backfill** on gate runs. When `/ssd gate` runs, the orchestrator
   unions `git diff --name-only <base>...HEAD` into the workstream's `current.yml.active[<slug>].touches`
   list. Empty + diff-only = the diff. Existing touches + diff = union. Architect-intent
   paths that haven't been touched yet stay in the list.

2. **Cross-workstream overlap check** in `code-reviewer/SKILL.md`. New OVERLAP-N finding
   category at SUGGESTION tier (never BLOCKER, never MAJOR — soft warning by design). Triggered
   when two or more active workstreams declare globs that intersect via `git ls-files`.

3. **`methodology/gate-rules.sh` workstream-aware base detection.** The current `--base main`
   default is correct for single-workstream flow but should respect a workstream's recorded
   base when present. Today this is a documentation note in iter A; in iter C the gate-rules
   script reads `current.yml.active[<current-branch>].base` if a future schema adds one, OR
   continues to default to `main` when nothing's recorded. Concretely: minimal change — verify
   the existing `--base` resolution doesn't silently mishandle worktree contexts.

## What does NOT ship in this iteration

- New orchestrator commands — iteration B shipped those.
- Schema changes — `touches:` already exists from iter A. No new fields added.
- Hard gate enforcement on overlap — by design, OVERLAP-N is SUGGESTION-tier (per ADR-0007
  alternatives-rejected: "MAJOR-tier overlap warnings" rejected).
- Multi-workstream gate orchestration changes — running `/ssd gate <slug>` still gates one
  workstream; cross-workstream consultation is read-only.

## Acceptance criteria (from ADR-0007 iter C acceptance)

1. **Overlap warning test** — two synthetic active entries with `touches: [foo.md]` produce a
   SUGGESTION-tier finding on each workstream's gate. No BLOCKER/MAJOR/MINOR.
2. **Empty-touches no-op test** — workstreams with `touches: []` produce zero overlap findings
   (no false positives during early-lifecycle workstreams).
3. **Self-exclusion test** — a workstream's `touches:` is never intersected against itself
   (single-workstream flow stays warning-free).
4. **Diff backfill test** — after running `/ssd gate`, the current workstream's `touches:` field
   includes every path in `git diff --name-only <base>...HEAD`, unioned with whatever was
   already there.
5. **No-regression test** — gate-rules.sh's five existing rules behave identically.

## Files in scope

| File | Change | Source spec |
|---|---|---|
| `code-reviewer/SKILL.md` | NEW § "Cross-Workstream Overlap Check" (~40 lines) + OVERLAP-N format added to the finding-tier discussion | iter A architect § "Overlap Warning" |
| `ssd/SKILL.md` | Two-line addition to § "Methodology Enforcement" naming the overlap check as part of the gate; touches-backfill documented in § "Session Continuity" near the existing `touches:` field doc | iter A architect § "Q4 — touches population" |
| `methodology/gate-rules.sh` | Optional `current.yml`-aware base detection (a few lines added near the existing `--base` parsing). Default behavior unchanged. | iter A architect § "Files in scope" |
| `CHANGELOG.md` | v1.17.0 entry | per release convention |
| `VERSION` | 1.16.0 → 1.17.0 | per release convention |

## Out-of-scope

- Iteration D commands (`adopt`, `set-branch`, `handoff`).
- Schema changes (no new fields).
- Hard overlap blocking (architecturally rejected).
- Auto-resolving merge conflicts (firmly OOS).

## Open questions for architect

1. **`gate-rules.sh` base detection scope.** Iter A's architect listed "workstream-aware base
   detection" but didn't fully spec it. Concretely: when `/ssd gate` is invoked from a
   workstream's branch, should `gate-rules.sh` derive `--base` from the workstream entry, or
   stay with `--base main` as the documented default? Recommend: document the workstream-base
   pattern; don't change the script's default behavior (the orchestrator can pass `--base`
   explicitly).
2. **OVERLAP-N tier severity.** Confirmed SUGGESTION in iter A. Confirm no second-thought.
3. **Glob intersection mechanism.** Iter A's architect proposed `git ls-files <glob>` for each
   side then set-intersect. Confirm this is the implementable approach and document any
   edge cases (e.g., globs containing `**`).
