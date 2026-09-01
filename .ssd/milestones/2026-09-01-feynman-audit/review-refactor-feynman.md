---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: branch refactor-feynman-findings vs main (v2.11.0) — remediation of the 2026-09-01 Feynman audit
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 0
  suggestion: 1
  nit: 0
gate_pass: true
remediation_mode: true
round: 1
closed_from_previous_round: [C3, C4, C7, C10, H1]
---

# Code Review — refactor-feynman-findings (v2.11.0), round 1

**Verdict: `gate_pass: true`.** `remediation_mode: true`, so Phase 1.5 (did each item close its cited
finding?) and Phase 3.5 (is the new destructive/defensive code correct?) are the operative phases.
No BLOCKER, no MAJOR. One MINOR and one SUGGESTION, both recorded rather than fixed inline.

## Phase 1.5 — closure verification, against the code and not the plan

| Item | Cites | Closed? | How I verified |
|---|---|---|---|
| R1 `rails-walked` | C3 | ✅ | Ran the rule against 25 historical releases in detached worktrees: 1 FAIL / 18 PASS / 6 SKIP. Reverting its one registration line fails 6 fixture assertions |
| R2 `_assert` guard | H1 | ✅ | Removing the guard fails all 3 assertions of `assert-rejects-non-integer`. Confirmed independently that `[[ "" -eq 0 ]]` and `[[ "banana" -eq 0 ]]` are both true in bash |
| R3 message + schemas | C7 | ✅ | Reverting the `elif` restores "no SSD artifacts in scope" and fails 2 assertions; deleting `deploy.yml` fails a third. Whole-tree validation 90 → 98 PASS, exit 0 |
| R4 `--force` | C4 | ✅ (claim) · ❌ (mechanism) | `grep -rn -- '--force'` across `ssd/ methodology/ docs/ README.md`: every surviving mention either states it does not exist or is ADR-0016's original text under its new addendum. The one unrelated hit is `gh label create --force` |
| R5 shellcheck | C10 | ✅ | `shellcheck -S warning methodology/*.sh scripts/*.sh` → 0 findings. CI job added, so a missing local binary cannot reopen it |

**Parity 264 → 281**, exit 0. `bash -n` clean on all four scripts.

## What I checked hardest, because it is the only behavioural addition

`rule_rails_walked` is the one thing here that can newly FAIL someone's gate, so I went looking for
ways it fires wrongly:

| Probe | Result |
|---|---|
| Ordinary work-in-progress commit (brief, no review) | SKIP — `VERSION unchanged`. Correct: a rule that fired here would be disabled in a week |
| Release touching no feature dir | SKIP with that reason. **This is the PR's own case** — see MINOR-1 |
| A `feynman.md` with `gate_pass: true` in the feature dir | still FAILs. Correct — the `find` filter admits only `code-review*.md` / `round-*.md`, so a passing epistemic audit cannot satisfy a code-review invariant. This was a real trap: the naive `grep -rlq '^gate_pass: true' <dir>` would have fallen into it |
| A review with `gate_pass: false` | still FAILs |
| A review nested under `iterations/<iter>/code-review/` | PASSes — `find` is recursive |
| Feature dir in the diff but deleted from the worktree | skipped via `[[ -d ]]`, not counted, no false FAIL |
| Empty `missing` array under `set -u` | guarded by `${#missing[@]} -gt 0` before `${missing[*]}` |
| `grep -qx "VERSION"` vs a path like `docs/VERSION.md` | `-x` anchors the whole line, so only a top-level `VERSION` triggers |

## 🟡 MINOR-1 — the rule SKIPs on the release that ships it, and 6 of 25 historical releases

`rails-walked` keys on `.ssd/features/<slug>/` paths in the diff. A release whose artifacts live under
`.ssd/milestones/` — every refactor and remediation release, including **this one** — is unchecked.
The experiment shows the real rate: **6 of 25** releases SKIP for this reason, among them v2.6.0 and
v2.7.0, the two remediation releases from the *previous* Feynman audit.

Not a MAJOR: the rule is strictly better than the nothing it replaces, it states this limitation in
its own comment, in the enforcement table, and in the refactor plan, and the alternative (require an
artifact of *some* kind per release) is a stronger policy claim than a refactor should make. But a
reader who sees `SKIP rails-walked` on a release should not read it as "invariant 4 held" — and the
skip text says `release touches no .ssd/features/ directory`, which is accurate but does not say *and
therefore nothing was checked*. Worth tightening when the milestone-artifact schemas land.

## 💡 SUGGESTION-1 — 8 artifact classes still have no schema, and one of them is the plan for this work

After R3 the remaining SKIPs are all milestone artifacts: `refactor-plan`, `refactor-prs`,
`skeptic-before`, `skeptic-after`, `verification`, `review-*`. `refactor/SKILL.md` already specifies
its frontmatter precisely — including per-item `cites` — so `schemas/refactor.yml` is nearly free and
would validate the file this review is reviewing. Left out to keep R3's scope to the two classes C7
actually named. Non-blocking.

## What I verified and did not flag

| Claim | How |
|---|---|
| The 3 backfilled artifacts are metadata-only | Diffed each: `project`, `scope`, `consumed_by`, `version` added to frontmatter; **not one line of body text changed.** Backfilling knowable metadata is not rewriting a record |
| Both new schemas were derived from real artifacts, not invented | Intersected the frontmatter keys of all 20 briefs and 11 deploy logs before writing them. This is the fixture-authenticity discipline the audit's Phase 5 named, applied to schemas |
| `skill: string` rather than an enum | Deliberate and documented in both schema headers: 6 distinct `skill:` values across the briefs. An enum would have failed most of the tree and blessing the drift silently would have been worse |
| ADR-0016 got an addendum, not an edit | Confirmed the original text is intact above the new section. A decision record should not be edited to have been right |
| The manifest entry is append-only | `migration-manifest-current` **FAILed** when I first inserted it mid-file, and PASSes now (14 entries). The gate caught my own ordering mistake |
| The new fixture referenced in a comment actually exists | The SC2043 comment cites `store-link-blanket-mode`; it is written and registered. A refactor that removes false claims must not add one |
| `store-link-blanket-mode` could not go red | **Stated plainly:** it tests pre-existing correct behaviour, so it is a *coverage addition, not a red-green test*. Calling it a closure would be the mislabelling this project has now caught itself doing six times |

## Self-verification

Every closure above was checked by running something, not by reading the plan. The four reversions
were executed and their exact failing assertions recorded. The one claim I initially accepted and then
tested was the audit's own C3 implication — the experiment contradicted it, and both the audit
(Phase 8, new claim C18) and the CHANGELOG now say so rather than quietly keeping the flattering
version. No sub-agents, so no unverified escalation.

## Required to close

Nothing. MINOR-1 and SUGGESTION-1 are recorded for the milestone-artifact schema work.
