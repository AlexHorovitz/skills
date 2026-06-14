---
skill: coder
version: 1.25.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-skill-chapter-split
consumed_by: [code-reviewer]
files_touched:
  - ssd/SKILL.md
  - ssd/chapters/phases.md
  - ssd/chapters/upgrade.md
  - ssd/chapters/workstreams.md
  - ssd/chapters/profile.md
  - ssd/chapters/artifacts.md
  - ssd/chapters/state.md
  - ssd/chapters/enforcement.md
  - ssd/chapters/skills.md
  - CHANGELOG.md
  - VERSION
tests_added: []
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 53/53 assertions"
lint_results:
  command: "n/a (markdown-only relocation)"
  exit_code: 0
  stdout_tail: "n/a"
type_check_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: "all PASS/SKIP; skill-version-sync PASS; migration-manifest-current PASS"
feature_flag:
  name: not_applicable
  default: off
spec_drift: false
---

# Coder Status — ssd-skill-chapter-split (v1.25.0)

Behavior-preserving split of the 1,465-line `ssd/SKILL.md` monolith → **295-line spine + 8 chapter
files** under `ssd/chapters/`. Path A (2.0 prerequisite P1; [ADR-0012](../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md)).

## What changed

- **Spine (`ssd/SKILL.md`, 1465→295)** keeps the front matter inline: Purpose / When / Prerequisite /
  Interface / Invocation / the no-arg **Auto-Detect** behavior (progressive-disclosure core) / The Rails
  / Hard Rules. Every moved section keeps its **heading as a redirect stub** + a new "Chapters" index.
- **8 chapters** carved byte-for-byte via `sed` from the original line ranges:
  `phases` (135–349), `upgrade` (350–427), `workstreams` (428–735), `profile` (736–829),
  `artifacts` (874–961), `state` (962–1169: structured-output + iterations + session-continuity),
  `enforcement` (1170–1229), `skills` (1230–1283).
- **Changelog** (was 1284–1465 in-file) → pointer to repo `CHANGELOG.md`, which was **backfilled** with
  the 1.22.0/1.23.0/1.24.0 entries (shipped earlier this session but never recorded there) + the new
  1.25.0 entry, so the pointer is truthful.
- `VERSION` + spine banner → 1.25.0.

## Behavior-preservation evidence (verified)

- **Zero cross-ref breakage:** every externally-referenced `§`-name (`Workstream Lifecycle Commands`,
  `Profile-aware defaults`, `Profile-aware sub-skill behavior`, `Structured Output Requirements`,
  `Iterations Inside a Feature`, `current.yml v2 schema`, `Session Continuity`, `Methodology
  Enforcement`, `Resolving Skill Overlap`, `The SSD Artifact Tree`, `Auto-Detect`) still appears in the
  spine (each as a stub heading / named in a stub) → grep-confirmed present.
- **No body duplicated** into the spine (distinctive phrases — `FM-14`, `invocations_remaining`,
  `legacy_v1_import`, `schema_version: 2` — appear in their chapter and not in the spine body).
- **Line accounting:** 295 (spine) + 1,129 (chapters) + changelog-moved ≈ original 1,465 — nothing lost.
- **No deletions:** `chapters/profile.md` carries the full developer-profile + teaching-mode doctrine
  verbatim, with a ⚠️ banner marking it the ADR-0012 Pillar-1 deletion candidate (relocated, not removed).

## Tests / gate

- `scripts/parity-test.sh` → **53/53** (unaffected — no engine/script change).
- `gate-rules.sh --base main` → exit 0 (`skill-version-sync` PASS, `migration-manifest-current` PASS).

## `.ssd/` artifacts NOT rewritten

Historical references to `ssd/SKILL.md § "…"` in `.ssd/` artifacts and prior CHANGELOG entries are
dated records and were deliberately left untouched.
