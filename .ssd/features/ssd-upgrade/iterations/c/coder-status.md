---
skill: coder
version: 1.24.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade#c
consumed_by: [code-reviewer]
files_touched:
  - methodology/migrate.sh
  - methodology/gate-rules.sh
  - scripts/parity-test.sh
  - ssd/SKILL.md
  - docs/decisions/ADR-0013-project-upgrade-migration-manifest.md
  - VERSION
tests_added:
  - scripts/parity-test.sh   # fixtures 18 (guided-adoption), 19 (manifest-current), 20 (yaml_get inline comment)
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 53/53 assertions"
lint_results:
  command: "bash -n methodology/migrate.sh && bash -n methodology/gate-rules.sh"
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

# Coder Status — ssd-upgrade iteration C (v1.24.0) — epic-closing

Closes the last three open items on issue #17 / ADR-0013.

## Changes

1. **Guided-adoption tracking** (`migrate.sh`): new `--adopt <id>` flag records a guided practice in
   `project.yml.ssd.adopted_guided` (block-list form, `.bak` first; rejects a non-guided id with exit 2).
   New `is_adopted()` helper reads both inline and block list forms. The guided branch in the report
   loop now emits `GUIDED-ADOPTED` (satisfied) when adopted, else `GUIDED` outstanding. New end-of-loop
   rule: if the contiguous adopted run never broke, bump the recorded version to `--to` (fully-current →
   zero drift), not just the highest manifest entry.
2. **`migration-manifest-current` gate rule** (`gate-rules.sh`): structural manifest validation
   (unique ids, ascending `introduced_in`, none > `VERSION`, ≥1 entry); SKIPs where no
   `methodology/migrations.yml` exists (everything but the skills-library repo). Registered in the run
   loop + `--rules` filter.
3. **`yaml_get` hardening** (`gate-rules.sh`): strips an inline `# comment` from scalar values,
   quote-aware (unquoted → strip ` #…`; quoted → take through the closing quote). Closes the parser half
   of iter-B MAJOR-4.

Docs: `ssd/SKILL.md` → 1.24.0 (iter-C section + Methodology Enforcement row + changelog), ADR-0013
marked fully shipped + iter-C addendum, `VERSION` → 1.24.0.

## Design notes (for reviewer)

- **Adoption is consented, never auto-detected.** `detect: null` guided entries can't be probed, so
  adoption is an explicit user assertion (warnings-not-walls). Unadopted guided entries keep
  re-surfacing (R3); only `--adopt` lets the version pass them.
- **`migration-manifest-current` is structural only.** It cannot detect "a convention changed but no
  entry was added" (intent) — that stays a documented human release obligation. It catches the
  authoring mistakes (dup id, future version, bad ordering) that silently rot the manifest.

## Tests

- `parity-test.sh` → **53/53** (+6: guided-adoption full flow incl. version→TO + invalid-adopt reject;
  manifest PASS/dup-FAIL/future-FAIL; yaml_get inline-comment strip).
- `gate-rules.sh --base main` exit 0; both scripts `bash -n` clean.
- Manual: adopt → re-apply advances 1.18.0 → 1.23.0 (zero drift); manifest dup-id → single FAIL line.
