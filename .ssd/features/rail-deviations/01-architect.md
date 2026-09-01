---
skill: architect
version: 2.12.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: rail-deviations
consumed_by: [systems-designer, coder, code-reviewer]
revision: 2
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  adrs: [ADR-0019]
  risk_assessment: true
  readiness_checklist: complete
quality_gate_pass: true
---

# Architect Spec — rail-deviations (D11)

## The finding, restated as a design constraint

A prose promise produced nothing in a year. **Therefore the deliverable is not a better sentence.**
Every decision below is filtered through one question: *what stops this from silently reverting to
nothing?*

## What already exists — measured, not assumed

Half the plumbing is built, which changes the design substantially:

| Piece | State |
|---|---|
| Schema `{step, reason, ts}` nested under `active[]` | **already parsed.** `parse_active_workstreams` is indent-aware and its comment names `rail_deviations` explicitly as a list field with `step/reason/ts` item keys |
| A reader for it | the parser exists; nothing consumes the parsed deviations yet |
| A writer | **none.** The only `rail_deviations` in any script is a fixture's YAML *input* |
| `production_runtime` condition | **new in v2.12.0**, in the committed `.ssd/gate.yml`, resolved through the `gate_input()` chain |

So this is not a greenfield feature. It is a writer, a consumer, and a record type — fitted to a schema
the gate already understands.

## Component design

```
                    ┌─────────────────────────────────┐
  orchestrator ────►│ methodology/deviation.sh        │
  (skips a step,    │   record  --slug --step --reason│
   or overrides     │   override --slug --rule --reason│──┐
   a red gate)      └─────────────────────────────────┘  │ appends
                                                          ▼
                                              .ssd/current.yml
                                              active[].rail_deviations[]
                                                          │ reads
                    ┌─────────────────────────────────┐   │
  /ssd gate ───────►│ rule_deviations_recorded        │◄──┘
                    │  (gate-rules.sh, crude bash)    │
                    └─────────────────────────────────┘
                                 │ reads
                                 ▼
                    .ssd/gate.yml  production_runtime
```

### D1 — `methodology/deviation.sh`, a new script rather than an orchestrator instruction

**Rejected: prose alone.** The orchestrator already writes `current.yml` for `phase` and `gate_rounds`,
so it *could* write this field too — and that is precisely the arrangement that has produced zero
records since v1.15.0. An instruction with no artifact is what failed.

**Rejected: a new flat file** (`.ssd/deviations.yml`). Easy for bash to append to, and wrong: it would
put the record somewhere `rails.md` does not name and the gate does not parse, creating a second
source of truth for the sake of an implementation convenience.

**Chosen:** a small script that appends into the documented location.

### D2 — the writer may use PyYAML; the reader may not

Appending an item to a list nested inside a YAML list item is the hard part, and is the most credible
explanation for why nothing has ever done it. `set_yaml_scalar` in `migrate.sh` handles block-scoped
*scalars*; this is a different shape.

- **Writer:** `python3` + PyYAML. Already a dependency of `frontmatter-validate.py`, so no new
  requirement enters the library.
- **Reader:** stays crude bash. `gate-rules.sh` deliberately carries a hand-rolled YAML walker with the
  comment *"no PyYAML dependency, consistent with yaml_get"*, and this feature must not make the gate
  itself depend on an optional package.

**The critical constraint:** PyYAML is currently a **soft** dependency — `frontmatter-valid` and
`skill-version-sync` SKIP cleanly without it. **The writer must not.** A deviation that silently fails
to record is this feature's own finding, reproduced. Absent PyYAML, `deviation.sh` exits **3** and says
so on stderr; the orchestrator surfaces that rather than proceeding.

**PyYAML round-trips lose comments.** `current.yml` carries a header block warning humans off manual
edits. The writer must therefore preserve it — read the leading comment run verbatim, re-emit it above
the dumped document. Verified as a risk, not assumed away (R3).

### D3 — two record shapes, discriminated by `kind`

