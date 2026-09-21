---
skill: systems-designer
version: 2.13.0
produced_at: 2026-09-21T20:05:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-autonomy
consumed_by: [ssd]
round: 2
machine_checked:
  tests_exist: false
  indexes_declared: not_applicable
  flag_wired: true
  migration_reversible: true
human_review:
  load_test: waived
  runbook_accuracy: required
  security_review: pass
block_conditions_met: true
block_conditions:
  rollback_plan_exists: true
  observability_hooks: true
  dependency_failure_modes_documented: true
---

# Production Readiness — ssd-autonomy (the autonomy ladder)

## Phase 0 — input validation

`01-architect.md` carries all eleven Quality Gate rows with real content: a measured scale baseline, a
component diagram, four data structures, a seven-subcommand interface contract, an integration
contract, ADR-0020 written, and six risks with a top-3 call. **Input accepted**; no send-back for
incompleteness.

## The thing that makes this pass different from every prior one in this repo

Every previous feature here moved *files*. This one moves **the agent**. The system under review has a
component no runbook has ever had to describe: an LLM in a loop, invoking other LLMs, with no human
between iterations.

That changes which sections of this skill apply. Load tests, capacity models, connection pools and
cost-per-request dashboards remain N/A for a markdown-and-bash library. **§7 (AI/LLM integration)
applies for the first time in this repo's history, and it is where both blocking findings came from.**

This is the second consecutive feature to produce that result — see the [`rail-deviations` round-1
finding](../rail-deviations/02-systems-designer.md) that `production_runtime: false` is *"on the wrong
axis"*: the question that predicts whether this pass is worth running is not *"does this project serve
users"* but *"does this change touch state that can be corrupted, or input that can be forged."* This
feature answers **yes** to both, and adds a third: *"does this change act without a human watching?"*
Two data points now. Recorded, not acted on — narrowing the declaration is its own cycle.

---

## 1. Failure modes

The dependency list for an auto-run, with the real ones first:

| Dependency | Failure | Detection | Impact | Mitigation | Status |
|---|---|---|---|---|---|
| **The orchestrator (an LLM)** | dies / context-exhausts between `start` and `finish` | next `/ssd run` → FM-2; `autorun.sh status` | lock held, all future runs blocked | record-before-act bounds loss to one announced step; `clear --confirm` (D8) | ✅ designed |
| **The orchestrator** | misreads state and announces a wrong-but-canonical transition | none automatic | one wrong phase runs | `advance` ≤ 1 phase; successor table; the gate is the referee | ⚠ accepted, R3 |
| **`code-reviewer` (an LLM)** | writes `gate_pass: true` about its own loop's work | **none** | the loop exits early on a self-report | see 🔴 **S1** | 🔴 open |
| **A sub-skill** | half-writes an artifact, then errors | the phase's own failure mode | partial artifact on disk | STOP-6, never retry — but no atomicity guarantee exists (architect's own item 4) | ⚠ accepted, stated |
| `python3` / PyYAML | absent | `start` exits 3 | no run can begin | hard-fail loudly, never skip (`deviation.sh` stance) | ✅ designed |
| `.ssd/current.yml` | absent / malformed | exit 3 | no run can begin | D8 table; refuse, never create | ✅ designed |
| `.ssd/current.yml` | concurrent write by `deviation.sh` | `st_mtime_ns` re-check | exit 10, nothing written | shared `fcntl.flock`, no new lock file | ✅ designed |
| The record file | write fails mid-run (disk, permissions) | non-zero exit from `transition` | run stops | no `state=ok` ⇒ no act (D7) | ✅ designed |
| `git` | unavailable / detached HEAD | Step 0 resolution fails | slug must be explicit | existing FM-1 | ✅ designed |
| The user | interjects mid-run | orchestrator sees the message | run pauses | STOP-5; current sub-skill finishes first | ⚠ prose-only, unenforceable |

Two rows deserve their names said out loud rather than left in a table.

**The orchestrator is the runtime.** Nothing in SSD has had a runtime before. "What happens when it
fails?" previously meant "what if `sed` behaves differently on BSD." It now means "what if the process
holding the loop stops existing halfway through." The architect answered that correctly — record
before act, so the durable state is never more than one announced step behind reality — and it is the
single best decision in the spec.

