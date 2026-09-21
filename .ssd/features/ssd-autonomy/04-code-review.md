---
skill: code-reviewer
version: 2.14.0
produced_at: 2026-09-21T21:35:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-autonomy (working tree, uncommitted)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 2
  minor: 4
  question: 1
  suggestion: 1
  nit: 0
gate_pass: false
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — ssd-autonomy (round 1)

## Context

The diff adds an autonomy ladder whose entire premise is **"do not trust the relay"**: the
orchestrator is an LLM, so every guarantee that can be an exit code is one. The review was aimed at
that premise. Two findings are places where the script trusts the relay anyway, and one of them
defeats three separate refusals.

Both referees, reported separately, because this feature's own D11 says a run must:

- **`code-reviewer`** (this review): `gate_pass: false` — 2 MAJOR.
- **`gate-rules.sh`**: `5 pass · 8 skip · 0 fail` — **and eight of those skips are `no diff (vs main)`.**
  The work is uncommitted, so `adr-delta`, `no-leaky-state`, `rails-walked`, `deviations-recorded` and
  `feynman-clean` had nothing to inspect. The coder-status says this plainly and is right to. **That is
  not a green gate on this feature.**

Cross-workstream overlap check: **skipped** — one active workstream in `current.yml`.

---

## 🟠 MAJOR-1 — `transition --from` is never checked against the recorded phase, so the review-loop budget is bypassable

[`methodology/autorun.sh:624-698`](../../../methodology/autorun.sh)

`cmd_transition` loads the workstream entry (line 630) and uses it **only** to read `auto_run`
(line 633). It never reads `entry["phase"]`. The successor table validates that `from → to` is a
rails edge; nothing validates that `from` is where the workstream actually *is*. `cmd_start`
(line 516) and `cmd_plan` (line 565) both read the recorded phase — `transition`, the one call that
authorizes an act, does not.

**Traced, not inferred.** Fixture: workstream at `phase: design`, `max_review_loops: 1`.

```
$ autorun.sh transition --slug feat#a --from code --to review   # workstream is at design
state=ok reason=- lowered=/ssd review feat#a transition=1/12 loops=0/1
  … repeated twice more …
transitions: 3 | loops_consumed: 0 | max: 1
phase_reached recorded as: review
```

Two consequences:

1. **STOP-1 is bypassable.** The loop counter increments only on the literal edge `review → code`
   (line 677). An orchestrator that mislabels the edge — announcing `code → review` each round
   instead — consumes **zero** review loops and never trips `max_review_loops`. The budget that
   exists to stop an agent thrashing against a failing gate is enforced against a string the agent
   supplies.
2. **The record asserts a phase that never happened.** `phase_reached` is set from `--to` (line 696),
   so the durable artifact — the one `codebase-skeptic` and `feynman` are told to consume — now says
   the run reached `review` when the workstream is at `design`.

This is not a hypothetical about a malicious agent. It is the ordinary failure the whole design
anticipates elsewhere: **an LLM misreading state.** D5 put the successor table in the script precisely
so the agent could not assert an off-rails move; leaving `from` unvalidated hands back most of that.

**Fix:** derive `from` from `current.yml.active[].phase` and refuse (or `state=stop`) when `--from`
disagrees. The value is already in hand at line 630. Consider deriving `to` as well for the
non-branching edges — `design`, `code` and `brief` each have exactly one successor, so only the
`review` fork genuinely needs the caller's input, and that fork can be resolved from the last
review's `gate_pass` instead.

---

## 🟠 MAJOR-2 — workstream resolution ignores `iteration`, so an iterated workstream resolves to the wrong entry

[`methodology/autorun.sh:292-297`](../../../methodology/autorun.sh)

```python
def find_workstream(doc, slug):
    for entry in active:
        if isinstance(entry, dict) and entry.get("slug") == slug:
            return entry
```

`split_slug` correctly parses `feat#b` into `BASE_SLUG` + `ITERATION`, and `ITERATION` is used to
choose the record **directory** — but `find_workstream` is called with the base slug alone and returns
the **first** matching entry. Iterations are first-class
([ADR-0001](../../../docs/decisions/ADR-0001-iterations-as-schema-substrate.md)) and two active
iterations of one feature are two `active[]` entries with the **same `slug`** and different
`iteration:` — `/ssd feature new` treats `(slug, iteration)` as the key precisely because of this.

