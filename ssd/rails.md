# SSD Rails — The Opinionated Path

<!-- License: See /LICENSE -->

**Version:** 1.0.0

## Purpose

`rails.md` documents the canonical SSD opinionated path: the sequence of phases every shippable
feature follows by default. It is the named, defended thing the conversational surface
(`/ssd <intent>`) walks. The command surface (`/ssd design`, `/ssd code`, etc.) **can** leave the
rails — but every deviation is logged in `current.yml.active[].rail_deviations` so reviewers and
future-self can see what was skipped and why.

This document is short by design. The rails are a sequence, not a treatise — the reasoning behind
each step lives in `methodology/core.md` (doctrine) and the per-skill SKILL.md files (mechanics).

## The Rails

A feature on the rails passes through these eight steps in order:

1. **Brief** — the user states intent. Saved as `00-brief.md` (or `iterations/<iter>/brief.md` for
   multi-iteration features). Free-form prose; the only structured content is "what does shipping
   this look like?"

2. **Design** — `architect` produces `01-architect.md` (component diagram, data model, API
   contract, ADRs, risk assessment, feature flag plan, current scale baseline). For projects with
   real production runtime, `systems-designer` produces `02-systems-designer.md` immediately
   after, sharing the architect's input. Bundle invocation: `/ssd design <slug>`.

3. **Code** — `coder` implements from the architect spec. Output: `03-coder-status.md`
   (frontmatter with files_touched, tests_added, test/lint/typecheck results, feature flag name,
   spec_drift). New code goes behind a feature flag unless it's infrastructure. For
   multi-iteration features, deferred items from prior iterations auto-load as input.

4. **Review** — `code-reviewer` produces `04-code-review.md` (single-cycle) or
   `iterations/<iter>/code-review/round-1.md` (multi-iteration). Frontmatter `gate_pass: true|false`
   and severity-classified findings.

5. **Gate** — methodology rules execute (`methodology/gate-rules.sh`): no WIP commits, tests pass,
   feature flag present in added code, ADR delta proportional to architectural change. PASS or FAIL
   with cited rule. Combined with the review: BLOCKER/MAJOR findings OR any FAIL gate-rule = back
   to step 3 with a round-2 review on return.

6. **Deploy** — push to staging, run smoke checks, push to production. Feature flag stays off
   (internal-only). Output: `05-deploy.md` (deployment log).

7. **Rollout-advance** — feature flag transitions: internal → beta → 100%. Each transition is its
   own deploy log entry; never skip stages.

8. **Flag removal** — once the feature is at 100% and stable, the flag is removed and dead code
   is deleted. The artifact tree archives to `.ssd/archive/features/<slug>/`. The workstream is
   removed from `current.yml.active`.

## Rail-Deviation Logging

A workstream that skips a step (or runs them out of order) records the deviation in
`current.yml.active[].rail_deviations`:

```yaml
rail_deviations:
  - step: systems-designer
    reason: "skills library has no production runtime; N/A throughout"
    ts: 2026-04-29T00:00:00Z
  - step: feature-flag
    reason: "documentation-only change; no flag applies"
    ts: 2026-04-29T00:00:00Z
```

Deviations are **not failures** — they are engineering judgment captured for the record. A future
reviewer or auditor can see what was skipped and why. The orchestrator never blocks based on
deviation count; it only records them. (A team that wants to enforce a deviation budget can
extend `gate-rules.sh` to read this field.)

## What the Rails Guarantee

A feature that walks all eight steps produces:

1. A brief (`00-brief.md` or per-iteration equivalent)
2. A design (`01-architect.md` and, where applicable, `02-systems-designer.md`)
3. A coder status (`03-coder-status.md` or `iterations/<iter>/coder-status.md`)
4. At least one code review with `gate_pass: true` in frontmatter
5. A passed methodology gate (`gate-rules.sh` exit 0)
6. A deploy log (`05-deploy.md` or `iterations/<iter>/deploy.md`) with rollout stage recorded
7. ADRs in `docs/decisions/` for any architectural decision (per `architect/SKILL.md` § "Decisions
   that are ALWAYS ADRs")
8. Runbooks in `docs/runbooks/` for any new operational surface

These are the **critic-grade invariants**. They are the rails' responsibility, not the surface's.
A novice using only `/ssd <intent>` produces all eight. An expert using the command surface
produces all eight (or explicit `rail_deviations:` if they skipped one).

## Surfaces (Conversational vs Command)

The rails are surface-agnostic. The conversational surface (`/ssd <intent>`, `/ssd` no-arg) walks
the rails by default. The command surface (`/ssd design`, `/ssd code`, …) lets the user invoke
each step explicitly. Both produce identical artifacts.

A user on the conversational surface **cannot leave the rails** by accident — they can only
decline to advance. A user on the command surface **can leave the rails** but every skipped step
appears in `rail_deviations:`.

## Why This Document Exists

Without a named rails artifact, "the opinionated path" is folklore — the thing experienced users
have internalized but new users have to reverse-engineer from the orchestrator's prompts. With
a named rails artifact:

- Conversational and command surfaces both read the same source of truth.
- `code-reviewer` can reference rail steps when flagging deviations.
- `codebase-skeptic` can audit "did this feature walk the rails?" mechanically.
- Newcomers can read one page (this one) and understand SSD's default flow.

If the rails change, they change in this one place. If a team adopts non-default rails, they fork
this file, name the variant, and reference the variant in their `project.yml`.

## What This Is NOT

- **Not a tutorial.** Onboarding lives in `methodology/adoption.md`. This is a reference.
- **Not a strict gate.** Deviations are allowed and logged, not blocked.
- **Not a replacement for `methodology/core.md`.** Doctrine ("why these eight steps") is in core.
  Mechanics ("how each step works") is in the per-skill SKILL.md files. This document is the
  middle layer: the named sequence.

## Changelog

- **1.0.0** (2026-04-29) — Initial release. Iteration 7 of the ssd-skill-upgrades epic (P2.A,
  ADR-0003). Documents the eight-step opinionated path, rail-deviation logging, and the
  surface-agnostic guarantee.
