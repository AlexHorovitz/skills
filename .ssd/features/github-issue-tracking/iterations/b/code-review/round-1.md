---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: add-github-issue-tracking-b (main...HEAD)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 1
  suggestion: 0
  nit: 1
gate_pass: true
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — github-issue-tracking iter B (round 1)

**Verdict: GATE PASS** (0 BLOCKER, 0 MAJOR). One MINOR + one QUESTION + one NIT, none blocking.

## Scope reviewed
`main...HEAD` — `issue-sync.sh` (close-feature/close-epic + auto_close gate + child discovery),
`gate-rules.sh` (issue-sync-current rule + parse_active_workstreams), `migrations.yml`, `ssd-init`,
`README`, `methodology/SKILL.md`, `ssd/chapters/phases.md`, `scripts/parity-test.sh` (mock-gh harness).
Not a remediation branch; no `deferred.yml` present → deferred-findings phase skipped.

## What I verified (traced, not pattern-matched)
- **`find_open_children` word-boundary regex** `Epic: #<e>([^0-9]|$)` — traced: `#27` matches
  `Epic: #27`/`Epic: #27 `; `#270` does **not** match (next char `0` is `[0-9]`). The parity fixture
  `close-epic-all-closed` asserts this exact #27-vs-#270 case. Correct.
- **close-epic open-children precedes the close gate** (issue-sync.sh:306 before :311) — so even
  `--confirm` cannot close an epic with an open child. `auto_close: true` likewise can't bypass it
  (fixture `close-epic-open-children` asserts skip with auto_close ON). Correct and matches D1.
- **`find_open_children` rc handling** — a failed `gh issue list` returns rc 2 → close-epic exits 3
  ("skipping to avoid a premature close"), never treats a failed lookup as "no children." This is the
  dangerous false-negative and it's handled. Good.
- **issue-sync-current never FAILs on a flaky/absent gh** — SKIPs on no-gh; a per-issue `gh view`
  failure `continue`s without counting; all-flaky → checked==0 → SKIP. Verified live: on this repo
  (tracking on, `issue: null`) the rule SKIPs "no active workstream has an issue binding."
- **parse_active_workstreams** — section toggling on top-level keys, `- ` item boundaries, comment
  skipping; extracts `github-issue-tracking|code|null` from the live current.yml (ran it). Correct.

## Findings

### 🟡 MINOR-1 — `issue-sync-current` runs the gh preflight (2 network calls) before checking whether any binding exists
`gate-rules.sh:590` does `gh auth status` + `gh repo view` *before* `parse_active_workstreams`
(`:608`). Consequence: an opted-in repo with no synced issues yet (every `issue:` still `null` — e.g.
this very repo right now) pays two `gh` round-trips on **every** `/ssd gate`, only to then SKIP with
"no issue binding." It also means a clean gate needs network even when there is provably nothing to
check.

**Fix:** parse active workstreams first; if no workstream has a numeric `issue:`, SKIP immediately and
never touch `gh`. Run the gh preflight only when there is at least one binding to verify. Small reorder,
no behavior change to the PASS/FAIL paths. (Non-blocking, but cheap and worth doing now.)

### 💭 QUESTION-1 — the epic-close "no planned iteration" guard is prose-only (orchestrator), not enforced in code
By design (ADR-0014 D1) `close-epic` only checks GitHub children; the "is another iteration planned?"
half lives in the orchestrator prose (`phases.md`). With `auto_close: true`, the deterministic safety
net for premature epic-close is therefore the LLM correctly reading `current.yml` before proposing the
close. This is acceptable here (closing is reversible — reopen is one click — and `auto_close` defaults
to `false`, so the user is prompted). Flagging to confirm the team is comfortable that the strongest
guarantee under `auto_close: true` is convention, not code. No change requested unless you want a
belt-and-suspenders script flag (e.g. `--has-planned-iterations` the orchestrator passes).

### 📝 NIT-1 — stale required-subcommand usage string
`issue-sync.sh:108` still reads `a subcommand is required (preflight|ensure-epic|ensure-feature|set-phase)`
— it omits `close-feature|close-epic`. Cosmetic; update for completeness.

## Notes (non-findings)
- Opportunistic add of the `migrate.sh` script-catalog row in `methodology/SKILL.md` (flagged by the
  coder) is correct and in-scope-adjacent; fine to keep.
- `auto_close_enabled` treats `true|yes|on` as truthy — consistent with how `issue_tracking: on` is
  read elsewhere. Fine.
- parity 69/69; `bash -n` clean; shellcheck unavailable in env (pre-existing gap, same as iter A).

## Round-1 inline closures (same session)
Both non-blocking findings were fixed inline before ship (gate already passed; no round 2 needed):
- **MINOR-1 closed** — `rule_issue_sync_current` now collects numeric `issue:` bindings via
  `parse_active_workstreams` *before* any `gh` call; SKIPs with zero network when there are none.
  Verified: this repo still SKIPs "no active workstream has an issue binding" and ran no gh calls.
- **NIT-1 closed** — `issue-sync.sh:108` required-subcommand string now lists `close-feature|close-epic`.
- **QUESTION-1** — left open for the user (prose-only orchestrator guard under `auto_close: true`);
  no code change pending an answer. Default `auto_close: false` keeps the close prompted + reversible.
