---
skill: brief
version: 2.12.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: rail-deviations
consumed_by: [architect]
---

# Brief — rail-deviations (D11)

## Why now

`rails.md` has promised, for a year, that *"every skipped step appears in `rail_deviations:`"*, and
that `codebase-skeptic` can therefore audit *"did this feature walk the rails?"* **mechanically**.

Measured: **zero** `rail_deviations:` fields across 15 archived workstreams, and no script writes one.
The only occurrence anywhere in the library is a test fixture's YAML *input*. Deviations are recorded
in **prose** in deploy logs, which nothing reads.

This is the last of the three conditions the 2026-09-01 audit set for moving the project's posture from
`drifting` to `calibrated`. The other two closed in v2.11.0.

It is also the load-bearing half of a second finding. `/ssd ship --force` was documented in four
places as *"the logged override leaving a durable `rail_deviations` trace"*. v2.11.0 struck the claim
because **neither half existed** — no script accepts `--force`, and there was nowhere for it to log.
The override cannot be built until the log does.

## What this must produce

1. Something **writes** `rail_deviations`, so the field stops being an aspiration.
2. Something **reads** it, so the write cannot quietly stop. A prose promise already failed for a year;
   repeating it with better wording is not a fix.
3. A **`--force` record** — an override is not a skipped step and should not be filed as one.

## Scope boundary, and it is the reason this brief exists at all

The audit's D17 finding was that rail step 2 had been skipped 13 times out of 13 and filed as a
deviation each time. **It was never a deviation** — `rails.md` step 2 reads *"for projects with real
production runtime"* and invariant 2 reads *"where applicable"*. The rails were correct; the paperwork
was theatre.

v2.12.0 made that condition first-class (`production_runtime` in the committed `.ssd/gate.yml`). This
matters here because **a deviation rule that does not read it would demand a deviation record for a
step that never applied** — instantly manufacturing the 14th instance of the finding it was built to
fix. That dependency is why D17 was decided before this feature was designed.

## Deliberately out of scope

- Backfilling deviations for the 15 archived workstreams. The prose record exists in the deploy logs;
  inventing structured records for decisions taken months ago would be fabrication, not history.
- Any change to what the rails *are*. This feature records deviations; it does not add, remove or
  reorder a step.

## Open questions for the architect

1. **Where does the write happen?** The orchestrator already writes `current.yml` as prose-driven
   edits (`phase`, `gate_rounds`). Appending to a nested list inside a YAML list item is the hard part,
   and is plausibly why nothing has ever done it.
2. **One record shape or two?** A skipped step and a gate override are different events.
3. **What makes the reader non-noisy?** `rails-walked` solved this by firing only on a `VERSION` bump.
   The same trigger may or may not fit here.