**STOP-5 cannot be enforced.** Interruption depends on the orchestrator noticing a message and choosing
to stop. There is no signal handler, no cancellation token, and no way to build one in prose. The
architect says so in its Rationale. I am not asking for a mechanism; I am asking that the chapter not
imply one. A user who believes interruption is guaranteed and finds it is best-effort has been misled
by exactly the kind of sentence this feature exists to stop writing.

---

## 2. 🔴 S1 — the loop's exit condition is a boolean the loop writes about itself

**The finding.** The successor table (architect D5) gates `review → gate` on *"last review frontmatter
`gate_pass: true`."* That field is written by `code-reviewer` — an LLM invoked by the same loop, about
code written by `coder`, another LLM invoked by the same loop, with no human reading either artifact.
In the manual flow a human reads the review before typing the next command. **Autonomy removes the only
independent reader in that edge.**

This is §7's "output schema validation" concern in its purest form: a structured field is being trusted
to make a control-flow decision, and the producer of the field is inside the system it is reporting on.
The library already knows this failure shape — `feynman-clean` deliberately reads *"the counters, not
`gate_pass`"* precisely because *"a rule cleared by flipping one boolean lets the report judge itself."*
The autonomy loop then turns around and steers on that boolean.

**The compounding half, which is worse.** `--until gate` means the run's last act is the `gate` phase,
where `gate-rules.sh` — a genuinely independent, executable referee — runs. Good. But the record has
**no field for its result.** A run that reaches the ceiling stops with `stop_reason: STOP-7`, described
in the PRD as *"normal completion."* So:

- a run that ends with a **green** gate, and
- a run that ends with a **red** gate,

produce **byte-identical** stop semantics. The auditor reading `auto-runs/` — the stated consumer,
`codebase-skeptic` and `feynman` — cannot tell a successful delegation from a failed one without going
and finding the gate output by hand. That is an observability hole in the artifact whose entire purpose
is to be the record, and it is why `observability_hooks: false` below.

**Required (blocking):**

1. The record carries the **executable gate's** result. Add `gate_result: pass|fail|not_run` to the
   run frontmatter, written at `finish`.
2. **STOP-7 splits.** Reaching the ceiling with a red gate is not "normal completion". Either a
   distinct stop reason, or `stop_reason: STOP-7` plus a mandatory `outcome: green|red` — the
   architect's call, but the two cases must be distinguishable in the frontmatter, not in the prose.
