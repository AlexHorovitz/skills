---
skill: architect
version: 2.13.0
produced_at: 2026-09-21T19:40:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-autonomy
consumed_by: [systems-designer, coder, code-reviewer]
revision: 3
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: true
  adrs: [ADR-0020]
  risk_assessment: true
  feature_flag: "autonomy.mode (config-as-flag; absent ⇒ propose ⇒ inert)"
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — ssd-autonomy (the autonomy ladder)

## The constraint that shapes every decision below

The brief names two prior failures. Only one of them is a design constraint, and it is this:

> A mechanism described only in prose is a mechanism that does not exist.

`--force` was documented in four files for eleven releases. Every sentence about it was true as a
*description* and false as a *fact*. The PRD for this feature is 14 sections of prose describing a
ceiling, a refusal set, a stop set, an ordering guarantee, and a lock. **Every one of those is
`--force` unless something executes it.**

So the filter on every decision here is not "is this well-specified?" It is: *what runs?* Where a
guarantee can be moved from prose into an exit code, this spec moves it, and says which ones it could
not move.

## What already exists — measured, not assumed

| Thing | State | Consequence for this design |
|---|---|---|
| `methodology/deviation.sh` (ADR-0019) | **Exists**, writes `current.yml` under `fcntl.flock` on `.ssd/current.yml.lock`, splices a `safe_dump`ed fragment, `.bak` + atomic replace + `copymode` | The hard dependency is clear, **and** it is a working, reviewed template for "a script that mutates `current.yml` safely". Copy the mechanics; do not reinvent them. |
| `.ssd/current.yml` | Created 2026-09-21 by this workstream's brief. **Had not existed** | The ADR-0019 writer shipped into a project with no file to write. This design must define absent/malformed behavior, not assume the file. |
| `.ssd/features/**/auto-runs/*.md` | **Gitignored today** (`.gitignore:20 → .ssd/features/**`) | FR-6.2's "committed under `selective`" is false until two files change. Verified with `git check-ignore -v`. |
| `yaml_get` (gate-rules.sh) | Matches `^[[:space:]]*<key>:` at any indent; resolves nested `ssd.autonomy.mode`; `gitignore_mode` does **not** collide | FR-1.5 passes today. Probed with a fixture, not reasoned about. |
| Gate rule table | 13 rules, incl. `deviations-recorded` (reader) and `rails-walked` | An auto-run's artifacts are indistinguishable to both — neither inspects authorship. Confirmed by reading both rules. |
| Exit-code family | `0 ok · 2 usage · 3 failure · 10 needs-retry` across `store.sh`, `issue-sync.sh`, `migrate.sh`, `deviation.sh` | A new script joins this family or it is a novelty. |
| `issue-sync.sh` | Emits `state=… reason=…` on stdout for "didn't act, and that's fine" | The precedent for signalling a STOP without pretending it is an error. |

## Current Scale Baseline

Measured 2026-09-21, not estimated:

| Dimension | Now (1x) | 10x target |
|---|---|---|
| Projects using this library | 1 (this repo, dogfooding) | 10 |
| Feature workstreams in `.ssd/features/` | 15 | 150 |
| Active workstreams at once | 1 | 10 |
| ADRs | 19 | 190 |
| Gate rules | 13 | 130 (implausible — see below) |
| Parity tests / lines | 79 tests, 3137 lines | 790 / ~31k |
| Releases recorded in CHANGELOG | 50 | 500 |
| Commits in the last 30 days | 12 | 120 |
| **Auto-run records per feature** | 0 | ~5–15 (one per `/ssd run`, one per `advance`) |

Two of these rows matter for the design:

- **Auto-run records are the only row that grows *per invocation* rather than per feature.** At 10x
  features and ~10 records each, `auto-runs/` holds ~1500 files repo-wide. That is fine for git and
  unpleasant for a human `ls`. R5 accepts it for v1 with a named trigger for revisiting.
- **The 10x gate-rule number is not a real target**, and saying so is the point of the baseline: the
  rule table grows by roughly one rule per release and 130 rules is not a system anyone would run. The
  constraint this implies for v1 is NG6's — no new gate rule here.

## Component Diagram

```
   user
     │  /ssd            /ssd run <slug> [--until gate]
     ▼
┌──────────────────────────────────────────────────────────────────┐
│  /ssd orchestrator  (prose: ssd/SKILL.md + chapters/autonomy.md) │
│                                                                  │
│   decision tree ──► next action ──► ANNOUNCE ──► LOG ──► ACT     │
└───────┬──────────────────────────────────┬──────────────┬────────┘
        │ preflight / start / transition   │              │ invoke phase
        │ finish / status / clear          │              │ (architect, coder,
        ▼                                  │              │  code-reviewer, gate)
┌───────────────────────────┐              │              ▼
│  methodology/autorun.sh   │              │      ┌───────────────────┐
│  (bash arg-parse +        │              │      │  sub-skills, run  │
│   python3 mutator)        │              │      │  exactly as the   │
│                           │              │      │  explicit command │
│  ENFORCES, not describes: │              │      │  would run them   │
│   · mode literal (FM-5)   │              │      └─────────┬─────────┘
│   · ceiling ≤ gate (FM-4) │              │                │
│   · rails successor (D5)  │              │                ▼
│   · budgets (STOP-3)      │              │      .ssd/features/<slug>/
│   · lock held (FM-2)      │              │        01-architect.md …
└──────┬─────────────┬──────┘              │
       │             │                     │ exit≠0 or state=stop
       │             │                     └──────► HAND BACK (never act)
       ▼             ▼
┌──────────────┐  ┌────────────────────────────────────────┐
│ current.yml  │  │ .ssd/features/<slug>/auto-runs/         │
│  active[]    │  │   2026-09-21T194011Z-run.md            │
│   .auto_run  │  │   (frontmatter: run.transitions[] …)   │
└──────┬───────┘  └───────────────┬────────────────────────┘
       │ shares .lock             │
       ▼                          ▼
┌──────────────┐          ┌──────────────────────────┐
│ deviation.sh │          │ gate-rules.sh            │
│ (ADR-0019)   │          │  frontmatter-valid reads │
│ NEVER called │          │  the record's schema     │
│ by autorun   │          └──────────────────────────┘
└──────────────┘
```

