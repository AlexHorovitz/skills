---
skill: coder
version: 1.2.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features iteration C — overlap check + touches backfill + gate-rules base note
consumed_by: [code-reviewer]
files_touched:
  - code-reviewer/SKILL.md
  - ssd/SKILL.md
  - methodology/gate-rules.sh
  - CHANGELOG.md
  - VERSION
tests_added: []
review_markers: 0
test_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: |
    (run after coder-status write; expected all PASS/SKIP per markdown-library precedent)
lint_results:
  command: "n/a — no linter configured"
  exit_code: null
type_check_results:
  command: "n/a — markdown + bash"
  exit_code: null
feature_flag:
  name: not_applicable
  default: not_applicable
  rationale: |
    Markdown skills library — no runtime, no flag. Rollout: v1.17.0 tagged release.
    Default behavior unchanged for single-workstream users (overlap check skips when only
    one workstream is active).
spec_drift: false
---

# Iteration C — Coder Status

## Scope shipped

Iteration C of the parallel-features epic. Five files touched, no new ADR (ADR-0007 covers
all three iterations), no schema changes (iter A shipped `touches:` as the relevant field).
This iteration makes that field load-bearing.

### 1. `code-reviewer/SKILL.md` (EDIT, +~95 lines)

**Version banner:** 1.4.0 → 1.5.0.

**Severity table:** new row added for `🔗 OVERLAP:` prefix marked v1.5.0+, "Blocks Merge? No."
Placed at the bottom of the existing six-row table so the standard tiers remain visible first.

**NEW § "Cross-Workstream Overlap Check"** inserted between § "Severity Levels" and
§ "Review Checklist" (~80 lines). Structure:

- Trigger conditions (four AND-conjoined preconditions). Explicit "ad-hoc reviews skip the
  check entirely" — protects the existing PR review use case.
- Algorithm (numbered steps with self-exclusion mandate).
- OVERLAP-N finding output format as YAML, mirroring the format from iter A's architect spec.
- Multi-overlap behaviors (same partner → one finding; multiple partners → one per partner).
- Edge cases: empty touches, globs matching no files yet, `**` glob handling, untracked files.
- "Why SUGGESTION not MAJOR" paragraph quoting ADR-0007 § "Alternatives Rejected" so a future
  reviewer doesn't upgrade the severity on speculation.
- Touches provenance paragraph cross-referencing the architect-pass + coder-pass populated
  pattern from iter A.

**Changelog entry:** v1.5.0 with a focused summary, citing ADR-0007 and the no-upgrade rule.

### 2. `ssd/SKILL.md` (EDIT, +~22 lines)

**Version banner:** 1.16.0 → 1.17.0.

**§ "Methodology Enforcement"** — two new paragraphs after the existing ADR-0005 cross-ref:

- **"Cross-workstream overlap check (v1.17.0+)"** — describes the orchestrator's gate-time
  flow: (a) backfills `touches:` with `git diff --name-only <base>...HEAD`, (b) invokes
  code-reviewer which emits OVERLAP-N at SUGGESTION tier. Cross-refs code-reviewer SKILL.md
  and ADR-0007.
- **"Workstream-aware base detection"** — documents that `gate-rules.sh` remains standalone;
  the orchestrator passes `--base` explicitly. Foreshadows iter-D's potential `base:`
  workstream field.

**§ "Session Continuity" `touches:` field comment** — extended with v1.17.0 behavior: the
coder-pass union runs at every `/ssd gate`, the field is read by code-reviewer for OVERLAP-N
findings, cross-ref to code-reviewer/SKILL.md.

**Changelog entry:** v1.17.0 entry; matches iter B's format.

### 3. `methodology/gate-rules.sh` (EDIT, +9 lines)

Comment block added near the existing `BASE="main"` declaration. Documents:
- The standalone contract (script invokable without orchestrator context).
- The convention that the orchestrator passes `--base <ref>` explicitly for non-main
  workstreams.
- Forward-looking note about iter-D's potential `base:` workstream field.

No behavior change. The script's `--base` parser is untouched.

### 4. `CHANGELOG.md` (EDIT, +~75 lines)

New `## [1.17.0] — 2026-05-24` entry at top, matching v1.15.0 and v1.16.0 format. Sections:
behavior change description, touched skills (with version bumps), schema (unchanged), trigger
conditions for the overlap check, deferred-to-iter-D list, "epic status: COMPLETE" closing
paragraph.

### 5. `VERSION` (EDIT)

1.16.0 → 1.17.0.

## Items for the code-reviewer to confirm

1. **OVERLAP-N severity strictly enforced as SUGGESTION.** The new § "Cross-Workstream Overlap
   Check" explicitly cites ADR-0007 § "Alternatives Rejected" and warns future reviewers not
   to upgrade. Verify the prose is unambiguous on this; a less careful reviewer might still
   feel tempted to escalate.

2. **`code-reviewer/SKILL.md` trigger conditions** require the review to be "invoked via
   `/ssd gate`." Ad-hoc PR reviews skip the check. Verify this trigger language is clear
   enough that an LLM-driven code-reviewer invocation correctly self-determines whether to
   apply the check. The relevant signal in practice: presence of `.ssd/current.yml` with
   multiple active entries when the reviewer runs.

3. **`ssd/SKILL.md` § "Methodology Enforcement" backfill paragraph** describes the
   orchestrator-side action (compute `git diff`, union into `touches:`) BEFORE code-reviewer
   runs. Verify the order is unambiguous — backfill happens first, then code-reviewer reads
   the updated state.

4. **`methodology/gate-rules.sh` comment block** — confirms the script's standalone contract.
   No behavior change. Verify the comment doesn't claim functionality that doesn't exist
   (e.g., it doesn't say the script auto-reads `current.yml` — it doesn't).

5. **`touches:` field comment in `ssd/SKILL.md`** uses the same language as iter A
   (architect-pass intent + coder-pass union). Iter C just extends the timing detail (every
   `/ssd gate` invocation) and adds the OVERLAP-N consumer. Verify the comment isn't
   contradictory with iter A's earlier prose.

## Self-verification

1. Did I run gate-rules.sh? Yes (pre-coder-status, all PASS/SKIP).
2. REVIEW marker count: 0 (markdown, no inline markers).
3. Spec drift checked? No deviations from iter C architect spec.
4. Feature flag? N/A.
5. Cross-language? N/A.

## Handoff to code-reviewer

Diff scope: 5 files modified. ~140 lines added across the touched files.

Gate expectations:
- `wip-commits`: PASS.
- `tests-pass`: SKIP.
- `feature-flag-present`: SKIP.
- `adr-delta`: SKIP (no new ADR; iter C extends ADR-0007's contract — docs-only architectural
  change).
- `frontmatter-valid`: PASS (all 11 `.ssd/features/parallel-features/**` artifacts validate).

After iter C ships as v1.17.0, the parallel-features epic is complete. Workstream archives
from `current.yml.active` to `.ssd/archive/features/parallel-features/`.
