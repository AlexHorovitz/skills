---
skill: architect
version: 1.2.1
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0013]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — ssd-upgrade (`/ssd upgrade`)

Design for issue #17 (v2.0 feature; epic #15). Governed by
**[ADR-0013](../../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)**.

> **Platform:** markdown skills library + bash/Python executable helpers. No runtime/data store/network.
> `systems-designer` is **N/A** (no deploy surface beyond the tagged release). Deliverables below are
> adapted to a CLI-tool/doctrine design.

## Current Scale Baseline
- **Versions a project can drift across:** v1.4.0 (first migratable convention, `current.yml` v2) →
  1.20.1 today = ~16 releases; **~5 carry a project-visible convention change** (the manifest's real size).
- **Manifest growth:** ~1 entry per release that changes a project-visible convention (historically
  well under 1/release). **10x target:** ~50 entries over the library's life — still a flat, ordered,
  greppable YAML file; no indexing needed. Selection is a linear scan filtered by `introduced_in >
  recorded`.
- **Per-run cost:** O(pending migrations); each `detect` is a file/grep check. Negligible.

## Component Diagram

```
  ~/.claude/skills/methodology/migrations.yml      (manifest — ships with the skills)
              │ read by
              ▼
     /ssd upgrade  (new orchestrator command)
        1. read project's .ssd/project.yml → ssd.version (recorded)
        2. read library VERSION (current)
        3. pending = manifest entries: applies_to=project AND introduced_in > recorded
        4. dry-run → print report     |     --apply → run engine
              │
              ▼
     methodology/migrate.sh   (shared engine — ssd-init ALSO calls it)
        for each pending entry:
          detect ──present?──► SKIP (idempotent)
            │ absent
            ├─ mechanical: backup(<file>.bak) → apply → log
            └─ guided:     emit guidance, record as outstanding (no write)
        on success: bump project.yml.ssd.version, append .ssd/init-log.md
              │
              ▼
   project's  .ssd/project.yml · .ssd/current.yml · .gitignore   (mutated, each with .bak)
```

## Data Model — the migration manifest (`methodology/migrations.yml`)

```yaml
schema_version: 1
migrations:
  - id: current-yml-v2            # stable kebab id (PK; never reused)
    introduced_in: "1.4.0"        # version that added the convention (selection key)
    applies_to: project           # project | library  — upgrade runs only `project`
    kind: mechanical              # mechanical | guided
    adr: ADR-0002
    title: "current.yml v2 schema + current.notes.yml sidecar"
    detect: "current.yml contains 'schema_version: 2'"   # idempotency probe; null = not detectable
    apply: "v1→v2 split (existing ssd-init logic): write current.yml.bak, split machine/notes"
  - id: parallel-features-keys
    introduced_in: "1.15.0"
    applies_to: project
    kind: mechanical
    adr: ADR-0007
    title: "project.yml.ssd.{branch_pattern,worktree_root,worktree_name_pattern,switch_note_default}"
    detect: "project.yml.ssd has key 'branch_pattern'"
    apply: "add the four keys with documented defaults if absent (non-destructive merge)"
  - id: selective-gitignore
    introduced_in: "1.18.0"
    applies_to: project
    kind: mechanical
    adr: ADR-0008
    title: "selective .ssd/ commit split"
    detect: "project.yml.ssd.gitignore_mode is set"
    apply: "set gitignore_mode: selective; rewrite .gitignore to selective pattern (.gitignore.bak)"
  - id: decision-record-doctrine
    introduced_in: "1.20.1"
    applies_to: project
    kind: guided                  # a practice — cannot be auto-applied
    adr: ADR-0011
    title: "decisions = ADR + revisit-aware issue"
    detect: null
    guidance: "Adopt the ADR + revisit-aware tracking-issue pattern for consequential decisions."
```

**Field rules:** `id` is a stable primary key (kebab; never renamed/reused). `introduced_in` is the
selection key. `kind: guided` entries have `detect: null` + `guidance:` (no `apply`). `applies_to:
library` entries are **excluded** from `/ssd upgrade` (they're skills-repo-internal, e.g.
`skill-version-sync`). Manifest is **append-only** and ordered by `introduced_in`.

## API / Interface Contract

**Command (orchestrator):**
- `/ssd upgrade` — **dry-run** (default). Prints, per pending migration: `id`, `introduced_in`,
  `kind`, `title`, ADR link, and (mechanical) what it would change / (guided) the guidance. Writes
  nothing. Exit 0.
- `/ssd upgrade --apply` — runs mechanical migrations (each `detect`-gated + `.bak`), prints guided
  items as outstanding manual steps, bumps `project.yml.ssd.version` to the highest fully-applied
  version, appends an entry to `.ssd/init-log.md`. Re-running re-surfaces still-outstanding guided
  items.
- `/ssd upgrade --to <version>` — apply only entries with `introduced_in <= <version>` (partial/staged).
- **Preconditions:** `.ssd/project.yml` must exist (else FM: "not initialized — run `/ssd-init`").
  If `recorded == current` → "already current," exit 0.

**Engine (`methodology/migrate.sh`):**
- `bash methodology/migrate.sh --from <recorded> --to <current> [--apply] [--manifest <path>] [--json]`
- Emits one line per entry: `PENDING|APPLIED|SKIP-present|GUIDED <id> :: <detail>`. Exit 0 normally;
  nonzero only on engine error (malformed manifest, unreadable target).
- Pure functions for `detect`/`apply` per `id` (a small dispatch table keyed by `id`), so the manifest
  stays declarative and the per-migration logic is unit-testable via the parity harness.

**Overlap rule (add to `ssd/SKILL.md` § "Resolving Skill Overlap"):**
`ssd-init` (`Skill A`) vs `/ssd upgrade` (`Skill B`) — *coordination, state-disjoint*: `ssd-init` when
`.ssd/project.yml` is **absent** (first run / create); `/ssd upgrade` when it's **present and behind**
(migrate). Both call `migrate.sh`; neither duplicates migration logic.

## Decision Log
- **[ADR-0013](../../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)** — manifest +
  shared engine + dry-run-default `/ssd upgrade`; new command (not an `ssd-init` flag); ship before 2.0.

## Integration Contract
N/A — no queues/events/network. (The closest analog, idempotency, is handled by per-entry `detect`.)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **R1 — a mechanical migration corrupts `project.yml`/`.gitignore`** | M | **H** | Dry-run default; `.bak` per mutated file; idempotent `detect` (skip if present); non-destructive merges only (add keys, never delete); apply logic unit-tested via parity fixtures. The one to guard hardest. |
| **R2 — manifest drift** (a release changes a convention but adds no entry) | M | M | Documented release obligation in ADR-0013 + a future `migration-manifest-current` gate rule (out of iter-A scope; logged). |
| **R3 — guided migrations silently ignored** after `--apply` | M | M | `--apply` prints outstanding guided items; re-running `/ssd upgrade` re-surfaces them until the project adopts them. Never auto-marked done. |
| R4 — manifest conflates project vs library changes | L | M | `applies_to` field; upgrade filters to `project`. |

**Top 3:** R1 (corruption — dangerous), R2 (manifest drift — maintainability), R3 (guided-ignored).

## Feature Flag Plan
**N/A (markdown library).** The safety mechanism that a runtime flag would provide is supplied by
**dry-run-by-default + `.bak` + idempotent `detect`** — a project sees zero mutation until it runs
`--apply`, and every mutation is reversible. Ships atomically in the release tag; existing projects
are unaffected until they choose to run it. (Recorded as the "rollout = dry-run first, `--apply` on
consent" model.)

## Recommended release vehicle — **v1.21.0, before the 2.0 cuts**
Strong recommendation (see ADR-0013 Consequences). It's independent of the contested surface cuts,
closes a live drift problem, and is the **prerequisite that makes 2.0's deprecations safe**: 2.0's
removed verbs/flags become manifest entries `/ssd upgrade` already migrates. Build the upgrader first.

## Implementable spec for the coder — suggested 3-iteration split (ADR-0007 style)

- **Iter A → v1.21.0 (read-only, zero mutation risk):** `methodology/migrations.yml` (seeded with the
  5 historical entries above) + `migrate.sh` *detect-only* + `/ssd upgrade` **dry-run report**.
  Solves "nothing told the maintainer" with no write path. Ship this alone — pure value, R1 can't fire.
- **Iter B → v1.22.0:** `--apply` for **mechanical** migrations (`.bak`, version bump, init-log
  append) + extract `ssd-init`'s v1→v2/`gitignore_mode` logic into `migrate.sh` (behavior-preserving;
  parity-test covers it) + the `ssd-init`-vs-`upgrade` overlap rule in `ssd/SKILL.md`.
- **Iter C → v1.23.0:** **guided** migrations + re-surfacing + the `migration-manifest-current` gate
  rule (R2). 

**Build-order notes:** Iter A writes no project files → the `no-leaky-state`/`frontmatter-valid` gates
are trivially satisfied; the manifest + dispatch table get parity-test fixtures from the start (each
`detect` is a pure check). Any SKILL.md banners touched stay synced per `skill-version-sync`.

## Self-verification
1. Every required section has real content (baseline with real counts, diagram, manifest data model, command+engine contract, ADR-0013, risks, flag-plan rationale). ✓
2. Adapted to the actual stack (markdown lib + bash/python helpers), not web/runtime defaults. ✓
3. `systems-designer` correctly N/A for the design phase. ✓
4. Always-ADR topic (schema migration) → ADR-0013 authored in `docs/decisions/`. ✓
5. Scale baseline uses real counts (~5 project-visible migrations across 16 releases), not placeholders. ✓
