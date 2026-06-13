---
skill: coder
version: 1.22.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade#b
consumed_by: [code-reviewer]
files_touched:
  - methodology/migrate.sh
  - methodology/migrations.yml
  - scripts/parity-test.sh
  - ssd/SKILL.md
  - VERSION
tests_added:
  - scripts/parity-test.sh   # fixtures 15 (migrate-apply-old) + 16 (migrate-apply-defer)
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 37/37 assertions"
lint_results:
  command: "bash -n methodology/migrate.sh"
  exit_code: 0
  stdout_tail: "syntax ok"
type_check_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: "all PASS/SKIP"
feature_flag:
  name: not_applicable
  default: off
spec_drift: false
---

# Coder Status — ssd-upgrade iteration B (`/ssd upgrade --apply`)

## What changed

| File | Change |
|---|---|
| `methodology/migrate.sh` | `--apply` mode: per-`id` apply dispatch, once-per-run `.bak` guards, `insert_under_ssd` (multi-line-safe via temp-file getline), 3 executable apply fns + 1 `DEFER`, re-detect confirmation, contiguous version bump, init-log append. Detect-only path unchanged. |
| `methodology/migrations.yml` | Header note updated — `apply` text now maps to `apply_<id>()` in the engine; `current-yml-v2` DEFERs. No new entries (iter B adds no project-visible convention). |
| `scripts/parity-test.sh` | +2 fixtures (15 `migrate-apply-old`, 16 `migrate-apply-defer`); 20 → 37 assertions. |
| `ssd/SKILL.md` | `/ssd upgrade` § rewritten: iter B `--apply` live, iter C re-scoped to guided-tracking + manifest gate. Banner 1.21.0 → 1.22.0; changelog entry. |
| `VERSION` | 1.21.0 → 1.22.0. |

## Design decisions (for the reviewer)

1. **`current-yml-v2` → `DEFER`, not a parallel split.** The v1→v2 `current.yml` migration lives in
   `ssd-init`'s prose. Re-implementing it here would (a) duplicate logic the deferred extraction is
   meant to unify and (b) risk R1 (corruption) with a half-baked split. `apply_dispatch` returns a
   `9` sentinel → `DEFER`, which does not advance the recorded version. Honest and safe.
2. **Version bump stops at the first outstanding entry (incl. guided).** This is how guided
   re-surfacing (R3) is preserved in iter B without iter C's separate tracking: the recorded
   version can't pass `decision-record-doctrine` (1.20.1, guided, never auto-detected), so it
   re-surfaces every run. Mechanical entries above it still apply; they just don't bump the version.
3. **`.bak` once per file per run** (`PJ_BACKED`/`GI_BACKED` flags — bash 3.2, no assoc arrays) so
   the backup captures the true pre-run original even when several apply steps touch `project.yml`.
4. **Non-destructive merges only.** `dev-profile-keys` appends top-level keys at EOF;
   `parallel-features-keys`/`gitignore_mode` insert as first children under `ssd:`;
   `selective-gitignore` drops only a bare blanket `.ssd/` line, then appends the canonical pattern.
   Nothing is ever deleted.
5. **Re-detect after apply** is the correctness gate: apply that doesn't make `detect` true →
   `ERROR` + engine exit 3 (loud failure, no false "applied").

## Known limitations / `# REVIEW:` items

- **`# REVIEW:` selective-`.gitignore` pattern is duplicated** between `ssd-init/SKILL.md` (prose)
  and `migrate.sh` (heredoc). Drift risk. The deferred ssd-init→engine extraction resolves this by
  making the engine the single source. Logged, not fixed here (out of iter-B scope).
- `current-yml-v2` apply is unimplemented by design (DEFER). Real v1 projects (< v1.4.0) are
  effectively extinct at v1.22.0; they get a clear pointer to `/ssd-init`.

## Tests

- `bash scripts/parity-test.sh` → **PASS 37/37** (was 20/20).
- `bash methodology/gate-rules.sh --base main` → all PASS/SKIP, exit 0.
- Manual: drifted fixture (`from 1.9.0`) applies 3 mechanical, writes `.bak` per file, bumps to
  1.18.0, appends init-log; second run idempotent (`SKIP-present` + guided re-surface), exit 0.
- Manual: v1 fixture (`from 1.3.0`) → `current-yml-v2` DEFER, `current.yml` untouched, version stays.
