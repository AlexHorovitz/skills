---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: add-github-issue-tracking (iter A diff vs main)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 0
  suggestion: 2
  nit: 1
gate_pass: true
remediation_mode: true
round: 2
closed_from_previous_round: [MAJOR-1, MINOR-1]
---

# Code Review — github-issue-tracking (iter A), round 2

**Verdict: GATE PASS** — `blocker == 0 AND major == 0`. The round-1 MAJOR is closed and verified
against the code (not the coder-status). One MINOR remains, deliberately deferred to iter B with the
reviewer's assent; two SUGGESTIONs and one NIT are non-blocking.

## Closures verified (against the code, per the round-2 discipline)

**🟠 MAJOR-1 (stdout/JSON contract) — CLOSED.** Traced in the current file:
- `emit()` [issue-sync.sh:63-71](methodology/issue-sync.sh#L63-L71): text-mode status now goes to
  **stderr** (`>&2`, line 69); JSON object to stdout (66-67).
- The bare return echo is guarded `if [[ $JSON -eq 0 ]]; then echo "$num"; fi` in both
  `ensure-epic` [:122](methodology/issue-sync.sh#L122) and `ensure-feature` (same pattern).
- Re-ran the round-1 reproductions: text `num="$(… ensure-epic …)"` → `27` (clean); `… --json` →
  one valid object, `jq .issue` → `27`; exit code `0` in `--json` mode (the `if/then/fi` tail can't
  leak a falsy `&&` status). Confirmed.

**🟡 MINOR-1 (false-empty → duplicate create) — CLOSED.** `find_issue_by_prefix`
[:102-109](methodology/issue-sync.sh#L102-L109) captures the `gh` exit code and `return 2` on a list
failure (107); both callers treat rc 2 as "unknown" and `exit 3` rather than create
([:117-119](methodology/issue-sync.sh#L117-L119)). Verified with a stub `gh` failing `issue list` →
`exit 3`, no create. `--limit` raised to 1000 (104). The genuine-empty path (rc 0, no match) still
correctly proceeds to create. Confirmed.

## Carried forward (non-blocking)

- **🟡 MINOR-2** (epic linkage = body mention, not task-list entry) — **deferred to iter B** with the
  resolution the round-1 review preferred: amend the data model to "epic child-tracking = `ssd:feature`
  label query, not the task list," to be done when `close-epic` lands (it performs that query). Tracked
  in `03-coder-status.md` § "Deferred to iter B". Acceptable to ship iter A: the body `**Epic:** #E`
  mention is a real GitHub back-reference.
- **💡 SUGGESTION-1** (set-phase sed locale fragility) / **💡 SUGGESTION-2** (document min `gh` version)
  / **📝 NIT-1** (`emit` detail not JSON-escaped) — unchanged, non-blocking; the two REVIEW markers in
  the source flag the first two for iter B.

## Gate-rules.sh
`fail_count: 0`. `adr-delta` / `no-leaky-state` SKIP on the uncommitted tree (will exercise at commit;
ADR-0014 present, machine-state gitignored). `skill-version-sync` PASS (chapter edits don't touch
`SKILL.md` example blocks — banner/VERSION bump remains a ship-phase action). Parity harness 59/59.

## Result
Gate is green. The workstream is shippable. Remaining MINOR-2 + suggestions are tracked for iter B and
do not block. Recommend `/ssd ship` (with the deploy-phase version/CHANGELOG/banner sync called out in
the coder-status).
