---
skill: ssd
version: 2.9.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-private-mode iteration b
consumed_by: []
---

# Deploy Log — ssd-private-mode iteration B (elective retrofit)

## Status

**Shipped to PR, awaiting merge.** Not tagged — `chapters/phases.md` § `/ssd ship` states the
orchestrator does **not** auto-tag, because tagging pushes to the remote and outward-facing actions
stay under explicit human control. The tag goes on the merge commit, by hand.

| | |
|---|---|
| Branch | `add-ssd-private-mode-b` |
| Commit | `0852d97` |
| PR | [#40](https://github.com/AlexHorovitz/skills/pull/40) — open |
| Epic issue | [#37](https://github.com/AlexHorovitz/skills/issues/37) (`ssd:epic`) — **iteration B completes it** |
| Feature issue | [#39](https://github.com/AlexHorovitz/skills/issues/39) (`ssd:feature`, `ssd:phase/deploy`) |
| Target version | v2.9.0 (tag pending merge) |
| Gate rounds | 2 |
| Predecessor | iteration A → v2.8.0, PR #36, squash `7a2c389`, tag `v2.8.0` |

## Gate at ship

```
PASS wip-commits              no WIP/checkpoint commits between main and HEAD
PASS tests-pass               `bash scripts/parity-test.sh` exit 0 (188/188)
SKIP feature-flag-present     no feature_flag_marker in .ssd/project.yml or .ssd/gate.yml
PASS adr-delta                2 ADR file(s) changed for 686 architectural lines
PASS frontmatter-valid        4 artifact(s) validated against schemas; 1 unvalidated
PASS no-leaky-state           no gitignored-by-policy files in diff
PASS skill-version-sync       9 skill example(s) match banner; 2 exempt
PASS migration-manifest-current  manifest valid (13 entries; ≤ VERSION 2.9.0)
SKIP feynman-clean            no feynman report in scope (vs main)
SKIP issue-sync-current       issue binding(s) present but gh lookups all failed
GATE 7 pass · 3 skip · 0 fail    EXIT=0
```

Committed **before** running the gate, applying iteration A's lesson without repeating it: on an
uncommitted branch `git diff main...HEAD` is empty, four diff-scoped rules SKIP, and the result reads
as a false green.

### On the three skips — two are N/A, one is not

- **`feature-flag-present`** — N/A by design. `project.yml` deliberately omits `feature_flag_marker`
  (a markdown library; the key would false-positive every doc edit). This iteration's flag is the
  `elective` manifest entry, which is inert until named.
- **`feynman-clean`** — N/A. **A SKIP here means "no failing audit in this change set", not "the
  project's beliefs are calibrated."** No `/feynman` ran this cycle, and not running it is not a
  violation.
- **`issue-sync-current`** — **not N/A.** It reports *"issue binding(s) present but gh lookups all
  failed"* when **zero `gh` calls were made**. This is the recorded `parse_active_workstreams`
  fragmentation defect (found at iteration A's ship): the parser treats every nested list item as a
  new workstream boundary, so the record carrying `issue:` has an empty slug and the rule's own guard
  skips it. **The gate did not verify the GitHub mirror.**

  **Compensating action** — a rule that *cannot run* must not be treated as one that *passed*, so the
  mirror was verified by hand at gate time:

  | | local (`current.yml`) | GitHub |
  |---|---|---|
  | iter B | `phase: review`, `issue: 39` | #39 OPEN · `ssd:phase/review` ✓ |
  | iter A | archived, `issue: 38` | #38 OPEN · `ssd:phase/deploy` |
  | epic | `epic: 37` | #37 OPEN · `ssd:epic` |

  In sync. This is a manual substitute for a broken rule, not evidence the rule works.

## Rail deviations

| Step | Reason |
|---|---|
| `systems-designer` (design) | Markdown/bash library — no production runtime, observability, or migration surface. `phases.md` sanctions skipping the bundled design pass for a skills library. |
| `systems-designer` (ship checklist) | Same. The library ships by tagging a version and pushing (`distribution.channel: direct-install`); no platform deploy checklist applies. |
| Rollout-advance / flag-removal (rail steps 7–8) | The `elective` manifest entry is permanent configuration surface, not a transitional flag. It is never removed. |

## Verification at ship

- **Parity 128 → 188 assertions** (+60 across both iterations). All 128 pre-existing pass.
- **Live dogfood** on a throwaway *team* repo — the retrofit case iteration A's greenfield dogfood
  could not cover — with jira+github integrations, real committed SSD history, a non-ASCII ADR, and a
  team-authored doc predating SSD:

```
plain /ssd upgrade                → private-mode NOT mentioned
--apply --from 2.0.0 --to 2.9.0   → index BYTE-IDENTICAL, still selective   ← acceptance criterion
--elect private-mode              → 3 SSD-owned + 1 UNCONFIRMED, exit 10, zero mutation
                                     docs/decisions/ADR-0001-café-auth.md classified correctly
                                     docs/runbooks/auth.md recognized by FRONTMATTER
                                     docs/architecture/legacy.md flagged for review
--elect private-mode --confirm    → tracked: .gitignore + app.py only; accented ADR on disk;
                                     gitignore_mode private; branch_pattern "{slug}";
                                     ONLY github's issue_tracking rewritten
re-run --confirm                  → "already private; nothing to do", exit 0, no dup pattern
--apply --confirm (no --elect)    → exit 2 usage error
```

- `shellcheck` unavailable (exit 127) — pre-existing environment gap, recorded identically in
  iteration A and in `github-issue-tracking` iter B.

## Outstanding — recorded, deliberately not fixed (hard rule 4)

1. **`parse_active_workstreams` fragmentation.** `issue-sync-current` can never PASS for a workstream
   carrying any nested list, and it blames `gh` for lookups it never attempted. One caller, contained.
   Needs its own PR **plus a fixture built from a realistic `current.yml`** — the existing fixture
   uses a flat stub, which is why this survived since v2.4.0.
2. **QUESTION-2** — `committed-gate-yml` / `strict-selective-gitignore` report `ERROR` for an absent
   precondition, reachable only when a ≥2.4.0 project has no `.gitignore` at all. Lives in
   `migrate.sh`, which this iteration had open; left alone on purpose.
3. **Tag drift** — v2.5.0, v2.6.0, v2.7.0 were never tagged.
4. **Feature issue #38** (iteration A) left open by user choice.
5. **No inverse migration.** Moving *out* of private mode is not built; the ADR-0017 amendment states
   this rather than implying symmetry.

## Post-merge checklist (human)

```bash
# after PR #40 merges to main
git tag -a v2.9.0 <merge-sha> -m "v2.9.0 — elective private-mode retrofit (ADR-0017 iter B)"
git push origin v2.9.0
# optional: backfill the missing tags v2.5.0 / v2.6.0 / v2.7.0

bash methodology/issue-sync.sh close-feature 39 --confirm     # iteration B
bash methodology/issue-sync.sh close-feature 38 --confirm     # iteration A, if you want it closed
bash methodology/issue-sync.sh close-epic 37 --confirm        # see the guard note below
```

**On closing epic #37.** Iteration B completes ADR-0017 — no iteration C is planned — so the epic is
genuinely closable, which is the first time that has been true. Both guards from
[ADR-0014](../../../../docs/decisions/ADR-0014-github-issue-state-tracking.md) D1 apply: the
orchestrator guard (no further iteration planned — satisfied) and the script guard (`close-epic`
refuses while any `ssd:feature` child is open, so **#38 and #39 must be closed first**). With
`auto_close: false`, each close returns exit 10 until `--confirm` is passed. That double gate is
working as designed; it is why #27 stayed open when #28 closed.
