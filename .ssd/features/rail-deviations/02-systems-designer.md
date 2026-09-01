---
skill: systems-designer
version: 1.5.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: rail-deviations
consumed_by: [ssd]
round: 2
machine_checked:
  tests_exist: false
  indexes_declared: true
  flag_wired: true
  migration_reversible: true
human_review:
  load_test: waived
  runbook_accuracy: pass
  security_review: pass
block_conditions_met: true
block_conditions:
  rollback_plan_exists: true
  observability_hooks: true
  dependency_failure_modes_documented: true
---

# Production Readiness — rail-deviations (D11)

**Phase 0: input validated.** `01-architect.md` is present and every Quality Gate section carries real
content. No send-back required.

> **Round 1: `block_conditions_met: false`** — three findings, two absent from the architect spec.
> **Round 2 (below): `block_conditions_met: true`** — all three block conditions met, and the runbook
> exists rather than being promised. **One MAJOR remains**, and it is in the *reasoning* of the fix
> rather than the mechanism: D7 claims a mitigation pointed in the wrong direction.
>
> Round 1's findings are preserved verbatim below. The verdict changed; the record of why should not.

## The experiment this pass was run to settle

v2.12.0 declared `production_runtime: false` for this project, on the reasoning that rail step 2 is
conditional and a markdown/bash library has no runtime. The declaration was tested by running this
pass anyway.

**Result: the declaration is too coarse, and this feature is the counterexample.**

| Concern | Applies here? |
|---|---|
| Deployment checklist (web / mobile / macOS) | **No.** Genuinely N/A. Ship = `git tag` + push |
| Load testing, capacity, scaling triggers | **No.** No request rate to model. Waived |
| Observability: dashboards, traces, p99 | **No** in form — **yes** in substance (§2) |
| Failure modes of external dependencies | **Yes.** One hard dependency, and it is optional today (§1) |
| Untrusted input reaching a parser | **Yes, and the spec misses it** (§3 / S1) |
| Corruption of shared mutable state | **Yes, and the spec misses it** (§5 / S3) |
| Recovery procedure for that corruption | **Yes, absent** (§6 / S2) |

**"No production runtime" is not the same as "no operational surface."** This feature writes to shared
mutable state from free-text input. That has failure modes whether or not anyone serves an HTTP request.

## 1. Failure modes

One external dependency, and the architect spec already handles it correctly:

| Failure | Detection | Impact | Mitigation | Status |
|---|---|---|---|---|
| PyYAML absent | `python3 -c "import yaml"` | cannot record a deviation | **exit 3, loud on stderr** (R6) | ✓ documented |
| `current.yml` absent or unparseable | PyYAML raises | cannot record | must exit non-zero, not create a fresh file | ⚠ unstated |
| Target slug not in `active[]` | lookup miss | record would go nowhere | must exit non-zero | ⚠ unstated |
| Disk full mid-write | `mv` fails | R4's temp+mv contains it | ✓ | ✓ |

**R6 is the right call and worth naming as such.** Making the writer fail *loudly* where two existing
rules SKIP softly is an asymmetry, and it is correct: a SKIPped validator leaves the artifact
unvalidated, while a silently-unrecorded deviation *is this feature's own finding, reproduced.*

The two ⚠ rows are cheap to close — both are "exit non-zero and say which precondition failed."

## 2. Observability, translated rather than waived

There are no metrics or dashboards, and asking for them would be cargo-culting the form. The
substantive question survives: **how do you know a deviation was recorded?**

The answer is already in the design and worth stating explicitly, because it is unusual: **the gate rule
*is* the observability hook.** `deviations-recorded` failing at release time is the alert. That is a
better arrangement than a log line nobody reads, and it is why `block_conditions.observability_hooks`
is `true` for a feature with no telemetry.

What is missing is the negative case: **nothing surfaces a deviation that was recorded against the
wrong workstream.** A typo'd `--slug` that happens to match another active workstream writes a true
record in a false place, and no rule can tell. Accepted risk; note it in the runbook.

## 3. 🔴 S1 — the `reason` string is untrusted input reaching a YAML writer

**Not in the architect spec.** `reason` is free text supplied at the moment of a deviation, and it lands
in a YAML document that the gate parses with a hand-rolled awk walker.

If the writer ever interpolates that string — `printf` into a heredoc, `sed`, an f-string into a
template — a reason containing a newline and a plausible key **forges records**:

```
--reason "ran out of time
      - kind: override
        rule: feynman-clean"
```

One argument, two records, the second one invented. The consumer cannot tell them apart because they
are structurally identical to real ones.

**Required:** the writer constructs a Python object and calls `yaml.safe_dump`. **Never** string
interpolation, at any point in the path. This must be pinned by a fixture that passes a `reason`
containing a newline and a forged `kind:` line, and asserts exactly **one** record lands.

