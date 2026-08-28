---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: working-tree diff on add-ssd-private-mode (19 paths) + QUESTION-1 / SUGGESTION-1 closures
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 1
  suggestion: 0
  nit: 0
gate_pass: true
remediation_mode: true
round: 3
closed_from_previous_round: [QUESTION-1, SUGGESTION-1]
---

# Code Review — ssd-private-mode (iteration A), round 3

User directed both carried-forward items be resolved now rather than deferred. Both are closed and
verified by reversion. **`gate_pass: true`.** Parity **127 → 128** (a net gain of 1 despite the
mirror fixture shrinking from 8 spot-check assertions to 4 stronger ones).

One **new** QUESTION is raised below — an adjacent case I deliberately did **not** fix, to keep this
change reviewable.

## Phase 1.5 — prior-round follow-up

| ID | Status | How verified |
|---|---|---|
| QUESTION-1 | **closed** | Reverted both NOOP returns → 4 assertions fail (`NOOP not ERROR`, `no ERROR line`, `exits 0 not 3`, `detail is actionable`). Restored → pass. |
| SUGGESTION-1 | **closed** | Added a pattern to each file in isolation → the set-equality assertion fails in **both** directions, naming the offending pattern under `-v`. |

---

## QUESTION-1 — closed: `NOOP` is now distinct from `ERROR`

