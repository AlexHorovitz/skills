# ADR-0020: The autonomy ladder — delegating the rails between the two human decisions

## Status

Proposed — 2026-09-21 — designed in the `ssd-autonomy` workstream
([01-architect.md](../../.ssd/features/ssd-autonomy/01-architect.md), revision 2).
D7 was added after systems-designer round 1 returned it as a blocking finding.

Depends on [ADR-0019](ADR-0019-rail-deviation-records.md) (landed v2.13.0): D4 below is expressed in
terms of a deviation record that something actually writes.

## Context

The highest-frequency, lowest-judgment interaction in a mature SSD project is the coder → reviewer →
coder loop until `gate_pass: true`. The orchestrator always *proposes* it and waits. Every ingredient
of a safe agent loop already exists: the gate is executable ([ADR-0005](ADR-0005-gate-execution-model.md)),
sub-skill outputs carry machine-readable frontmatter ([ADR-0006](ADR-0006-frontmatter-validator.md)),
and the rails are a named canonical sequence ([ADR-0003](ADR-0003-rails-as-canonical-path.md)).

What is missing is a sanctioned posture in which the orchestrator may execute its own proposal, and a
durable record of what it did unattended.

Two things in this repo's history constrain the answer, and neither is hypothetical.

**The `--force` failure.** An override was documented in four files for eleven releases. No script
accepted the flag; nothing logged the result. v2.11.0 struck the claim. The lesson is not *document it
better* — it is that **a mechanism described only in prose is a mechanism that does not exist**. This
ADR is written against a 14-section specification of a ceiling, a refusal set, a stop set, an ordering
guarantee and a lock. Each of those is `--force` unless something executes it.

**Pillar 5** ([ADR-0012](ADR-0012-ssd-2.0-architecture.md)): enforcement is warnings, not walls; SSD
trusts the developer. An autonomy feature that is careless here converts trust of the *developer* into
trust of an *agent* without anyone deciding to.

## Decision

### D1 — three rungs, and the default is the current behavior

`project.yml.ssd.autonomy.mode` takes exactly `propose` | `advance` | `run`.

| Rung | What bare `/ssd` does | Phases per invocation |
|---|---|---|
| `propose` (default, and the default is **absence**) | proposes; waits | 0 |
| `advance` | executes its own top proposal when it is unambiguous | ≤ 1, unconditionally |
| `run` | offers `/ssd run`, which walks to a ceiling | ≤ `budget_transitions` |

An absent `autonomy:` block produces byte-identical behavior to v2.13.0. Not "equivalent" — the
orchestrator makes no additional call at all when the block is absent, which is what makes the claim
checkable instead of careful.

An unrecognized literal is a **refusal that quotes the value**, never a silent default. This follows
[ADR-0017](ADR-0017-private-mode.md)'s `gitignore_mode` precedent exactly, and for the same reason: a
misspelled `gitignore_mode` used to disable leak detection without saying so.

### D2 — rule-zero forbids silence, not autonomy

Rule-zero is the one genuinely inviolable rule in `ssd/SKILL.md`: the orchestrator never advances a
phase *without surfacing the decision*. The reading that would forbid this feature is "surfaced =
a human approved it." That is not what the rule says, and the distinction is load-bearing.

Under autonomy, surfaced means **announce → log → act**, in that order:

- **announce** — the transition is narrated in the terminal, naming the lowered command
  (`→ /ssd code auth-flow`), so an attended user sees it before it happens;
- **log** — the transition is appended to a durable record on disk **before the phase runs**;
- **act** — and only then.

The ordering is the whole claim. Announce-then-act is a nicety that evaporates when nobody is
watching, which is the only condition under which this feature is used. Log-then-act means state lags
reality by at most one announced step — which is precisely what makes recovery from an orchestrator
death possible.

### D3 — the ceiling is `gate`, and it is not configurable

`--until` accepts `design` | `code` | `review` | `gate`. `ship`, `deploy`, `rollout-advance` and
`flag-removal` are **refusals**, not settings.

