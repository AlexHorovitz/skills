---
skill: coder
version: 1.4.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: github-issue-tracking#b
consumed_by: [code-reviewer]
files_touched:
  - methodology/issue-sync.sh
  - methodology/gate-rules.sh
  - methodology/migrations.yml
  - methodology/SKILL.md
  - ssd-init/SKILL.md
  - ssd/chapters/phases.md
  - README.md
  - docs/decisions/ADR-0014-github-issue-state-tracking.md
  - scripts/parity-test.sh
tests_added:
  - close-feature-idempotent
  - close-feature-needs-confirm
  - close-feature-confirm
  - close-epic-open-children
  - close-epic-all-closed
  - issue-sync-current-skip-no-gh
review_markers: 0
test_results:
  parity: "69/69 (10 new assertions)"
  syntax: "bash -n clean on issue-sync.sh, gate-rules.sh, parity-test.sh"
lint_results:
  shellcheck: "not installed in env (flagged — same gap as iter A)"
type_check_results:
  n_a: "bash + markdown; no type checker"
feature_flag:
  name: integrations.github.issue_tracking
  default: "off (absent ≡ off — close paths dormant until opted in)"
spec_drift: false
---

# Coder Status — github-issue-tracking iter B

## Built (per the iter B architect spec)
1. **`methodology/issue-sync.sh` — `close-feature` / `close-epic`** (replaces the iter A exit-2 stubs):
   - `--confirm` flag + `auto_close_enabled()` reading `integrations.github.auto_close` via a small
     `yaml_scalar` (consistent with `gate-rules.sh yaml_get`, inline-comment-safe). `close_gate_or_exit10`
     centralizes the toggle/confirm gate → emits `needs-confirm` + **exit 10** when ungated.
   - `close-feature`: idempotent (already-CLOSED → exit 0 state=closed); else gated → `gh issue close`.
   - `close-epic`: `find_open_children` discovers children by the **`ssd:feature` label query**
     (MINOR-2/D2), word-boundary match so `#27` ≠ `#270`; any open child → exit 0 `state=skipped`
     (NOT an error, even with auto_close on); a failed list → exit 3 (never close on unknown). All-closed
     + gate → close. Header docs + exit-code table updated (added exit 10).
2. **`methodology/gate-rules.sh` — `issue-sync-current` rule** (ADR-0014 Q3): informational,
   SKIP-by-default (tracking off / no current.yml / `gh` unavailable / no issue binding). FAIL only on
   hard drift (recorded issue closed while active, or phase-label ≠ local phase). New
   `parse_active_workstreams` awk walker for `current.yml.active[]` (no PyYAML dep). Registered after
   `migration-manifest-current`.
3. **`migrations.yml`** — `github-issue-tracking-keys` (guided, introduced_in 2.3.0, ADR-0014): teaches
   the opt-in toggles. Guided not mechanical because absent ≡ off (nothing to migrate unless wanted).
4. **`ssd-init/SKILL.md`** — `issue_tracking: off` / `auto_close: false` in the github integration
   template, with intent comments.
5. **Docs:** README "GitHub Issue Tracking (optional)" section (convention table + enable snippet);
   `methodology/SKILL.md` script-catalog rows for `issue-sync.sh` **and** `migrate.sh` (the latter was
   missing — opportunistic completeness, flagged for the reviewer); `ssd/chapters/phases.md` close
   lifecycle prose (the `done` transition, D1 split guard, D3 iteration-qualified slug).
6. **ADR-0014** amended: Status Proposed→Accepted; "Amendments — iter B" (MINOR-2, D1, D3, Q3 resolved).
7. **Tests:** mock-`gh` shim (`setup_mock_gh` + `run_issue_sync`) — first unit coverage for
   `issue-sync.sh`. 6 new fixtures / 10 assertions: close-feature idempotent / needs-confirm / confirm;
   close-epic open-children-skip / all-closed-closes (+ #270 boundary); issue-sync-current SKIP-no-gh.

## Decisions & notes for the reviewer
- **D1 split** (epic-close guard half in orchestrator, half in script) is deliberate — keeps the script
  context-free + unit-testable. The orchestrator half is prose in `phases.md`, not executable; the
  "open planned iterations" guard is therefore enforced by convention, not code (acceptable: closing is
  already double-gated and reversible).
- `close-epic` skips on open children **even when `auto_close: true`** — auto_close authorizes the
  close, it does not bypass the all-children-closed precondition. Asserted by fixture 24.
- **Not done (deliberately deferred):** live GitHub dogfood of `close-*` against #27/#28, and creating
  the iter B feature issue (`current.yml.active[].issue` is still `null`). These are outward actions —
  surfaced to the user separately at ship, not run silently.
- VERSION / `ssd` banner bump to 2.4.0 handled at ship (deploy step), not here.

## Verification
- `bash scripts/parity-test.sh` → 69/69.
- `bash methodology/gate-rules.sh --base main` → no FAIL (issue-sync-current SKIPs: active issue null).
- `bash -n` clean on issue-sync.sh, gate-rules.sh, parity-test.sh. shellcheck unavailable in env.
