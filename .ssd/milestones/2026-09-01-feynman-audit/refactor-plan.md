---
skill: refactor
version: 1.3.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: 2026-09-01-feynman-audit
consumed_by: [code-reviewer, ssd]
input_artifact: .ssd/milestones/2026-09-01-feynman-audit/feynman.md
items:
  - id: R1
    cites: [C3]
    pattern: add-missing-check
    files: [methodology/gate-rules.sh, scripts/parity-test.sh, ssd/chapters/enforcement.md, ssd/SKILL.md, methodology/migrations.yml]
    budget_hours: 2
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R2
    cites: [H1]
    pattern: harden-invariant
    files: [scripts/parity-test.sh]
    budget_hours: 1
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R3
    cites: [C7]
    pattern: truthful-reporting
    files: [methodology/gate-rules.sh, methodology/schemas/brief.yml, methodology/schemas/deploy.yml]
    budget_hours: 2
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R4
    cites: [C4, C2]
    pattern: delete-false-claim
    files: [ssd/SKILL.md, ssd/chapters/enforcement.md, ssd/chapters/phases.md, methodology/gate-rules.sh, methodology/migrations.yml, docs/decisions/ADR-0016-feynman-orchestrator-integration.md]
    budget_hours: 1
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R5
    cites: [C10]
    pattern: run-the-thing
    files: [methodology/store.sh, scripts/parity-test.sh, .github/workflows/quality.yml]
    budget_hours: 1
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
---

# Refactor Plan — closing the 2026-09-01 Feynman audit

**Governing principle, taken from the audit's own verdict:** *prefer a dumb rule that runs to a smart
audit that has to be trusted.* Every item below converts a finding from prose into something that
executes, or deletes a claim that cannot execute. Nothing here adds capability — that boundary is
hard rule 4, and it is what keeps R4 from becoming a feature (see § "Explicitly out of scope").

Each item cites a claim ID from [feynman.md](feynman.md). No cite → not in scope.

---

## R1 — `rails-walked`: the first gate rule that checks a rails invariant · cites **C3**

