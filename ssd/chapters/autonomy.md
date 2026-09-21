<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

## The Autonomy Ladder — `advance` mode and `/ssd run`

(added v2.14.0, see [ADR-0020](../../docs/decisions/ADR-0020-autonomy-ladder.md))

The default orchestrator posture is propose-and-wait, and it stays the default. This chapter
describes two rungs above it, both opt-in, and the wall above them that is not configurable.

**One line:** delegate walking the rails between the two human decisions that bound a feature — the
brief at the start and the ship at the end — with the executable gate as referee and a written record
of every step.

### The ladder

| Rung | What bare `/ssd` does | Phases per invocation | How you get it |
|---|---|---|---|
| `propose` | proposes the next action; waits | 0 | the default, **and the default is absence** |
| `advance` | executes its own top proposal when it is unambiguous | ≤ 1, unconditionally | `autonomy.mode: advance` |
| `run` | offers `/ssd run`, which walks to a ceiling | ≤ `budget_transitions` | `autonomy.mode: run`, or `/ssd run` per-invocation |

With no `autonomy:` block in `.ssd/project.yml`, the orchestrator makes **no additional call at all**
and behavior is identical to v2.13.0. That is why the claim is checkable rather than careful.

### Rule-zero, reinterpreted

Rule-zero — the orchestrator never advances a phase *without surfacing the decision* — is the one
inviolable rule in this library. **It forbids silence, not autonomy.**

Under an autonomy rung, "surfaced" means **announce → log → act**, in that order:

1. **announce** — the transition is narrated, naming the lowered command (`→ /ssd code auth-flow`), so
   an attended user sees it before it happens;
2. **log** — the transition is appended to a durable record on disk **before the phase runs**;
3. **act** — and only then.

The ordering is the whole claim. Announce-then-act is a nicety that evaporates when nobody is
watching, which is the only condition under which this feature is used. Log-then-act means **state
lags reality by at most one announced step**, which is what makes recovery from an orchestrator death
possible at all.

### The delegation wall

`--until` accepts `design`, `code`, `review`, `gate`. `ship`, `deploy`, `rollout-advance` and
`flag-removal` are **refusals** (FM-4), not settings, at every rung.

This is not a retreat from [ADR-0012](../../docs/decisions/ADR-0012-ssd-2.0-architecture.md) Pillar 5.
Pillar 5 says SSD trusts *the developer* and does not lock the door; the developer's door is
untouched — `/ssd ship <slug>` typed by a human works exactly as before. What is walled is an
*agent's* ability to walk through it unattended, which is a different door and has never been open.

### What an auto-run can and cannot do

Read this before enabling `run`. Under `propose`, a human reads every proposal before a sub-skill
runs; that human has been an unacknowledged security control, and `/ssd run` removes them for up to
`budget_transitions` consecutive phases.

**At worst, an auto-run can:** write code, write SSD artifacts, commit to a feature branch, fail a
gate, and consume tokens and wall-clock up to its budgets — leaving a written record of every step.

**An auto-run cannot:** ship, deploy, advance a rollout, remove a feature flag, write a
`rail_deviations` entry, leave the rails, start while another run is in flight, or run without a
record. None of those has a bypass flag, and the absence of a bypass flag is the feature — `--force`
is what a bypass becomes.

### Configuration

In `.ssd/project.yml` under `ssd:` (written commented-out by `ssd-init` and `/ssd upgrade --apply`;
uncommenting is the opt-in):

```yaml
  autonomy:
    mode: propose                # propose | advance | run   (absent block ⇒ propose)
    max_review_loops: 3          # coder<->reviewer rounds per gate attempt before STOP-1
    budget_transitions: 12       # phase transitions per invocation before STOP-3
    budget_wall_minutes: 30      # wall-clock cap per invocation; 0 = uncapped
    announce: full               # full | compact
```

- Exactly three literals are recognized for `mode:`. **An unrecognized value is a refusal** (FM-5)
  that quotes what it found — never a silent default. This follows the `gitignore_mode` precedent
  ([ADR-0017](../../docs/decisions/ADR-0017-private-mode.md)), where a misspelled mode disabled leak
  detection without saying so.
