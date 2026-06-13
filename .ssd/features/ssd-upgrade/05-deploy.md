---
skill: systems-designer
version: 1.4.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade (iter A)
consumed_by: [ssd]
deliverables:
  readiness_checklist: complete
---

# Deploy Readiness — ssd-upgrade iter A (v1.21.0)

**Platform:** markdown skills library + bash/awk CLI helper. `systems-designer`'s full deploy
checklist (web/mobile/macOS) is **N/A** — no runtime/service/migration/rollout surface. Deploy = the
tagged GitHub release; users get it via `~/.claude/skills/<skill>/`. Applicable checklist:

| Item | Status |
|---|---|
| Clean `/ssd gate` (no BLOCKER/MAJOR) | ✅ [04-code-review.md](04-code-review.md) — PASS; MINOR-1 closed inline |
| `gate-rules.sh --base main` PASS/SKIP | ✅ incl. `skill-version-sync` PASS |
| `parity-test.sh` | ✅ 20/20 (incl. 2 new migrate fixtures) |
| `bash -n methodology/migrate.sh` | ✅ syntax clean |
| CI green on PR (`quality.yml`) | ⏳ verified at PR time |
| `VERSION` + `CHANGELOG.md` bumped | ✅ 1.20.1 → 1.21.0 |
| Tag the release after merge (R7) | ⏳ `git tag -a v1.21.0 <merge-sha>` post-merge |
| Rollback story | trivial — additive (new command + manifest + engine); `git revert` the merge + retag. No project mutation (read-only), so no consumer rollback needed. |

**Failure modes:** none new for consuming projects — iter A is detect-only (reports drift, writes
nothing). The corruption risk of a bad migration (ADR-0013 R1) is structurally absent until iter B
introduces `--apply`. The bash engine degrades safely (missing manifest → exit 3; missing project
files → detect returns absent → PENDING).

**Monitor post-deploy:** N/A (no telemetry). Real-world signal: the tool already flags this repo's
own `gitignore_mode` drift — that's the validation that detection works on a live project.
