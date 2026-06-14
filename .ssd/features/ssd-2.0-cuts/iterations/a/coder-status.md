---
skill: coder
version: 2.0.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#a
consumed_by: [code-reviewer]
files_touched:
  - ssd/SKILL.md
  - ssd/chapters/profile.md
  - ssd/chapters/workstreams.md
  - code-reviewer/SKILL.md
  - coder/SKILL.md
  - systems-designer/SKILL.md
  - codebase-skeptic/SKILL.md
  - architect/SKILL.md
  - methodology/SKILL.md
  - refactor/SKILL.md
  - ssd-init/SKILL.md
  - docs/decisions/ADR-0004-developer-profile-and-teaching-mode.md
  - docs/decisions/ADR-0010-profile-aware-subskills.md
  - docs/decisions/ADR-0012-ssd-2.0-architecture.md
  - VERSION
  - CHANGELOG.md
tests_added: []
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 53/53 assertions"
lint_results:
  command: "grep — no live dangling profile refs"
  exit_code: 0
  stdout_tail: "none outside .ssd/ history, CHANGELOG, ADRs"
type_check_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: "all PASS/SKIP; skill-version-sync PASS; migration-manifest-current PASS @ 2.0.0"
feature_flag:
  name: not_applicable
  default: off
spec_drift: false
---

# Coder Status — ssd-2.0-cuts iter A (Pillar 1: remove the profile concept) — v2.0.0

Executes the [iter-A cut-plan](../../01-architect.md). **Breaking** (project.yml keys removed). Pure
subtraction; every profile-keyed behavior collapsed to its former `standard` default (no behavior lost).

## Deletions / collapses

- **`ssd/chapters/profile.md`** — deleted (whole chapter). Spine stub + chapter-index row removed from
  `ssd/SKILL.md`.
- **4 profile-aware skills** — `## Profile-Aware Behavior` *replaced* (not just deleted) with an
  unconditional section stating the standard default: `code-reviewer` → § "Finding-Severity Reporting"
  (MINOR inline, NIT summarized); `coder` → § "REVIEW-Marker Density"; `systems-designer` → § "Checklist
  Depth"; `codebase-skeptic` → § "Voice Selection". (Subagent-applied, verified.)
- **3 invariant skills** — `architect`/`methodology`/`refactor`: removed the obsolete
  `> Profile stance: invariant` blockquote (verified gone from each top; only the changelog mention
  remains). No behavior change — they never branched.
- **`ssd-init`** — removed `developer_profile`/`teaching_mode` from the `project.yml` template (replaced
  with a 2.0 note); Step 5 + Step 5.5 no longer branch on profile (always propose, user declines);
  `switch_note_default` is a plain knob (default `prompt`).
- **`.ssd/project.yml`** (this repo, dogfood) — keys removed.
- **ADR-0004 + ADR-0010** — marked Superseded by ADR-0012 (retained). **ADR-0012** status updated:
  cuts shipping in v2.0.0.
- Banners bumped (9): `ssd` 2.0.0, `ssd-init` 1.10.0, `code-reviewer` 1.7.0, `coder` 1.4.0,
  `systems-designer` 1.5.0, `codebase-skeptic` 1.4.0, `architect` 1.3.0, `methodology` 1.7.0,
  `refactor` 1.3.0. `VERSION` → 2.0.0; CHANGELOG 2.0.0 entry.

## Verification (per architect risk table)

- **R1 (silent behavior loss):** every profile-aware section was *replaced* with its standard default,
  not blanked — grep-confirmed all four new sections present.
- **R2 (dangling refs):** grep for `developer_profile`/`profile-aware`/`chapters/profile` in live files
  → only dated changelog history, `.ssd/` artifacts, and the superseded/governing ADRs remain. No live
  cross-ref or link breaks.
- **R3 (NeXTSTEP over-cut):** no verb/capability removed — only the profile *enum* + tiered deltas. The
  escape-hatch chapters (verbs) are untouched.
- **R4 (`skill-version-sync` drift):** PASS — 8 examples match banners (methodology banner-only).

## Tests / gate

- `parity-test.sh` 53/53; `gate-rules.sh --base main` exit 0. Iter B/C remain on #15.
