---
skill: coder
version: 1.3.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade
consumed_by: [code-reviewer]
files_touched:
  - methodology/migrations.yml
  - methodology/migrate.sh
  - ssd/SKILL.md
  - scripts/parity-test.sh
tests_added:
  - scripts/parity-test.sh   # fixtures 13 (migrate-detect-old) + 14 (migrate-detect-current)
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 20/20 assertions"
lint_results:
  command: "bash -n methodology/migrate.sh"
  exit_code: 0
  stdout_tail: "syntax ok"
type_check_results:
  command: "bash methodology/gate-rules.sh --base main (skill-version-sync + no-leaky-state)"
  exit_code: 0
  stdout_tail: "all PASS/SKIP; skill-version-sync PASS (ssd SKIP'd as placeholder)"
feature_flag:
  name: not_applicable
  default: off
spec_drift: false
---

# Coder Status — ssd-upgrade iter A (read-only drift report → v1.21.0)

Implemented [01-architect.md](01-architect.md) + [ADR-0013](../../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md),
**iter A only** (detect-only; no write path). markdown skills library + bash.

## What was built
1. **`methodology/migrations.yml`** — declarative manifest, `schema_version: 1`, the 5 historical
   project-visible migrations (`current-yml-v2`, `dev-profile-keys`, `parallel-features-keys`,
   `selective-gitignore`, `decision-record-doctrine`). Append-only, ordered by `introduced_in`.
2. **`methodology/migrate.sh`** — detect-only engine, pure bash + awk (bash 3.2-compatible, mirrors
   `gate-rules.sh`). `--from <recorded> [--to <ver>] [--manifest <path>] [--json]`. Selects
   `applies_to: project` entries with `introduced_in > recorded` (and `<= --to`), runs a per-`id`
   detect probe (the dispatch table the spec calls for), emits `PENDING|SKIP-present|GUIDED <id> ::
   detail`. `--apply` **refuses with exit 2** ("lands in iter B") — the read-only guarantee. `--to`
   defaults to the installed `VERSION`.
3. **`ssd/SKILL.md`** — `/ssd upgrade` in the Invocation list + new § "/ssd upgrade — Keep the
   Project on the Latest SSD Approach" (iter-A dry-run behavior + iter-B/C plan). New `ssd-init` ↔
   `/ssd upgrade` state-disjoint coordination row in § "Resolving Skill Overlap" (**8 pairs** now).
   Banner 1.20.0 → 1.21.0 + changelog.
4. **`scripts/parity-test.sh`** — fixtures 13/14: an old project sees the expected
   `SKIP-present`/`PENDING`/`GUIDED`; a current project (`--from == --to`) sees an empty report.
   14 → **20 assertions** (4 new), all PASS.

## Notable: the tool found real drift in *this* repo
`bash methodology/migrate.sh --from 1.3.0 --to 1.20.1` against this repo reports **`PENDING
selective-gitignore`** — this repo adopted selective-gitignore *behavior* (the `.gitignore` is
selective, `no-leaky-state` passes) but `project.yml.ssd` never recorded `gitignore_mode`. That is
accurate detection and exactly the value prop. Fixing it is an iter-B `--apply` action (and
`project.yml` is gitignored machine state), not an iter-A change — flagged here for the reviewer and
for iter B.

## Deferred to iter B/C (explicit, per ADR-0013 / the architect's iteration plan)
- **iter B:** `--apply` for mechanical migrations (`.bak` per file, version bump, `init-log` append);
  extract `ssd-init`'s v1→v2 / `gitignore_mode` logic into `migrate.sh` (behavior-preserving;
  parity-covered); record force-style overrides. The `--apply` path is stubbed (exit 2), not partial.
- **iter C:** guided-migration re-surfacing + a `migration-manifest-current` gate rule (Risk R2 —
  a release that changes a convention but forgets a manifest entry).

## Self-verification
1. Ran the commands (parity 20/20; `bash -n`; gate-rules). ✓
2. No `# REVIEW:` markers emitted (standard profile; the iter-A/B boundary is explicit code — `--apply`
   exits 2 — not an uncertainty marker). `review_markers: 0` matches. ✓
3. Compared to the spec — no drift. The manifest holds metadata + human `detect` text; the executable
   probe is `migrate.sh`'s per-`id` dispatch, exactly as the spec's API contract specifies. ✓
4. `feature_flag: not_applicable` — markdown lib; dry-run-default + (iter B) `.bak` is the safety
   mechanism per the architect's Feature Flag Plan. No flag to wire. ✓
5. Single-language (bash); no cross-language boundary. ✓
