---
skill: code-reviewer
version: 1.8.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: branch fix-doc-truth-d12-d13a vs fix-diff-files-quotepath (v2.11.2) — D12 + D13a remediation
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
closed_from_previous_round: [D12, D13a]
---

# Code Review — D12 + D13a remediation (v2.11.2), round 1

**Verdict: `gate_pass: true`.** Documentation-truth fixes, which are the easiest kind to accept
carelessly: there is no runtime behaviour to break, so the usual review instincts have nothing to bite
on. The operative question is therefore narrow — **are the new sentences true, and can they rot again?**

## Phase 3.5 step 8 — was the class swept?

Ran the new step 8 on both claims rather than fixing only where the audit pointed:

| Claim | Other instances | Action |
|---|---|---|
| "no branch protection is required" | `quality.yml:7` (live) · `CHANGELOG.md:1044` (a historical entry recording that the line was added) | Fixed the live one. The CHANGELOG entry is a dated record of what was true then — annotated by this release's entry, not rewritten |
| Pillar 5 "rejects branch-protection walls" | `ADR-0012:73` · `ADR-0016:56` · `feynman/SKILL.md:138` | **Left alone, deliberately — all three are still true.** See below |
| "the missing-tags drift the post-v1.19 milestone fixed" | `phases.md:311` only | Fixed in the same sentence |
| `git tag -m` in a copyable example | `phases.md` only (the deploy logs already use `-F`) | Fixed |

**The doctrine reconciliation is the part worth checking, not the wording.** Three files say Pillar 5
rejects branch-protection walls, and the repo has an active ruleset — which looks like four
contradictions rather than one. It is not: the ruleset lists `deletion`, `non_fast_forward`,
`pull_request`, `required_signatures` and **not** `required_status_checks`. Verified directly:

```
gh api repos/:owner/:repo/rulesets/<id> --jq '[.rules[].type]'
  -> ["deletion","non_fast_forward","pull_request","required_signatures"]
```

So no CI job can gate a merge, admins bypass, and Pillar 5's actual claim holds. Only `quality.yml`'s
broader statement was false. A weaker fix — deleting the ruleset to make the sentence true — would have
traded signed commits and PR history for a tidier comment.

## Phase 1.5 — closure verification

| Item | Verified how |
|---|---|
| D13a: `core.md` §4 carries the tooth | `grep -cF "Every release is tagged on its merge commit"` → 1 |
| D13a: `phases.md` quotes it verbatim | same grep → 1. The citation now resolves by string match, not by charity |
| D12: `quality.yml` no longer asserts the false claim | assertion 3, plus reading the header |
| Nothing else regressed | 291 pre-existing assertions still pass; the suite is 294 |

**Each of the three new assertions was individually shown to fail.** Not as a batch — reverting
`core.md`'s phrase fired assertions 1 and 3, and assertion 2 stayed green because it reads a different
file, so `phases.md` was reverted separately to see it fire. Two reversions, three confirmed bites. A
batch reversion would have left assertion 2 unproven.

## The assertion caught the fix, which is the finding worth keeping

Assertion 3 **failed on its first run against the completed fix.** The new header explains what the
file used to claim, and in explaining it quoted the false sentence verbatim — so
`grep -q "no branch protection is required, by design"` matched the *correction*.

That is not a flaw in the assertion; a grep cannot distinguish an assertion from a quotation. The
correction was reworded to paraphrase the old claim instead of reproducing it, which is also better
documentation practice: a file that restates a false sentence verbatim is one careless copy-paste away
from asserting it again. **Weakening the assertion was the available alternative and would have been the
wrong call.**

## 🟡 MINOR-1 — three assertions pin three specific strings, not the general property

What would actually close this class is a check that **every quoted cross-document citation resolves** —
scan for `` `core.md` §N ("…") `` shapes and confirm the quoted text exists in the cited file. That is a
new gate rule, i.e. a feature, and this is a documentation-truth PR under hard rule 4.

The honest limitation: these three assertions guard the two citations the audit found. A fourth phantom
citation elsewhere in 41,482 lines of markdown would not be caught. Recorded rather than implied — the
general rule is the right eventual answer and `cites-resolve` is a plausible name for it.

## What I verified and did not flag

| Claim | How |
|---|---|
| `quality.yml` is still valid YAML after a 14-line comment block | `yaml.safe_load` — the CI would have failed on the next push otherwise |
| The `-F` heredoc example is actually correct | It is the exact form used successfully for `v2.10.1` and `v2.11.0` in this repo, after `-m` mangled `v2.10.0` |
| Adding a ratchet tooth to `core.md` creates no new obligation | The tagging requirement already existed in `phases.md`; §4 now makes it citable. That is why there is no `migrations.yml` entry, and the CHANGELOG says so |
| The stacked base is right | Branched from `fix-diff-files-quotepath`, not `main`, so `VERSION` and `CHANGELOG.md` do not conflict with PR #47. It must merge after #47 |
| No behaviour change | Nothing executable was touched except a CI comment block. The 291 pre-existing assertions are the evidence |

## Self-verification

Each closure was established by a command, and the two reversions were run separately precisely
because a single batch reversion would have let one assertion pass unproven. The one thing I initially
got wrong was the fix itself, caught by my own new assertion within a minute — recorded above rather
than smoothed over. No sub-agents.

## Required to close

Nothing. MINOR-1 names `cites-resolve` as the general form, deliberately out of scope here.
