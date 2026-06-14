---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: add-ssd-2.0-cuts-c vs main (ssd-2.0-cuts#c)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 1
  suggestion: 1
  nit: 0
gate_pass: true
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — ssd-2.0-cuts iter C (round 1)

**Verdict: PASS** (blocker=0, major=0). The `obsoleted_in` deprecation path is implemented
correctly and matches the user-ratified architect design (D1 = `obsoleted_in`, not `applies_to:
library`). No spec drift. The two open items below are non-blocking.

## Scope reviewed
`methodology/migrate.sh`, `methodology/migrations.yml`, `scripts/parity-test.sh`,
`ssd/chapters/upgrade.md`, `docs/decisions/ADR-0013-…md`, `VERSION`, `CHANGELOG.md`. Diff read in
full; engine logic traced; boundary cases executed live (not asserted from memory).

## What I verified (Phase 3 + 3.5 — the guard is new defensive branch code)

1. **Select-loop guard direction** ([migrate.sh:356](methodology/migrate.sh)) —
   `if [[ -n "$ob" && -n "$TO" ]] && ! ver_gt "$ob" "$TO"; then continue; fi`. `ver_gt` is strict
   (equal → "not greater"), so `! ver_gt ob TO` skips when `ob <= TO` — i.e. when the target is
   **at or past** the removal version. Traced + executed:
   - `--to 2.2.0` → dev-profile-keys **skipped** (0 lines). ✓
   - `--to 2.0.0` (the `ob == TO` boundary) → **skipped** (0 lines) — correct, the removal version
     itself is the first world without the convention. ✓
   - `--to 1.25.0` (staged, pre-removal) → **still offered**. ✓
2. **`read_manifest` trailing column** — `ob` appended last in both the per-entry and `END` prints;
   reset in the `- id:` rule. **Both** consumers (the only two: [migrate.sh:318](methodology/migrate.sh)
   `--adopt` loop, [migrate.sh:348](methodology/migrate.sh) main loop) updated to `read -r … ti ob`.
   The diff's own comment flags the fold-into-`title` hazard a 6-var read would cause — good defensive
   doc. Confirmed no third consumer exists.
3. **`val()` parse cleanliness** — the `obsoleted_in` value carries **no inline comment** (the two
   `#` lines sit above it on their own lines), so the iter-B MAJOR-4 leak (`val()` strips quotes but
   not trailing `# …`) cannot recur. The coder even annotated *why* in the manifest. ✓
4. **Manifest-gate compatibility** — `migration-manifest-current` ignores unknown fields; ran it
   live → PASS (7 entries; ids unique, ascending incl. the two equal `2.0.0` entries via the rule's
   `<=` check; ≤ VERSION 2.2.0). ✓
5. **Contiguous version-bump unaffected** — a skipped (obsoleted) entry `continue`s before the
   `advancing`/`satisfied` block, so it neither advances nor caps the recorded version: a removed
   convention is correctly transparent to version progression. ✓
6. **JSON mode** — skipped entries emit no object and don't disturb comma handling; `--json` output
   parses and lists exactly the 5 live entries (dev-profile-keys absent, both guided present). ✓
7. **Parity coverage** — `migrate-obsoleted-in` exercises both directions **and** the regression this
   iteration exists to kill (`--apply` to 2.x never writes `developer_profile`). Harness 53 → 59. ✓
8. **Docs/ADR accuracy** — ADR-0013 addendum is correctly titled distinctly from the pre-existing
   "Iteration C addendum (v1.24.0)" (ssd-upgrade) with a disambiguating blockquote; the quoted guard
   line matches the code; the rejected `applies_to: library` alternative is recorded. `chapters/upgrade.md`
   link `../../docs/decisions/…` resolves correctly from the one-level-deeper chapter dir (the v1.25.0
   MAJOR-1 lesson). CHANGELOG 53→59 accurate. ✓

## Findings

### 💭 QUESTION-1 — obsoleted guard is inert when `$TO` is empty
The guard requires `-n "$TO"`. If the `VERSION` file is missing **and** no `--to` is passed, `TO=""`,
so the guard never fires and an obsoleted entry would be offered (and, under `--apply`, re-applied).
This is **not a regression**: the existing `--to` upper-bound check ([migrate.sh:349](methodology/migrate.sh))
is guarded on `-n "$TO"` identically, so empty-`TO` already means "no upper bound, select everything
> FROM." The new guard simply inherits that pre-existing degenerate behavior rather than defending
against a broken install the rest of the engine also doesn't defend against. Non-blocking — flagging
only so it's a conscious choice. If desired, a future hardening could make empty-`TO` fail fast
(`VERSION` missing is an abnormal install), but that's an engine-wide decision, not iter-C scope.

### 💡 SUGGESTION-1 — `--adopt` path doesn't apply the obsoleted guard
The `--adopt` loop ([migrate.sh:317-320](methodology/migrate.sh)) doesn't skip obsoleted entries.
This is **moot today** — no obsoleted entry is `kind: guided` (the only adoptable kind), so nothing
adoptable is obsoletable. If a future release ever obsoletes a *guided* convention, revisit whether
`--adopt` of an obsoleted-for-your-target entry should be rejected. No action needed now; noted so
the assumption is on record.

## Self-verification
1. Read the actual files + diff, not memory. ✓
2. No BLOCKER/MAJOR raised; all claims traced or executed. ✓
3. Citations checked against current line numbers. ✓
4. Stated assumptions explicitly (QUESTION-1 empty-TO; SUGGESTION-1 future obsoleted-guided). ✓
5. No sub-agents used. ✓
6. Speculative items kept at QUESTION/SUGGESTION, not MAJOR. ✓
7. Phase 3.5 applied to the new guard branch (boundary, empty-input, apply-path, JSON, version-bump). ✓
8. Not a remediation branch (`remediation_mode: false`); no `deferred.yml` present → deferred phase skipped. ✓
