# ADR-0013: Project upgrade via a declarative migration manifest

## Status
Proposed — 2026-06-13. Drives the `ssd-upgrade` feature
([01-architect.md](../../.ssd/features/ssd-upgrade/01-architect.md), issue #17). Recorded under the
[ADR-0011](ADR-0011-decision-record-doctrine.md) pattern.

## Context

SSD conventions evolve every release (new `project.yml.ssd.*` keys, `current.yml` schema bumps,
`gitignore_mode`, doctrine). A project that adopted SSD at version X has no way to detect or close
that drift — proof: this repo records `ssd.version: 1.15.0` while the library is 1.20.1. Migration
logic exists but is **scattered and undiscoverable**: `ssd-init`'s idempotent re-run does the v1→v2
`current.yml` migration and the `gitignore_mode` switch, but nobody knows to re-run it, and nothing
enumerates "what conventions have I missed."

This is the architect's always-ADR topic #6 (**schema/convention migration strategy**), so the
decision is recorded here.

## Decision

**Drift is closed by a declarative migration manifest + a shared migration engine, surfaced through a
new `/ssd upgrade` command that is dry-run by default.**

1. **Manifest** — `methodology/migrations.yml` (ships with the skills). One entry per release that
   changed a *project-visible* convention. Each entry: `id`, `introduced_in` (version),
   `applies_to: project|library`, `kind: mechanical|guided`, `adr`, `title`, `detect` (idempotency
   check — is this already present?), and `apply` (mechanical) or `guidance` (guided). The manifest is
   the **single, ordered, append-only record** of how a project's conventions evolve — each future
   release that changes a convention adds exactly one entry.

2. **Shared engine** — `methodology/migrate.sh`. Given a recorded version and the current version, it
   selects `applies_to: project` entries with `introduced_in > recorded`, and for each runs
   `detect` (skip if already present), then — only with consent — backs up the target file (`.bak`),
   applies, and logs. `ssd-init`'s existing v1→v2 / `gitignore_mode` logic is **extracted into this
   engine** so there is one migration code path, not two.

3. **`/ssd upgrade` command** (new orchestrator command, *not* a flag on `ssd-init`):
   - **dry-run by default** — detect drift, print the pending-migration report, write nothing.
   - `--apply` — run mechanical migrations (each with a `.bak`), print guided items for manual
     adoption, bump `project.yml.ssd.version`, append to `.ssd/init-log.md`.
   - Warnings, not walls (ADR-0012 Pillar 5): never forces; a project may stay on old conventions —
     `/ssd upgrade` only *reports* until the user opts to `--apply`. Never a silent rewrite (matches
     the ADR-0002 v1→v2 prompted/`.bak` precedent).

4. **`ssd-init` vs `/ssd upgrade` boundary** (new command-overlap rule): `ssd-init` *creates* (no
   `.ssd/project.yml` → first run); `/ssd upgrade` *migrates* (`.ssd/project.yml` present, recorded
   version < library). Mutually exclusive by project state; both call `migrate.sh`.

## Rationale

A manifest beats ad-hoc per-version `if` branching: it's append-only (one entry per release), it
makes "what changed between X and Y" a data query, and it doubles as a human-readable changelog of
*project-affecting* changes. Dry-run-default + `.bak` + idempotent `detect` makes the dangerous part
(mutating someone's `project.yml`/`.gitignore`) safe and reversible. A distinct command (not an
`ssd-init` flag) is discoverable — the Jobs "Software Update" affordance — and keeps `ssd-init`'s
contract ("first-run housekeeping") clean.

## Consequences

- **Ship before 2.0 (recommended v1.21.0).** `/ssd upgrade` is largely independent of the contested
  2.0 surface cuts, delivers immediate value, and — critically — is the **vehicle ADR-0012's
  deprecation path needs**: when 2.0 removes commands/flags, those become *manifest entries*
  `/ssd upgrade` already knows how to migrate. Build the upgrader before you need it to deprecate.
- New maintenance obligation: every release that changes a project-visible convention MUST add a
  manifest entry. This is itself driftable — mitigated by a future `migration-manifest-current`
  gate check (Risk R2; out of scope for iter A).
- `ssd-init` is refactored to call the shared engine — a behavior-preserving extraction that must be
  covered by the parity-test harness.

## Alternatives rejected

- **`ssd-init --upgrade` mode.** Undiscoverable (a flag on a "first-run" command), and muddies
  `ssd-init`'s contract. Rejected in favor of a first-class command sharing the engine.
- **Ad-hoc per-version migration code.** Unmaintainable; no single place to answer "what's the gap."
- **Auto-migrate on every `/ssd` invocation.** Violates warnings-not-walls (silent rewrites) and the
  single-writer assumption. Upgrade is an explicit, consented action.
- **Hold for 2.0.** Rejected — it's independent, immediately valuable, and it's the prerequisite that
  makes 2.0's deprecations safe.