The defect was larger than round 1 characterized it. Round 1 called it a cosmetic status problem;
tracing the code showed `engine_error=1` reaches
[migrate.sh:568](../../../methodology/migrate.sh#L568) → **`exit 3`**. So
`/ssd upgrade --apply` announced a **broken upgrade engine** on any project that simply has no test
framework yet — a blameless, ordinary state.

The root cause is two individually-correct decisions colliding:

- [ADR-0015](../../../docs/decisions/ADR-0015-ssd-init-gate-readiness.md) Decision 1 specifies a
  *commented* `test_command` placeholder when no framework is detected.
- The manifest's `detect` probe deliberately does not match a commented key — *"it does not define
  the input, so the convention stays PENDING until a real key exists."*

The apply returned success; `detect` then correctly reported absent; the engine had no vocabulary for
"cannot apply" and called it a failure.

**Fix.** `apply_dispatch` now has an explicit return-code contract
([migrate.sh:392-406](../../../methodology/migrate.sh#L392)): `0` applied · `8` NOOP · `9` DEFER ·
other ERROR. The report loop renders `NOOP`/`DEFER` with `satisfied=0` and **without** setting
`engine_error`, so the convention stays outstanding, the recorded version correctly does not advance
past it, and a later `--apply` re-offers it once the precondition exists.

Verified end to end on a realistic 2.4.0-era project (selective block present, no test framework):

```
NOOP gate-inputs-present :: … — no test framework detected; commented placeholder written to
                            .ssd/gate.yml — set test_command by hand once tests exist
SKIP-present committed-gate-yml · SKIP-present strict-selective-gitignore
GUIDED feynman-gate-rule
exit=0
```

Was `ERROR` + `exit 3`. The control arm (add a `Makefile` `test:` target → `APPLIED`) is asserted in
the same fixture, so the fix cannot pass by making the apply inert.

**This is ADR-0015's own distinction, applied to the migration engine.** That ADR exists because a
rule that *cannot run* was indistinguishable from one that *passed*. The engine had the inverse bug:
a state that *cannot apply* was indistinguishable from one that *failed*. Recorded as a second
addendum item on ADR-0015, since that ADR owns gate inputs.

**Bonus: a dead contract made live.** `9 = DEFER` was documented in `apply_dispatch`'s comment but
handled by **neither** producer nor consumer — every non-zero return collapsed to ERROR. The first
apply function to return 9 would have produced a spurious ERROR + exit 3. Handling it alongside 8
costs two lines and removes the trap; leaving it would have reproduced round-1 MINOR-2 (a new branch
sitting next to an inconsistent sibling).

## SUGGESTION-1 — closed: the mirror test can now actually fail

The old fixture asserted four **known** patterns appeared in both files. It could not detect the
failure it existed to prevent: a fifth pattern added to one side left it green, because the fixture
never learned about the fifth.

It now extracts both sides and compares them as **sets** — non-comment lines from
`private.gitignore`, quoted tokens from the `private_baseline` array (via an `awk` range, so
reflowing the array across lines cannot quietly break extraction) — and asserts equality. Verified in
both directions:

```
DRIFT A (pattern in private.gitignore only):  FAIL … are the SAME SET
    --- only in private.gitignore ---  docs/adr-extra/
DRIFT B (pattern in private_baseline only):   FAIL … are the SAME SET
```

Two hardening details worth noting: an explicit "both sides are non-empty" assertion means a broken
extraction fails loudly rather than comparing two empty strings and passing (the failure mode that
made round-2's ordering assertion useless), and under `-v` the fixture prints the symmetric
difference so a future failure is diagnosable without reading the fixture.

---

## 💭 QUESTION-2 (new) — two adjacent apply functions still report ERROR for an absent precondition

Surfaced while testing QUESTION-1. On a project at `--from 2.4.0` with **no `.gitignore` at all**:

```
ERROR committed-gate-yml :: apply ran but convention still absent — inspect manually
ERROR strict-selective-gitignore :: apply ran but convention still absent — inspect manually
```

Both are the *same semantic* as QUESTION-1 — `apply_committed_gate_yml` can only add the
`!.ssd/gate.yml` line `if [[ -f "$gi" ]]`, and `apply_strict_selective_gitignore` only upgrades a
project that already carries the selective block (the manifest says so in prose). Precondition
absent ⇒ `NOOP`, by the contract this round introduced.

**Deliberately not fixed.** The state is only reachable when a ≥2.4.0 project has no `.gitignore`
whatsoever, meaning `selective-gitignore` (introduced **1.18.0**) never ran — an inconsistent project
outside the version window under test. It is pre-existing, does not involve private mode, and fixing
it would widen a change already carrying two rounds of findings. The realistic QUESTION-1 path exits
0, verified above.

Recording rather than silently fixing is the point: the new `NOOP` vocabulary makes these two visibly
wrong, and that should be a tracked decision, not a quiet extension. Recommend its own issue.

---

## Process note — the recurring defect, fourth instance

Round 2 named it: *a check that cannot fail looks identical to a check that passes.* It happened again
during **this** round. My first attempt to verify the QUESTION-1 fixture by reversion used a
`str.replace` with the wrong indentation and **no assertion** on the match count. The replace was a
silent no-op, the file never changed, and the suite reported `128/128` — which I briefly read as
"the fixture doesn't catch it."

Four instances now, all the same shape:

| # | Where | Masked by |
|---|---|---|
| 1 | `find -newermt` | an interactive GNU-compatible `find` shim |
| 2 | BSD-first `stat` | developing on macOS |
| 3 | round-2 ordering assertion | grepping the whole file, matching the comment |
| 4 | the reversion test itself | `replace()` with no `count` assertion |

The operative rule, now demonstrated four times: **an unasserted edit and an unfailed test are the
same bug.** Every reversion check in this round asserts its anchor matched before writing.

---

## Re-verified after these changes

| Claim | How |
|---|---|
| Regression floor intact | 128/128; all 83 pre-existing assertions pass. |
| Private mode unaffected | Full dogfood re-run: **6 pass · 4 skip · 0 fail**, exit 0; `git status --untracked-files=all` empty; ADR confirmed untracked. |
| `--apply` still works where it should | Control arm in the new fixture: `Makefile` `test:` → `APPLIED` with a real key written. |
| Recorded version does not advance past a NOOP | Asserted directly — otherwise a NOOP would be silently equivalent to APPLIED for version purposes, and the convention would never be re-offered. |
| `APPLY_NOTE` cannot leak across ids | Cleared at the top of every loop iteration; a note attached to the wrong migration would be worse than none. |
| Docs match behavior | `chapters/upgrade.md` documents all five statuses; ADR-0015 carries the reasoning. Neither was left describing the old two-status vocabulary. |

## Self-verification

Read every file cited; line numbers resolve after the edits. Both closures verified by execution, not
by reading the change. No sub-agents. The one claim I cannot execute here remains GNU `stat`
behavior (round-1 MAJOR-1) — still defended by output validation that holds regardless of which
variant runs, so the fix does not depend on that inference.

**Gate: PASS.** Clear to proceed to `/ssd gate`.
