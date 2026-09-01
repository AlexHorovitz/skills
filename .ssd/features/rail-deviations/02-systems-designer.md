---
skill: systems-designer
version: 1.5.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: rail-deviations
consumed_by: [ssd]
machine_checked:
  tests_exist: false
  indexes_declared: true
  flag_wired: true
  migration_reversible: false
human_review:
  load_test: waived
  runbook_accuracy: required
  security_review: required
block_conditions_met: false
block_conditions:
  rollback_plan_exists: false
  observability_hooks: true
  dependency_failure_modes_documented: true
---

# Production Readiness — rail-deviations (D11)

**Phase 0: input validated.** `01-architect.md` is present and every Quality Gate section carries real
content. No send-back required.

> **`block_conditions_met: false`.** Three findings below, two of which the architect spec does not
> contain. `/ssd ship` should refuse until S1 and S3 are answered.

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
