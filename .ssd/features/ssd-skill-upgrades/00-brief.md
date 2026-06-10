---
skill: ssd (orchestrator, /ssd feature)
version: 1.3.0
produced_at: 2026-04-28T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: implement upgrades described in real-world-artifacts/ssd-upgrades-plan.md
consumed_by: [architect, systems-designer, coder, code-reviewer]
---

# Brief — SSD Skill Upgrades

## Source
[real-world-artifacts/ssd-upgrades-plan.md](../../../real-world-artifacts/ssd-upgrades-plan.md) — 343-line strategic proposal authored from athena working sessions through 2026-04-28.

## What is being asked

Two stacked proposals:

**Part I — seven engine upgrades** (path-of-least-friction):
1. First-class iterations inside a feature (`iterations/<id>/` subtree, `<slug>#<iter-id>` resolution)
2. Multi-round gates as a built-in (auto-numbered `code-review/round-N.md`, `gate_rounds:` counter, `closed:`/`still_open:` frontmatter)
3. Single `/ssd` command with phase auto-detection (no-arg becomes primary entrypoint)
4. Collapse `architect` + `systems-designer` into a single "design" pass
5. Structured carry-over ledger (`deferred.yml` per-feature/per-iteration)
6. Real (executable) gate automation — turn methodology rules into a bash routine
7. Split `current.yml` into machine-managed + human-notes sidecar

**Part II — strategic reframing**:
- Two surfaces (conversational / command) over one engine; identical artifact output guaranteed
- `rails.md` as a first-class artifact documenting the canonical sequence
- `developer_profile: novice | standard | expert` field with profile-aware defaults
- Teaching mode (decaying narration) for the first N invocations
- `.ssd/hooks.yml` for project-level event automation
- Anti-drift rules + a parity test harness comparing artifact trees from both surfaces

## Acceptance criteria (from the plan)
1. Iteration test — `/ssd` no-arg surfaces active workstreams, identifies current phase, proposes next action.
2. Multi-round gate test — synthetic BLOCKER produces `round-1.md`, fix produces `round-2.md` with `closed: [BLOCKER-1]`.
3. Carry-over test — deferred MINOR auto-loads as coder context in next iteration.
4. Real gate test — WIP commit fails `/ssd gate` with methodology cite.
5. Design bundling test — single design phase produces both `01-architect.md` and `02-systems-designer.md`.
6. No regressions — existing athena `current.yml` still parses.
7. Two-surface parity test — same feature built via both surfaces produces identical artifact trees.
8. Novice walkthrough — fresh user ships hello-world without reading `SKILL.md` or seeing YAML.
9. Expert walkthrough — same feature shipped scripted with CI hook firing on deploy, byte-identical output.

## Files in scope (per the plan)
- `ssd/SKILL.md` (largest edit)
- `methodology/core.md`
- `code-reviewer/SKILL.md`
- `architect/SKILL.md`, `systems-designer/SKILL.md`
- `ssd-init/SKILL.md`
- New: `ssd/rails.md`, `.ssd/hooks.yml` schema doc

## Out-of-scope (per the plan)
- Plan-mode integration with Claude Code
- Replacing codebase-skeptic / software-standards
- Distribution / packaging changes

## Open question to user
The plan ends with an explicit ask: *"Is there appetite for automating the rollout stage transitions (`0-deployed-flag-off → 1-internal → 2-beta → 3-100pct → 4-flag-removed`) as a `/ssd rollout advance` subcommand?"* This is a candidate eighth upgrade flagged for explicit yes/no.

## Scope reality check

This is not a single `/ssd feature`. It is at minimum a multi-iteration epic and arguably a milestone-class effort:

- **9 distinct deliverables** (7 engine upgrades + `rails.md` + profile/teaching mode), each touching multiple skill files.
- **Cross-skill coordination**: changes ripple across `ssd`, `architect`, `systems-designer`, `code-reviewer`, `methodology`, `ssd-init`.
- **A new schema** (`current.yml` v2 with iterations, gate_rounds, rail_deviations) requiring a back-compat story.
- **A test harness** (parity test) which is itself a new artifact category.
- **Self-referential**: the proposal argues SSD lacks first-class iterations — applying the current `/ssd feature` chain (which itself lacks iterations) is exactly the failure mode the plan documents.

The right shape is **architect-first scoping**, then incremental implementation in 5–9 iterations, each independently shippable (mergeable to main, no broken state). The first iteration should be the one with no dependencies on the others.

## Recommended next step (this session)
Invoke `architect` at the **epic level** to produce a sequenced implementation plan that:
1. Identifies the dependency graph between the 7+2 upgrades (e.g., #6 gate automation depends on `methodology/core.md` having executable rules; #1 iterations is a prerequisite for #2 multi-round gates that live inside iterations).
2. Picks the lowest-risk, highest-value first iteration to ship.
3. Defers Part II surface work until Part I engine substrate is in place (Part II explicitly reframes Part I as engine; without engine, no surfaces).
4. Decides the back-compat story: existing athena `current.yml` must keep parsing.
5. Names the open question (rollout-advance) as either in or out of scope.

`systems-designer` is N/A for this work — there is no production deployment, no observability, no failure modes in the runtime sense. The "deployment" step here is `git push origin main` after each iteration's `code-reviewer` clears.