This is the same class as `migrate.sh`'s C-quoting defect and `diff_files()`'s: *a value that looks
like a path or a key, treated as one.* Third occurrence of the family in this library, which is
`code-reviewer` step 8 territory.

## 4. Performance

Genuinely not applicable. One file, a handful of records, invoked at human cadence. `load_test:
waived` — and *waived* rather than *required* is the honest grade, because there is no workload to test
rather than a test nobody has run.

## 5. 🔴 S3 — concurrent write against the orchestrator's own edits, with no lock

**Not in the architect spec.** R4 covers a torn write (temp + `mv`, correct). It does not cover the
sequence:

1. the orchestrator reads `current.yml` to advance `phase`
2. `deviation.sh` reads, appends a record, `mv`s
3. the orchestrator writes its `phase` change **from the copy it read at step 1**

The deviation is silently gone. No corruption, no error, no torn file — a lost update. `chapters/state.md`
documents *"one Claude session per project at a time"*, which is a **convention, not a lock**, and it
does not constrain a script and an LLM inside the *same* session both writing the file.

**Required:** either the writer takes a lock (`flock` on `current.yml`, or an `O_EXCL` lockfile with a
stale-age escape), or the orchestrator is forbidden from holding a read across a `deviation.sh` call
and that ordering is stated in `phases.md`. The second is cheaper and is probably right — but it is a
**documented protocol**, and this feature exists because a documented protocol with no enforcement
produced nothing for a year. Prefer the lock.

## 6. ⚠ S2 — no recovery procedure; `rollback_plan_exists: false`

`migration_reversible: false` and `rollback_plan_exists: false` are the two machine-checked failures,
and they are the same gap: **`current.yml` is the project's state file, and this is the first script
that appends to it.** `migrate.sh` writes `current.yml.bak` before mutating. The spec's R4 stops a
*torn* write; it does not answer *"the write succeeded and the result is wrong."*

**Required, minimally:**
- write `current.yml.bak` before mutating, matching `migrate.sh`'s existing behaviour
- a runbook entry: symptom (`/ssd` reports a malformed `current.yml`), diagnosis (`python3 -c
  "import yaml,sys; yaml.safe_load(open('.ssd/current.yml'))"`), recovery (restore the `.bak`, re-run
  the record)
- state what happens to a deviation on **archive** — R5 names it as a risk with no answer

`docs/runbooks/` exists and is empty of anything about state files. This would be its first genuine
entry, which is invariant 8's territory ("runbooks for any new operational surface") — and **appending
to the project's state file from a script is a new operational surface**, whether or not there is a
server.

## 7–9. AI integration · chaos · cost

All three genuinely N/A. No LLM in the mechanism path (the *caller* is an LLM; the *writer* is not), no
dependencies to fail-inject beyond PyYAML, no spend. Recorded as considered rather than skipped.

## Block conditions

| Condition | Met | Why |
|---|---|---|
| `rollback_plan_exists` | **false** | S2 — no `.bak`, no recovery procedure, no archive answer |
| `observability_hooks` | true | the gate rule is the hook (§2), which is the right shape here |
| `dependency_failure_modes_documented` | true | R6 handles PyYAML correctly and loudly |

**`block_conditions_met: false`.** `/ssd ship` should refuse. Two of the three findings — S1 and S3 —
are absent from the architect spec entirely, and both are the kind that ship silently and are found by
an audit later.

## Send back to the architect

1. **S1 — `yaml.safe_dump`, never interpolation**, plus a forged-record fixture. Blocking.
2. **S3 — decide lock vs. protocol** and say which, in the spec. Blocking. Prefer the lock, on this
   feature's own evidence about what documented protocols achieve.
3. **S2 — `.bak` + a runbook entry + an answer to R5 (archive).** Blocking.
4. Close the two ⚠ rows in §1 (missing `current.yml`, unknown slug → exit non-zero).

## What this pass says about `production_runtime: false`

The declaration held for **half** its intended reach and failed for the other half. Deployment
checklists, load tests, capacity models and cost dashboards were correctly N/A. Failure modes,
untrusted input, state corruption and recovery were **not**, and two blocking findings came from
exactly there.

**The condition is on the wrong axis.** *"Does this project serve users?"* is not the question that
determines whether this pass is worth running. *"Does this change touch state that can be corrupted, or
input that can be forged?"* is. A skills library answers **no** to the first and **yes** to the second,
and this feature is the proof.

Recorded here rather than acted on: narrowing the declaration is a change to what v2.12.0 just shipped,
and it should go through its own cycle with this artifact as the evidence.

---

# Round 2 — do D6, D7 and D8 close S1, S2 and S3, or relocate them?

## S1 → D6: **closed**