Two properties are visible in the diagram and are the whole design:

1. **Every arrow into "ACT" passes through `autorun.sh` first.** The log is not a side-channel the
   orchestrator writes when it remembers; it is the gate the act is conditional on.
2. **`autorun.sh` and `deviation.sh` share one lock file** and `autorun.sh` never invokes
   `deviation.sh`. NG5 ("zero autonomous deviations") is therefore structural, not a promise.

---

## Decisions

### D1 — a script enforces the ladder; the chapter only explains it

**Decision:** add `methodology/autorun.sh`. It owns: reading and validating `autonomy.mode`, opening
and finalizing the record, appending transitions, setting and clearing the `auto_run` lock, and
refusing every condition the PRD calls a failure mode.

ADR-0019 already litigated this exact question (D2: *"a script writes it, not an instruction"*) for a
feature whose entire problem statement was a prose promise that produced nothing in a year. Autonomy
has strictly more to lose: a prose-only ladder yields an agent that acts and a record that is written
when the agent remembers to write it — and the one case where it will not remember is the crash, which
is the one case the record exists for.

**Against NG4.** The brief's non-goal says "no new daemons, lock files, or protocols." A script is
none of those. On lock files specifically: `autorun.sh` takes **`.ssd/current.yml.lock`, the lock
`deviation.sh` already creates** — no new lock is introduced, and the two writers become mutually
exclusive for free.

**What stays prose.** Execution itself. `autorun.sh` never invokes a sub-skill; the orchestrator does,
exactly as it does today. The script is a referee, not a runner. This keeps NG4's real intent — no new
execution machinery — while moving the *guarantees* into code.

### D2 — the record is committed, which takes two `.gitignore` edits the PRD does not list

`git check-ignore -v` resolves `.ssd/features/ssd-autonomy/auto-runs/<ts>-run.md` to `.gitignore:20`
(`.ssd/features/**`). FR-6.2 says the record is committed under `selective`; today it is not.

**Decision:** add one negation line — `!.ssd/features/**/auto-runs/*-run.md` — to **both**
`.gitignore` (the canonical copy) and `methodology/selective.gitignore` (appended verbatim by
`migrate.sh` for every other project). The existing `!.ssd/features/**/` directory re-inclusion already
covers the intermediate directory, so one line per file suffices; the coder must verify that with
`git check-ignore`, not by reading the pattern.

`methodology/private.gitignore` needs **no** change — private mode tracks nothing SSD produces, and an
auto-run record is exactly the class of thing it exists to keep untracked.

Under `blanket`, the record is untracked like every other artifact. Same tier as coder-status, per
FR-6.2.

### D3 — a colon-free timestamp in the filename

FR-6 specifies `<UTC-ISO-8601>-run.md`. A literal ISO-8601 instant contains colons
(`2026-09-21T19:40:11Z`). Colons are legal on APFS and ext4, illegal on NTFS/FAT, and rendered as `/`
by the macOS Finder. A record whose filename cannot survive a Windows checkout is a record that
disappears exactly when someone tries to audit the repo from a different machine.

**Decision:** `.ssd/features/<slug>/auto-runs/YYYY-MM-DDTHHMMSSZ-run.md` — ISO-8601 basic-format time,
extended-format date, no colons, still lexically sortable. Example:
`2026-09-21T194011Z-run.md`. The full-precision instant is in the frontmatter's `produced_at`, where
it belongs.

Nested layout for iterated workstreams: `.ssd/features/<slug>/iterations/<iter>/auto-runs/…`,
matching every other per-iteration artifact.

### D4 — the mode literal is validated by the script, and only when the block is present

FR-1.2 says an unrecognized `mode:` is a refusal, never a silent default. If the orchestrator reads
that key in prose, FR-1.2 is a sentence, and the failure it prevents (a typo masquerading as a
deliberate setting) is precisely the failure that is invisible from inside.

**Decision:**
- `autorun.sh preflight` resolves `ssd.autonomy.mode` and exits `2` quoting the value if it is not
  exactly `propose` | `advance` | `run`.

  **Amended at implementation (coder, spec_drift).** This said *"via the existing `yaml_get` chain."*
  The implementation reads `project.yml` with `yaml.safe_load` instead, addressing the key by **path**
  (`ssd.autonomy.mode`) rather than by first match at any indentation. Two consequences, both
  deliberate: FR-1.5's parser hazard **disappears** rather than being verified-and-watched, and
  `preflight` now requires PyYAML — which every mutating path already required, and which this library
  hard-fails on rather than skipping (ADR-0019 D3). The config is also read from `project.yml` **only**,
  not the `gate.yml` fallback: `gate.yml` exists for portable *gate inputs* that must travel to CI, and
  a per-machine autonomy posture is the opposite of that.
