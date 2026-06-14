---
skill: coder
version: 1.4.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#b
consumed_by: [code-reviewer]
files_touched:
  - ssd/SKILL.md
  - VERSION
  - CHANGELOG.md
tests_added: []
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 53/53 assertions"
lint_results:
  command: "grep -rniE 'perfect parity|dual.?surface|co-equal|no surface hides' (live files)"
  exit_code: 0
  stdout_tail: "only live hit is the intentional doctrine-reframing line in ssd/SKILL.md + immutable ADR-0004/0012"
type_check_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: "all PASS/SKIP; skill-version-sync PASS (8); migration-manifest-current PASS @ 2.1.0"
feature_flag:
  name: not_applicable
  default: off
spec_drift: false
---

# Coder Status — ssd-2.0-cuts iter B (Pillar 3: single surface + verb collapse) — v2.1.0

Executes the [iter-B cut-plan](01-architect.md). Subtraction + reframing on the v1.x spine; **not
breaking** (every v1 invocation still works). Markdown library — no runtime; the "tests" are the
parity harness + the R2 dangling-ref grep + the gate.

## Changes

- **`ssd/SKILL.md` § "Invocation"** — collapsed the front-loaded 13-verb table into a
  progressive-disclosure block: bare `/ssd` (no-arg Auto-Detect) is the headline everyday path
  (+ `/ssd start` for an un-stated project); the **full verb set is relocated** into an
  intent→verb→chapter pointer table (`phases` · `upgrade` · `workstreams`). Added the single-surface
  doctrine sentence (command path = thin alias, not a co-equal stateful surface; ADR-0012 Pillar 3).
  Applied verbatim from the architect spec's "Target text."
- **Banner** `ssd` 2.0.0 → **2.1.0**; **`VERSION`** → 2.1.0; **CHANGELOG** 2.1.0 entry.

## Verification (per architect risk table)

- **R1 (discoverability):** the new intent→verb→chapter table lists all 12 v1 verbs and routes each to
  its chapter — confirmed every verb resolves spine **and** chapters (presence matrix, all `y/y`).
- **R2 (residual live parity prose):** grep over live files (excl. `.ssd/`/CHANGELOG) returns only
  (a) the intentional new doctrine-reframing line in `ssd/SKILL.md` ("**not** a co-equal surface")
  and (b) the immutable governing ADR-0012 + superseded ADR-0004. **No old parity-asserting prose
  survives in the spine or `methodology/core.md`** (confirming the architect's finding that iter A
  already removed it).
- **R3 (NeXTSTEP over-cut):** no verb added/removed/renamed; only front-page teaching order changed.
  All 12 verbs present + chapter-documented.
- **R4 (`skill-version-sync` drift):** PASS — 8 sub-skill examples match banners; `ssd` orchestrator
  carries no frontmatter example, so its banner bump is unconstrained by the rule.

## Spec drift

None. The architect spec itself corrected the earlier touch-guess (`methodology/core.md` is **not**
touched — its only ADR cite is ADR-0011 decision-record-doctrine, correct and unrelated). Implementation
matches the spec; `current.yml` touches already reconciled to `ssd/SKILL.md` + `VERSION` + `CHANGELOG.md`.

## Tests / gate

- `parity-test.sh` 53/53; `gate-rules.sh --base main` exit 0 (`adr-delta`/`no-leaky-state` SKIP on the
  dirty working tree — they evaluate on the committed branch diff at `/ssd gate`). Iter C remains on #15.