- `/ssd run` works with the block absent, using the defaults above. `mode: run` only changes what bare
  `/ssd` offers.
- `budget_wall_minutes` bounds **starting new work**, not the call in flight: it is checked between
  phases, so one long sub-skill can overrun it. A 30-minute cap is not a 30-minute guarantee.
- `announce: compact` suppresses the reason line in the **terminal** only. The record always carries
  it — a record that is thinnest exactly when something went wrong unattended is not a record.

### `advance`

**Before it can execute anything, the orchestrator runs `autorun.sh preflight` — and it runs it iff
an `autonomy:` block is present in `project.yml`.** With no block there is no call, no output and no
new code path, which is what makes "byte-identical to v2.13.0" a property rather than a claim. With a
block present, a non-zero exit is FM-5 and nothing executes. `/ssd run` always calls `preflight`,
because it works with the block absent.

With `mode: advance`, bare `/ssd` **executes** its top proposal iff the existing decision tree resolves
to exactly one unambiguous next action for exactly one workstream (auto-detect cases 1–2). It
announces the lowered command, appends an auto-run record entry (`mode: advance`), runs that one
phase, and stops.

**Falls back to `propose` behavior verbatim** when: multiple workstreams and no branch resolution
(case 3); the proposal is a question rather than a command; the next step is `ship` or beyond; or any
STOP condition already holds. **Fallback is not a failure and not a deviation.** At most one phase
executes per invocation, unconditionally.

### `/ssd run`

```
/ssd run [<slug>[#<iter>]] [--until <phase>] [--max-loops N] [--budget-transitions N] [--dry-run]
```

`<slug>` is optional when Step 0 branch→workstream resolution succeeds, required otherwise.
`--until` defaults to `gate`. `--dry-run` prints the transition plan and exits, writing nothing.

**Behavior (the orchestrator executes in order):**

1. **Preflight.** `.ssd/project.yml` must exist (the standing init prerequisite). Run
   `bash methodology/autorun.sh preflight` — a non-zero exit is FM-5 and the run does not start.
   With `--dry-run`, run `autorun.sh plan --slug <slug> [--until <p>]` instead and stop here.
2. **Resolve the workstream** via the standard Step 0, then the explicit `<slug>`. Ambiguity ⇒ FM-1.
   Never guess.
3. **Open the run:** `autorun.sh start --slug <slug> --mode run [--until …]`. This is where FM-1,
   FM-2, FM-3, FM-4 and the over-budget refusal fire. It writes the record **and then** the
   `auto_run` lock that points at it.
4. **Loop — announce → log → act:**
   a. Consult the no-arg decision tree for this workstream's next action.
   b. **Announce** the transition, naming the lowered command; `announce: full` also prints the reason.
   c. **Log** it: `autorun.sh transition --slug <s> --from <p> --to <p> --reason "<why>"`.
   d. **Act only on `state=ok` and exit 0.** Any `state=stop` line hands back to step 5 with that
      STOP as the reason. Run the phase exactly as the explicit command would, including that
      command's own failure modes. A phase-level hard failure is STOP-6 — **never a retry**.
   e. **Write `current.yml.active[].phase`** for the phase that just completed, along with
      `last_touched`, `elapsed_hours` and `gate_rounds`; continue.

      The phase write is not bookkeeping. `transition` checks `--from` against the recorded phase and
      hands back with **STOP-4** when they disagree, because `--from` is supplied by the orchestrator
      — the component this design treats as untrusted — and the review-loop budget is counted off the
      edge it names. A stale `phase` therefore stops the run rather than letting it proceed on two
      disagreeing accounts of where the work is.
5. **Hand back:** `autorun.sh finish --slug <s> --stop <STOP-N> --phase-reached <p>`. When the run
   reached the `gate` phase, redirect that phase's `gate-rules.sh` output to a file and pass
   `--gate-output <file>`; `finish` **refuses** to close a gate-phase run with no verdict. Then write
   a handoff note to `current.notes.yml.features.<slug>.handoff_notes` (the existing `/ssd switch`
   machinery) and emit the summary: phases walked, loops consumed, **both referees' verdicts**, stop
   reason, outcome, and the next *proposed* command — past a passing gate that is `/ssd ship <slug>`,
   for the human to type.