A skipped step and a gate override are different events, and collapsing them would make the reader
unable to distinguish *"we didn't need step 2"* from *"we shipped past a red gate"*.

```yaml
active:
  - slug: some-feature
    rail_deviations:
      - kind: skip                     # a rail step that applied and was not walked
        step: 2
        reason: "no observability surface in this change"
        ts: 2026-09-01T14:00:00Z
      - kind: override                 # a FAILing gate rule shipped past deliberately
        rule: feynman-clean
        reason: "audit report is the input artifact for its own fix; see PR body"
        ts: 2026-09-01T15:00:00Z
```

`kind` is additive: the existing parser reads `step/reason/ts` and ignores keys it does not know, so a
record carrying `kind` and `rule` does not fragment it. **This must be verified by fixture, not by
reading the awk** — the last parser assumption that went unverified cost a rule its ability to pass for
five releases.

### D4 — `rule_deviations_recorded`, and it must read `production_runtime`

**Trigger:** a `VERSION` bump, matching `rails-walked`. A rule that fired on every commit would demand
a deviation record for a step you simply have not reached yet, and would be switched off in a week.

**Check:** for each `.ssd/features/<slug>/` in the release, for each in-scope rail step with no
artifact present, require a `rail_deviations` entry naming that step.

**In-scope is where D17 lives.** Step 2's `systems-designer` half is out of scope when
`production_runtime` resolves false. Without that read, this rule's **first act** on this repo would be
to demand deviation records for 13 features that never needed them — manufacturing the fourteenth
instance of the finding it exists to prevent. This is why D17 was decided first.

**Deliberately not checked:** whether the `reason` string is *true*. A record is only as honest as its
author. The rule enforces that a decision was written down, not that it was a good one.

### D5 — `/ssd ship --force` becomes buildable, and is not built here

With `kind: override` existing, the override finally has somewhere to log. Wiring the orchestrator verb
is a separate change: it is a **surface** decision (ADR-0012 Pillar 5 territory) and this feature is the
**mechanism**. Shipping the mechanism first means the next PR that needs to merge a red gate can record
why — including, plausibly, its own.

## ADR-0019 — required

The record schema is a **public contract**: it lands in `current.yml`, is parsed by the gate, and is
what a future `--force` writes. ADR-0012 Pillar 5's reasoning depended on this trace existing, and
ADR-0016 has an addendum saying so. Contested decisions to capture: the new script vs. orchestrator
prose, the PyYAML asymmetry between writer and reader, the two-shape `kind` discriminator, and the
release-scoped trigger.

## Revision 2 — closing systems-designer's three blockers

Round 1 of this spec returned `block_conditions_met: false`. Two of the three findings were **absent
from this document**, which is the useful part: the design was internally coherent and operationally
incomplete, and only the production-readiness lens separated those.

### D6 — closes **S1**: the `reason` string is untrusted input

Two mechanisms, and both are required. Either alone is insufficient.

1. **Structural writing only.** The writer builds a Python `dict`, appends it to a list, and calls
   `yaml.safe_dump`. There is **no** point in the path where YAML is produced by string concatenation,
   `printf`, `sed`, or an f-string template. This is what makes a forged record impossible rather than
   unlikely.
2. **Normalise the reason to a single line** before it enters the dict — newlines and carriage returns
   collapse to a single space, leading/trailing whitespace stripped.

Mechanism 2 is not belt-and-braces decoration; it closes a *second* problem `safe_dump` alone creates.
A multi-line scalar is emitted as a block or quoted string spanning several indented lines, and the
gate's reader is a hand-rolled awk walker whose rule is `!have || ind <= bnd { next }` — it would skip
the continuation lines, so the record would be structurally sound and its reason **unreadable to the
consumer**. A single-line scalar is both unforgeable and legible to a crude reader.

**Fixture, and it must fail against a naive implementation:** pass
`--reason $'ran out of time\n      - kind: override\n        rule: feynman-clean'` and assert
**exactly one** record exists afterwards, and that its reason contains the literal text
`- kind: override` as data.