This is not a retreat from Pillar 5. Pillar 5 says SSD trusts *the developer* and does not lock the
door; the developer's door is untouched — `/ssd ship <slug>` typed by a human works exactly as it did.
What is walled is an *agent's* ability to walk through it unattended, which is a different door and
has never been open.

The feature's shape follows from where the judgment is. A feature is bounded by two decisions that are
irreducibly human — **the brief** at the start (what are we building, and is it worth it) and **the
ship** at the end (is this good enough to put in front of people). Everything between them is
mechanical, refereed by an executable gate. Autonomy delegates the middle and neither end.

### D4 — an auto-run writes zero rail deviations, by construction

A deviation is engineering judgment captured for the record ([ADR-0019](ADR-0019-rail-deviation-records.md)).
An agent that can record its own deviations can rationalize its own shortcuts, and the record — whose
entire value is that a human decided something and wrote down why — becomes a log of the agent
agreeing with itself.

So: needing a deviation is a **stop condition**. The enforcement is structural rather than
behavioral — `autorun.sh` validates every transition against the rails successor table and cannot
express an off-rails edge, and because the act is conditional on a successful log, a transition it
refuses is a phase that does not run. `autorun.sh` never invokes `deviation.sh`; the two share one
lock file and one of them is not reachable from the other.

### D5 — bounded, refusable, interruptible

Three properties, none optional:

- **Bounded.** Review loops, phase transitions, wall-clock, and the workstream's own `budget_hours`
  each end the run. Over budget means a scope-cut conversation, not more automated work — which is
  existing doctrine (`chapters/state.md`), applied to the agent.
- **Refusable.** Five failure modes refuse *before* the run starts (ambiguous workstream, a lock
  already held, nothing to do, an invalid ceiling, an unrecognized mode). **No bypass flag exists for
  any of them.** Adding one would recreate `--force` with the same argument that produced it.
- **Interruptible.** Any user message is a pause. The current sub-skill finishes — never a half-written
  artifact — and the run hands back. Delegation is revocable mid-flight; re-invoking resumes from
  recorded state with fresh budgets.

### D6 — a script enforces the ladder; the chapter only explains it

`methodology/autorun.sh` owns mode validation, the ceiling, the successor table, the budgets, the
record, and the lock. The orchestrator still *executes* phases in prose, exactly as today — the script
is a referee, not a runner.

This is [ADR-0019](ADR-0019-rail-deviation-records.md) D2 applied to a feature with more to lose. A
prose-only ladder yields an agent that acts and a record written when the agent remembers to write it,
and the one occasion it will not remember is the crash — the occasion the record exists for.

### D7 — a stop reason is not an outcome

The first version of the record had a field for *why the run ended* and none for *how it went*. A run
that reached the ceiling with a green gate and a run that reached it with a red one produced
byte-identical frontmatter, both reading `stop_reason: STOP-7` — described in the specification as
*"normal completion."*

The consumers named on every record are `codebase-skeptic` and `feynman`, whose shared purpose is
catching the sentence *"the run completed"* standing in for *"the run ended."* A record that cannot
distinguish those is a record that launders the distinction.

**Decision:** a run records `gate_result` (the **exit status of `gate-rules.sh`** — a number from a
script, not a boolean an LLM wrote about its own work) alongside `stop_reason`, and derives
`outcome: green | red | incomplete` from the pair. Where the reviewer's `gate_pass` and the executable
gate disagree, the hand-back names both referees rather than picking one.

This generalizes past this feature. **Any autonomous process that reports on itself needs a field for
the verdict of something that is not it.** The loop may trust `code-reviewer` to judge the code — that
is the job it exists to do — but the *run's* verdict comes from the script.

## Rationale

Every guarantee in this ADR that could be moved into an exit code has been:

| Guarantee | Enforced by |
|---|---|
| `mode` is one of three literals (D1) | `autorun.sh preflight`, exit 2 |
| Absent block ⇒ no behavior change (D1) | no call is made at all |
| Log precedes act (D2) | the orchestrator acts only on `state=ok` from `transition` |
| Ceiling ≤ `gate` (D3) | `start --until ship` exits 2; the successor table has no edge out of `gate` |
| Zero autonomous deviations (D4) | the successor table cannot express an off-rails edge |
| Budgets end the run (D5) | `transition` returns `state=stop reason=STOP-3` |
| One run per project (D5) | the `auto_run` lock in `current.yml`, no bypass flag |
| The verdict is not self-reported (D7) | `gate_result` is `gate-rules.sh`'s exit status; `finish` refuses to close a run at the `gate` phase without it |