**Side effects (in order):**
1. `.ssd/features/<slug>/auto-runs/<ts>-run.md` created (step 3).
2. `current.yml.active[].auto_run` set (step 3), cleared (step 5).
3. One record transition entry per announced phase (step 4c), each written **before** its phase runs.
4. Whatever the executed phases themselves write — artifacts, commits, `current.yml` phase updates.
5. A handoff note in `current.notes.yml` (step 5).

**Interjection is a pause.** Any user message mid-run is STOP-5. Finish the currently executing
sub-skill — never abandon a half-written artifact — then hand back per step 5. Re-invoking `/ssd run`
resumes from recorded state as a **fresh invocation with fresh budgets**.

### STOP conditions (the run started, then handed back)

| # | Condition | Rationale |
|---|---|---|
| STOP-1 | gate still fails after `max_review_loops` rounds | don't thrash; persistent failure needs human judgment |
| STOP-2 | the next action would leave the rails | deviations are engineering judgment ([ADR-0019](../../docs/decisions/ADR-0019-rail-deviation-records.md)); an auto-run writes zero |
| STOP-3 | `budget_transitions`, `budget_wall_minutes`, or the workstream's `budget_hours` exceeded | over budget ⇒ suggest a scope cut, not more work |
| STOP-4 | a sub-skill would have to guess — brief/spec ambiguity, an unresolvable prompt, a missing prerequisite artifact, **or `--from` disagreeing with the recorded phase** | guesses compound silently in a loop |
| STOP-5 | user interjection | delegation is revocable mid-flight |
| STOP-6 | phase-level hard failure (sub-skill error, git error, state-write failure) | fail loudly once; never retry past an error |
| STOP-7 | `--until` reached | the ceiling — see the outcome note below |

