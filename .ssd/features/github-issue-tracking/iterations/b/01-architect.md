---
skill: architect
version: 1.3.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: github-issue-tracking#b
iteration: b
consumed_by: [coder]
deliverables:
  data_model: true
  api_contract: true
  integration_contract: true
  adrs: [ADR-0014]            # amended (MINOR-2 + iter-B close lifecycle addendum)
  risk_assessment: true
  feature_flag: integrations.github.issue_tracking
quality_gate_pass: true
---

# Architect Spec — github-issue-tracking iter B (close lifecycle + gate rule)

**Platform:** headless skills library (orchestrator prose + bash helper). Parent:
[ADR-0014](../../../../docs/decisions/ADR-0014-github-issue-state-tracking.md),
[iter A 01-architect.md](../../01-architect.md). Brief: [`brief.md`](brief.md).

Iter A built the additive half (ensure/relabel). Iter B builds the **subtractive half** (close) plus
the **read-back check** (gate rule). The hard part is not the `gh issue close` call — it is deciding
*when* a close is safe, given that closing an epic fans out notifications and an SSD workstream can
re-open for a later iteration.

## Design decisions (new this iteration)

### D1 — Where the "don't close the epic yet" guard lives (split of responsibility)
The iter A dogfood surfaced the bug: when feature #28 (iter A) closed, the epic #27 had **no open
children**, yet iter B was still planned — a naïve "all children closed → close epic" would have
closed #27 prematurely.

**Decision:** split the judgment across the two sources of truth, each owning the half it can see:

| Check | Owner | Why |
|---|---|---|
| "are all GitHub `ssd:feature` children of this epic closed?" | `issue-sync.sh close-epic` | a fact about GitHub state — query it from GitHub |
| "is there a planned/active future iteration for this epic locally?" | the **orchestrator** (reads `.ssd/current.yml`) | planned work only exists in local state; GitHub never knows about an iteration until it's synced |

This is the same one-way-authority principle the whole feature rests on: GitHub is a mirror, local
`.ssd/` is the planner. `close-epic` never reads `current.yml` (keeps the script context-free and
unit-testable with mock `gh`); the orchestrator never re-counts GitHub children (it trusts the
script's exit code). Neither closes the epic alone:

```
orchestrator (workstream → done):
  if local state has another planned iteration for this epic  → DO NOT propose close-epic. stop.
  else                                                        → propose close-epic; on accept, run it.
issue-sync.sh close-epic <epic#> [--confirm]:
  if any child ssd:feature issue is OPEN   → exit 0, state=skipped reason=open-children  (NOT an error)
  elif not (auto_close or --confirm)        → exit 10, state=needs-confirm               (caller prompts)
  else                                      → gh issue close <epic#>; exit 0, state=closed
```

Rejected alt: a single `current.yml`-aware close-epic. It would couple the script to local-state
parsing (YAML in bash, again) and make the mock-`gh` unit test need a fake `current.yml` too. The
split keeps each piece testable in isolation.

### D2 — Child discovery = `ssd:feature` label query, not the epic task list (MINOR-2)
Iter A's `ensure-feature` links a child to its epic by an `Epic: #<n>` line in the feature body, and
the data model spoke of a "task-list entry on the epic." MINOR-2 (iter A review) recommended
formalizing child-tracking as the **label query**, which is also what close-detection needs:

> child issues of epic `#E` = every issue with label `ssd:feature` whose body contains `Epic: #E`.

This is the discovery key `close-epic` uses (`gh issue list --label ssd:feature --state open --search
"Epic: #E in:body"`, with a local `grep` confirm to dodge search tokenization, mirroring
`find_issue_by_prefix`). The epic task list becomes optional human affordance, not load-bearing state.
**ADR-0014 amended** accordingly (see addendum).

### D3 — A new iteration gets a new feature issue (iteration-qualified title prefix)
`ensure-feature`/`find_issue_by_prefix` match `--state all`, so a re-run during one iteration
converges even if the issue was briefly closed (idempotent — keep this). But iter A's #28 is *closed
for good*; iter B is genuinely new shippable work. If iter B synced with the bare `github-issue-tracking:`
prefix it would re-find and re-open the closed #28.

**Decision:** for an **iterated** workstream the orchestrator passes the iteration-qualified slug to
`ensure-feature`, so the title prefix is `<slug>#<iter>:` (e.g. `github-issue-tracking#b:`). A
non-iterated workstream is unchanged (`<slug>:`). `startswith` keeps the two prefixes distinct, so
iter A's #28 and iter B's new issue never collide. No script change — `ensure-feature` already takes
the slug verbatim; only the orchestrator's call-site composes `slug[#iter]`. Documented in the phases
chapter.

## Data Model (deltas only)

### `.ssd/project.yml` — no new keys
`auto_close` already exists (iter A). This iteration only *consumes* it in the close path.

### GitHub issue shapes — unchanged
Close transitions an issue's `state` open→closed; labels are left intact (a closed
`ssd:phase/done` feature issue is the archival record). No new labels.

## API / Interface Contract — `methodology/issue-sync.sh` (new subcommands)