Structural `safe_dump` of a constructed dict makes a forged record impossible, and single-line
normalisation keeps the reason legible to the crude bash reader. Both mechanisms are required and the
spec now says why — round 1 named only the first, and `safe_dump` alone would have produced a valid
record whose reason the consumer could not read.

**New MINOR-1: `--step` and `--rule` are also user input and are unvalidated.** `safe_dump` makes them
*safe*; nothing makes them *true*. A `--step 47` or `--rule feynman-clen` writes a well-formed record
naming something that does not exist, and the reader would count it as satisfying a deviation it does
not describe. Validate `step` as an integer in 1–8 against `rails.md`, and `rule` against the rule names
`gate-rules.sh` actually emits. Not a safety issue; a record-quality one, and this feature's whole value
is record quality.

## S2 → D8: **closed, and the runbook is written**

Round 1's challenge was that *"a runbook that exists as a promise in a design document is the exact
shape of the thing this feature is about."* Fair, and answered:
[`docs/runbooks/ssd-state-recovery.md`](../../../docs/runbooks/ssd-state-recovery.md) exists.

Three things worth crediting because they are what a *useful* runbook does and a template does not:

- It applies **today**, before `deviation.sh` exists, because `migrate.sh` already mutates `.ssd/` state.
- Step 1 says *"'parses OK' does not mean the content is right"* — the lost-update case produces a
  **valid** file missing a record, and a runbook that stopped at "does it parse" would send you away
  satisfied.
- Step 4 says that if a record is missing and nothing exited 10, **that is a defect to report, not a
  recovery to perform.** A runbook that distinguishes "fix this" from "this should have been impossible"
  is doing the job.

`docs/runbooks/` did not exist in this repository at all. Rails invariant 8 has therefore never been
satisfiable, and this is the first artifact that satisfies it. `runbook_accuracy` moves `required` →
`pass`; `rollback_plan_exists` → true on the `.bak` plus the recovery procedure.

## 🟠 S3 → D7: mechanism adequate, **stated mitigation aimed the wrong way**

`fcntl.flock` in Python instead of `flock(1)` is the right call, and checking `flock`'s absence on the
maintainer's machine **before** choosing is exactly the discipline that three prior portability defects
in this library were missing.

**But D7's central claim does not hold.** It says the in-lock mtime re-check *"converts a silent lost
update into a loud one."* Trace the scenario D7 itself describes:

```
T0  orchestrator reads current.yml          (holds a copy)
T1  deviation.sh takes the lock, re-checks mtime → UNCHANGED since ITS read → writes
T2  orchestrator writes its `phase` change from the T0 copy → the deviation is gone
```

The writer's mtime check protects **the writer** against a change landing under it. The loss in this
scenario happens in the **orchestrator's** write at T2, and nothing in D7 observes that. A reader of
D7 would believe the direction that actually loses data is covered. It is not.

**The real mitigation already exists elsewhere in the design and D7 does not cite it:** the
`deviations-recorded` rule (D4/ADR-0019 D6). A lost deviation means the release arrives with a skipped
step and no record, and the rule FAILs at the release boundary. The loss is not *prevented*; it is
**detected**, one boundary later, by the paired reader.

That is consistent with this feature's whole thesis — pair a writer with a reader, because a writer
nothing reads decays into silence — and it is a better answer than the one D7 gives. **It just has to
be the one the spec says**, because a coder implementing D7 as written would reasonably conclude the
hazard is handled and not think about the release-boundary catch at all.

**Required before `/ssd code`:** correct D7 to state that (a) the lock and mtime check protect the
writer, (b) the orchestrator's stale write is **not** prevented, and (c) the detection is
`deviations-recorded` at the next release. Not a block condition — the mechanism ships correctly either
way — but a spec that misdescribes its own safety property is how the next audit finds this.

## Block conditions — round 2

| Condition | Round 1 | Round 2 | Why |
|---|---|---|---|
| `rollback_plan_exists` | false | **true** | `.bak` before mutating + a written recovery runbook |
| `observability_hooks` | true | true | the gate rule is the hook, and S3 shows it is load-bearing rather than decorative |
| `dependency_failure_modes_documented` | true | true | PyYAML exit 3, plus the two preconditions round 1 flagged as unstated, now specified |

`migration_reversible` false → **true** (the `.bak`). `security_review` `required` → **pass**: S1 was
the security finding and D6 closes it structurally, with MINOR-1 as a record-quality follow-on rather
than an exposure.

**`block_conditions_met: true`. `/ssd ship` no longer refuses.** `tests_exist` stays **false** and
correctly so — no code exists yet, and the fixtures named in D6/D8 are the coder's first obligation.

## Send back to the architect — round 2

1. **Correct D7's stated mitigation** (above). Required before code; not blocking the phase.
2. **MINOR-1 — validate `--step` and `--rule`.** Cheap, and it protects the thing this feature is for.

Nothing else. The design is implementable.