**Current state.** Eleven gate rules, all hygiene. Rails invariant 4 ("at least one code review with
`gate_pass: true`") had no mechanical check for the library's entire life, and PR #43 shipped v2.10.0
with zero review artifacts while every rule was green and CI passed.

**Target state.** A release — a change set that bumps `VERSION` — must carry a passing code review for
every `.ssd/features/<slug>/` directory it touches.

**Design decisions, and why the obvious alternatives were rejected:**

| Decision | Rejected alternative | Why |
|---|---|---|
| Fire only when `VERSION` changes | fire on every commit touching a feature dir | you commit a brief long before a review exists; a rule that fired there would be disabled within a week, and a disabled rule is worse than none |
| Only `code-review*.md` / `round-*.md` count | grep the dir for `^gate_pass: true` | `feynman.md` also carries `gate_pass:` — a passing epistemic audit would have satisfied a *code* review invariant |
| Scope to the feature dir, recursively | resolve the iteration being shipped | needs iteration resolution; not built. Stated as a limitation in the rule's own comment and in the enforcement table rather than left for a reader to discover |

**Closure: ✅ — and the closure falsified the finding's own prediction.** See
[feynman.md § Phase 8](feynman.md). Run against all 25 VERSION-bumping commits in history:
**1 FAIL, 18 PASS, 6 SKIP.** The audit predicted ≥2 failures and warned that >4 would mean the rails
were never walked. Actual compliance was **18/19** — the gap was in *checking*, not in *doing*. The
rule also returned PASS for #41, which falsifies the *"#41 was the first occurrence"* line carried in
CHANGELOG 2.10.1, in the ssd-store review, and in the audit's own first draft (now ledgered **C18**).

## R2 — an assertion whose verdict is not an integer is broken, not passing · cites **H1**

`_assert` compared `[[ "$ok" -eq 0 ]]`, and bash arithmetic coerces both `""` and `"banana"` to 0. A
substitution that produced **nothing** — a typo'd path, an errored pipeline, a grep against a missing
file — scored as a PASS, silently and green.

All 211 call sites were already guarded by an `echo 0`/`echo 1` fallback, so **this changes no result
today.** It makes the guard structural instead of conventional, which is the difference between
"sound" and "sound so far" — and this session had already produced one instance of the class.

**Closure: ✅.** Verified by reversion: removing the guard fails all 3 assertions of
`assert-rejects-non-integer`. The harness is tested inside an extracted probe, because a genuinely
broken assertion would otherwise fail the suite it is meant to be measuring.

## R3 — `frontmatter-valid` must not report absence when it means "no schema" · cites **C7**

Two halves:

1. **The false message.** At `count == 0` the rule emitted *"no SSD artifacts in scope"* on a diff
   containing artifacts the validator had seen and had no schema for. Now: *"N artifact(s) in scope,
   none with a matching schema."* Still a SKIP — nothing was checked — but it says why.
2. **The coverage gap behind it.** `brief` and `deploy` had no schema, so ~31 artifacts (the two
   largest unvalidated classes) were never checked against `chapters/state.md`'s documented MUST.
   Added `schemas/brief.yml` and `schemas/deploy.yml`.

**Measured consequence:** whole-tree validation went **90 PASS / 16 SKIP → 98 PASS / 8 SKIP**, and
surfaced **3 real violations** in older iterations (missing `project`, `scope`, `consumed_by`),
backfilled here. The remaining 8 SKIPs are milestone artifacts (`refactor-plan`, `skeptic-*`,
`verification`, `review-*`) — including *this file*. Recorded, not fixed.

Both schemas type `skill:` as `string`, not an enum, and say why: the 20 existing briefs carry **six**
distinct values and the 11 deploy logs split `ssd` / `systems-designer`. Pinning presence now and
recording the value drift is honest; blessing it with an enum would not be.

**Closure: ✅.** Verified by reversion twice — restoring the old message, and deleting `deploy.yml`.

## R4 — delete the override that does not exist · cites **C4**, **C2**

`/ssd ship --force` was documented as "the logged override" in four places. **No script accepts
`--force`, and `rail_deviations:` — the trace ADR-0012 Pillar 5 says it would write — has never been
written by any tool across 15 workstreams.** One document (ADR-0012) disclosed this honestly; four
asserted the mechanism existed.

Corrected in `ssd/SKILL.md`, `chapters/enforcement.md`, `chapters/phases.md`,
`gate-rules.sh`, and the user-facing `migrations.yml` guidance string. ADR-0016 reasoned *from* the
override's existence, so it gets an **addendum** rather than a rewrite — a decision record should not
be edited to have been right.

What the docs now say is what actually happens: you merge a red gate deliberately and write the reason
into the deploy log's rail-deviations table **by hand**.

**Closure: ✅ for the false claim. ❌ for the mechanism** — implementing a real `--force` that writes
`rail_deviations:` is new capability and belongs to a feature workstream with its own ADR.

## R5 — install the linter that was called an environment gap · cites **C10**

`lint_results:` recorded `shellcheck … exit_code: 127 — pre-existing environment gap` in five
artifacts across three features. **5,124 lines of shell had never been linted, once.** The gap was
`brew install shellcheck`, and it took thirty seconds.

**What it found, honestly reported:** **2 warnings and 9 findings total.** My own prediction in the
audit's Phase 7 was *"a handful of MINORs and at least one genuine quoting bug."* There was no quoting
bug. The code is clean. The prediction was wrong in the project's favour.

The one substantive finding was not a bug but a **coverage gap**: SC2043 flagged
`for pat in private; do … done`, a one-iteration loop left over from an iteration that never
materialised — and asking *why only private* revealed that **blanket mode, documented as supported by
the store, had no test at all.** New fixture `store-link-blanket-mode` covers it.

Added a `shellcheck` job to CI, so the finding cannot silently reopen the next time a local
environment lacks the tool.

**Closure: ✅.** `shellcheck -S warning methodology/*.sh scripts/*.sh` → **0 findings.**

---

## Explicitly out of scope, and why

| Finding | Why not here |
|---|---|
| **C2** — write `rail_deviations:` | New capability in the orchestrator, not a defect fix. Needs an ADR. Hard rule 4. |
| **C4 mechanism** — a real `--force` | Same. The false *claim* is deleted; the *feature* is a separate PR. |
| **C9** — 16 untagged v1.x releases | Sixteen outward-facing tag pushes. The maintainer's decision, not a refactor's. |
| **C11** — fork `rails.md` | A methodology policy choice about whether rail step 2 applies to a skills library. Belongs to a human. |
| **C12** — the store has no migration entry | Adding one is a `/ssd upgrade` capability question for the store, not for this audit. |
| **C5/C6** — CI has never failed; the `Overwatch` ruleset contradicts the workflow header | Config and policy, not code. Recorded. |
| **The referee experiment** — run SSD on another project | The highest-value item in the whole audit, and it cannot be done in a PR. It needs a real project and a human's working day. |
| **Every Jobs finding** | A different audit with a different standard. Mixing product-surface cuts into an epistemic refactor is how both get done badly. |

## Rollback

Five independent concerns, each revertable alone. R1 is the only behavioural addition to the gate; if
`rails-walked` proves noisy, unregistering one line in the runner disables it and the fixture will say
so loudly rather than passing vacuously.

## The blind spot this PR demonstrates on itself

`rails-walked` will **SKIP** on the very PR that ships it: this change set bumps `VERSION` but touches
no `.ssd/features/` directory — its artifacts live under `.ssd/milestones/`. The first release to
carry the rule is one the rule cannot check. That is a real limitation, it is stated in the rule's
comment and in the enforcement table, and it is written here rather than discovered later by someone
who trusted a green line.
