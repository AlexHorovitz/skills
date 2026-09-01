# ADR-0016: `/feynman` must be *invoked* by the workflow it claims to serve

## Status
Accepted — 2026-08-26. Drives the `feynman-orchestrator-integration` change. Recorded under the
[ADR-0011](ADR-0011-decision-record-doctrine.md) decision-record doctrine. Target skill: `feynman`
(1.0.0 → 1.1.0), with companion changes in `methodology/gate-rules.sh`,
`methodology/schemas/feynman.yml`, and three `ssd/chapters/` files. Qualifies — and does **not**
overturn — [ADR-0012](ADR-0012-ssd-2.0-architecture.md) Pillar 5.

## Context

`feynman` shipped at v2.6.0 as the executable form of the doctrine at
[insanelygreat.com/fooling-yourself.html](https://insanelygreat.com/fooling-yourself.html). Its
`## Interface` table made three claims about how it participates in SSD:

| Claim (v1.0.0, verbatim) | Status |
|---|---|
| `consumed_by: [codebase-skeptic, refactor, ssd]` | **Contradicted** |
| **SSD Phase** — `/ssd milestone`, `/ssd verify`, `/ssd audit`, pre-`/ssd ship` | **Contradicted** |
| **Consumed by** — `ssd` (`gate_pass` blocks ship on `contradicted` or `theater` claims) | **Contradicted** |

The evidence is one command:

```
$ grep -rn 'feynman' ssd/ methodology/gate-rules.sh
(no output)
```

No orchestrator chapter referenced the skill. No gate rule read `gate_pass`. No schema existed, so
`frontmatter-valid` counted every feynman report among its "unvalidated (no matching schema)" tally —
the very count v2.6.0 added in order to stop overstating coverage.

This is not a small documentation slip. It is the exact defect the skill exists to detect, in the
skill itself: **a load-bearing claim about integration, stated in the present tense, backed by
nothing.** A reader deciding whether to trust `/ssd ship` would have concluded that a failing
epistemic audit could not silently pass the gate. It could.

Worse, it is a claim about *the skill's own participation in the workflow* — which is the kind a user
cannot easily check, because checking it means reading the orchestrator rather than the skill. The
asymmetry Feynman describes applies: nobody lied, and the claim survived precisely because it was the
kind of thing everyone wanted to be true.

### Two genuine tensions, not excuses

The claims could not simply be made true by wiring, because two doctrines pull against it:

1. **The skill's own frequency rule.** `feynman/SKILL.md` § "Frequency": *"Running it every sprint
   turns it into the eighteenth ritual nobody can trace to a decision — at which point Phase 3 will
   catch it, and should."* Auto-invoking the audit on every milestone would make the skill fail its
   own Phase 3 inventory.
2. **ADR-0012 Pillar 5, "warnings, not walls",** whose reversibility contract is explicit: *"reconsider
   hard enforcement only if ungated defects actually reach users at a rate the discouragement + audit
   trail demonstrably fails to catch. Absent that evidence, the answer to 'should the gate block?'
   stays no."* No such evidence exists.

Tension 2 dissolves on inspection. Pillar 5 rejects **branch-protection walls and required merge
checks** — machinery that makes the repo physically unable to receive the change. It does not reject
FAILable gate rules: `wip-commits` has FAILed since v1.4.0, and `ssd/chapters/enforcement.md` has
always documented the escape as *"use `/ssd ship --force` (logged)."* A rule that FAILs loudly and
records a deliberate override **is** the Pillar 5 gesture — propose the safe path, allow the informed
override, keep the trace. Adding one more such rule is not hard enforcement and needs no exception.

Tension 1 is real and constrains the design: the audit must be **proposed, never automatic.**

## Decision

### 1. New gate rule: `feynman-clean`

Any `feynman.md` appearing in the change set must report `claim_counts.contradicted == 0` and
`claim_counts.theater == 0`. Otherwise FAIL. Four properties, each chosen against a specific failure:

- **Reads the counters, not `gate_pass`.** `gate_pass` is documented as *computed* from the counters,
  but a rule that trusted the boolean could be cleared by editing one character — making the report
  the judge of its own verdict. The rule recomputes.
- **Reads frontmatter only, never the body.** Report prose and grade tables legitimately contain lines
  like `contradicted: 0`. A `yaml_get` over the whole file would let report *prose* argue with the
  gate. A dedicated `frontmatter_get()` refuses to look past the closing `---`. (Negative test in the
  parity harness.)
- **Diff-scoped**, like `frontmatter-valid` and `no-leaky-state`.
- **No report in scope → SKIP, never FAIL.** Not running the audit is not a violation; see § 3.

### 2. Frontmatter schema (`methodology/schemas/feynman.yml`)

So `frontmatter-valid` stops counting these reports as unvalidated. `not_examined` is **required** —
structural validation cannot tell whether an audit was honest, but it can insist the audit declares
what it did not look at, which is the field most likely to be quietly dropped when a scoped audit is
presented as a complete one.

### 3. Proposed at four points; auto-run at none

`/ssd milestone` gains **Step 0.5**, which offers the audit, states why in one line, and — if
declined — **records the declining** in the milestone record. `/ssd verify` re-proposes it when the
milestone ran one (verification's own "all findings closed" is itself a claim worth grading).
`/ssd audit` offers it as the internal counterpart to `software-standards`' comparative question.
`/ssd ship` surfaces the rule result verbatim at the gate boundary.

A declined audit is a recorded decision, not an absence — the same move v2.6.0 made for the
deliberately-unset `feature_flag_marker`. The reader can tell a choice from a gap.

### 4. Say what a PASS does *not* mean

Every place this rule is documented states that a PASS or SKIP means *"no failing audit in this change
set"* — **not** *"this project's beliefs are calibrated."* A rule that gets cited as the latter would
be a new instance of the misleading-coverage defect v2.6.0 was released to fix.

## Scope and degradation

| Situation | Behavior |
|---|---|
| Project never runs `/feynman` | Every gate run SKIPs the rule. Byte-for-byte unchanged. |
| Audit ran, clean | PASS, with the report count in the detail |
| Audit ran, contradicted/theater > 0 | FAIL, exit 1; `/ssd ship --force` overrides, logged |
| Report present, counters unreadable | SKIP naming the unreadable count — never a silent PASS |
| Audit committed on an earlier branch | **Not re-read.** Stated limitation, not a silent gap. |

## Consequences

- The gate grows from nine rules to ten. A project that never runs the audit sees one more SKIP, which
  the v2.6.0 census now names rather than hiding.
- `frontmatter-valid`'s unvalidated count drops by one per feynman report in scope.
- `/ssd milestone` gains a decision point. This is a real cost in ceremony, accepted because the
  alternative (auto-run) is worse and the alternative (nothing) is the status quo being fixed.
- The skill can no longer be described as standalone; downstream docs saying so need updating.

## Alternatives rejected

1. **Documentation-only honesty fix** — strip the three false rows, leave the orchestrator alone.
   Cheapest and fully honest. Rejected because the claims described the *right* design: an epistemic
   audit nothing consumes is an audit whose findings depend on someone remembering to read it. Making
   the documentation match a weaker reality would have been truthful and worse.
2. **Auto-run `/feynman` at every milestone** — makes the SSD Phase row unambiguously true. Rejected:
   fails the skill's own Phase 3, and a ritual audit produces ritual findings.
3. **Read `gate_pass` directly** — simpler, and matches the v1.0.0 wording. Rejected: lets a report
   clear the gate by flipping one boolean.
4. **Mandatory audit before ship** (no report → FAIL) — maximal rigor. Rejected for the same reason as
   (2), plus it would block every project that has never heard of the skill.
5. **A Pillar 5 exception** — document `feynman-clean` as sanctioned hard enforcement. Rejected as
   miscategorization: a FAILable rule with a logged override is what Pillar 5 already prescribes. An
   exception would have set a precedent for a rule that never needed one.

## Migration (ADR-0013)

`feynman-gate-rule` (guided, `introduced_in: 2.7.0`). Nothing to install — the rule ships in
`gate-rules.sh` and SKIPs where no audit exists. The guidance explains the new milestone Step 0.5 and
suggests running the audit once before the next release.

## Acceptance criteria

1. `feynman-clean` FAILs on a report with `contradicted > 0` and the gate exits non-zero. ✅ verified
2. It PASSes on a clean report. ✅ verified
3. Body prose mimicking clean counters does **not** override the frontmatter verdict. ✅ verified
   (negative assertion in the parity harness)
4. It SKIPs with no report in scope, and SKIPs-while-naming-the-count on unreadable counters. ✅ verified
5. The library's own audit report validates against the new schema. ✅ verified
6. Parity harness fails when the rule is deliberately broken. ✅ verified (3 assertions fail)
7. No `grep -rn 'feynman' ssd/` returns empty. ✅ verified

## Revisit when

- **Proposed, not automatic** → reopen if milestones routinely decline the audit *and* subsequent
  incidents trace to claims the audit would have graded. The declining is recorded specifically so
  this is answerable from the artifacts rather than from memory.
- **Diff-scoped** → reopen if a stale-but-clean report on an earlier branch is ever cited as evidence
  that the current change set is calibrated. The fix would be a staleness check, deliberately deferred
  here because it invents time-dependent policy this ADR has no evidence to size.
- **Counters over `gate_pass`** → reopen if the two ever legitimately diverge, which would mean the
  skill's "computed" contract has changed and this rule is enforcing the wrong one.
- **Pillar 5 read** → if a future rule genuinely needs to *prevent* a merge rather than fail loudly,
  that is a real Pillar 5 exception and needs its own ADR. This one is not that, and should not be
  cited as precedent for it.

---

## Addendum — 2026-09-01: the override this ADR reasoned from does not exist

This ADR's § "Why this is not a Pillar 5 violation" rests on the premise that a FAILing rule has a
sanctioned escape: *"`ssd/chapters/enforcement.md` has always documented the escape as 'use
`/ssd ship --force` (logged)'"*, and the decision table above lists `/ssd ship --force` as the
override for a failing audit.

**Neither the flag nor the log exists.** A Feynman audit on 2026-09-01 (claims C2 and C4) established
by execution that no script in the library accepts `--force`, and that `rail_deviations:` — the
durable trace ADR-0012 Pillar 5 says the override would leave — has never been written by any tool
across 15 workstreams. The premise was true about the *documentation* and false about the *system*.

**What this does and does not change.** The decision stands: `feynman-clean` is a loud FAILable rule,
not a wall, and it exits 1 rather than blocking a merge. What changes is the reasoning's honesty — the
rule is *less* gated than this ADR claimed, not more, because a developer overriding it leaves no
machine-readable trace at all. The four documents that asserted the override have been corrected to
say what actually happens: you merge a red gate deliberately and write the reason into the deploy
log's rail-deviations table by hand.

**Consequence for the Pillar 5 argument.** "Keep the override, keep the trace" was the load-bearing
clause. The trace is the half that was never built, so implementing it — a real `--force` that writes
`rail_deviations:` — is now a *feature* with its own ADR, deliberately not folded into the refactor
that found this (hard rule 4).
