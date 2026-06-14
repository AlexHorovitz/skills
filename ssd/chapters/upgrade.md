<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

### `/ssd upgrade` — Keep the Project on the Latest SSD Approach

(added v1.21.0, see [ADR-0013](../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md))

SSD conventions evolve every release (new `project.yml.ssd.*` keys, `current.yml` schema bumps,
`gitignore_mode`, doctrine). `/ssd upgrade` detects when a project has drifted past the latest
conventions and — from iteration B — migrates it forward. It reads the declarative manifest
`methodology/migrations.yml` via the `methodology/migrate.sh` engine.

**Iteration A (v1.21.0) — read-only drift report.** The orchestrator:

1. Reads the project's recorded version from `.ssd/project.yml.ssd.version` (the `--from`).
2. Reads the installed skills' `VERSION` (the `--to`).
3. Runs `bash methodology/migrate.sh --from <recorded> --to <current>`, which selects
   `applies_to: project` manifest entries with `introduced_in > recorded` and reports each:
   - `PENDING <id>` — a mechanical convention not yet adopted (detect probe found it absent),
   - `SKIP-present <id>` — already adopted (idempotent; nothing to do),
   - `GUIDED <id>` — a *practice* (e.g. the decision-record doctrine) to adopt by hand.
4. Surfaces the report. **Iter A writes nothing** — it is a pure dry-run, so the corruption risk of
   a bad migration cannot fire (ADR-0013 Risk R1).

**Iteration B (v1.22.0) — `--apply` for mechanical migrations.** `/ssd upgrade --apply` runs
`bash methodology/migrate.sh --from <recorded> --to <current> --apply`, which for each selected
**mechanical** entry whose `detect` probe reports *absent*:

1. Backs up every file it will mutate (`<file>.bak`) — the ADR-0013 R1 (corruption) guard.
2. Runs the per-`id` apply function (non-destructive merges only: add keys / rewrite-with-backup;
   never delete), then **re-runs `detect`** to confirm the convention is now present. Statuses:
   `APPLIED` (was absent, now present), `SKIP-present` (idempotent no-op), `ERROR` (apply ran but
   `detect` still absent; engine exits 3).
3. After a successful pass, bumps `.ssd/project.yml.ssd.version` to the **highest contiguous
   adopted version** and appends a dated entry to `.ssd/init-log.md`.

The version bump walks the adopted entries in ascending order and **stops at the first outstanding
one — including any guided entry**. That keeps guided practices re-surfacing (their `introduced_in`
stays `> recorded`) on every run until the project adopts them (ADR-0013 R3), without iter C's
separate tracking. Mechanical entries above an outstanding guided entry are still applied; they
just don't advance the recorded version yet. Re-running `--apply` is therefore idempotent:
already-present conventions report `SKIP-present`, guided items re-surface.

`--apply` honors `--to <version>` (apply only entries `introduced_in <= <version>`, staged upgrade)
and `--json`. As of v1.23.0 **all four** mechanical migrations have executable apply functions in the
shared engine — `current-yml-v2`, `dev-profile-keys`, `parallel-features-keys`, `selective-gitignore`.
The `current-yml-v2` apply uses the **conservative-safe** v1→v2 form (back up to `current.yml.bak`,
write a fresh v2 skeleton, preserve the *entire* original under `current.notes.yml` `legacy_v1_import:`
for reconciliation) rather than a field-classifying heuristic — so R1 stays airtight. The selective
`.gitignore` pattern is single-sourced in [`methodology/selective.gitignore`](../../methodology/selective.gitignore),
which both `migrate.sh` and `ssd-init` consume (no drift between the first-run and upgrade paths).
`ssd-init`'s prompted, field-by-field v1→v2 flow remains the richer first-run path; `/ssd upgrade`
is the non-interactive consented equivalent.

Per ADR-0012 Pillar 5 (warnings, not walls), `/ssd upgrade` never forces — a project may stay on
old conventions; it only *reports* until the user opts to `--apply`, and never performs a silent
rewrite (every mutation is `.bak`-backed and consented, matching the ADR-0002 v1→v2 precedent).

**Iteration C (v1.24.0) — guided-adoption tracking + manifest-currency gate.** Guided practices
(`detect: null`, e.g. the decision-record doctrine) can't be auto-probed, so iter B pinned the
recorded version below the newest unadopted guided entry forever (R3 re-surfacing). Iter C decouples
the two: a project asserts it follows a guided practice with

```
/ssd upgrade --adopt <id>          # records id in project.yml.ssd.adopted_guided (.bak first)
```

An adopted guided entry reports `GUIDED-ADOPTED` and counts as *satisfied*, so the recorded version
can finally advance past it — and when the whole contiguous run through `--to` is satisfied, the
bump goes to `--to` itself (a fully-caught-up project records **zero drift**). Unadopted guided
entries still re-surface every run (R3 preserved). Adoption is an explicit, consented assertion —
never auto-detected — matching warnings-not-walls. Iter C also adds the **`migration-manifest-current`
gate rule** (R2; see § "Methodology Enforcement") and hardens `gate-rules.sh`'s `yaml_get` to strip
inline comments (the parser half of iter-B's MAJOR-4). With iter C the ssd-upgrade feature (issue #17)
is **complete**.

**Prerequisite:** `.ssd/project.yml` must exist. If absent, the project hasn't been initialized —
run `/ssd-init` (see the overlap rule in § "Resolving Skill Overlap").

---

