---
skill: code-reviewer
version: 1.8.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: branch fix-diff-files-quotepath vs main (v2.11.1) — D1 remediation
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 0
  suggestion: 0
  nit: 0
gate_pass: true
remediation_mode: true
round: 1
closed_from_previous_round: [D1, D3]
---

# Code Review — D1 remediation (v2.11.1), round 1

**Verdict: `gate_pass: true`.** `remediation_mode: true`, so Phase 1.5 (did the item close its cited
finding?) and Phase 3.5 (is the new code correct, **including step 8 — was the class swept?**) are the
operative phases. One MINOR, recorded.

This is the first review to run Phase 3.5 step 8, which this same PR adds. Applying a checklist item to
the PR that introduces it is either good discipline or circular; I think good discipline, because step 8
is a *grep*, and the grep either finds other instances or it does not.

## Phase 3.5 step 8 — was the class swept?

Every place the library enumerates paths out of git, not every place missing a flag:

| Site | Exposed? | How established |
|---|---|---|
| `gate-rules.sh:300,302` — `diff_files()` | **yes, the defect** | control test: ascii FAILs, accented PASSes while tracked |
| `migrate.sh:488` — `ls-files -z` | no | already fixed, iteration B MAJOR-1 |
| `gate-rules.sh:697` — `ls-files --error-unmatch .ssd` | no | literal ASCII pathspec, exit status only, no enumeration |
| `store.sh`, `issue-sync.sh` | no | **neither enumerates paths at all** — no `ls-files`, no `--name-only` |
| `frontmatter-validate.py` | no | filesystem walk, never invokes git |

**This corrects the audit that commissioned the fix.** D3 was graded 🟠 on `grep -c '\-z'` across four
scripts — a measure of a missing flag, not of an exposure. Two enumerators exist; one was blind. The
audit's "three other scripts unswept" was inference presented as measurement, and it erred toward
making the finding sound worse. Regraded ✅ in the audit's Phase 8 with the correction stated.

## Phase 1.5 — closure verification, against the code

| | |
|---|---|
| Red first | **5 assertions** failed against the unfixed enumerator |
| Green | **291/291**, exit 0 |
| Reversion | `sed` the flag out → exactly those 5 re-fail. Not 4, not 6 |
| Live control, outside the fixture | `FAIL no-leaky-state :: 1 file(s) gitignored by policy but tracked: .ssd/archive/café.md` |
| shellcheck | 0 findings at warning level |
| `bash -n` | clean |

## What I attacked, and what I found

| Probe | Result |
|---|---|
| Does `-c` before the subcommand actually apply? | Yes — `git -C <root> -c core.quotepath=false diff …`. Verified by output, not by man page |
| Does it fix **both** branches, `--staged` and `BASE...HEAD`? | Both changed. The `--staged` path is what a pre-commit hook uses, i.e. the one that would catch a leak *before* it lands |
| Space in the path | still caught (`with space.md`) — pinned as a regression guard |
| Apostrophe | still caught (`quote'name.md`) — pinned |
| Umlaut / other non-Latin-1 | verified raw in the enumerator test |
| Literal newline in a path | **still broken.** `-z` would survive it; see MINOR-1 |
| Does the fixture pin behaviour or implementation? | Behaviour — it asserts what the *rules* report, so swapping to `-z` later stays free |
| `rails-walked` on an accented dir with no review | now FAILs, and no longer claims the release touched no feature directory |
| `frontmatter-valid` on a **mixed** diff | now names both artifacts. Previously it validated the ASCII one and skipped the accented one — a real FAIL with silently partial coverage, the hardest variant to notice |

## 🟡 MINOR-1 — the newline case remains, deliberately, and is the only thing `-z` would have bought

`core.quotepath=false` returns raw bytes but the pipeline is still newline-delimited, so a path
containing a literal `\n` would still split into two bogus entries. `-z` closes that; it also changes
`diff_files()`'s contract and moves six consumers.

Not a MAJOR: the exposure is a filename with an embedded newline under `.ssd/` or the three `docs/`
trees, which requires deliberate effort to create, whereas an accented filename is ordinary in any
non-English project. The trade is stated in the function's own comment rather than left implicit, and
the fixture tests behaviour so a later move to `-z` needs no test changes. Revisit if anyone ever
reports it — not before.

## What I verified and did not flag

| Claim | How |
|---|---|
| One assertion passed for the wrong reason on the first red run | Reproduced: the accented case was masked by the ASCII control still in the diff. The fixture now `git rm --cached`s the control and **asserts that it is gone** before testing the accented path |
| The fix is not a v2.11.0 regression | `git log -S` puts the un-flagged call in `ee3b897`, v1.5.0. 27 releases |
| The code-reviewer bump is complete | 1.7.0 → 1.8.0 in the banner, the example block, and a changelog entry. `skill-version-sync` PASSes: 9 match, 2 exempt |
| No behaviour change for ASCII repos | The flag only affects how git *renders* paths it would otherwise quote. Every pre-existing assertion (281) still passes untouched |
| `migration-manifest-current` | PASSes; no manifest entry added, and none is warranted — nothing to install, the rule ships in the script and the change is invisible to a project on ASCII paths |

## Self-verification

Every closure was established by running something. The one claim I initially accepted and then tested
was the audit's own assumption that `-z` was the fix; testing it produced a smaller change and a
narrower true statement about the blast radius, and the audit was amended rather than left flattering
itself. No sub-agents, so no unverified escalation.

## Required to close

Nothing. MINOR-1 is a recorded trade with its rationale in the code.
