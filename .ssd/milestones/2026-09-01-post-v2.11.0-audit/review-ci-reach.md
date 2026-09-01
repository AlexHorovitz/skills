---
skill: code-reviewer
version: 1.8.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: branch fix-ci-covers-stacked-prs vs main (v2.11.3) — CI reach on stacked PRs
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 2
  question: 0
  suggestion: 0
  nit: 0
gate_pass: true
remediation_mode: true
round: 1
closed_from_previous_round: []
---

# Code Review — CI reach on stacked PRs (v2.11.3), round 1

**Verdict: `gate_pass: true`.** Two MINORs, both about the limits of what this change can prove.

This finding is not in the audit's ledger. It was found by running `/ssd gate` on a stacked PR and
reading the CI line rather than the gate line — the audit never tested a stacked PR because none
existed when it ran. Worth noting for the next audit's `not_examined`: **CI reach was never in scope.**

## Phase 3.5 step 8 — was the class swept?

The class is "a workflow whose trigger is narrower than its purpose." Swept the whole file:

| Trigger / job | Reach | Verdict |
|---|---|---|
| `pull_request` | was `branches: [main]` → **now unfiltered** | the defect, fixed |
| `push` | `branches: [main]`, left alone | correct — a push has no base ref, which is why `gate-rules` is already `if: github.event_name == 'pull_request'` |
| `gate-rules` job | was `--base origin/main` → **now `github.base_ref`** | the second half; without it the first half produces noise |
| `parity-test` job | no base ref needed | unaffected, and it is why #48's *content* was eventually covered |
| `shellcheck` job | no base ref needed | unaffected |

No other workflow files exist (`ls .github/workflows/` → one file), so the sweep is complete rather
than sampled.

## The second change is what makes the first one useful

Unfiltering `pull_request` alone would have been a trap. A stacked PR would then trigger the gate, and
the gate would diff against `main` — reporting **the whole stack**, not the PR under review. Concretely:
PR #48 would have gone red on `feynman-clean` for an audit report it did not contain, inheriting its
parent's finding. A check that fires with the wrong scope trains you to ignore it, which is worse than
one that does not fire.

Verified the two halves are independent by reverting them separately: three reversions, six assertions,
each seen to fail.

## 🟡 MINOR-1 — the assertions are structural, and cannot prove the workflow runs

A bash suite cannot exercise a GitHub Actions trigger. All six assertions parse or grep the YAML. The
fixture says so in its header, and the CHANGELOG repeats it, because the failure mode here is a reader
concluding "300 assertions pass, so stacked PRs are covered."

**What would actually prove it: a green check on a stacked PR.** This release's own PR is not stacked,
so it does not supply that evidence. The next stacked PR does. Until then this is a well-reasoned
change with structural guards, not a verified one — the same distinction the audit drew about the
`shellcheck` CI job after a single green run.

## 🟡 MINOR-2 — `github.base_ref` on a PR from a fork

`git fetch origin "$BASE_REF"` assumes the base branch exists on `origin`, which holds for same-repo
PRs and for fork PRs too (the base is always in the upstream repo). What I did **not** test is a fork
PR at all — this repo has never received one, so `pull_request` vs `pull_request_target` semantics,
secret availability and checkout refs are untested territory here.

Unfiltering the trigger widens *which* PRs run CI, and a first fork PR would now be the first fork PR
to run it. Not a defect in this diff; a newly reachable state worth knowing about before it happens.

## What I verified and did not flag

| Claim | How |
|---|---|
| YAML still parses | `yaml.safe_load`; also asserted the parsed `pull_request` value is falsy rather than grepping for `branches:`, which appears under `push:` too and would have matched the wrong one |
| `base_ref` cannot be shell-injected | It reaches bash only via `env:`. Asserted the interpolation occurs exactly once and on the `BASE_REF:` line |
| `push` scoping is deliberate, not overlooked | Reverted it: assertion 6 fires. The comment explains why a push-triggered gate has no base |
| No behaviour change for PRs into `main` | `github.base_ref` is `main` there, so the fetch and the `--base` are byte-identical to before |
| The suite's own reversion discipline held | Three separate reversions, not one batch. A batch would have left "push is still scoped to main" and the two `base_ref` assertions unproven |

## Self-verification

Every assertion was seen to fail. One of them failed against the *finished fix* first — an over-broad
regex matching the correct `env:` line — and was restated rather than deleted; that is recorded in the
fixture comment and the CHANGELOG. The claim I deliberately did **not** make is that this change is
verified end to end. It is not, and MINOR-1 says so.

## Required to close

Nothing. MINOR-1 resolves itself the next time a stacked PR opens; MINOR-2 is a recorded unknown.