What could **not** be moved, stated rather than glossed: *interruption* (D5) depends on the
orchestrator noticing a user message; *sub-skill atomicity* has no guarantee today and this feature
does not invent one; and `gate_result` is a script's exit status **relayed by the orchestrator**,
because `gate-rules.sh` writes no file for anything to read independently. The relay is verifiable
after the fact — re-run the gate on the same commit — and capturing the gate's output to a file is the
named improvement rather than a claimed property.

## Consequences

- `current.yml` gains a **second** writer three weeks after gaining its first. Mitigated by sharing
  `deviation.sh`'s lock, mtime guard, `.bak` and atomic replace rather than reimplementing them. The
  complete answer — every state write through one script — remains named and unattempted
  (ADR-0019 Consequences).
- A **new artifact class** (`auto-runs/*-run.md`) enters the committed tree, which requires a
  `.gitignore` negation in two files. Until that lands the record is invisible to the gate, which
  would be the `--force` failure wearing a filename.
- The **stale lock** is a new operational failure mode: an orchestrator death between `start` and
  `finish` blocks every subsequent run until a human clears it. It extends the existing runbook
  ([`docs/runbooks/ssd-state-recovery.md`](../runbooks/ssd-state-recovery.md)) rather than adding a
  second one.
- SSD acquires a **posture on agent autonomy** it did not have. Previously the answer to "may the
  orchestrator act on its own?" was an unwritten no. It is now a written, bounded, opt-in yes with a
  named ceiling — which is a larger change than the diff suggests.

## Non-Goals

- **Any autonomy past `gate`.** Not configurable, not deferred pending demand.
- **Parallel auto-runs.** One per project, matching the one-session-per-project doctrine.
- **Auto-`ssd-init`.** Committing to the SSD convention stays a user decision.
- **A gate rule for auto-runs.** An informational `auto-run-recorded` rule is a plausible follow-up and
  is not in this release. The rule table grows about one rule per release; this one has not earned its
  slot before a single record exists.
- **Judging whether the agent's work was any good.** The gate does that, and it did before.

## Alternatives Rejected

| Alternative | Why not |
|---|---|
| A single `auto: true` switch | Collapses "execute one accepted proposal" and "walk five phases unattended" into one decision. They have different blast radii and deserve different opt-ins |
| Autonomy through `gate` **and** ship, gated on a clean gate | The gate answers "does this meet the bar", never "should this exist". Shipping is the second irreducible human decision (D3) |
| Let an auto-run record deviations with `auto: true` on the entry | An honest-looking record of an agent agreeing with itself. The need for judgment is the signal to stop, not to write it down and continue |
| Orchestrator prose alone, no script | The arrangement that produced zero `rail_deviations` in a year and four files describing a `--force` that did not exist |
| A `--force`-style bypass for the FM refusals | Same argument, same file, same outcome. The absence of a bypass is the feature |
| Age-based auto-expiry of the stale lock | A mechanism to get wrong (ADR-0019 D5 rejected it for `fcntl` locks). A blocked run is loud and recoverable; a silently-expired lock resumes a run whose working tree nobody checked |
| A daemon or queue | No background execution anywhere in SSD, and this feature is not where that starts |

## What would reopen this

- **A `run` that a user habitually interrupts at the same phase.** That is the ceiling being in the
  wrong place, measured rather than argued.
- **Auto-run records becoming boilerplate nobody reads** — the failure that befell the deploy logs'
  deviation tables. The next epistemic audit is what would catch it.
- **A STOP-2 that fires on a transition the rails genuinely permit.** That would mean the successor
  table and `rails.md` have drifted, and the table is the copy nothing else reads.
- **Evidence that `advance` acts on misread state in practice.** One phase per invocation bounds the
  damage; it does not prevent it.