- The orchestrator calls `preflight` **iff an `autonomy:` block is present in `project.yml`**. Absent
  block ⇒ no call, no output, no behavior change — which is what makes AC-1 (byte-identical output at
  v2.13.0) mechanically true rather than carefully worded.
- `/ssd run` always calls `preflight`, because FR-1.3 lets it work with the block absent.

### D5 — the rails successor table lives in the script, which is how NG5 becomes structural

The strongest available version of "an auto-run writes zero rail deviations" is not a rule the agent
follows. It is a writer that **cannot express** an off-rails transition.

**Decision:** `autorun.sh transition --from <p> --to <p>` validates the edge against a hardcoded
successor table and refuses anything not on it:

| from | allowed `to` | when |
|---|---|---|
| `brief` | `design` | always |
| `design` | `code` | always |
| `code` | `review` | always |
| `review` | `gate` | last review frontmatter `gate_pass: true` |
| `review` | `code` | last review `gate_pass: false` — consumes one review loop |
| `gate` | *(none)* | ceiling; `finish` only |

Everything else — `design` → `review`, any `to:` of `deploy`/`ship`/`rollout`/`flag-removal`, any jump
that skips a step — is a **STOP-2 hand-back**, reported as `state=stop reason=STOP-2` on stdout with
exit 0. Because the act is conditional on `state=ok` (D7), the phase does not run. The agent is not
trusted to decline a deviation; it is unable to log one, and unable to act without logging.

This is also why `--until` never needs a "don't go past ship" check at act time: the table has no edge
out of `gate`.

### D6 — the ceiling is an exit code

`autorun.sh start --until ship` exits `2`. So do `deploy`, `rollout-advance`, `flag-removal`, and any
unrecognized phase name (FM-4). `--until` accepts exactly `design` | `code` | `review` | `gate`,
default `gate`.

D3 of ADR-0020 argues why this is not a Pillar-5 violation: Pillar 5 says SSD trusts *the developer*
and does not lock the door. The developer's door is untouched — `/ssd ship <slug>` typed by a human
works exactly as before (AC-5). What is locked is the *agent's* ability to walk through it unattended,
which is a different door that has never been open.

### D7 — a STOP is not an error, and the orchestrator acts only on `state=ok`

Reusing `issue-sync.sh`'s convention rather than inventing one:

- **stdout contract:** every subcommand prints exactly one machine-readable line,
  `state=ok|stop|refused reason=<STOP-N|FM-N|-> …`, followed by any human text.
- **exit codes:** `0` the call was handled (including a STOP — the run ended normally), `2`
  usage/validation refusal (the FM table), `3` hard failure, `10` needs-retry (the file changed under
  us, or another writer holds the lock).

**The orchestrator executes a phase iff the preceding `transition` call printed `state=ok` and exited
0.** That single sentence is the entire enforcement of FR-6.1 (record-before-act), and it answers the
brief's open question 3: a failed log aborts the act, because there is no `state=ok` to act on.

### D8 — the lock is `auto_run` in `current.yml`, and all three of its bad states are defined

The brief's open question 2. `active[].auto_run` is `null`, or `{started: <ISO>, until: <phase>,
record: <path>}` while a run is in flight. The `record:` path is an addition to FR-2 and it is
load-bearing: without it, FM-2's refusal cannot name the file a human needs to read, and FR-8's
recovery procedure becomes "go look in a directory."

| State of `current.yml` | Behavior |
|---|---|
| **Absent** | Exit `3`. Verbatim stance of `deviation.sh`: *"Refusing to create one — a fresh state file would lose every active workstream."* Autonomy is not the feature that gets to invent state. |
| **Malformed** | Exit `3`, surfacing the parse error — the orchestrator's existing fall-back-to-ask rule. |
| **`auto_run` non-null (in flight or stale)** | FM-2: exit `2`, naming the holding slug, its `started`, and its `record:` path, plus the one recovery command. **No bypass flag** — the whole point of the `--force` lesson. |
| **Slug not in `active[]`** | Exit `2`, listing the active slugs (`deviation.sh`'s behavior). |

**Crash recovery (FR-8)** is then a procedure with real inputs: `autorun.sh status` prints any non-null
lock and the tail of its record (the last announced transition = the last phase that may have run);
the human verifies the working tree; `autorun.sh clear --slug <s> --confirm` clears it. `clear` without
`--confirm` prints what it would do and exits 10, matching `store.sh link`'s dry-run-by-default stance
for the destructive direction.

### D9 — the structured record is complete enough to regenerate the narration

The brief's open question 6. FR-6 asks for the announce lines verbatim in the prose body; FR-6.1 asks
for the transition entry to precede the act. Writing prose twice (once before, once at hand-back) is
the kind of duplication that drifts.

**Decision:** each transition entry carries the announce line's full payload —
`{ts, from, to, lowered, reason}` — where `lowered` is the exact copyable command and `reason` is the
`announce: full` explanation. The prose body is **rendered from** those fields at `finish`. A crash
loses the rendered prose and loses nothing else: every announce line is reconstructible from the
frontmatter, which was written before each act. `announce: compact` suppresses `reason` in the
*terminal* output only — the record always carries it, because a record that is quieter when the user
asked for quiet is a record that is thinnest exactly when something went wrong unattended.

### D10 — `advance` uses the same three calls as `run`

`advance` is one transition, so `start` + `transition` could collapse into one call. They do not.
Uniformity means one record format, one crash shape, one recovery procedure, and one code path to
test — at a cost of two extra `exec`s on a phase that is about to invoke an LLM sub-skill. That trade
is not close.

`advance` writes `run.mode: advance`, `until: <the single target phase>`, and finishes `STOP-7`.

---

## Data Model

### 1. `current.yml` — one additive nullable field (FR-2, extended by D8)

```yaml
active:
  - slug: ssd-autonomy
    # ... existing fields unchanged ...
    auto_run: null
    # ... or, while a run is in flight:
    # auto_run:
    #   started: 2026-09-21T19:40:11Z
    #   until: gate
    #   record: .ssd/features/ssd-autonomy/auto-runs/2026-09-21T194011Z-run.md