**Traced in both orderings.** Fixture: `feat#a` at `phase: gate`, `elapsed_hours: 99`,
`budget_hours: 2`; `feat#b` at `phase: design`, 1 of 8 hours.

*Entry A first:* `start --slug feat#b` (valid, at `design`, in budget) →
```
state=refused reason=FM-3
autorun: 'feat' is already at or past 'gate' (phase: gate)
```
A legitimate run is refused because of a *sibling iteration's* phase, and the message names `feat`
without the iteration, so the user cannot see why.

*Entry B first:* `start --slug feat#a` (at the ceiling **and** 97 hours over budget) →
```
state=ok reason=- record=.ssd/features/feat/iterations/a/auto-runs/…-run.md from_phase=design
```

That second one is the serious form. Reading the sibling's fields defeated **three** refusals in one
call:

- **FM-3** (at/past the ceiling) — bypassed; A is at `gate`.
- **the over-budget refusal** (`elapsed_hours > budget_hours`, line 529) — bypassed; it read B's 1/8.
- **lock/record coherence** — the lock landed on **entry B** while the record was written under
  `iterations/a/`. `status` now reports B holding a record belonging to A, and FM-2's recovery
  instructions name the wrong iteration.

Every one of those is a refusal this feature exists to make reliable.

**Fix:** match on `(slug, iteration)` — compare `entry.get("iteration")` against the parsed
`ITERATION` (treating `None` and absent as the flat workstream). `active_slugs()` should report the
qualified form (`feat#a`, `feat#b`) so FM-1's "Active: …" list is actionable.

**Class sweep** (Phase 3.5 step 8): [`methodology/deviation.sh:127`](../../../methodology/deviation.sh)
resolves a workstream the same slug-only way and has the same blindness. **That is pre-existing
(v2.13.0) and not charged to this diff** — but the pattern is now in two scripts, and fixing one
while leaving the other is the exact granularity error this repo has recorded three times. Fix both,
or file the second explicitly.

---

## 🟡 MINOR findings

**MINOR-1 — a wrong-shaped `current.yml` produces a traceback and exit 1, outside the documented exit family.**
[`methodology/autorun.sh:283-290`](../../../methodology/autorun.sh). `load_current` catches
`yaml.YAMLError`, so *unparseable* YAML exits 3 as designed. Structurally valid YAML of the wrong
*shape* does not:

```
$ printf -- '- not\n- a mapping\n' > .ssd/current.yml && autorun.sh status
AttributeError: 'list' object has no attribute 'get'
actual exit code = 1
```

The script header documents `0 / 2 / 3 / 10`; the runbook's malformed-state path promises exit 3 with
the parse error. A caller distinguishing "retry" (10) from "refuse" (2) from "broken" (3) sees an
undocumented 1 and a `<stdin>` stack trace. Guard the shape after `safe_load` — `if not isinstance(doc,
dict)` → `fail(...)`.

**MINOR-2 — `README.md` never mentions `/ssd run`.**
The verb block at [`README.md:112-125`](../../../README.md) lists every other top-level verb through
`/ssd upgrade`. A new top-level verb absent from the library's front door is the kind of drift
`doc-claims-are-true` cannot catch, because it tests for *false* claims, not missing ones.

**MINOR-3 — the chapter never states the rule that makes AC-1 true.**
D4 says the orchestrator calls `preflight` **iff** an `autonomy:` block is present, and that is the
entire mechanism behind "with no block, no additional call at all."
[`ssd/chapters/autonomy.md:115`](../../../ssd/chapters/autonomy.md) tells the orchestrator to run
`preflight` in `/ssd run` step 1 and says nothing about the `advance`/bare-`/ssd` path or the
gating condition. The claim survives either way (a `preflight` on an absent block returns
`mode=propose` and prints nothing to the user), so this is MINOR rather than MAJOR — but the rule
currently exists only in an architect spec, which is where mechanisms go to be forgotten.