| Subcommand | Args | Behavior | Exit |
|---|---|---|---|
| `close-feature` | `<issue#> [--confirm]` | already-closed → `state=closed` (idempotent); else if `auto_close`\|`--confirm` → `gh issue close`; else `state=needs-confirm` | 0 ok; 10 needs-confirm; 3 gh-error; 2 bad args |
| `close-epic` | `<epic#> [--confirm]` | any open child → `state=skipped` reason `open-children`; else gated like close-feature | 0 ok/skipped; 10 needs-confirm; 3 gh-error; 2 bad args |

- **`auto_close` resolution:** read `integrations.github.auto_close` from `.ssd/project.yml` (reuse a
  small yaml getter consistent with the existing helpers; default `false`/absent → gated). `--confirm`
  is the orchestrator's "user said yes this once" signal and overrides the toggle for this call only.
- **`--json`** extends the iter A object with `state` ∈ {closed, needs-confirm, skipped} and an
  optional `reason`. Text mode emits the `OK …`/intent line to **stderr** (iter A MAJOR-1 contract:
  stdout stays the machine channel; close-* return no number so stdout is empty in text mode).
- **Exit 10 = needs-confirm** is the documented "caller prompts" signal (architect iter A table).

### Orchestrator integration (prose → `ssd/chapters/phases.md`)
Extend the existing auto-sync block with the `done` transition:
1. On advance to `done`: run `close-feature <issue#>`. Exit 10 → **surface the intent and prompt
   once** ("Close feature issue #F? [auto_close is off]"); on yes re-run with `--confirm`.
2. Then, **iff local state shows no further planned iteration for this epic** (D1), run `close-epic
   <epic#>`; same exit-10 prompt. Open-children (exit 0 skipped) → report "epic kept open (N open
   children)" and move on.
Every outward close is surfaced before it runs (rule-zero). With `auto_close: false` (this repo) the
user is always prompted; with `true` closes are automatic but still announced.

## Integration Contract (deltas)
- **Idempotency.** Close is convergent: closing a closed issue is a no-op success. Re-running the
  `done` sync after a crash re-attempts cleanly.
- **Failure / degradation.** Unchanged from iter A: any `gh` failure → warn + continue; a failed
  close is retried on the next `done` sync (self-healing). No close is ever required for SSD to
  proceed.
- **Safety.** Close is the only destructive-ish action; double-gated (toggle/confirm + the
  open-children/planned-iteration guards). Reopen is one click, so the gate is a prompt not a lock.

## `issue-sync-current` gate rule (ADR-0014 Q3)
New rule in `methodology/gate-rules.sh`, registered after `migration-manifest-current`. Informational,
SKIP-by-default — models on `rule_migration_manifest_current`:
- **SKIP** when: `issue_tracking` not `on`; OR `gh` preflight fails; OR no active workstream has an
  `issue:` binding (every project except an opted-in one). SKIP detail names the reason.
- **PASS** when every active workstream with an `issue:` has that issue **open** and its single
  `ssd:phase/*` label equal to `current.yml.phase`.
- **FAIL** only on a hard inconsistency: a recorded `issue:` is **closed** while its workstream is
  active, or the phase label ≠ local phase. (A mirror drifting is a warning-class event, but the gate
  is where SSD surfaces drift loudly — consistent with "enforcement is warnings, not walls.")

Because it shells out to `gh`, the rule must SKIP (never FAIL) on any `gh` error, so CI without `gh`
stays green. Parity-test asserts the SKIP-by-default path with no `gh` present.

## Risk Assessment (iter-B-specific)
| Risk | L | I | Mitigation |
|---|---|---|---|
| Premature epic close (iter still planned) | M | H | D1 split guard — orchestrator blocks the proposal; script blocks on open children |
| Re-opening a closed prior-iteration issue | M | M | D3 iteration-qualified prefix → new iteration = new issue |
| Gate rule FAILs CI when `gh` absent | M | H | rule SKIPs on any preflight/`gh` error; parity fixture asserts SKIP-no-gh |
| Close needs-confirm misread as failure | L | M | exit 10 reserved + documented; orchestrator maps 10→prompt, not error |
| Mock-`gh` test diverging from real `gh` | M | M | mock only stubs the 3–4 verbs close-* calls; contract documented at top of harness |

## Decision Log
- **[ADR-0014](../../../../docs/decisions/ADR-0014-github-issue-state-tracking.md)** — amended this
  iteration: (a) MINOR-2 child-tracking = `ssd:feature` label query (D2); (b) iter-B close-lifecycle
  addendum recording the D1 split guard and D3 iteration-qualified feature issue.
- No new always-ADR topic triggered (no DB/auth/topology/deploy-target change).

## Test plan (mock-`gh`)
First unit coverage for `issue-sync.sh`: a `gh` shim on `PATH` (a stub script honoring the handful of
`gh issue {list,view,close}` invocations close-* makes) lets the parity harness assert close-feature
idempotency, the auto_close gate (exit 10), close-epic open-children skip (exit 0), and close-epic
all-closed+confirm (close). Plus a gate-rules fixture asserting `issue-sync-current` SKIPs with no `gh`.