### D7 — closes **S3**: the lock lives in Python, not in bash

systems-designer said *"prefer the lock"*. Taken literally as `flock(1)` that would have been a
portability defect on the maintainer's own machine: **`command -v flock` → absent on macOS.** BSD does
not ship it. This is the same family as `stat -f` vs `stat -c` and `sed -i ''`, which have produced
three defects in this library already.

**The writer is already `python3`, and `fcntl.flock` is available there** (verified on this machine).
So the lock goes inside the writer:

- acquire an exclusive `fcntl.flock` on `.ssd/current.yml.lock` before read, hold it through write
- the OS releases it on process exit, **so there is no stale-lock state to detect** and no age-based
  escape hatch to get wrong — strictly better than the portable `mkdir`-lock alternative, which needs
  both
- if the lock is held, wait briefly then exit **10** (needs-retry), never proceed unlocked

**What the lock does not cover — corrected in round 2, because the first version of this paragraph
claimed the wrong thing.** It said the in-lock mtime re-check *"converts a silent lost update into a
loud one."* It does not. Trace the scenario:

```
T0  orchestrator reads current.yml          (holds a copy)
T1  deviation.sh takes the lock, re-checks mtime → unchanged since ITS read → writes
T2  orchestrator writes its `phase` change from the T0 copy → the deviation is gone
```

The lock and the mtime check protect **the writer** against a change landing under it. The loss above
happens in the **orchestrator's** write at T2, and nothing here observes it. A coder reading the
original paragraph would have concluded the hazard was handled.

So, precisely:

- **Prevented:** script-against-script, and any change landing under the writer mid-operation
  (`fcntl.flock` + an in-lock mtime re-check → exit **10**, never an overwrite).
- **NOT prevented:** the orchestrator writing `current.yml` from a copy it read before
  `deviation.sh` ran. The orchestrator takes no lock and cannot be made to.
- **Detected, one boundary later:** by **`deviations-recorded` (D4)**. A lost deviation means the
  release arrives with a skipped step and no record, and the rule FAILs. This is the actual mitigation
  and the original paragraph failed to cite it.

That is consistent with this feature's thesis rather than an exception to it: **pair a writer with a
reader**, because a writer nothing reads decays into silence — and here the reader is also what catches
the write that got lost. The convention in `phases.md` (call `deviation.sh` at a phase boundary, never
mid-edit) is recorded as a convention and **not counted as a mitigation**, since a documented protocol
with no enforcement is precisely what produced nothing for a year.

The complete fix is for **every** `current.yml` write to go through one script. That is a larger
refactor, named here and deliberately not attempted: it would mean moving orchestrator state writes out
of prose, which is a surface change, not a mechanism one.

### D8 — closes **S2**: backup, runbook, and an answer for archiving

- **Backup.** `cp .ssd/current.yml .ssd/current.yml.bak` before mutating, matching `migrate.sh`'s
  existing `backup_pj()` pattern rather than inventing a second convention.
- **Runbook.** `docs/runbooks/ssd-state-recovery.md` — symptom (`/ssd` reports a malformed
  `current.yml`), diagnosis (`python3 -c "import yaml,sys; yaml.safe_load(open('.ssd/current.yml'))"`),
  recovery (restore the `.bak`, re-run the record). **This is the library's first genuine runbook**, and
  it satisfies rails invariant 8 — appending to the project's state file from a script *is* a new
  operational surface, whether or not anything serves a request.
- **Archiving (R5, previously unanswered).** `rail_deviations` moves with the workstream entry into
  `archived[]` verbatim. Nothing prunes or summarises it: the record's whole value is that it survives
  the decision it documents. Asserted by fixture.

### Also closed — the two ⚠ rows systems-designer flagged in §1