```

Additive and nullable: `parse_active_workstreams` reads `slug|phase|…` by field name and ignores keys
it does not know, so no existing reader changes. The indent-aware parser fixed in v2.9.0 (the
`issue-sync-current` defect) already handles nested maps under a list item; `auto_run` is the third
such field after `rail_deviations` and `touches`.

**`auto_run` is never written by hand and never committed** — `current.yml` is gitignored in all three
modes. It is machine-local state whose durable counterpart is the record file.

### 2. The auto-run record

Path: `.ssd/features/<slug>[/iterations/<iter>]/auto-runs/YYYY-MM-DDTHHMMSSZ-run.md`

```yaml
---
skill: ssd
version: 2.14.0
produced_at: 2026-09-21T19:40:11Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature
consumed_by: [codebase-skeptic, feynman]
run:
  mode: run                  # run | advance
  slug: ssd-autonomy
  iteration: null
  until: gate
  budgets: {review_loops: 3, transitions: 12, wall_minutes: 0}
  transitions:
    - ts: 2026-09-21T19:40:12Z
      from: design
      to: code
      lowered: "/ssd code ssd-autonomy"
      reason: "phase: design, architect spec present"
  loops_consumed: 0
  stop_reason: null          # null WHILE IN FLIGHT; STOP-1..STOP-7 at hand-back
  phase_reached: code
  gate_result: not_run       # pass | fail | not_run — the EXECUTABLE gate's exit status (D11)
  outcome: incomplete        # green | red | incomplete — how the run turned out (D11)
