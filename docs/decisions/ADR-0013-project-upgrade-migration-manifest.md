# ADR-0013: Project upgrade via a declarative migration manifest

## Status
Accepted — 2026-06-13. Shipped across iterations A (v1.21.0, read-only report, PR #18) and B
(v1.22.0, `--apply` for mechanical migrations). Drives the `ssd-upgrade` feature
([01-architect.md](../../.ssd/features/ssd-upgrade/01-architect.md), issue #17). Recorded under the
[ADR-0011](ADR-0011-decision-record-doctrine.md) pattern. Iteration C (guided-adoption tracking +
`migration-manifest-current` gate rule, R2) remains open on issue #17.

## Iteration-B implementation decisions (2026-06-13)

Three decisions were made while implementing `--apply` that refine, but do not contradict, the
Decision above:

1. **`current-yml-v2` reports `DEFER`, not a re-implemented split.** The v1→v2 `current.yml`
   migration logic still lives in `ssd-init`. Re-implementing it inside `migrate.sh` now would
   duplicate the very logic the planned extraction (Decision §2) is meant to unify, and a half-baked
   split is exactly the R1 (corruption) hazard this ADR guards hardest. So `--apply` emits
   `DEFER current-yml-v2` and points the user at `/ssd-init`; the recorded version does **not** advance
   past a deferred entry. Real pre-v1.4.0 projects are effectively extinct at v1.22.0, so this path is
   cold.
2. **The `ssd-init` → engine extraction is split into its own follow-up PR**, not bundled into iter B.
   Mixing a behavior-preserving refactor of working `ssd-init` logic with new feature work violates
   SSD Hard Rule 4 (refactor only after shipping, separate PRs). The extraction — which also closes the
   selective-`.gitignore`-pattern duplication between `ssd-init/SKILL.md` and `migrate.sh` — is tracked
   on issue #17.
3. **Guided re-surfacing (R3) is preserved in iter B by the version-bump rule, not by new state.** The
   recorded-version bump advances only across the *contiguous* run of adopted entries and stops at the
   first outstanding one — including any guided entry (which can never be auto-`detect`ed as adopted).
   A guided entry therefore keeps `introduced_in > recorded`, so it re-surfaces on every run until the
   project adopts it. Iter C's separate guided-adoption tracking then decouples re-surfacing from the
   version gate so the recorded version can advance past an adopted guided practice.

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
