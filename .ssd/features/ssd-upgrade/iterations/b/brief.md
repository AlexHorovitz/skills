---
skill: brief
version: 1.22.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade#b
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-upgrade iteration B (`/ssd upgrade --apply`)

Reopens the archived `ssd-upgrade` workstream (iter A shipped v1.21.0, PR #18) for its second
iteration, per the 3-iteration split in
[01-architect.md](../../01-architect.md) (lines 169–171) and tracked on issue #17.

## Goal

Make `/ssd upgrade --apply` real: run the **mechanical** migrations the iter-A drift report
already detects, safely and reversibly.

## In scope (iter B)

- `--apply` in `methodology/migrate.sh`:
  - For each selected mechanical entry whose `detect` probe reports **absent**, run a per-`id`
    `apply_<id>` function.
  - Per-mutated-file `.bak` backup before writing (ADR-0013 R1).
  - Re-run `detect` after apply to confirm the convention is now present (`APPLIED` vs a loud
    failure); idempotent — an already-present convention is `SKIP-present`, never re-applied.
  - Bump `.ssd/project.yml.ssd.version` to the highest fully-applied `introduced_in`.
  - Append a dated entry to `.ssd/init-log.md`.
  - **Guided** entries are printed as outstanding manual steps and re-surfaced on every run
    (never auto-marked done) — ADR-0013 R3.
  - Honor `--to <version>` (apply only entries `introduced_in <= <to>`) and `--json`.
- Mechanical apply functions for the manifest's four mechanical entries: `current-yml-v2`,
  `dev-profile-keys`, `parallel-features-keys`, `selective-gitignore`. Non-destructive merges
  only (add keys / split / rewrite-with-backup, never delete).
- Parity-test fixtures: mechanical apply mutates + backs up + bumps version; a second run is an
  idempotent no-op (`SKIP-present`); guided item re-surfaces post-apply.
- Orchestrator docs: `/ssd upgrade --apply` promoted from "planned" to live in `ssd/SKILL.md`;
  `migrate.sh` header updated; `VERSION` → 1.22.0; changelog + banner.

## Out of scope (deferred)

- **`ssd-init` prose-extraction** — folding `ssd-init`'s v1→v2 / `gitignore_mode` instructions to
  *call* `migrate.sh`. That is a behavior-preserving refactor of existing working instructions;
  per SSD Hard Rule 4 it ships as a **separate follow-up PR**, not mixed with this feature.
- **`migration-manifest-current` gate rule** + guided-adoption tracking — that is **iter C**
  (v1.23.0) per the architect split.

## Acceptance

- `bash methodology/migrate.sh --apply --from <old> --to <cur>` on a drifted fixture: applies each
  mechanical convention, writes a `.bak` per file, bumps recorded version, appends init-log, and a
  second invocation is a clean `SKIP-present` no-op. Guided items re-surface both times.
- `scripts/parity-test.sh` green (existing 20 assertions + new apply assertions).
- `/ssd gate` clean (no BLOCKER/MAJOR).