---
```

Three notes on fields that are not obvious:

- **`stop_reason: null` is the crash marker in the durable artifact.** A record with a null
  `stop_reason` and no live process is exactly the set of runs that died mid-flight, findable without
  `current.yml`.
- **`scope: feature`** follows FR-6. Note the drift this joins: `chapters/state.md` documents `scope:`
  as `<branch|feature|commit-range|files>` while all 14 existing briefs put the *slug* there, and
  `schemas/brief.yml` already records that the field's values are inconsistent library-wide. This spec
  does not fix that; it declines to add a 15th variant by inventing a third convention, and puts the
  slug in `run.slug` where a consumer can actually rely on it.
- **`version:`** is the library version, per every other artifact.

### 3. New schema — `methodology/schemas/autorun.yml` (FR-6.3)

```yaml
skill: ssd
applies_to:
  - auto-runs/*-run.md       # fnmatch path-tail; `*` crosses `/`, verified in match_schema()
required:
  skill: string
  version: string
  produced_at: timestamp
  produced_by: string
  project: string
  scope: string
  consumed_by: list
  run: dict
```

v1 is structural, matching every other schema in the directory. The validator whitelists nothing, so
no other change is needed — FR-6.3's "extend the validator if it whitelists fields" is a no-op, checked
by reading `validate()` rather than assumed.

### 4. `project.yml` config block (FR-1)

```yaml
  # Autonomy ladder (v2.14.0, ADR-0020). ABSENT ⇒ propose ⇒ behavior identical to v2.13.0.
  # Exactly three literals are recognized. A typo is NOT a silent default: autorun.sh preflight
  # exits 2 quoting the value (the ADR-0017 gitignore_mode precedent).
  # autonomy:
  #   mode: propose              # propose | advance | run
  #   max_review_loops: 3        # coder<->reviewer rounds per gate attempt before STOP-1
  #   budget_transitions: 12     # phase transitions per invocation before STOP-3
  #   budget_wall_minutes: 0     # wall-clock cap per invocation; 0 = uncapped
  #   announce: full             # full | compact
```

Written **commented out** by `ssd-init` and by `/ssd upgrade --apply`, for the same reason `store_root`
is: an absent block is the inert default, and a written-out `mode: propose` invites a one-word edit to
`run` without reading the chapter. The comment is the documentation; uncommenting is the opt-in.

---

## API / Interface Contract

`methodology/autorun.sh <subcommand> [options]` — bash argument handling, `python3` for every mutation
(D1, ADR-0019 D2/D3: the writer may use PyYAML, the gate's reader may not).

| Subcommand | Required options | Effect | Exits |
|---|---|---|---|
| `preflight` | — | resolve + validate `autonomy.mode`; print resolved config | `0` `state=ok mode=<m>`; `2` on an unrecognized literal (FM-5) |
| `status` | `[--slug <s>]` | report any non-null `auto_run` + the tail of its record | `0` always (`state=ok` / `state=stop reason=in-flight`) |
| `start` | `--slug` `--mode` `[--until]` `[--max-loops]` `[--budget-transitions]` `[--budget-wall-minutes]` | create `auto-runs/<ts>-run.md`, set `auto_run` | `0`; `2` FM-1/2/3/4; `3` absent/malformed state; `10` lock contention |
| `transition` | `--slug` `--from` `--to` `[--reason]` | validate the edge (D5) + budgets, append the entry. **`lowered` is constructed, not passed** (D12) | `0` `state=ok` or `state=stop reason=STOP-2\|3`; `2`; `3`; `10` |
| `finish` | `--slug` `--stop <STOP-N>` `--phase-reached <p>` `[--gate-result <pass\|fail\|not_run>]` | render the prose body, write `stop_reason` + `gate_result` + `outcome`, clear `auto_run` | `0`; `2` if `--phase-reached gate` without `--gate-result` (D11); `3`; `10` |
| `clear` | `--slug` `[--confirm]` | hand-clear a stale lock (FR-8) | `10` dry-run without `--confirm`; `0` with; `2` if nothing held |
| `plan` | `--slug` `[--until]` | `--dry-run`'s engine: walk the successor table from the current phase, print the transition plan | `0`; **writes nothing** |

**Invariants the contract carries:**

1. `transition` is the only call that authorizes an act, and only on `state=ok` + exit 0 (D7).
2. `start` is **not** idempotent — a second `start` against a held lock is FM-2, by design.
3. `finish` **is** idempotent — finishing an already-finished run is `state=ok`, so a retry after a
   partial hand-back cannot wedge the lock.
4. `plan` and `status` are the only read-only subcommands, and `--dry-run` uses exactly `plan`
   (AC-8: no record file, no state write — enforced by the call graph, not by care).

### Orchestrator surface (`/ssd run`)

```
/ssd run [<slug>[#<iter>]] [--until <phase>] [--max-loops N] [--budget-transitions N] [--dry-run]
```

Behavior is the PRD's FR-4 steps 1–6, with each guard bound to the call that enforces it:

| PRD step | Enforced by |
|---|---|
| 1. preflight, `project.yml` required, lock check | existing init check; `autorun.sh preflight`; `start` (FM-2) |
| 2. resolve workstream (Step 0 → explicit slug) | orchestrator prose; ambiguity ⇒ FM-1, `start` refuses an unknown slug |
| 3. over budget / `done` / at ceiling ⇒ refuse | `start` (FM-3, STOP-3 semantics before starting) |
| 4. open record + set lock | `start` |
| 5. announce → log → act, loop | orchestrator prose; **gated** on `transition` (D5, D7) |
| 6. hand back | `finish` + handoff note via the existing `/ssd switch` machinery |

---

## Integration Contract

No queues or network calls, but this feature has the shape Principle 6 exists for: a multi-step
process that can die between steps, retries, and two writers on one file.

- **Idempotency.** Stated per subcommand above. The one asymmetry is deliberate: `start` refuses a
  retry (a second run is a real conflict), `finish` accepts one (a retry after a partial hand-back
  must not wedge the lock).
- **Ordering.** The single ordering guarantee is record-before-act, enforced by D7. Its observable
  consequence: **state lags reality by at most one announced step**, which is what makes crash recovery
  possible at all.
- **Concurrency.** `autorun.sh` and `deviation.sh` share `.ssd/current.yml.lock` via `fcntl.flock`
  (never `flock(1)` — absent on macOS). Both carry the `st_mtime_ns` re-check before replace and exit
  `10` if the file moved underneath them. This does not make SSD multi-writer safe; the
  one-session-per-project doctrine still holds, and NG2 (no parallel auto-runs) is enforced by the
  `auto_run` lock being per-project-visible, not per-process.
- **Schema evolution.** `run:` is one new nested key in `current.yml` and one new artifact class. Both
  are additive; every existing reader ignores unknown keys. A record written by v2.14.0 stays readable
  by later versions because `run.transitions[]` entries are append-only maps.
- **Failed-message analogue.** There is no DLQ, but there is its equivalent: a record with
  `stop_reason: null` plus a non-null `auto_run`. `status` is the reader. That pair is the *only*
  evidence a crashed run leaves, which is why D8 puts the record path inside the lock.
- **Sync boundary.** Everything is synchronous and in-process. The orchestrator blocks on each
  sub-skill; there is no background execution, no polling, and no window in which the user's terminal
  is not the authority on what is happening.

---

## Feature Flag Plan

This repo has no runtime flag system — `feature_flag_marker` is deliberately unset in `.ssd/gate.yml`,
so `feature-flag-present` SKIPs by design. That does not make the flag question `not_applicable` here,
because this feature *does* ship a kill switch:

| | |
|---|---|
| **Flag** | `project.yml.ssd.autonomy.mode` |
| **Default** | **absent** ⇒ `propose` ⇒ every new code path inert |
| **Stage 1 (internal)** | this repo only, `mode` absent; `/ssd run` exercised per-invocation (FR-1.3) on the library's own next workstream |
| **Stage 2 (beta)** | `mode: advance` in this repo after one clean `/ssd run` record exists |
| **Stage 3 (100%)** | documented in `chapters/autonomy.md` as available; no project gets it by upgrading |
| **Removal** | **never.** This is a permanent configuration surface, not a rollout flag. |

`/ssd upgrade` therefore treats the block as an **additive no-op migration** (FR-1.4): `applies_to:
project`, `kind: mechanical`, `detect:` = the `autonomy:` key present in `project.yml`, `apply:` =
append the commented block. It is **not** `elective` — writing five commented lines is not the class of
action `elective` exists to guard (that flag exists because a mechanical private-mode entry could
untrack a team's committed ADRs). Manifest entry id: `autonomy-ladder`, `introduced_in: 2.14.0`,
`adr: ADR-0020`.

---

## Risk Assessment

| Risk | L | I | Mitigation |
|---|---|---|---|
| **R1. The record is gitignored** — FR-6.2 claims committed, `.gitignore` says otherwise | **H** (true today) | **H** — an invisible record is the `--force` failure wearing a filename | D2: negation in both `.gitignore` and `methodology/selective.gitignore`; coder verifies with `git check-ignore`, and the parity suite asserts it |
| **R2. Prose drift** — the chapter describes a ceiling/refusal/ordering nothing executes | M | **H** — this is precisely the `--force` class, repeated with a bigger blast radius | D1/D4/D5/D6/D7: mode literal, ceiling, successor table, budgets and record-before-act are all exit codes. The chapter documents the script's behavior, never asserts its own |
| **R3. `advance` acts once on a misread state** | M | M | FR-3.1/3.2 inherited verbatim: one phase maximum, falls back to propose on any ambiguity, and `transition` refuses any non-canonical edge |
| **R4. PyYAML absent** | L | M | Same hard-fail stance as `deviation.sh` — refuse loudly, never skip. A run that cannot record cannot start |
| **R5. Records accumulate** (~1500 files at 10x) | H | L | Accepted for v1 (PRD R3). Revisit trigger, stated so it is not open-ended: **any single feature exceeding 25 records, or repo-wide `auto-runs/` exceeding 500 files** |
| **R6. AC-3 is unverifiable under this repo's timestamp habit** | **H** | M | See below — this needs a decision before the coder writes the acceptance test |

**Top 3:** R1, R2, R6.

### R6 in full, because it invalidates an acceptance criterion as written

AC-3 requires that *"every transition entry timestamp precedes its phase artifacts' `produced_at`"*.
Every committed artifact in this repo carries a **midnight** stamp — `2026-09-01T00:00:00Z` across all
five `rail-deviations` artifacts, and the same in every other feature directory. `autorun.sh` will
write real clock instants. A transition logged at `19:40:12Z` will therefore appear to *follow* an
artifact stamped `00:00:00Z` on the same day, and AC-3 fails on a correctly-ordered run.

This is not a bug in the ordering guarantee; it is a measurement instrument that cannot see it. Two
honest options, and the coder should not pick one silently:

- **(a)** Sub-skills write real UTC instants from here on, and AC-3 is verified only against artifacts
  produced after this feature lands. Cheap, and it makes ~20 artifacts' timestamps retroactively
  look precise when they were not.
- **(b)** AC-3 is restated as an *intra-record* invariant — transition N's `ts` precedes transition
  N+1's, and `produced_at` precedes all of them — which `autorun.sh` fully controls and the parity
  suite can assert. The cross-artifact ordering becomes a documented property of the design rather than
  a tested one.

**Recommendation: (b), plus (a) going forward but not retroactively.** The cross-artifact claim is the
one worth having and the one this repo cannot currently make; saying so is better than a test that
passes by convention.

---

## ADR-0020 — required

Written as part of this pass: [`docs/decisions/ADR-0020-autonomy-ladder.md`](../../../docs/decisions/ADR-0020-autonomy-ladder.md).
Carries D1 (the ladder), D2 (rule-zero reinterpreted as announce → log → act), D3 (the ship wall vs
Pillar 5), D4 (zero autonomous deviations), D5 (bounded / refusable / interruptible), and the D1-here
decision that a script — not an instruction — enforces all of it.

No other always-ADR topic applies: no database, no auth, no service boundary, no deployment target, no
third-party dependency, no licensing change. The sync-vs-async row is addressed in the Integration
Contract and resolved as "synchronous, in-process, no background execution" — recorded there rather
than as a second ADR.

---

## Quality Gate

| Gate item | Section | Status |
|---|---|---|
| Platform guide applied | Component Diagram | ✅ headless (`architect/headless/GUIDE.md`); this is a CLI/skills library — no HTTP surface, so the guide's API/queue/container sections are out of scope and the observability triad is answered by the record itself |
| Major decisions are ADRs | Decision Log | ✅ ADR-0020 written |
| Data model reviewed | Data Model | ✅ 4 structures: `current.yml` delta, record, schema, config block |
| API/interface contract defined | API / Interface Contract | ✅ 7 subcommands, exits, invariants |
| Auth/authorization specified | — | n/a — no network surface, no identity. The authorization question here is *the ceiling*, answered by D6 |
| Async/background work identified | Integration Contract | ✅ explicitly none; synchronous in-process |
| Feature flag strategy defined | Feature Flag Plan | ✅ config-as-flag, default absent |
| CI/CD and deployment path sketched | Risk R1 + Feature Flag Plan | ✅ parity suite assertions named; `/ssd upgrade` manifest entry specified |
| Top 3 risks with mitigations | Risk Assessment | ✅ R1, R2, R6 |
| Current Scale Baseline + 10x | Current Scale Baseline | ✅ measured 2026-09-21 |
| Walking Skeleton deployable today | — | ✅ the library ships as files; absent config ⇒ inert |

`quality_gate_pass: true`.

---

## For systems-designer

Four things I want challenged, in priority order:

1. **Is `autorun.sh` the right blast radius?** It mutates `current.yml` — the file `deviation.sh`
   already mutates and the one whose loss costs every active workstream. I reuse the proven mechanics
   (shared lock, mtime guard, `.bak`, atomic replace, `copymode`) and add a second writer to a file
   that has had exactly one for three weeks. Two writers, one lock, no new lock file — is that the
   right call, or should the record file be the sole source of truth with `auto_run` derived from it?
2. **The stale lock is the most likely field failure.** An orchestrator death between `start` and
   `finish` leaves a lock that blocks every future run. D8 gives it a `status` reader and a
   `clear --confirm`. Is a manual-only recovery correct, or does an age-based auto-expiry belong here?
   ADR-0019 D5 explicitly rejected age-based escape hatches for `fcntl` locks — but this lock is YAML
   state, not an fd, so that reasoning does not transfer unexamined.
3. **R6 (the timestamp instrument).** I recommend restating AC-3. Second opinion wanted before the
   coder builds a test around it.
4. **Failure-mode coverage.** The PRD names 7 STOPs and 5 FMs. I have bound each to a call site;
   what I have *not* done is enumerate what happens when a sub-skill half-writes an artifact and then
   the phase fails (STOP-6). FR-5 says finish the current sub-skill atomically — sub-skills have no
   atomicity guarantee today, and I have not invented one. That gap is deliberate and needs a ruling.

Note on scope: `production_runtime: false` makes rail step 2's second half out of scope for this
project generally — this pass is being run **anyway** because the feature's whole risk surface is
failure modes, a lock, and crash recovery. That is a scope decision, **not** a rail deviation, and no
`rail_deviations` entry belongs in this workstream for it (v2.12.0, D17).

---

# Revision 2 — closing S1 and S2

Round 1 of systems-designer returned `block_conditions_met: false` with two blockers, three
recommendations, and a manifest gap. Both blockers were real and both came from §7 (AI/LLM
integration), which has never applied to a feature in this repo before. D11–D14 close them.

## D11 — closes **S1**: the record carries the referee's verdict, and a run says how it turned out

S1 has two halves. The second one is the defect.

**The half I am not changing.** `review → gate` stays gated on the reviewer's `gate_pass`. That field
is `code-reviewer`'s judgment of the code, which is the job it exists to do, and replacing it with
anything else means the loop no longer runs a review. The mitigation is not to distrust the reviewer —
it is to stop treating its boolean as the *run's* verdict.

**The half that changes.** `--until gate` ends with `gate-rules.sh`, an executable, independent
referee — and the record had nowhere to put its answer. A green hand-back and a red one produced
byte-identical frontmatter. The consumers named in `consumed_by:` are `codebase-skeptic` and `feynman`,
both of which exist to catch precisely the claim *"the run completed"* covering for *"the run ended."*

**Decision:**

1. Two new run fields:
   - `gate_result: pass | fail | not_run` — the **exit status of `gate-rules.sh`**, relayed by the
     orchestrator. Not an LLM's opinion: a number from a script.
   - `outcome: green | red | incomplete` — `green` iff `stop_reason: STOP-7` **and**
     `gate_result: pass`; `red` for a ceiling reached on a failing gate or any STOP-1/2/3/4/6;
     `incomplete` for STOP-5 (user interruption) and for any record still in flight.
2. `finish --phase-reached gate` **without** `--gate-result` exits `2`. The field is optional exactly
   where it is meaningless and mandatory exactly where it matters.
3. The hand-back summary **names both referees separately**. The sentence the old design could not
   produce — *"review says `gate_pass: true`; `gate-rules.sh` FAILs on `rails-walked`"* — is now the
   required shape when the two disagree.

STOP-7 keeps its PRD meaning (*the ceiling was reached*) rather than being split. Splitting it would
fork this spec from the PRD's normative table for a distinction `outcome:` expresses better: **the stop
reason says why the run ended; the outcome says how it went.** Conflating those is what produced the
finding.

## D12 — closes **S2**: `lowered` stops being an input

The strongest available answer to *"an untrusted string reaches a YAML writer"* is to notice that one
of the two strings did not need to be an input at all.

**Decision:**

1. **`--lowered` is removed from the interface.** `transition` **constructs** it from parts it has
   already validated: the phase verb is derived from `--to` (which must be on the successor table), the
   slug from `--slug` (validated below), the iteration from the workstream entry. A field whose purpose
   is to be pasted into a human's shell (AC-3) is never assembled from free text.
2. **`autorun.sh` validates `--slug` itself** against `[a-z0-9][a-z0-9-]*`, and `#<iter>` against
   `[A-Za-z0-9_-]+` — the same patterns `/ssd feature new` step 1 applies. Round 1 is right that
   "probably validated two commands away" is not the standard this repo applied three weeks ago.
3. **`--reason` inherits [ADR-0019](../../../docs/decisions/ADR-0019-rail-deviation-records.md) D4 and
   D6 by citation, not by implication:** the record fragment is `yaml.safe_dump`ed (never
   interpolated), and `reason` is normalized to a single line with `" ".join(reason.split())`. The
   second is not cosmetic — a multi-line scalar is emitted as indented continuation lines that the
   gate's hand-rolled awk walker skips, producing a structurally valid record whose reason no consumer
   can read.
4. A **forged-record fixture** in `scripts/parity-test.sh`, adapted from the ADR-0019 one: a `--reason`
   carrying YAML structure and a newline must round-trip to a single-line scalar with no injected keys.

## D13 — **S3** accepted: `budget_wall_minutes` defaults to 30, with its limit stated

`0` (uncapped) was the wrong default for the one dimension that bounds unattended spend. New default:
**30**.

The number is a guess and this spec says so rather than dressing it up — the U1 story is "step away and
come back to a passing gate," and half an hour is the shape of that errand. What makes it a *good*
guess later is data: each transition entry gains `elapsed_minutes`, so the next value is chosen from
records instead of from this paragraph.

**Its honest limit:** the wall is checked in `transition`, so it bounds *starting new work*, not the
call in flight. A single long sub-skill can overrun it. The cap is a ceiling on how long a run keeps
going, not a timeout on any individual phase — and the chapter must say that in those words, because a
user who reads "30-minute cap" and gets 45 minutes has been misled by a number.

## D14 — **S4** and the manifest gap

**Threat model, one paragraph, in `chapters/autonomy.md`** — stating what an auto-run can do at worst
(write code, commit to a feature branch, fail a gate, leave a record of every step) and what it cannot
(ship, deploy, advance a rollout, remove a flag, write a rail deviation, run a second time
concurrently). Round 1 is right that the human reading every proposal has been an unacknowledged
security control, and right that the ceiling is a better answer than most systems have. Both sentences
belong in the chapter.

**The file manifest in PRD FR-7 is short six files**, because the PRD assumed a prose-only
implementation and D1 chose a script. Corrected manifest — *additions only*, FR-7's rows still stand:

| File | Change | Found by |
|---|---|---|
| `methodology/autorun.sh` | **new** — the referee (D1) | D1 |
| `methodology/schemas/autorun.yml` | **new** — record frontmatter schema (FR-6.3) | D1 |
| `.gitignore` | `!.ssd/features/**/auto-runs/*-run.md` | D2 / brief finding 2 |
| `methodology/selective.gitignore` | same line — `migrate.sh` appends it verbatim for every other project | D2 |
| `docs/runbooks/ssd-state-recovery.md` | **new section** — stale `auto_run` lock recovery (FR-8) | S-D §8 |
| `scripts/parity-test.sh` | 4 fixtures: stale lock, forged record, off-rails edge, **record-not-gitignored** | S-D §9 |

The fourth fixture is the one that earns its place: it makes R1 — the defect that was true in the
working tree when this feature was briefed — impossible to reintroduce silently.

## What round 1 flagged and I am deliberately not changing

- **STOP-5 is unenforceable.** Interruption depends on the orchestrator noticing a message. No signal
  handler exists and prose cannot build one. The chapter states it as best-effort; it does not imply a
  mechanism.
- **Sub-skills are not atomic.** FR-5 says finish the current sub-skill atomically; no sub-skill offers
  that guarantee today and this feature does not invent one. A phase that half-writes an artifact and
  then fails leaves that artifact, and STOP-6 hands back rather than retrying.
- **`advance` can act once on misread state.** One phase per invocation bounds it; the successor table
  constrains it; nothing prevents it.

All three stay *stated* in the chapter rather than smoothed. A chapter that omits them is the genre of
document this feature exists to stop producing.

## Quality gate — revision 2

Unchanged rows still hold. Data Model and API/Interface Contract are updated in place (D11 fields,
D12 signature). Risk Assessment gains no new row: S1 and S2 are closed rather than accepted, S3 and S4
are closed by D13/D14, and R6 (the timestamp instrument) is **still open and still needs the user's
call** — it is the one item in this spec that a second design pass cannot settle, because it is a
question about what this repo wants its acceptance criteria to mean.

`quality_gate_pass: true`.


---

# Revision 3 — closing review round 1

Two MAJORs, four MINORs, one QUESTION and one SUGGESTION. Both MAJORs were the same shape and it is
worth naming, because the spec did not see it: **the script trusted the orchestrator for `--from` and
for which workstream `--slug` meant**, while every other guarantee in this design exists because the
orchestrator is not trusted.

## D15 — `--from` is checked against the recorded phase (closes MAJOR-1)

`transition` now compares `--from` with `current.yml.active[].phase` and hands back **STOP-4** on a
mismatch. D5 put the successor table in the script so the agent could not assert an off-rails *move*;
leaving the *origin* unvalidated handed most of that back — the review-loop counter increments only on
the literal `review → code` edge, so mislabelling made STOP-1 unreachable.

This makes the orchestrator's phase write load-bearing rather than bookkeeping, so
`chapters/autonomy.md` step 4e now requires it explicitly and says why.

## D16 — resolution is on `(slug, iteration)` (closes MAJOR-2)

`find_workstream`, the textual splice, `status`, and every refusal message now use the pair.
`active_slugs()` reports qualified names so FM-1's list is actionable, and refusals print what the user
typed (`feat#a`), not the bare slug.

**The same defect was in `methodology/deviation.sh` and is fixed there too.** The review offered "fix
both, or file the second explicitly"; with no issue tracker enabled on this project, filing is not an
option that produces anything, and fixing one instance of a two-instance class is the granularity error
this repo has recorded three times.

## D17 — `outcome` has a rule (closes QUESTION-1)

`red` = **something judged the work and said no** (STOP-1, STOP-6, or the ceiling reached with a
failing gate). `incomplete` = **the run stopped before anything judged it** (STOP-2/3/4/5). The old
mapping made STOP-3 red, which said "the work is failing" when the truth was "the run ran out of room".

## The four MINORs

Shape-guard on `current.yml` (exit 3, not an `AttributeError` traceback at exit 1) · `README.md` lists
`/ssd run` · the chapter states the `preflight`-iff-block-present rule that AC-1 rests on · one timing
field became two (`since_start_minutes` for the wall budget, `phase_minutes` for how long a phase
actually took).

## What the fixtures now assert

Two new ones and one repaired. **SUGGESTION-1's mirror**: a *rails-valid* edge announced from the
wrong phase reports STOP-4 and logs nothing — the missing half of the STOP-2 assertion, and the test
that would have caught MAJOR-1. **An iteration fixture**: an at-the-ceiling iteration is refused on
its own phase, its in-budget sibling starts, the lock lands on the right entry, and `deviation.sh`
records against the named iteration. The referee fixture now writes `phase` between transitions,
because that is the contract it is testing.
