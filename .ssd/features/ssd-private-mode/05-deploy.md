---
skill: ssd
version: 2.8.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-private-mode (iteration A)
consumed_by: []
---

# Deploy Log — ssd-private-mode (iteration A)

## Status

**Shipped to PR, awaiting merge.** Not tagged — `chapters/phases.md` § `/ssd ship` states the
orchestrator does **not** auto-tag, because tagging pushes to the remote and outward-facing actions
stay under explicit human control. Tagging happens after the merge, by hand.

| | |
|---|---|
| Branch | `add-ssd-private-mode` |
| Commit | `cc6fe46` |
| PR | [#36](https://github.com/AlexHorovitz/skills/pull/36) — open |
| Epic issue | [#37](https://github.com/AlexHorovitz/skills/issues/37) `[ADR-0017] private mode` (`ssd:epic`) |
| Feature issue | [#38](https://github.com/AlexHorovitz/skills/issues/38) (`ssd:feature`, `ssd:phase/deploy`) |
| Target version | v2.8.0 (tag pending merge) |
| Gate rounds | 3 |

## Gate at ship

```
PASS wip-commits              no WIP/checkpoint commits between main and HEAD
PASS tests-pass               `bash scripts/parity-test.sh` exit 0
SKIP feature-flag-present     no feature_flag_marker in .ssd/project.yml or .ssd/gate.yml
PASS adr-delta                2 ADR file(s) changed for 808 architectural lines
PASS frontmatter-valid        5 artifact(s) validated against schemas; 1 unvalidated
PASS no-leaky-state           no gitignored-by-policy files in diff
PASS skill-version-sync       9 skill example(s) match banner; 2 exempt
PASS migration-manifest-current  manifest valid (12 entries; ≤ VERSION 2.8.0)
SKIP feynman-clean            no feynman report in scope (vs main)
SKIP issue-sync-current       no active workstream has an issue binding
GATE 7 pass · 3 skip · 0 fail    EXIT=0
```

**The first gate attempt was not reported as a pass.** With zero commits on the branch,
`git diff main...HEAD` was empty and four diff-scoped rules never ran — including `no-leaky-state`,
the rule this feature is about. Raw output read `5 pass · 0 fail, exit 0`, which is exactly the
[ADR-0015](../../../docs/decisions/ADR-0015-ssd-init-gate-readiness.md) Context failure. Real signal
came from `--staged`, then the full gate above once committed. The gate's own footer — *"a skip is a
check that did not run"* — is what made the hollow run visible.

**On the three skips.** `feature-flag-present`: no `feature_flag_marker` by design — `project.yml`
documents that adding one would false-positive every doc edit in a markdown library; this feature's
flag is the `gitignore_mode` config value. `feynman-clean`: **SKIP means "no failing audit in this
change set", not "the project's beliefs are calibrated"** — no `/feynman` ran this cycle, and not
running it is not a violation. `issue-sync-current`: accurate at gate time (bindings were null); see
the defect below, found immediately after they were created.

**`adr-delta` = 808 lines** matched the pre-commit prediction exactly, computed by mirroring the
rule's own filter and array form.

## Rail deviations

| Step | Reason |
|---|---|
| `systems-designer` (design) | Markdown skills library — no production runtime, observability, or migration surface. `phases.md` sanctions skipping the bundled design pass for a skills library. |
| `systems-designer` (ship checklist) | Same. No platform deploy checklist applies; the library "ships" by tagging a version and pushing to GitHub (`project.yml.distribution.channel: direct-install`). |
| Rollout-advance / flag-removal (rail steps 7–8) | The flag is a permanent user-facing configuration axis (`gitignore_mode: private`), not a transitional flag. It is never removed — same status as `selective` and `blanket`. |

## Verification at ship

- **Parity 83 → 128 assertions**, all green. All 83 pre-existing pass.
- **Live dogfood** on a throwaway private repo (this repo stays `selective` — ADR-0008 makes its
  `.ssd/` history a deliverable): full feature cycle → commit contained only `app.py` +
  `auth_service.py` (254 lines), **zero SSD artifacts**; gate 6 pass · 4 skip · 0 fail;
  `git status --untracked-files=all` empty; ADR confirmed untracked via `git ls-files --error-unmatch`.
- **Four negative paths** verified live: force-added ADR → `FAIL no-leaky-state` + exit 1;
  `issue_tracking` on → `REFUSED` exit 4; mode typo → `FAIL … leak detection is NOT running`;
  promoted gate inputs → `tests-pass` + `feature-flag-present` both PASS.
- `shellcheck` unavailable (exit 127) — pre-existing environment gap, recorded identically in the
  `github-issue-tracking` iter-B status.

## 🟠 Defect found during ship — NOT fixed here (hard rule 4)

Creating the issue bindings immediately exposed a **pre-existing defect** in
`gate-rules.sh`'s `parse_active_workstreams`:

```
$ parse_active_workstreams .ssd/current.yml
  [ssd-private-mode|deploy|]      <- slug + phase, no issue
  [||]  × 16                       <- one per nested list item
  [||38]                           <- the issue, with NO slug
```

The awk treats **any** `^[[:space:]]*-[[:space:]]` line as a new workstream boundary
(`flush(); have=1`). But `rail_deviations`, `adrs_authored`, and `touches` are all **documented v2
schema fields that are lists**, so a single workstream fragments into ~18 records. The record holding
`issue:` has an empty `slug`, the rule's `[[ -n "$slug" ]]` guard skips it, `checked` stays 0, and it
emits:

```
SKIP issue-sync-current :: issue binding(s) present but gh lookups all failed — mirror not checkable
```

**Zero `gh` calls were made.** The detail string asserts a cause that did not occur — a misleading
signal on top of a dead rule.

**Impact.** `issue-sync-current` can never PASS for any workstream carrying any nested list — i.e.
essentially every real workstream. It has most likely never returned PASS since it shipped in v2.4.0.
Blast radius is contained: `rule_issue_sync_current` is the parser's only caller.

**Why it was never caught.** The existing fixture builds a flat synthetic `current.yml`
(`slug`/`phase`/`issue`, no nested lists) — it tests a shape no real workstream has. The same theme
as the rest of this workstream: *the test passes because it tests something simpler than reality.*

**Deliberately not fixed in this PR.** Hard rule 4 — *"Refactor only after shipping — separate PRs,
never mixed with feature work."* PR #36 is scoped to private mode and its gate already passes; folding
in an unrelated parser rewrite would violate the rule this methodology enforces. Recommend its own
issue and PR, with a fixture built from a **realistic** `current.yml` (nested `rail_deviations`,
`adrs_authored`, and `touches`) rather than a flat stub.

## Remaining work

**Iteration B** — retrofit via `/ssd upgrade`: the `private-mode` migration entry,
`detect_`/`apply_` functions, the **itemized-consent interlock** before any `git rm --cached`, the
history-not-rewritten warning, and `branch_pattern` plumbing in `chapters/workstreams.md`. Tracked on
epic #37. Iteration A never runs `git rm --cached` — the one destructive operation is quarantined
behind its own review cycle.

**Recorded, unfixed** (each deserves its own issue):
- `parse_active_workstreams` fragmentation — above.
- **QUESTION-2** — `committed-gate-yml` / `strict-selective-gitignore` still report `ERROR` for an
  absent precondition, but only when a ≥2.4.0 project has no `.gitignore` at all.
- **SUGGESTION-1 residue** — none; adopted in round 3 as a real set-equality test.
- **Tag drift** — highest tag is `v2.4.0` while `VERSION` was already 2.7.0 before this change:
  **v2.5.0, v2.6.0, and v2.7.0 were never tagged.** Pre-existing, not introduced here, and the exact
  drift the post-v1.19 milestone was supposed to have closed. Worth backfilling alongside the v2.8.0 tag.

## Post-merge checklist (human)

```bash
# after PR #36 merges to main
git tag -a v2.8.0 <merge-sha> -m "v2.8.0 — gitignore_mode: private (ADR-0017 iter A)"
git push origin v2.8.0
# consider backfilling the missing tags: v2.5.0, v2.6.0, v2.7.0
```

Then close feature issue #38 (`issue-sync.sh close-feature 38 --confirm`). **Leave epic #37 open** —
iteration B remains, and the epic-close guard exists precisely to prevent a premature close.
