---
skill: coder
version: 1.23.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade#extraction
consumed_by: [code-reviewer]
files_touched:
  - methodology/selective.gitignore
  - methodology/migrate.sh
  - methodology/migrations.yml
  - scripts/parity-test.sh
  - ssd-init/SKILL.md
  - ssd/SKILL.md
  - docs/decisions/ADR-0013-project-upgrade-migration-manifest.md
  - VERSION
tests_added:
  - scripts/parity-test.sh   # fixture 16 rewritten: migrate-apply-v1-to-v2
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 43/43 assertions"
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

# Coder Status — ssd-upgrade `extraction` (v1.23.0)

Retires the two iter-B deferrals (issue #17): the `current-yml-v2` `DEFER` and the selective-`.gitignore`
pattern duplication. This is the `ssd-init`→engine extraction (a refactor; shipped as its own PR per
Hard Rule 4).

## Changes

1. **`methodology/selective.gitignore`** (new) — canonical single source of the selective pattern.
2. **`migrate.sh`**: `apply_selective_gitignore` now `cat`s the canonical file instead of an inline
   heredoc; new **`apply_current_yml_v2`** (conservative-safe v1→v2: refuse-if-`.bak`, back up, fresh v2
   skeleton, original preserved verbatim under `current.notes.yml` `legacy_v1_import:`); dispatch maps
   `current-yml-v2` to it; the `DEFER` (`rc 9`) path and its dead loop branch are removed; header updated.
3. **`ssd-init/SKILL.md`** (→1.9.0): Step 5 points to the canonical pattern file; Step 7 cross-refs the
   shared non-interactive engine path.
4. **`migrations.yml`** header note + **`ssd/SKILL.md`** `/ssd upgrade` section (→1.23.0) + **ADR-0013**
   extraction addendum + **VERSION** 1.22.0→1.23.0.

## Design note (for reviewer)

`apply_current_yml_v2` is deliberately **conservative-preserve**, not a field-classifying split. A bash
heuristic deciding which arbitrary v1 keys are machine-vs-notes is the R1 corruption hazard; preserving
the whole original (in `.bak` *and* in the notes import) is provably lossless and lets the human
reconcile `active[]`. `ssd-init`'s prompted field-by-field flow stays the richer first-run path. The
two never write conflicting `.gitignore` patterns now (single source).

## Tests

- `parity-test.sh` → **43/43** (fixture 16 rewritten DEFER→v1→v2; asserts `.bak`, v2 skeleton, and the
  undocumented key `custom_user_note` preserved — no data loss).
- `gate-rules.sh --base main` exit 0; `bash -n` clean.
- Manual: v1 project (`from 1.0.0`) applies all four mechanical incl. v1→v2; gitignore sourced from the
  canonical file (sentinel once); recorded version capped at 1.18.0 below the guided entry.
