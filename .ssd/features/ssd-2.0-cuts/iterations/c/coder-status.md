---
skill: coder
version: 1.4.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#c
consumed_by: [code-reviewer]
files_touched:
  - methodology/migrations.yml
  - methodology/migrate.sh
  - scripts/parity-test.sh
  - ssd/chapters/upgrade.md
  - docs/decisions/ADR-0013-project-upgrade-migration-manifest.md
  - VERSION
  - CHANGELOG.md
tests_added:
  - scripts/parity-test.sh   # fixture: migrate-obsoleted-in (+6 assertions, 53 → 59)
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 59/59 assertions"
lint_results:
  command: "bash -n methodology/migrate.sh && bash -n scripts/parity-test.sh"
  exit_code: 0
type_check_results:
  command: "n/a — markdown library + bash/awk (no type system)"
  exit_code: 0
feature_flag:
  name: not_applicable
  default: off
deferred:
  loaded: 0
  closed: []
  rolled_forward: []
spec_drift: false
---

# Coder Status — ssd-2.0-cuts iter C (the deprecation path)

Implemented the architect spec ([01-architect.md](01-architect.md)) verbatim — D1 resolved as the
**`obsoleted_in`** field (user-ratified). No spec drift.

## What changed

1. **`methodology/migrations.yml`**
   - `dev-profile-keys` gains `obsoleted_in: "2.0.0"` (comment on its **own line** — an inline `# …`
     after the value would leak into the parsed value, the iter-B MAJOR-4 class bug).
   - Two new `kind: guided`, `introduced_in: "2.0.0"` entries: `profile-concept-removed` and
     `single-surface-doctrine` (`detect: null`, single-line quoted `guidance` to match the existing
     `decision-record-doctrine` form and keep both bash parsers happy).
   - Header documents the new `obsoleted_in` field.

2. **`methodology/migrate.sh`** (the only engine change)
   - `read_manifest()` extracts `obsoleted_in` as a **trailing** 7th column; both
     `while IFS=$'\t' read -r … ob` consumers updated (a 6-var read would fold col 7 into `title`).
   - Selection loop guard (after the `--to` check):
     `if [[ -n "$ob" && -n "$TO" ]] && ! ver_gt "$ob" "$TO"; then continue; fi`.
   - No new flags, no status changes, `--apply`/`--adopt`/`--json`/version-bump untouched.

3. **`scripts/parity-test.sh`** — new fixture `migrate-obsoleted-in` (Fixture 21), wired into the run
   list. Six assertions: not offered at `--to 2.2.0`; both guided entries surface at 2.x;
   `dev-profile-keys` still offered at `--to 1.25.0`; guided entries not offered below 2.0.0;
   `--apply` to 2.x never writes `developer_profile` (the R2 regression this iteration exists to
   prevent).

4. **Docs/version:** `chapters/upgrade.md` paragraph on `obsoleted_in`; ADR-0013 `obsoleted_in`
   addendum (+ Status line note + rejected `applies_to: library` alternative); `VERSION` → 2.2.0;
   CHANGELOG 2.2.0 entry.

## Verification (all run, not asserted from memory)

| Check | Result |
|---|---|
| `bash scripts/parity-test.sh` | **PASS — 59/59** (was 53; +6 from the new fixture) |
| `bash methodology/gate-rules.sh --rules migration-manifest-current` | **PASS** — 7 entries; ids unique, ascending, ≤ VERSION 2.2.0 |
| `bash -n` migrate.sh + parity-test.sh | exit 0 |
| **D4 dogfood** — `migrate.sh --from 1.24.0 --to 2.2.0` on this repo | exactly two `GUIDED` lines (`profile-concept-removed`, `single-surface-doctrine`); `dev-profile-keys` correctly **suppressed** by `obsoleted_in` |

## Deferred to deploy / human-controlled (per architect D2/D4)

- **D2 — ADR-0011 revisit ledger on #15** (outward-facing `gh`; NOT auto-posted). Verify #15 carries
  ADR-0012's four "Revisit when" triggers; if absent, post the comment body below. No new issue
  (ADR-0012 anchors the ledger on #15).
- **D4 — adopt the two guided entries on this repo** (records 2.2.0, zero drift) in the deploy step,
  to keep the code PR free of a `project.yml` version bump:
  `bash methodology/migrate.sh --adopt profile-concept-removed` then `--adopt single-surface-doctrine`.

### Prepared #15 comment body (D2)

```markdown
## Deprecation-window / revisit ledger (ADR-0012 Pillar 4 · ADR-0011 revisit-aware issue)

SSD 2.0 (ssd-2.0-cuts) is shipped: iter A v2.0.0, iter B v2.1.0, iter C v2.2.0. Per ADR-0012
§ "Revisit when", these reversibility triggers are tracked here:

- [ ] **Profile concept removed** → reopen if onboarding-confusion signal recurs (users repeatedly
      lost without tiered guidance), OR a non-conversational consumer (CI/automation) needs the
      command surface as a stable contract.
- [ ] **Dual-surface doctrine removed** → reopen if a real tool/integration needs the command
      surface as a stable machine API (the parity doctrine's only genuine justification).
- [ ] **Verb set collapsed** → reopen if power users report the escape-hatch verbs became
      undiscoverable (progressive disclosure failed to disclose).
- [ ] **Warnings, not walls (Pillar 5)** → reconsider hard enforcement only if ungated defects
      reach users at a rate the discouragement + audit trail demonstrably fails to catch.
```

## Self-verification
1. Ran test/lint commands (not from memory) — outputs recorded above. ✓
2. No `# REVIEW:` markers added → `review_markers: 0` is accurate. ✓
3. Compared impl to `01-architect.md` — matches D1-ratified design; `spec_drift: false`. ✓
4. Feature flag N/A (manifest/doc change, not a runtime code path) — correctly recorded. ✓
5. Single-language (bash/awk + markdown); both bash files pass `bash -n`. ✓
