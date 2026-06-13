---
skill: ssd
version: 1.20.1
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-upgrade
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-upgrade

## Ledger
Tracked on [issue #17](https://github.com/AlexHorovitz/skills/issues/17), a v2.0 feature under the
SSD 2.0 epic ([#15](https://github.com/AlexHorovitz/skills/issues/15)), recorded per the
[ADR-0011](../../../docs/decisions/ADR-0011-decision-record-doctrine.md) decision-record doctrine.
This brief is the committed expansion of that issue.

## Problem
SSD's conventions evolve every release — schema bumps, new `project.yml.ssd.*` keys, `gitignore_mode`,
new gate rules, new doctrine (e.g. decision-record). A project that adopted SSD at version X has **no
single way to ask "am I following the latest approach?" and migrate forward.** Migration logic today
is scattered inside `ssd-init`'s idempotent re-run (v1→v2 `current.yml`, `gitignore_mode`) and is
undiscoverable as a deliberate "stay current" action.

**Live proof:** this repo records `project.yml.ssd.version: 1.15.0` while the library is **1.20.1** —
silently drifted past selective-gitignore/`no-leaky-state` (1.18), `skill-version-sync` (1.19.1),
profile-aware sub-skills (1.20.0), and decision-record doctrine (1.20.1). Nothing told the maintainer.

## Goal
A discoverable `/ssd upgrade` command that (1) detects the project's recorded SSD adoption version,
(2) diffs it against the installed skills' `VERSION`, (3) enumerates the gap as a checklist of
convention migrations, (4) applies them **idempotently, with prompts + backups**, and (5) reports
what changed and what new capabilities are now available. The Jobs-simple "Software Update" for an
SSD project.

## Design sketch (the architect resolves; do not pre-decide)
- **Declarative migration manifest** (version → migration steps) so each release that changes a
  convention adds one entry, not ad-hoc per-version branching.
- **Dry-run by default**: show the gap, apply on confirm.
- **Warnings, not walls** ([ADR-0012](../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md)
  Pillar 5): propose and apply with consent; never silently rewrite. Mechanical migrations (add a
  `project.yml` key with safe default, bump `schema_version`, switch `gitignore_mode`) auto-applied on
  confirm; judgment migrations (adopt decision-record issue-linking) surfaced as guidance.
- **Reuses `ssd-init`'s migration primitives** (already does v1→v2 + `.bak` + prompted, no silent
  rewrites). `/ssd upgrade` is that engine promoted to a first-class recurring command. **Needs a
  skill/command-overlap rule:** `ssd-init` = first-run/greenfield; `/ssd upgrade` = already-initialized
  drift. Mutually exclusive by project state.
- Writes/refreshes `project.yml.ssd.version` — the field currently going stale.

## Open questions
1. New command vs. an explicit `--upgrade` mode on `ssd-init`? (Lean: distinct, discoverable command
   sharing the engine.)
2. Migration-manifest format + location (`methodology/migrations/`?).
3. Auto vs. manual split; rollback artifact per migration (`.bak` per file vs. one pre-upgrade snapshot).
4. **Release vehicle: ship as its own minor (v1.21.0) *before* the contested 2.0 cuts, or hold for
   2.0?** This feature is largely independent of the profile-concept removal / verb collapse, so it
   *can* land early. Architect + user decide.
5. Interaction with ADR-0012's required deprecation path — `/ssd upgrade` is the natural vehicle that
   walks a v1 project off removed verbs/flags with alias-warnings.

## Out of scope
- The 2.0 surface cuts themselves (separate epic work on #15).
- Auto-tagging or any outward-facing git action (orchestrator never auto-pushes).

## Constraints
- Markdown skills library — `systems-designer` is N/A for the design phase (architect runs alone).
- Must be opt-in / safe on projects that never adopted newer conventions (no forced migration).
- Honor `skill-version-sync` + `no-leaky-state` gates throughout.

## Next step
`/ssd design ssd-upgrade` — architect only (systems-designer N/A for a markdown library).
