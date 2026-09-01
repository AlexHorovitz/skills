---
skill: architect
version: 2.12.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: rail-deviations
consumed_by: [systems-designer, coder, code-reviewer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  adrs: [ADR-0019]
  risk_assessment: true
  readiness_checklist: not_applicable
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

## Quality gate

Component diagram ✓ · data model (the record schema) ✓ · API contract (the two verbs and their exit
codes) ✓ · ADR-0019 named ✓ · risk assessment ✓ · readiness checklist **not_applicable** —
`production_runtime: false`, and this spec is the first artifact produced under that declaration.

## For systems-designer

The one question worth your time: **this project declares no production runtime, so does your pass
produce anything?** The honest answer decides whether v2.12.0's declaration was right. Read the
readiness_checklist field above as a claim to test, not a conclusion to accept.