**STOP-7 is not a verdict.** It says the run reached its ceiling, not that anything went well. The
record carries `gate_result` (the executable gate's answer) and `outcome` separately, because a run
that ended on a red gate and one that ended on a green gate used to produce identical frontmatter.
The stop reason says *why the run ended*; the outcome says *how it went*:

| `outcome` | Means | Which stops |
|---|---|---|
| `green` | the ceiling was reached and the **executable** gate passed | STOP-7 + `gate_result: pass` |
| `red` | **something judged the work and said no** | STOP-1 (the gate kept failing), STOP-6 (hard failure), STOP-7 + `gate_result: fail` |
| `incomplete` | the run stopped **before** anything judged it | STOP-2, STOP-3, STOP-4, STOP-5, and STOP-7 with no gate result |

Running out of budget is not a verdict on the code, which is why STOP-3 is `incomplete` and not
`red`.

### Failure modes (refusals — the run never starts)

- **FM-1: workstream unresolvable.** Trigger: no slug and Step 0 resolves nothing, or the slug is not
  in `current.yml.active[]`. Refusal names the active workstreams. Bypass: none — re-invoke with a
  slug.
- **FM-2: an auto-run is already in flight.** Trigger: any `active[].auto_run` is non-null. Refusal
  names the holding slug, its start time, and its record path. **No bypass flag.** If the holding run
  died, the lock is stale — see Partial-failure recovery.
- **FM-3: nothing to run.** Trigger: `phase: done`, or the current phase is at or past `--until`.
  Bypass: none.
- **FM-4: the ceiling was exceeded.** Trigger: `--until` is `ship`, `deploy`, `rollout-advance`,
  `flag-removal`, or unrecognized. Refusal restates the delegation wall. **Not configurable.**
- **FM-5: unrecognized `autonomy.mode`.** Trigger: a `mode:` literal outside
  `propose|advance|run`. Refusal quotes the value. No silent default.
- **FM-6: a gate-phase run with no verdict.** Trigger: `finish --phase-reached gate` without
  `--gate-output` or `--gate-result`. The field is optional exactly where it is meaningless and
  mandatory exactly where it matters.

**Not an FM: a corrupt state file.** A `current.yml` that does not parse, is not a mapping, or
carries **two `active[]` entries sharing `(slug, iteration)`** makes `autorun.sh` exit **3** without a
`state=` line — the same stance the orchestrator takes on a malformed `current.yml`, and the same one
the spine takes on duplicate `branch:` values: *emit an error and refuse to guess rather than picking
a first match*. A duplicate pair is only reachable by hand-editing, because `/ssd feature new` rejects
creating one.

### Partial-failure recovery

**The stale lock is the failure you will actually hit.** An orchestrator death between `start` and
`finish` leaves `auto_run` non-null, and every subsequent run refuses with FM-2 naming it.

```bash
bash methodology/autorun.sh status                      # what is held, and its record
bash methodology/autorun.sh clear --slug <slug>         # dry run: prints, changes nothing, exit 10
bash methodology/autorun.sh clear --slug <slug> --confirm
```

Read the record **first** — its last transition entry names the last phase that was announced, and
therefore the last phase that may have run. Verify the working tree against it. Then clear.

The full procedure, including a corrupted or missing `current.yml`, is in
[`docs/runbooks/ssd-state-recovery.md`](../../docs/runbooks/ssd-state-recovery.md). Recovery is
**manual by design**: an age-based auto-expiry would silently resume a run whose working tree nobody
checked.

### The record

Every `run` invocation and every `advance` execution writes
`.ssd/features/<slug>/auto-runs/<YYYY-MM-DDTHHMMSSZ>-run.md` (nested layout:
`iterations/<iter>/auto-runs/…`). The timestamp is colon-free so the filename survives a Windows
checkout; full precision lives in `produced_at`.

```yaml
run:
  mode: run                    # run | advance
  slug: auth-flow
  until: gate
  budgets: {review_loops: 3, transitions: 12, wall_minutes: 30}
  transitions:
    - {ts: …, from: design, to: code, lowered: "/ssd code auth-flow", reason: …,
       since_start_minutes: 0.4, phase_minutes: 0.4}
  loops_consumed: 1
  stop_reason: STOP-7          # null WHILE IN FLIGHT — which is how a crashed run is found
  phase_reached: gate
  gate_result: pass            # pass | fail | not_run — the EXECUTABLE gate's answer
  outcome: green               # green | red | incomplete
```

Committed under `gitignore_mode: selective`, untracked under `blanket` and `private` — the same tier
as a coder-status report. The prose body is **rendered from** the frontmatter, so a crash loses the
narration and nothing else.

### The referee — `methodology/autorun.sh`

The orchestrator still executes phases in prose, exactly as it does today. The script decides whether
it may, because a mechanism described only in prose is a mechanism that does not exist.

| Subcommand | Enforces |
|---|---|
| `preflight` | the `mode` literal (FM-5); prints the resolved budgets |
| `status` | what is held and where its record is |
| `plan` | `--dry-run`; writes nothing |
| `start` | FM-1/2/3/4, the over-budget refusal, the lock, the record |
| `transition` | `--from` against the recorded phase (STOP-4), the rails successor table (STOP-2), the ceiling, all three budgets (STOP-1, STOP-3) |
| `finish` | the gate verdict (FM-6), the outcome, clearing the lock — idempotent |
| `clear` | dry-run by default; `--confirm` acts |

It takes the **same** `.ssd/current.yml.lock` that `methodology/deviation.sh` takes, so the two
writers are mutually exclusive and no new lock file enters the project. It never calls `deviation.sh`:
that is how "an auto-run writes zero rail deviations" is structural rather than promised.

### What is not enforced, stated rather than implied

Three things this chapter would be lying about if it left them out:

- **STOP-5 (interruption) is best-effort.** It depends on the orchestrator noticing your message.
  There is no signal handler and prose cannot build one.
- **Sub-skills are not atomic.** "Finish the current sub-skill" is an instruction, not a guarantee. A
  phase that half-writes an artifact and then fails leaves that artifact; STOP-6 hands back rather
  than retrying.
- **`advance` can act once on misread state.** One phase per invocation bounds it and the successor
  table constrains it; nothing prevents it.

### v1 scope guardrails

Out of scope, deliberately, and not pending demand: any autonomy past `gate`; parallel auto-runs
across worktrees; auto-`ssd-init`; a gate rule for auto-run records; configurable `stop_at:`; record
archival or rotation. Records accumulate — revisit when a single feature exceeds 25 of them, or
`auto-runs/` exceeds 500 files repo-wide.
