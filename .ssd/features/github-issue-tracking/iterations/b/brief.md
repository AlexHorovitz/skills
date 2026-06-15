---
skill: orchestrator
phase: brief
feature: github-issue-tracking
iteration: b
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
epic: 27
parent_adr: ADR-0014
---

# Brief — github-issue-tracking iter B

## Why now
Iter A (v2.3.0, PR #29) shipped the opt-in one-way mirror: `preflight` / `ensure-epic` /
`ensure-feature` / `set-phase` in `methodology/issue-sync.sh`, the `epic:`/`issue:` cache on
`current.yml`, the `project.yml` toggles, and the orchestrator auto-sync prose. The `close-*`
subcommands were **stubbed** (exit 2) and the close lifecycle deferred here. ADR-0014
§ "Suggested iteration split" scopes iter B; the iter A handoff note enumerates the carry-overs.

## Scope (this iteration)
1. **`close-feature <issue#> [--confirm]`** — close the feature issue when a workstream reaches
   `done`. Gated behind `integrations.github.auto_close` (default `false` → emit intent + exit 10
   so the caller prompts once; `true` or `--confirm` → close). Idempotent: already-closed → exit 0.
2. **`close-epic <epic#> [--confirm]`** — close the epic only when **all** child `ssd:feature`
   issues are closed (child discovery = `ssd:feature` label + `Epic: #<n>` body reference, **not**
   the task list — MINOR-2 amendment) **and** the close gate (`auto_close`/`--confirm`) is
   satisfied. The **"open planned iterations" guard** (epic #27 stayed open after #28 closed
   because iter B was still planned) is owned by the **orchestrator** — it only proposes
   `close-epic` once local `.ssd/` shows no further planned iteration for the epic. See the iter B
   architect spec for the split-of-responsibility rationale.
3. **`issue-sync-current` gate rule** (ADR-0014 Q3) — informational, SKIP-by-default. SKIPs when
   tracking off / `gh` unavailable / no `issue:` bindings; FAILs only on a hard inconsistency
   (recorded issue closed while workstream active, or phase-label mismatch).
4. **`migrations.yml` entry + `ssd-init` template keys** for `integrations.github.issue_tracking`
   / `auto_close` so a v1-era or fresh project learns the toggles via `/ssd upgrade` / init.
5. **README convention docs** + **`methodology/SKILL.md` script-catalog row** for `issue-sync.sh`.
6. **MINOR-2 data-model amendment** to ADR-0014: child-tracking is the `ssd:feature` label query,
   not the epic task list (the iter A `ensure-feature` already links by body mention).
7. **mock-`gh` unit harness** + parity fixtures: first real test coverage for `issue-sync.sh`
   (iter A shipped with `bash -n` only) plus the new gate rule.

## Out of scope (unchanged from ADR-0014)
- Bidirectional sync (issue → workstream). One-way authority stands.
- Non-GitHub trackers.
- Richer body block beyond what `set-phase`/`close-*` need (the architect's "Gate rounds"/"Branch"
  fields are optional polish; include only if cheap).

## Definition of done
Off-path byte-for-byte unchanged (zero network when toggle absent/off). `close-*` no longer stubbed;
gate rule SKIPs cleanly on every project except an opted-in one. parity-test green with new
assertions. Dogfooded against epic #27 (kept open via the orchestrator guard; closes only when iter
B itself ships and no further iteration is planned).
