---
skill: systems-designer
phase: deploy
feature: github-issue-tracking
iteration: b
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
version: v2.4.0
gate_pass: true
gate_rounds: 1
---

# Deploy Readiness — github-issue-tracking iter B (v2.4.0)

**Platform:** markdown skills library — "deploy" = tag a version + push to GitHub (per
`project.yml.notes`). No runtime, no migration, no rollout sequence.

## Pre-merge checklist
- [x] `bash scripts/parity-test.sh` → **69/69** (10 new mock-`gh` assertions).
- [x] `bash methodology/gate-rules.sh --base main` → **0 FAIL** (issue-sync-current SKIPs: active
      `issue:` is null; migration-manifest-current 8 entries ≤ VERSION 2.4.0).
- [x] `bash -n` clean: issue-sync.sh, gate-rules.sh, parity-test.sh.
- [x] Code review round 1 **PASS** (0 BLOCKER / 0 MAJOR); MINOR-1 + NIT-1 closed inline; QUESTION-1
      surfaced to user.
- [x] VERSION 2.3.0 → **2.4.0**; `ssd` banner 2.3.0 → 2.4.0; CHANGELOG 2.4.0 entry.
- [ ] shellcheck — **not run** (not installed in this env; pre-existing gap, same as iter A).

## Default-off safety (the rollout story)
The entire close lifecycle + gate rule are dormant unless `integrations.github.issue_tracking: on`.
A project without the toggle makes **zero** network calls and behaves byte-for-byte as before — so
merging this is always shippable, no flag-flip sequence required. The toggle is a permanent user
choice, not temporary scaffolding (no "remove the flag" stage).

## Post-merge (human-gated, per phases.md `/ssd ship`)
1. Squash-merge the PR to `main`.
2. Tag the merge commit:
   ```bash
   git tag -a v2.4.0 <merge-sha> -m "v2.4.0 — github-issue-tracking iter B (close lifecycle + gate rule)"
   git push origin v2.4.0
   ```
3. **Live dogfood (outward — surface before running):** create the iter B feature issue
   (`ensure-feature github-issue-tracking#b ...` under epic #27) and drive its phase labels; cache the
   number in `current.yml.active[].issue`. On iter B `done`, prompt-close it (auto_close is `false`).
   Epic #27 closes only once iter B's issue closes AND no further iteration is planned.

## Rollback
Revert the PR. No data migration, no state to unwind. Any GitHub issues created during dogfood are
closed/reopened by hand (cheap, reversible — the reason close is prompt-gated).