| Precondition | Behaviour |
|---|---|
| `.ssd/current.yml` missing or unparseable | exit **3**, name the file. **Never** create a fresh one — silently starting a new state file loses the workstream |
| `--slug` not found in `active[]` | exit **2** (usage/validation), list the active slugs so a typo is obvious |
| `--step` not an integer in 1–8 | exit **2**. `safe_dump` makes the value *safe*; nothing makes it *true*, and `--step 47` writes a well-formed record naming a rail step that does not exist |
| `--rule` not a name `gate-rules.sh` emits | exit **2**. `--rule feynman-clen` would satisfy a `deviations-recorded` check for a rule it does not describe (systems-designer round 2, MINOR-1) |

Both are "exit non-zero and say which precondition failed", matching the exit-code vocabulary already
used by `migrate.sh`, `issue-sync.sh` and `store.sh`: **0** ok · **2** usage · **3** failure ·
**10** needs-confirm/retry.

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | The rule becomes noisy and gets disabled | Release-scoped trigger; `production_runtime` keeps out-of-scope steps out of the count |
| R2 | `kind`/`rule` keys fragment `parse_active_workstreams` | Fixture built from a **realistic** `current.yml` carrying both shapes. The flat-stub fixture is exactly how the last parser defect survived |
| R3 | PyYAML round-trip destroys `current.yml`'s header comments | Preserve the leading comment run explicitly; assert it survives a write |
| R4 | The writer corrupts state mid-write | Write to a temp file and `mv`, matching `migrate.sh`'s `set_yaml_scalar`; never edit in place |
| R5 | Deviations lost when a workstream archives | Assert a recorded deviation survives archiving |
| R6 | PyYAML absent ⇒ deviations silently not recorded | Exit 3 and say so. **Never** a silent no-op — that is this feature's own finding |
| R7 | The reason field becomes boilerplate, as the deploy-log tables did | Unmitigated and stated. No mechanism can make a human write a true sentence. The rule checks presence; a future audit checks quality |
| R8 | A forged record injected through `reason` | **D6** — structural `safe_dump` plus single-line normalisation. Fixture passes a reason containing a forged `kind:` line and asserts one record |
| R9 | Lost update between the writer and an orchestrator edit | **D7** — `fcntl.flock` inside the writer, plus an mtime re-check inside the lock that exits 10 rather than overwriting. Residual: the orchestrator itself takes no lock, stated in D7 |
| R10 | `flock(1)` absent on BSD/macOS | **D7** — the lock is `fcntl.flock` in Python, not `flock(1)` in bash. Verified absent on the maintainer's machine before choosing |
| R11 | A write succeeds and the result is wrong | **D8** — `.bak` before mutating, plus the library's first runbook. R4's temp+`mv` only prevents a *torn* write |
| R12 | Multi-line reason unreadable to the crude bash reader | **D6** mechanism 2 — normalise to one line. `safe_dump` alone would have produced a valid record the consumer could not read |

## Quality gate

Component diagram ✓ · data model (the record schema) ✓ · API contract (the two verbs and their exit
codes) ✓ · ADR-0019 named ✓ · risk assessment ✓ · readiness checklist **not_applicable** —
`production_runtime: false`, and this spec is the first artifact produced under that declaration.

## For systems-designer — round 2

Round 1 asked whether the pass produces anything for a project declaring no production runtime. It
produced three findings and blocked the ship, two of them absent from this spec. **The answer was no,
the declaration was not right, and it is recorded in `02-systems-designer.md` and the v2.12.0
CHANGELOG rather than quietly dropped.**

`readiness_checklist` moves from `not_applicable` to **`complete`** on that evidence. Round 2's
question is narrower: **do D6, D7 and D8 actually close S1, S2 and S3, or do they relocate them?**

Two things worth attacking specifically:

1. **D7's residual.** The lock serialises script against script. The orchestrator does not take it. The
   mtime re-check turns a lost update into an exit 10 — is that sufficient, or is a partial lock worse
   than none because it *reads* as solved?
2. **D8's runbook is unwritten.** The spec names the path and the three sections. A runbook that exists
   as a promise in a design document is the exact shape of the thing this whole feature is about.