**MINOR-4 — `elapsed_minutes` is cumulative-since-run-start, not per-transition.**
[`methodology/autorun.sh:666`](../../../methodology/autorun.sh) computes it against
`meta["produced_at"]` (the run's start). The field sits inside a *transition* entry and its name
reads as that transition's duration. D13's stated purpose for the field is choosing a future
`budget_wall_minutes` default "from data" — per-phase durations are the data you would want, and they
are recoverable only by differencing consecutive entries. Either rename it (`elapsed_since_start`) or
record both.

---

## 💭 QUESTION-1 — is a budget stop really `red`?

[`methodology/autorun.sh:756-762`](../../../methodology/autorun.sh) maps STOP-5 → `incomplete`,
STOP-7 + pass → `green`, and **everything else** → `red`, so STOP-1 (loops exhausted) and STOP-3 (over
budget) both read `red`. The parity fixture asserts it.

`red` is defensible as "did not end green," and I am not asserting it is wrong. But `outcome` exists
because D11 objected to one field carrying two meanings, and "the work is failing review" and "the run
ran out of room" are two meanings. `incomplete` already exists and fits the budget stops. Worth one
sentence of intent in the chapter either way — the current mapping is a decision the reader has to
reverse-engineer from source.

---

## 💡 SUGGESTION-1 — the fixture that would have caught MAJOR-1

`test_fixture_autorun_referee` asserts an off-rails edge is refused, which is the property the
successor table provides. It does not assert that a **rails-valid edge from the wrong place** is
refused, which is the property MAJOR-1 shows is absent. When MAJOR-1 is fixed, the assertion to add is
the mirror of the existing one: workstream at `design`, `transition --from code --to review`, expect a
refusal — and, critically, expect `loops_consumed` to be unreachable by mislabelling.

---

## What I checked and found correct

Named so the next round knows what not to re-litigate:

- **Record-before-act.** `transition` writes the entry before returning `state=ok`; every stop path
  returns *before* appending. The fixture proves a refused edge logs nothing.
- **`safe_dump` containment.** A `--reason` carrying `injected: true` and a forged list item
  round-trips as one scalar with exactly six keys on the entry. Verified independently of the fixture.
- **`current.yml` comment survival.** The textual splice preserves interior comments; a whole-document
  round-trip would not. Correctly inherited from ADR-0019 D4 rather than re-derived.
- **Lock sharing.** `autorun.sh` takes `deviation.sh`'s `.ssd/current.yml.lock`; no new lock file.
  `fcntl.flock`, never `flock(1)` — the BSD/macOS trap this repo has hit before.
- **`copymode` before `os.replace`.** Present, with the comment explaining the measured 644→600 defect.
  This is the instance of a class that already bit `deviation.sh`; it was swept here.
- **The gitignore fix, and its test.** Asserted against `methodology/selective.gitignore` — what other
  projects actually receive — not merely this repo's `.gitignore`. That is the right granularity, and
  the negation correctly re-includes only `*-run.md` while `secrets.env` under `auto-runs/` stays
  denied.
- **The migration.** PENDING → APPLIED → `SKIP-present` → re-apply is a no-op, verified in a sandbox.
  The sentinel-comment probe is the right call and the reasoning is recorded in both the manifest and
  the chapter.
- **FM-4 fires before the lock is taken**, so the ceiling refusal works even while a run is in flight.
- **Honest limits.** STOP-5's unenforceability, sub-skill non-atomicity, and `advance`-on-misread-state
  are stated in the chapter rather than smoothed. AC-9 is marked untested in the coder status rather
  than claimed. That is the standard this repo sets and this diff meets it.

---

## Verdict

**`gate_pass: false`** — 2 MAJOR. Back to the coder.

Both MAJORs are the same shape and it is worth naming: **the script trusts the orchestrator for
`--from` and for which workstream `--slug` means.** Everything else in this design is built on not
doing that. Fixing MAJOR-1 and MAJOR-2 makes the referee consistent with its own premise; neither fix
is large, and both are in code the diff already touches.

The gate's own SKIPs should be re-run once a branch exists — a gate that reports eight "no diff" skips
has not seen this change.
