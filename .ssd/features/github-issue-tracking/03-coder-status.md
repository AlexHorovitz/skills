---
skill: coder
version: 1.4.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: github-issue-tracking
consumed_by: [code-reviewer]
files_touched:
  - methodology/issue-sync.sh
  - .ssd/project.yml
  - ssd/chapters/state.md
  - ssd/chapters/phases.md
tests_added: []
review_markers: 2
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 59/59 assertions"
lint_results:
  command: "bash -n methodology/issue-sync.sh"
  exit_code: 0
  stdout_tail: "syntax ok (shellcheck not installed in this environment)"
type_check_results:
  command: "n/a — bash + markdown, no type system"
  exit_code: 0
feature_flag:
  name: integrations.github.issue_tracking
  default: off
spec_drift: false
---

# Coder Status — github-issue-tracking (iter A)

## What shipped (iter A)
1. **`methodology/issue-sync.sh`** (new, +~190 lines) — the one-way SSD→GitHub mirror helper, in the
   house style of `gate-rules.sh`/`migrate.sh` (bash 3.2-compatible, `set -uo pipefail`, exit-code
   driven, `--json`, `-h/--help` self-doc, license footer). Subcommands:
   - `preflight` — `gh` present + authed + repo resolvable; **exit 3** otherwise (caller no-ops).
   - `ensure-epic <ADR-NNNN> <title>` — find-or-create the `ssd:epic` issue (title `[ADR-NNNN] …`).
   - `ensure-feature <slug> <phase> <epic#>` — find-or-create the `ssd:feature` issue, linked to epic.
   - `set-phase <issue#> <phase>` — swap the single `ssd:phase/*` label + refresh the body Phase token.
   - `close-feature`/`close-epic` — **iter B** (ADR-0014 Q2); documented stub, exits 2.

   Idempotency is by **local exact-prefix match** over `gh issue list` (not GitHub search), so
   hyphenated slugs / bracketed ADR ids can't mis-tokenize and spawn duplicates.
2. **`.ssd/project.yml`** — added `issue_tracking` + `auto_close` under the github integration. This
   repo opts **in** (`issue_tracking: on`) to dogfood; the documented default for other projects is `off`.
3. **`ssd/chapters/state.md`** — documented the new optional `current.yml.active[]` fields `epic:` /
   `issue:` (lazy-cached, `branch:` precedent).
4. **`ssd/chapters/phases.md`** — orchestrator prose: on every Feature-Loop phase advance, when
   `issue_tracking: on` and `preflight` passes, run ensure-epic → ensure-feature → set-phase; each
   action surfaced before it runs (rule-zero); gh-absent (exit 3) → warn + continue, never block.

