# ADR-0013: Project upgrade via a declarative migration manifest

## Status
Accepted — 2026-06-13. **Fully shipped** (issue #17 complete): iter A (v1.21.0, read-only report,
PR #18), iter B (v1.22.0, `--apply` for mechanical migrations, PR #19), the extraction (v1.23.0,
PR #20 — engine owns all four mechanical migrations + single-source gitignore), and iter C (v1.24.0,
guided-adoption tracking + `migration-manifest-current` gate rule + `yaml_get` hardening). Drives the
`ssd-upgrade` feature ([01-architect.md](../../.ssd/features/ssd-upgrade/01-architect.md)). Recorded
under the [ADR-0011](ADR-0011-decision-record-doctrine.md) pattern. **Extended v2.2.0** with the
`obsoleted_in` manifest field for the ssd-2.0-cuts epic (#15) — see the addendum at the end.

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
   on issue #17. **Shipped v1.23.0** (see Extraction addendum below).
3. **Guided re-surfacing (R3) is preserved in iter B by the version-bump rule, not by new state.** The
   recorded-version bump advances only across the *contiguous* run of adopted entries and stops at the
   first outstanding one — including any guided entry (which can never be auto-`detect`ed as adopted).
   A guided entry therefore keeps `introduced_in > recorded`, so it re-surfaces on every run until the
   project adopts it. Iter C's separate guided-adoption tracking then decouples re-surfacing from the
   version gate so the recorded version can advance past an adopted guided practice.

## Extraction addendum (v1.23.0)

The `ssd-init`→engine extraction that iter-B decision §2 deferred has shipped. Two concrete changes
retire the iter-B `DEFER` and the pattern duplication:

1. **`current-yml-v2` now has an executable apply** (`apply_current_yml_v2` in `migrate.sh`) — it no
   longer reports `DEFER`. The apply is the **conservative-safe** v1→v2 form: refuse if a `.bak`
   already exists, copy the original to `current.yml.bak`, write a fresh valid v2 skeleton, and
   preserve the *entire* original verbatim under `current.notes.yml` `legacy_v1_import:` for the user
   to reconcile. This was chosen over a bash heuristic that classifies arbitrary v1 keys into
   machine-vs-notes: that classification is exactly the R1 corruption hazard, and a preserve-everything
   approach has provably zero data loss (the original lives in both `.bak` and the notes import).
   `ssd-init`'s prompted, field-by-field flow remains the richer first-run path; `/ssd upgrade --apply`
   is the non-interactive consented equivalent. Both `.bak` and never discard.
2. **The selective `.gitignore` pattern is single-sourced** at `methodology/selective.gitignore`.
   `migrate.sh` (`apply_selective_gitignore`) `cat`s it; `ssd-init/SKILL.md` Step 5 points to it
   instead of re-listing the block. The two paths can no longer drift (closes iter-B review SUGGESTION-1).

## Iteration C addendum (v1.24.0) — epic complete

The three items iter-B/extraction left open all shipped:

1. **Guided-adoption tracking, decoupled from the version gate.** `detect: null` guided entries can't
   be auto-probed, so iter B pinned the recorded version below the newest unadopted guided entry
   forever. `/ssd upgrade --adopt <id>` now records an explicit, consented adoption assertion in
   `project.yml.ssd.adopted_guided` (`.bak` first; rejects a non-guided id). An adopted entry reports
   `GUIDED-ADOPTED` and counts as satisfied — the recorded version advances past it, and when the whole
   contiguous run through `--to` is satisfied the bump goes to `--to` (a fully caught-up project records
   zero drift). Unadopted guided entries still re-surface every run (R3 preserved). Adoption is never
   auto-detected — it's the user's judgment, matching warnings-not-walls.
2. **`migration-manifest-current` gate rule (R2)** — structural manifest health (unique ids, ascending
   `introduced_in`, none newer than `VERSION`); SKIPs outside the skills-library repo. The residual
   "convention changed but no entry added" case stays a documented human release obligation — a script
   can't read intent, but these checks catch the authoring mistakes that silently rot the manifest.
3. **`gate-rules.sh` `yaml_get` hardened** to strip inline comments on scalar values, quote-aware
   (the parser half of iter-B's MAJOR-4 — the emitter half was fixed in iter B).

With iter C the ssd-upgrade feature is fully delivered against this ADR's Decision.

## `obsoleted_in` addendum (v2.2.0) — convention retirement (ssd-2.0-cuts iter C)

> Distinct from the "Iteration C addendum" above (that closed the *ssd-upgrade* feature, #17). This
> addendum extends the manifest **schema** for the *ssd-2.0-cuts* epic (#15, [ADR-0012](ADR-0012-ssd-2.0-architecture.md)).

SSD 2.0 *removed* two project-visible conventions (`developer_profile` / `teaching_mode`, retired in
iter A). The manifest was append-only and could express "a convention was introduced" but not "a
convention was removed" — so the stale `dev-profile-keys` mechanical entry would still tell a v1-era
project to **add** `developer_profile` on `/ssd upgrade --apply`: re-adding the exact key 2.0 deleted.

**Decision.** Add an optional **`obsoleted_in: <version>`** field to a manifest entry. The engine's
selection loop skips an entry whose `obsoleted_in <= --to` (the convention does not exist in the
destination world), while a staged upgrade to a target *below* `obsoleted_in` still sees it. The id
is never deleted (the append-only / stable-id contract holds); the entry simply stops being *offered*
once you upgrade into the world that removed it. `dev-profile-keys` gets `obsoleted_in: 2.0.0`. The
"delete the keys if you still carry them" message moves to a new paired **guided** entry
`profile-concept-removed` (plus `single-surface-doctrine` for the iter-B surface collapse), both
`introduced_in: 2.0.0`, that re-surface (R3) until the project `--adopt`s them.

**Why guided, not a mechanical deletion.** The mechanical contract is explicitly non-destructive
("add keys / rewrite-with-backup; never delete"); a deletion-apply is a new R1 corruption hazard for
marginal benefit, and the dead keys are *ignored* by 2.0 (harmless to leave) — the profile of an
advisory item, not a must-converge one.

**Alternative rejected — `applies_to: library`.** Flipping `dev-profile-keys` to `library` would
neutralize it with zero engine change (the engine already skips non-`project` entries). Rejected: it
overloads the `applies_to` category — a reader of this reference manifest would see a clearly
project-scoped convention mislabeled "library." For a methodology artifact downstream projects copy,
the honest, generalizable `obsoleted_in` model (every future convention removal reuses one field) is
worth one guard line + one parser column + one parity fixture.

Engine: `migrate.sh` `read_manifest()` extracts `obsoleted_in` as a trailing column; the selection
loop adds `if [[ -n "$ob" && -n "$TO" ]] && ! ver_gt "$ob" "$TO"; then continue; fi`. The
`migration-manifest-current` gate rule needs no change (it ignores unknown fields). Regression test:
parity fixture `migrate-obsoleted-in` (not offered at `--to 2.2.0`, still offered at `--to 1.25.0`,
and `--apply` to 2.x never writes `developer_profile`).

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
