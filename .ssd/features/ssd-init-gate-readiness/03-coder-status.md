---
skill: coder
version: 1.4.0
produced_at: 2026-08-06T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-init-gate-readiness
consumed_by: [code-reviewer]
files_touched:
  - methodology/selective.gitignore
  - methodology/gate-rules.sh
  - methodology/migrations.yml
  - methodology/migrate.sh
  - ssd-init/SKILL.md
  - VERSION
  - CHANGELOG.md
  - docs/decisions/ADR-0015-ssd-init-gate-readiness.md
tests_added: []
review_markers: 0
test_results:
  command: "bash -n gate-rules.sh && bash -n migrate.sh; migrate.sh --apply end-to-end self-test in scratch repo"
  exit_code: 0
  stdout_tail: "gate-rules.sh OK; migrate.sh OK. Scratch repo: PENDING->APPLIED->SKIP-present for both migrations; gate.yml=`test_command: make test`; !.ssd/gate.yml added after .ssd/*; re-apply no-op (counts stay 1). gate_input: gate.yml fallback=make test, absent=empty, project.yml override wins."
lint_results:
  command: "bash -n (shellcheck not installed in env)"
  exit_code: 0
type_check_results:
  command: "n/a (bash + markdown; no static type checker)"
  exit_code: 0
feature_flag:
  name: none
  default: off
spec_drift: true
---

# Coder Status — ssd-init-gate-readiness (Iter A)

Iteration **A — "gate inputs travel"** of [ADR-0015](../../../docs/decisions/ADR-0015-ssd-init-gate-readiness.md).
Implements Decisions 1 + 2, the `gate-rules.sh` fallback companion, and the two mechanical migrations.
Iters B–D (library-root resolution + hook fix, gate-readiness reporting, docs + CI vendoring) are not
started.

## What was built

**Decision 2 — committed gate inputs (P2 fix)**
- `methodology/selective.gitignore`: added the `!.ssd/gate.yml` exception (single source; `ssd-init`
  Step 5 and `migrate.sh` both consume it).
- `methodology/gate-rules.sh`: added `GATE_YML` and a `gate_input()` fallback that reads `project.yml`
  first (local override), then the committed `gate.yml` (portable floor). `rule_tests_pass` and
  `rule_feature_flag_present` now call it; their SKIP messages name both files.

**Decision 1 — detect & write `test_command` (P1 fix)**
- `ssd-init/SKILL.md`: new **Step 6.5** describes the detection table (Makefile `test:` → npm → pytest
  → go → cargo → swift, most-specific-first; prompt on ambiguity; commented placeholder + MAJOR log
  when undetected) and the `.ssd/gate.yml` template; `project.yml` template gains commented override
  stubs; `.ssd/gate.yml` added to the init-log Directory Setup and the Quality Checklist.

**Migrations (`/ssd upgrade --apply` retrofit)**
- `methodology/migrations.yml`: `gate-inputs-present` + `committed-gate-yml` (mechanical, ADR-0015,
  `introduced_in: 2.5.0`).
- `methodology/migrate.sh`: `detect()` cases, `apply_gate_inputs_present()` / `apply_committed_gate_yml()`
  (with an `ensure_gate_yml_header()` helper), and `apply_dispatch()` wiring. Detection mirrors the
  ssd-init prose; idempotent on both the file and the gitignore exception.

**Version bookkeeping**: `VERSION` 2.4.0 → 2.5.0; `ssd-init` banner + init-log example 1.10.0 → 1.11.0;
`CHANGELOG.md` `[2.5.0]` entry; `ssd-init` changelog entry.

## Spec drift (recorded — `spec_drift: true`)

ADR-0015 Decision 1 (as originally written) asks for a **live** `ssd.test_command` in `project.yml`;
Decision 2 asks for it in `gate.yml`. Writing the same value *live* in both a gitignored and a
committed file is redundant and ambiguous about which is authoritative. Iter A makes the **committed
`gate.yml`** authoritative and leaves `project.yml` a **commented override stub**. The fallback
precedence (project.yml → gate.yml) is unchanged and P1/P2 are both still fixed. I added a
reconciliation note to ADR-0015 § Decision 2 rather than leaving the contradiction latent. If the
reviewer prefers the literal both-files write, that is a one-line change to Step 6.5 and
`apply_committed_gate_yml()`.

## Verification performed

- `bash -n` on both edited scripts: clean.
- End-to-end migration self-test in a scratch git repo (Makefile `test:` target, pre-ADR-0015
  selective `.gitignore`): `PENDING → APPLIED → SKIP-present` for both ids; `gate.yml` written with
  `test_command: make test`; `!.ssd/gate.yml` inserted after `.ssd/*`; re-apply is a no-op (line
  counts stay 1).
- `gate_input()` precedence unit-checked: gate.yml-only → `make test`; absent key → empty;
  `project.yml` override wins over `gate.yml`.
- Gate rules that don't depend on the commit diff: `frontmatter-valid` PASS (49 artifacts),
  `skill-version-sync` PASS (8 examples match banner), `migration-manifest-current` PASS (10 entries,
  unique, ascending, ≤ VERSION 2.5.0).

## Not done (out of Iter A scope)

- This repo's own `.ssd/gate.yml`: skipped — the skills library has no standard test harness, so its
  `test_command` is a legitimate commented placeholder. Iter C's gate-readiness reporting is where
  that surfaces as a classified SKIP.
- No feature flag: this is SSD library tooling (infrastructure), which the coder discipline exempts
  from the flag requirement.
