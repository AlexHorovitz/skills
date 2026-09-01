# ADR-0019: Rail deviation records — a written trace for a step that was skipped

## Status

Proposed — 2026-09-01 — designed in the `rail-deviations` workstream
([01-architect.md](../../.ssd/features/rail-deviations/01-architect.md), revision 2).

## Context

`ssd/rails.md` has promised since v1.15.0 that *"every skipped step appears in `rail_deviations:`"*,
and that `codebase-skeptic` can therefore audit *"did this feature walk the rails?"* **mechanically**.

Measured on 2026-09-01: **zero** `rail_deviations:` fields across 15 archived workstreams. No script
writes one. The only occurrence anywhere in the library is a test fixture's YAML *input*. Deviations
were recorded in prose in deploy logs, which nothing reads.

[ADR-0012](ADR-0012-ssd-2.0-architecture.md) Pillar 5's reasoning depends on this trace existing: a
"hard rule" is *loud when broken* rather than a wall, and the override is supposed to leave a durable
record. Four documents described `/ssd ship --force` as exactly that. v2.11.0 struck the claim because
**neither half was built** — no script accepts `--force`, and there was nowhere for it to log.
[ADR-0016](ADR-0016-feynman-orchestrator-integration.md) carries an addendum saying the same.

So this is not a new capability. It is the missing half of a mechanism two ADRs already reasoned from.

## Decision

### D1 — a record has two shapes, discriminated by `kind`

```yaml
active:
  - slug: some-feature
    rail_deviations:
      - kind: skip
        step: 2
        reason: "no observability surface in this change"
        ts: 2026-09-01T14:00:00Z
      - kind: override
        rule: feynman-clean
        reason: "the audit report is the input artifact for its own fix; see PR body"
        ts: 2026-09-01T15:00:00Z
```

A skipped rail step and a gate rule shipped past deliberately are different events. Collapsing them
would leave a reader unable to distinguish *"we didn't need step 2"* from *"we shipped on a red gate"*,
which is the distinction the record exists to preserve.

`kind` is additive: `parse_active_workstreams` already reads `step`/`reason`/`ts` as list-item fields
and ignores keys it does not know.

### D2 — a script writes it, not an instruction

`methodology/deviation.sh record|override`. The orchestrator already writes `current.yml` for `phase`
and `gate_rounds`, so it *could* write this field as prose — and that is precisely the arrangement that
produced zero records in a year. **An instruction with no artifact is what failed.**

### D3 — the writer may require PyYAML; the reader may not

The writer is `python3` + PyYAML, already a dependency of `frontmatter-validate.py`. The gate's reader
stays a hand-rolled bash walker, which carries the deliberate comment *"no PyYAML dependency,
consistent with `yaml_get`"*.

**The asymmetry is load-bearing.** PyYAML is a *soft* dependency today: `frontmatter-valid` and
`skill-version-sync` SKIP cleanly without it. The writer must **not**. Absent PyYAML it exits **3** and
says so. A deviation that silently fails to record is this feature's own finding, reproduced.

### D4 — the reason is untrusted input: structural writing plus single-line normalisation

Both are required.

`safe_dump` of a constructed dict, never string concatenation — that is what makes a forged record
impossible.

The reason is also normalised to a single line, and **the original rationale for that was wrong.** This
ADR claimed `safe_dump` would emit a multi-line scalar across continuation lines the crude bash reader
skips. Measured at code time: it emits `reason: "a\nb"` on one line with escapes inline. Mechanism 1
alone gives both forgery-resistance and single-line output. Normalisation buys a **legible** reason
instead of an escaped blob — kept for that, and recorded as cosmetic rather than load-bearing.

### D5 — the lock is `fcntl.flock` in Python, not `flock(1)` in bash

**`flock(1)` is absent on BSD and macOS** — verified on the maintainer's own machine before choosing.
The writer is already Python, where `fcntl.flock` is available and is released by the OS on process
exit, so there is no stale-lock state to detect and no age-based escape hatch to get wrong. That is
strictly better than the portable `mkdir`-lock alternative, which needs both.

Inside the lock, the writer re-checks the file's mtime and exits **10** if it changed, converting a
lost update into a loud one.

### D6 — `deviations-recorded` reads `production_runtime`

The reader fires on a `VERSION` bump, matching `rails-walked`. It resolves `production_runtime`
through the ADR-0015 `gate_input()` chain, so a step that is **out of scope** is not demanded a
deviation.

Without that read, this rule's first act on this repository would be to demand deviation records for 13
features that never needed them — manufacturing the fourteenth instance of the finding it was built to
prevent. This is why D17 was decided before this ADR was written.

## Rationale

The whole design is filtered through one question: *what stops this reverting to nothing?* A prose
promise already failed for a year, so every mechanism here is either a script or a rule, and the two
are paired — a writer nothing reads decays into the same silence, and a reader with no writer is a rule
that can never pass.

## Consequences

- `/ssd ship --force` becomes buildable. It is **not** built here: wiring an orchestrator verb is a
  *surface* decision in ADR-0012 Pillar 5 territory, and this ADR is the *mechanism*.
- `current.yml` gains a second writer. That is a real cost, and D5 is the price of it. The complete
  answer — every state write through one script — is a larger refactor, named and not attempted.
- The library gains its **first runbook** ([`docs/runbooks/ssd-state-recovery.md`](../runbooks/ssd-state-recovery.md)),
  satisfying rails invariant 8. Appending to the project's state file from a script *is* a new
  operational surface, whether or not anything serves a request.

## Non-Goals

- **Backfilling the 15 archived workstreams.** The prose record exists in the deploy logs; inventing
  structured records for decisions taken months ago would be fabrication, not history.
- **Judging the `reason` string.** A record is only as honest as its author. The rule enforces that a
  decision was written down, not that it was a good one. Unmitigated and stated.
- **Changing what the rails are.** This records deviations; it does not add, remove or reorder a step.

## Alternatives Rejected

| Alternative | Why not |
|---|---|
| Orchestrator prose alone | Exactly the arrangement that produced zero records since v1.15.0 |
| A new flat file (`.ssd/deviations.yml`) | Easy for bash to append to, and wrong: a second source of truth for implementation convenience, in a location `rails.md` does not name and the gate does not parse |
| `flock(1)` | Absent on BSD/macOS. Same family as `stat -f`/`stat -c` and `sed -i ''`, which have produced three defects here |
| A `mkdir` lock | Portable, but needs stale-lock age detection — a mechanism to get wrong where `fcntl` has none |
| One record shape | Cannot distinguish a skipped step from a red-gate override, which is the distinction worth keeping |
| Fire on every commit | Would demand a deviation for a step not yet reached, and be switched off within a week |

## What would reopen this

- A deviation recorded against the wrong workstream by a typo'd `--slug`. Nothing can detect it, and
  it is accepted in the runbook rather than mitigated.
- The `reason` field becoming boilerplate the way the deploy-log deviation tables did. That is the
  failure this ADR cannot prevent, and the next epistemic audit is the thing that would catch it.
