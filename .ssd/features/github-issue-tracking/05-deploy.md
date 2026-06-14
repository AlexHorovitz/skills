---
skill: systems-designer
version: 1.4.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: github-issue-tracking (iter A, v2.3.0)
consumed_by: [ssd]
deliverables:
  readiness_checklist: complete
---

# Deploy Readiness — github-issue-tracking iter A (v2.3.0)

**Platform:** markdown skills library + a `gh`-driven bash helper. `systems-designer`'s full
web/mobile/macOS deploy checklist is **N/A** — no runtime/service/migration/rollout surface. "Deploy"
= the tagged GitHub release; users get it via `~/.claude/skills/<skill>/`. Applicable checklist:

| Item | Status |
|---|---|
| Clean `/ssd gate` (no BLOCKER/MAJOR) | ✅ round-2 PASS — [04-code-review-round-2.md](04-code-review-round-2.md) (`gate_pass: true`, MAJOR-1 + MINOR-1 closed & verified) |
| `gate-rules.sh --base main` | ✅ `fail_count: 0` (incl. `skill-version-sync` PASS after the `ssd` 2.1.0→2.3.0 banner bump) |
| `parity-test.sh` | ✅ 59/59 |
| `bash -n methodology/issue-sync.sh` | ✅ syntax clean |
| `VERSION` + `CHANGELOG.md` bumped | ✅ 2.2.0 → 2.3.0; CHANGELOG `[2.3.0]` entry added |
| Skill banner sync | ✅ `ssd` 2.1.0 → 2.3.0 (chapters changed); `methodology`/`ssd-init` untouched (their content unchanged — banner-lag holds) |
| CI green on PR (`quality.yml`) | ⏳ verified at PR time |
| Tag the release after merge (R7) | ⏳ `git tag -a v2.3.0 <merge-sha>` post-merge |
| Default-off safety | ✅ `issue_tracking: off` ⇒ zero network, behavior identical to pre-feature — the property that makes this safe to merge dark |

## Failure modes for consuming projects
**None new when the toggle is off** (the default) — the feature is fully dormant. When **on**: the only
outward effect is best-effort `gh` issue create/update on phase advance; `preflight` failure (no `gh`,
unauthenticated, offline) degrades to warn-and-continue and never blocks an SSD phase. Closing issues
is gated behind `auto_close` (default prompt), so no surprise issue closures.

## Rollback story
Trivial — additive and opt-in. `git revert` the merge + retag. No consuming-project state is mutated
by merging (the toggle is off by default), so there is no consumer rollback. The dogfood issues
(#27/#28) are independent of the code and can be closed/reopened freely.

## Selective-commit manifest (ADR-0008)
**Commit (durable):** `methodology/issue-sync.sh`, `docs/decisions/ADR-0014-*.md`,
`.ssd/features/github-issue-tracking/*.md`, `ssd/chapters/state.md`, `ssd/chapters/phases.md`,
`ssd/SKILL.md`, `VERSION`, `CHANGELOG.md`.
**Do NOT commit (gitignored machine state):** `.ssd/current.yml`, `.ssd/current.notes.yml`,
`.ssd/project.yml` (the repo's own `issue_tracking: on` opt-in is local state; the *convention* +
default ship via the spec/ADR + iter-B migration).

## Outstanding (deploy-phase, human-gated — not yet performed)
Commit · push · PR · merge · `git tag -a v2.3.0` · post-merge sync #28→`ssd:phase/deploy` + decide on
closing #28 (`auto_close: false` ⇒ prompt). These are outward-facing and await explicit go-ahead.