## Live dogfood (verified against real issues)
- `preflight` → ok. `ensure-epic ADR-0014` → **finds #27** (no dup). `ensure-feature
  github-issue-tracking … 27` → **finds #28** (no dup). Idempotency re-confirmed after edits.
- `set-phase 28 code` → label swapped `ssd:phase/design` → `ssd:phase/code` **and** body Phase token
  updated to `code`, verified via `gh issue view 28`. `--json` mode emits a single parseable object.
- Issue #28's `epic: 27` / `issue: 28` are cached in `current.yml.active[]`.

## Test / verification
- `scripts/parity-test.sh` → **59/59 PASS** (no regression; I touched shared chapters + project.yml
  but not `gate-rules.sh`).
- `bash -n` clean. `shellcheck` not installed in this env — **flagged for the reviewer / CI** (the
  other `methodology/*.sh` would benefit from a shellcheck CI step; out of scope to add here).
- No automated test for `issue-sync.sh` itself: it requires a **mock-`gh`** harness, which the
  architect scoped to **iter B** alongside the `issue-sync-current` gate rule. Iter A relies on the
  live dogfood above as its verification. Called out so the gap is visible, not silent.

## Spec adherence / drift
`spec_drift: false`. One intentional simplification within spec: the architect's body block listed
`Gate rounds` and `Branch` lines; iter A's `feature_body_block()` emits the `Workstream · Phase ·
Epic` line only (the fields available without coupling the helper to `current.yml` parsing). The
richer block + a `--gate-rounds`/`--branch` pass-through is a natural iter-B addition. Recorded here
rather than amending ADR-0014, since it narrows rather than contradicts the design.

## REVIEW markers (2)
1. `gh issue create --json number` needs gh ≥ 2.37; a URL-parse fallback covers older gh. Confirm the
   minimum supported gh version and whether the fallback can be dropped.
2. The `set-phase` body-token `sed` is coupled to the exact `**Phase:** <token>` format; a format
   change silently no-ops the body refresh (label still updates). Acceptable for a best-effort
   mirror; worth a fixture in iter B.

## Deferred to iter B (explicit)
- `close-feature` / `close-epic` automation behind `auto_close` (ADR-0014 Q2).
- `issue-sync-current` gate rule (ADR-0014 Q3) + mock-`gh` parity fixture.
- `migrations.yml` entry for the new `project.yml` keys (so `/ssd upgrade` teaches them).
- README convention docs.
- Richer feature-issue body block (gate rounds, branch).

## Not committed
Working-tree only, on branch `add-github-issue-tracking`, per SSD (commit/push only on request).
VERSION bump + CHANGELOG entry + `ssd`/`ssd-init` skill-banner sync are **deploy-phase** actions, not
done here — flagged for `/ssd gate` (skill-version-sync) and `/ssd ship`.

---

## Round-2 remediation (2026-06-14) — closes round-1 review findings

Addressing [04-code-review.md](04-code-review.md) (round 1, gate_pass: false).

**MAJOR-1 — CLOSED.** Split the machine channel from diagnostics in `issue-sync.sh`:
- `emit()` now writes the human `OK …` line to **stderr** in text mode (stdout reserved).
- The bare `echo "$num"` in `ensure-epic`/`ensure-feature` is guarded by `if [[ $JSON -eq 0 ]]`, so
  `--json` stdout is a single valid object (the number is in `.issue`) and text-mode stdout is *only*
  the number.
- Verified live: `num="$(… ensure-epic …)"` → `27` (was `"OK … \n27"`); `… ensure-epic --json` →
  one line, `jq .issue` → `27` (was object + bare int). `set-phase` unchanged (was already clean).
  Function tail uses `if/then/fi` so the exit code stays 0 in `--json` mode.

**MINOR-1 — CLOSED.** `find_issue_by_prefix` now distinguishes a `gh` list **failure** from a genuine
empty result: it captures the call's exit code and `return 2` on failure; both `ensure-*` callers
treat rc 2 as "unknown" and **exit 3 (skip)** rather than create — verified with a stub `gh` that
fails `issue list` (→ `exit 3`, no create). `--limit` raised 200 → 1000 (only `ssd:epic`/`ssd:feature`
issues count); server-side `--search … in:title` confirmation noted as the iter-B hardening beyond 1000.

**MINOR-2 — deferred to iter B (with reviewer's preferred resolution).** The review preferred amending
the data model to "epic child-tracking = `ssd:feature` label query, not the task list" over maintaining
a task list in `ensure-feature`. That's a doc/ADR change best made when iter B implements
`close-epic` (which will do the label query). Tracked in the deferred list; the body `**Epic:** #E`
mention (which creates a real GitHub back-reference) stays as the linkage for iter A.

**SUGGESTION-1/-2, NIT-1 — non-blocking, left as-is** (REVIEW markers remain for the gh-floor and
sed-locale notes; both are best-effort/cosmetic and acknowledged).

**Regression:** `scripts/parity-test.sh` → 59/59. `bash -n` clean.

Files changed in round 2: `methodology/issue-sync.sh` only.