3. The `review → gate` edge stays as designed (it is the reviewer's job to judge the code), but the
   **hand-back summary must state which referee said what**: "review says `gate_pass: true`;
   `gate-rules.sh` says FAIL on `rails-walked`" is an honest sentence and the current design cannot
   produce it.

---

## 3. 🔴 S2 — `--lowered` and `--reason` are untrusted strings reaching a YAML writer

**The finding.** `transition --lowered "/ssd code auth-flow" --reason "phase: design, …"` writes both
into `current.yml`-adjacent YAML. The architect says *"copy the mechanics"* of `deviation.sh` and lists
lock, mtime guard, `.bak`, atomic replace, `copymode` — **it does not list `safe_dump` or the
single-line normalization**, which are the two that exist for exactly this input class.

This repo has already had this finding, on the previous feature, as its own round-1 blocker
([S1 → ADR-0019 D4/D6](../../../docs/decisions/ADR-0019-rail-deviation-records.md)): the `reason` string
is untrusted input, so the record is `yaml.safe_dump`ed and the reason is normalized to one line —
because a multi-line scalar is emitted as indented continuation lines that the gate's hand-rolled awk
walker **skips**, producing a structurally valid record whose reason no consumer can read.

Everything in that reasoning transfers unchanged. `reason` here is generated prose. `lowered` is worse
in one specific way: **it is a shell command string designed to be copy-pasted by a human**, which is
its stated purpose in AC-3. A record field that a human is expected to paste into a terminal is a field
that must not be constructible from unvalidated input.

**Mitigating context, stated so this is not overblown:** `start` refuses a slug that is not already in
`current.yml.active[]`, and slugs enter `active[]` through `/ssd feature new`, which validates
`[a-z0-9][a-z0-9-]*`. The path is *probably* closed. "Probably closed, by a validation two commands
away, that this spec does not cite" is not the standard this repo applied three weeks ago to the same
question.

**Required (blocking):**

1. State `yaml.safe_dump` for the record fragment and single-line normalization for `reason`,
   explicitly, in the spec — inheriting ADR-0019 D4/D6 by citation rather than by implication.
2. `autorun.sh` validates `--slug` against `[a-z0-9][a-z0-9-]*` (and `#<iter>` against
   `[A-Za-z0-9_-]+`) **itself**, rather than relying on the workstream having been created by a command
   that did.
3. `lowered` is **constructed by the script from validated parts**, never passed through as free text.
   A forged-record fixture in the parity suite, matching the one ADR-0019 required.

---

## 4. 🟠 S3 — the only budget that bounds spend defaults to uncapped

`budgets: {review_loops: 3, transitions: 12, wall_minutes: 0}` — and `0` means uncapped.

Translate the units. Each transition invokes at least one LLM sub-skill; a coder or reviewer pass on
this repo is a large-context call. Twelve transitions with three review loops is plausibly **20+
sub-skill invocations**, unattended, with the user away from the terminal — that is the use case
(U1: *"returns to a passing gate"*).

§9 (cost observability) is not waivable here just because there is no cloud bill: the resource being
spent is tokens and wall-clock, and **`budget_transitions` bounds the count while `wall_minutes`, the
only dimension that bounds *duration*, ships off by default.** A run that stalls on a slow sub-skill
burns wall-clock with no ceiling and no metric.

**Recommended (non-blocking):** default `budget_wall_minutes` to a real number (30 is a reasonable
first guess for the U1 story, and the number matters less than its being non-zero), and record
`elapsed_minutes` per transition so a future default is chosen from data rather than from this
paragraph. If the architect keeps `0`, the chapter must say plainly that the default run is
time-unbounded.

---

## 5. 🟠 S4 — autonomy widens the prompt-injection surface, and the PRD does not mention it

Under `propose`, a human reads every proposal before a sub-skill runs. That human is not *designed* as
a security control, but that is what they have been: the reason a hostile string in a source file,
brief, or dependency never steered an SSD session is that someone was reading the output at every step.

`/ssd run` removes that reader for up to twelve consecutive phases. `coder` and `code-reviewer` read
repository files, the brief, and prior artifacts — all of which are *inputs* to an LLM in an automated
loop. The PRD's fourteen sections do not contain the word "injection", and §7 of this skill asks
specifically: *"every place user-controlled content enters a prompt must be escaped or delimited."*

**What actually limits the blast radius**, and it is genuinely good: the ceiling stops at `gate`, so no
autonomous path reaches deploy, ship, rollout, or flag removal. The worst outcome is a bad commit on a
feature branch behind a failing gate, with a written record of every step. That is a containable
incident, not a breach.

**Recommended (non-blocking):** one paragraph in `chapters/autonomy.md` stating the threat model
plainly — *what an auto-run can do at worst* (write code, commit to a feature branch, fail a gate) and
*what it cannot* (ship, deploy, push a rollout, remove a flag, write a deviation). A user deciding
whether to enable `run` deserves that sentence, and the ceiling is a much better answer than most
systems have.

---

## 6. Observability, translated

There are no dashboards, so the translation is direct and mostly already satisfied:

| Concern | Runtime equivalent | Here | State |
|---|---|---|---|
| Structured logging | log line per operation | `run.transitions[]`, written before each act | ✅ |
| Trace ID | request correlation | the record path in `auto_run.record` (D8) | ✅ |
| Metrics | counters | `loops_consumed`, transition count, `phase_reached` | ✅ |
| **Result of the operation** | status code | **missing** — see S1 | 🔴 |
| Dashboard | health view | `autorun.sh status` | ✅ |
| Alerting | threshold notification | FM-2 refusal on the next invocation | ✅ (pull, not push — correct for a CLI) |

The one hole is the one that matters: every field describes *what the run did* and none describes
*how it turned out*.

---

## 7. Performance

Genuinely a non-issue, quantified so nobody has to wonder: three `autorun.sh` invocations per phase,
each a `bash` + `python3` start (~50–100 ms), against LLM sub-skill invocations measured in tens of
seconds. Overhead is **well under 1%** of a transition. The record is rewritten in full on each
transition — a few KB, twelve times, worst case.

D10's choice of uniformity over saving two `exec`s is correct and the numbers are not close.

---

## 8. Deployment safety and rollback

**The migration is additive and reversible**, which is unusually clean:

- `autonomy:` block absent ⇒ no new code path executes at all.
- Downgrading the library to v2.13.0 with an `autonomy:` block present in `project.yml`: nothing reads
  the key; inert.
- A stale `auto_run:` field in `current.yml` under a v2.13.0 library: unknown keys are ignored by every
  reader; inert.
- **One-way residue:** an auto-run record that was *committed* under the new `.gitignore` negation
  stays tracked if the negation is later reverted — git does not untrack a tracked file when a pattern
  changes. Cosmetic, but it should be in the changelog note rather than discovered.

**Rollback plan exists** (D8): `autorun.sh status` → verify the working tree → `clear --confirm`. It is
documented in the architect spec and belongs in [`docs/runbooks/ssd-state-recovery.md`](../../../docs/runbooks/ssd-state-recovery.md),
which already exists and already covers `current.yml` corruption. `rollback_plan_exists: true`, with
the runbook section as a **required coder deliverable** — `runbook_accuracy: required` until it is
written, because the recovery procedure in a design document is a plan, and the recovery procedure in
the runbook is where a human at 3am will look.

**The file manifest is short two entries** (both already found, neither yet in FR-7):
`.gitignore` + `methodology/selective.gitignore` (architect D2), and the runbook section.

---

## 9. Chaos / failure injection

The failure modes above must be *exercised*, not catalogued. Three parity-suite fixtures, all cheap:

1. **Stale lock.** Fixture `current.yml` with non-null `auto_run` → assert `start` refuses with FM-2 and
   names the record path.
2. **Forged record.** A `--reason` / `--lowered` containing YAML structure and a newline → assert the
   written record parses back to a single-line scalar and no injected keys (ADR-0019's fixture, adapted).
3. **Off-rails edge.** `transition --from design --to review` → assert `state=stop reason=STOP-2`, exit
   0, **and that no phase artifact was created**.

A fourth, which is the one that would have caught the real bug: **assert the record path is not
gitignored** (`git check-ignore` returns non-zero) — the R1 the architect already found, made
permanent.

---

## 10. Security · compliance · AI integration

- **Security review: `required`** — on S2 (untrusted strings into a YAML writer, and a field designed
  to be pasted into a shell). Not on auth or PII: there is no network surface, no identity, and no
  personal data anywhere in this feature.
- **Compliance / data lifecycle: N/A.** No PII. The one adjacent item is R5 (records accumulate), which
  is retention-shaped but not compliance-shaped, and is accepted for v1 with a named revisit trigger.
- **AI/LLM integration (§7): applies, first time in this repo.** Prompt injection → S4. Output schema
  validation → S1. Cost → S3. Rate limits, model drift, cache scoping → N/A (no hosted API is called by
  this library's own code; the sub-skills are invoked by the harness).

## 11. Load testing

**Waived.** One user, one session, one run at a time, by design (NG2). There is no concurrency to load
and no throughput target to miss.

---

## Block conditions

| Condition | Verdict | Why |
|---|---|---|
| `rollback_plan_exists` | ✅ true | D8: `status` → verify → `clear --confirm`; runbook section required of the coder |
| `observability_hooks` | 🔴 **false** | S1: the record cannot distinguish a green hand-back from a red one. The artifact's stated consumers are auditors |
| `dependency_failure_modes_documented` | ✅ true | §1, including the two that are accepted rather than mitigated |
| `destructive_migrations_two_phase` | n/a | no migration touches existing data; the config block is additive and commented |

**`block_conditions_met: false`.** One blocker, and it is in the record's semantics rather than its
machinery.

## Send back to the architect

1. **S1 — the record must carry the gate's verdict, and STOP-7 must stop meaning two things.**
   Blocking. This is the one that changes the data model.
2. **S2 — inherit ADR-0019 D4/D6 explicitly:** `safe_dump`, single-line `reason`, script-side slug
   validation, `lowered` constructed from validated parts, forged-record fixture. Blocking.
3. **S3 — give `budget_wall_minutes` a non-zero default**, or say in the chapter that the default run
   is time-unbounded. Non-blocking, but choose deliberately.
4. **S4 — one threat-model paragraph in the chapter.** Non-blocking. The ceiling already does the hard
   part; the sentence is owed to whoever decides to enable `run`.
5. Add `.gitignore`, `methodology/selective.gitignore`, and the runbook section to the file manifest.

Nothing in §1's accepted rows (STOP-5 unenforceable, sub-skill non-atomicity, `advance` on misread
state) is a send-back. They are correctly identified, correctly unmitigated, and must stay stated in
the chapter rather than smoothed over.

---

# Round 2 — do D11–D14 close S1 and S2?

## S1 → D11: **closed**, with one residue worth naming

The data model now distinguishes the two cases that were byte-identical. `stop_reason` says **why the
run ended**; `outcome` says **how it went**; `gate_result` records what the executable referee
actually returned. Keeping STOP-7's PRD meaning and adding `outcome:` alongside is the better of the
two options offered — splitting STOP-7 would have forked this spec from the PRD's normative table to
express something a second field expresses more precisely.

`finish --phase-reached gate` exiting `2` without `--gate-result` is the part that makes it stick. An
optional field on the case that matters is a field that will be absent in the record someone needs.

### 🟠 S5 — the verdict is a script's exit code relayed by an LLM

D11's own sentence is *"not an LLM's opinion: a number from a script."* It is a number from a script
**passed through the orchestrator**, and the orchestrator is the component this whole pass treats as
the runtime. The self-report moved one level down; it did not disappear.

Measured rather than assumed: `gate-rules.sh` **writes no file**. Results accumulate in a bash array
and go to stdout with an exit code. So there is no artifact `autorun.sh` could read independently
today — which is exactly why this is a residue and not a hole I should have caught in round 1.

**Cheap fix, and it is genuinely better than the flag:** the orchestrator redirects the gate phase's
stdout to `auto-runs/<ts>-gate.txt`, and `finish` derives `gate_result` by parsing that file's FAIL
count rather than by being told a word. The relay becomes an artifact a human can re-read, and the
gate output stops being something that only ever existed in a terminal scrollback.

**Non-blocking**, because the current design is still strictly better than round 1 and the residue is
verifiable after the fact — anyone can re-run the gate on the same commit. Required of the coder:
implement the file-derived form, or record in the coder status why the flag form was kept.

## S2 → D12: **closed**, and by a better route than the one I asked for

I asked for `safe_dump` and single-line normalization on two untrusted strings. D12 supplies that for
`reason` — citing ADR-0019 D4/D6 rather than gesturing at it — and then removes the other string from
the interface entirely. `lowered` is constructed from a validated slug, a validated iteration, and a
`to:` value that must be on the successor table.

That is the right instinct and worth naming as a pattern: the question *"how do I sanitize this
input?"* sometimes has the answer *"it should not have been an input."* The field exists to be pasted
into a human's shell; it is now assembled from three validated parts and nothing else.

Script-side slug validation closes the "probably validated two commands away" objection. `security_review: pass`
at the design level — the forged-record fixture is the code-level proof, owed at review.

## S3 → D13 and S4 → D14: **closed**

D13 takes the non-zero default (30) **and** states the limit that makes the number honest: the wall is
checked in `transition`, so it bounds starting new work, not the call in flight. Recording
`elapsed_minutes` per transition so the next default comes from records rather than from a paragraph
is the part I did not ask for and should have.

D14's threat-model paragraph and the corrected six-file manifest close the rest. The fourth parity
fixture — **assert the record path is not gitignored** — is the one I would keep if forced to drop the
other three: it makes a defect that was *true in the working tree when this feature was briefed*
impossible to reintroduce silently.

## Block conditions — round 2

| Condition | Round 1 | Round 2 | Why |
|---|---|---|---|
| `rollback_plan_exists` | ✅ | ✅ | D8 procedure; runbook section now in the manifest |
| `observability_hooks` | 🔴 | ✅ | D11: `gate_result` + `outcome` distinguish a green hand-back from a red one |
| `dependency_failure_modes_documented` | ✅ | ✅ | §1, with three failure modes accepted-and-stated rather than mitigated |

**`block_conditions_met: true`.** The design phase is clear to proceed to code.

## Send back to the architect — round 2

Nothing blocking. Two items travel forward to the coder rather than back to the architect:

1. **S5** — derive `gate_result` from a captured gate-output file, or record why not.
2. **`runbook_accuracy: required`** — the stale-lock section of
   [`docs/runbooks/ssd-state-recovery.md`](../../../docs/runbooks/ssd-state-recovery.md) does not exist
   yet. A recovery procedure in a design document is a plan; a recovery procedure in the runbook is
   where a human at 3am will look.

And one item belongs to **the user, not to either skill**: **R6**, the timestamp instrument. AC-3 as
written cannot pass against artifacts this repo stamps at midnight. The architect recommends restating
it as an intra-record invariant. That is a question about what the acceptance criteria are *for*, and
neither design pass should answer it quietly.
