---
skill: coder
version: 2.14.0
produced_at: 2026-09-21T21:10:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-autonomy
consumed_by: [code-reviewer]
files_touched:
  - methodology/autorun.sh
  - methodology/deviation.sh
  - methodology/schemas/autorun.yml
  - methodology/migrate.sh
  - methodology/migrations.yml
  - methodology/selective.gitignore
  - .gitignore
  - ssd/SKILL.md
  - ssd/chapters/autonomy.md
  - ssd/chapters/state.md
  - ssd/chapters/artifacts.md
  - ssd/chapters/upgrade.md
  - ssd-init/SKILL.md
  - docs/decisions/ADR-0020-autonomy-ladder.md
  - docs/runbooks/ssd-state-recovery.md
  - scripts/parity-test.sh
  - README.md
  - CHANGELOG.md
  - VERSION
  - .ssd/features/ssd-autonomy/01-architect.md
tests_added:
  - scripts/parity-test.sh::test_fixture_autorun_referee
  - scripts/parity-test.sh::test_fixture_autorun_iteration_resolution
  - scripts/parity-test.sh::test_fixture_autorun_record_not_gitignored
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: |
    fixture: autorun-referee
    fixture: autorun-record-not-gitignored
    ================================================================
    PASS — 371/371 assertions
lint_results:
  command: "shellcheck -S warning methodology/*.sh scripts/*.sh"
  exit_code: 0
type_check_results:
  command: "bash -n (autorun.sh, deviation.sh, migrate.sh, parity-test.sh) + compile() on the embedded python"
  exit_code: 0
feature_flag:
  name: "project.yml.ssd.autonomy.mode — config-as-flag; ABSENT is the default and makes every new path inert"
  default: off
spec_drift: true
---

# Coder Status — ssd-autonomy (the autonomy ladder)

The specification for this feature is fourteen sections describing a ceiling, a refusal set, a stop
set, an ordering guarantee and a lock. **Every one of those is `--force` unless something executes
it**, so the implementation's organising question was not *did I write what the spec said* but *what
runs*. Seven guarantees moved from prose into exit codes. Three did not, and they are named below
rather than glossed.

## What runs

`methodology/autorun.sh` — 7 subcommands, bash arg-handling over one embedded python mutator, joining
the `0 / 2 / 3 / 10` exit-code family of `store.sh`, `issue-sync.sh`, `migrate.sh` and `deviation.sh`.

| Guarantee | Enforced by | Verified by |
|---|---|---|
| `mode` is one of three literals | `preflight` exits 2, quoting the value | fixture: typo'd mode |
| ceiling ≤ `gate` | `start --until ship\|deploy\|…` exits 2 | fixture: 2 assertions |
| record precedes act | orchestrator acts only on `state=ok` | the call graph + fixture |
| zero autonomous deviations | the successor table cannot express an off-rails edge | fixture: STOP-2 logs nothing |
| one run per project | the `auto_run` lock, no bypass flag | fixture: FM-2 |
| budgets end the run | `transition` returns `state=stop` | fixtures: STOP-1, STOP-3 |
| a gate-phase run records a verdict | `finish` exits 2 without one | fixture: FM-6 |

**The lock is `deviation.sh`'s lock.** `autorun.sh` takes the same `.ssd/current.yml.lock` via
`fcntl.flock` — two writers, one lock, no new lock file entering the project (NG4). It never calls
`deviation.sh`, which is how NG5 became structural instead of promised.

**`current.yml` is spliced, not round-tripped.** Whole-document `safe_dump` would destroy the file's
own header comment. The *value* is `safe_dump`ed and the lines are spliced in — ADR-0019 D4's
arrangement, reused rather than re-derived, and the fixture asserts an interior comment survives.

## What the implementation changed about the design

### `lowered` stopped being an input, and that closed the whole question

D12 asked for `safe_dump` on two untrusted strings. The implementation removes one of them: there is
no `--lowered` flag. `transition` constructs the command from a slug it validated itself
(`[a-z0-9][a-z0-9-]*`), an iteration it validated itself, and a `to:` value that must be on the
successor table. A field whose stated purpose is to be pasted into a human's shell is now assembled
from three validated parts and nothing else.

### `--gate-output` — closing S5 rather than recording why not

Round 2 left the choice open: relay the gate's verdict as a word, or derive it from a captured file.
**Measured first:** `gate-rules.sh` writes no file — results accumulate in a bash array and go to
stdout with an exit code. So `finish --gate-output <file>` parses `^FAIL` / `^PASS` lines from the
redirected output. The verdict becomes an artifact a human can re-read instead of a word an LLM
passed along. The `--gate-result` form still exists for the case where no output was captured.

### FM-6 is new

The spec's failure-mode table has five entries. `finish --phase-reached gate` with no verdict is a
sixth, and it is what makes D11 stick: an optional field on the one case that matters is a field that
will be absent in the record someone needs.

## Spec drift (`spec_drift: true`)

1. **Config is read with `yaml.safe_load`, not the `yaml_get` chain** (D4 said the chain). The key is
   addressed by path (`ssd.autonomy.mode`) rather than by first match at any indentation, so FR-1.5's
   parser hazard **disappears** instead of being verified and watched. Cost: `preflight` requires
   PyYAML — which every mutating path already required. **`01-architect.md` D4 is amended in place.**
2. **Config comes from `project.yml` only, not the `gate.yml` fallback.** `gate.yml` exists for
   portable gate inputs that must reach CI; a per-machine autonomy posture is the opposite of that.
3. **`budget_wall_minutes` default is 30** (D13), not the PRD's 0. Recorded here because the PRD text
   still says 0.
4. **The migration's `detect` probe is a sentinel comment**, `# ssd:autonomy-block=`. The block
   `--apply` writes is *commented out* — an inert block is the byte-identical default — so there is no
   live key to probe, and a key-form probe would report PENDING forever after `--apply` (AC-11 would
   fail). Precedent: private-mode's `# ssd:gitignore-mode=private` sentinel. Verified end to end:
   PENDING → APPLIED → `SKIP-present` → re-apply is a no-op, one block in the file.

## R6 — resolved as (b), on an assumption the user has not confirmed

AC-3 requires each transition timestamp to precede its phase artifacts' `produced_at`. Every committed
artifact in this repo is stamped at **midnight**; `autorun.sh` writes real instants. A correctly
ordered run therefore fails AC-3 as written.

**I implemented the architect's recommendation (b)** — the invariant is asserted *inside* the record
(`produced_at` precedes every transition; transitions are non-decreasing), which `autorun.sh` fully
controls, and the fixture tests exactly that. The cross-artifact claim remains a documented property
of record-before-act rather than a tested one. **If the user wants (a) instead** — sub-skills write
real UTC instants from here on — that is a separate, wider change and this assertion should be
tightened when it lands.

## Three things that are not enforced

Stated in `chapters/autonomy.md` § "What is not enforced" rather than smoothed over, because a
chapter that omits them is the genre of document this feature exists to stop producing:

- **STOP-5 (interruption) is best-effort** — it depends on the orchestrator noticing a message. No
  signal handler exists and prose cannot build one.
- **Sub-skills are not atomic.** A phase that half-writes an artifact and then fails leaves it.
- **`advance` can act once on misread state.** One phase per invocation bounds it; nothing prevents it.

## Two things the reviewer should push on

1. **The gate's verdict on this change is weaker than it looks.** `bash methodology/gate-rules.sh`
   returns `5 pass · 8 skip · 0 fail`, and **eight of those skips are "no diff (vs main)"** — the work
   is uncommitted, so every diff-scoped rule (`adr-delta`, `no-leaky-state`, `rails-walked`,
   `deviations-recorded`, `feynman-clean`) had nothing to inspect. That is not a green gate on this
   feature; it is a gate that has not seen it yet. Re-run after the branch exists.
2. **This working tree mixes two workstreams.** `methodology/gate-rules.sh` and
   `ssd/chapters/enforcement.md` carry an unrelated in-flight change (configurable `adr_dir`) that was
   already uncommitted when this feature was briefed, and **`ssd-init/SKILL.md` now carries edits from
   both**. I did not touch the first two and cannot separate the third by file. No branch was created
   for exactly this reason — `/ssd feature new` refuses a dirty tree (FM-1), and creating one here
   would have carried the other workstream onto it. This needs a human decision before commit, and it
   is hard rule 4 ("separate PRs, never mixed") pointing at itself.

## Acceptance criteria

| AC | Status |
|---|---|
| AC-1 byte-identical with no block | ✅ by construction — with no `autonomy:` block the orchestrator makes no call |
| AC-2 typo refused, value quoted | ✅ fixture |
| AC-3 record + transitions + ordering | ⚠️ **restated** — see R6 above |
| AC-4 STOP-1 after N loops | ✅ fixture |
| AC-5 `--until ship` refused | ✅ fixture (2 assertions); `/ssd ship` untouched |
| AC-6 FM-2 on a held/stale lock | ✅ fixture + runbook § "A stale `auto_run` lock" |
| AC-7 STOP-2, zero deviations | ✅ fixture asserts both the stop **and** that nothing was logged |
| AC-8 `--dry-run` writes nothing | ✅ fixture |
| AC-9 `advance` falls back on ambiguity | ⚠️ **orchestrator prose, untestable here** — `advance` is a decision-tree behavior in `chapters/autonomy.md`, not a script path. Stated so it is not mistaken for tested |
| AC-10 CI green, no stale claims | ✅ 364/364 assertions, shellcheck clean, `doc-claims-are-true` passes |
| AC-11 upgrade reports + applies + idempotent | ✅ verified end to end in a sandbox |


---

# Round 2 — all eight findings closed

Round 1 returned `gate_pass: false` with 2 MAJOR, 4 MINOR, 1 QUESTION, 1 SUGGESTION. All eight are
closed. 371/371 assertions, shellcheck clean.

## The two MAJORs were one mistake

Both findings are the same sentence: **the script trusted the orchestrator for `--from` and for which
workstream `--slug` meant** — in a design whose every other guarantee exists because the orchestrator
is not trusted. Worth stating plainly rather than fixing quietly, because the spec did not see it
either and neither did the systems-designer pass.

**MAJOR-1** — `transition` now compares `--from` against `current.yml.active[].phase` and hands back
STOP-4 on a mismatch. Verified: announcing `code → review` from a workstream at `design` now stops
instead of silently spending no review loop. Consequence worth naming: the orchestrator's phase write
is now **load-bearing**, so `chapters/autonomy.md` step 4e requires it and says why. A stale phase
stops the run rather than letting it proceed on two disagreeing accounts of where the work is.

**MAJOR-2** — resolution is on `(slug, iteration)` in `find_workstream`, the textual splice, `status`,
and every refusal message. Verified against the exact fixture from the review: `feat#a` at the ceiling
and 97 hours over budget is now refused **on its own phase**, its in-budget sibling starts, and the
lock lands on the right entry.

**And the class, not just the instance.** `methodology/deviation.sh` had the same slug-only
resolution — an iteration-qualified `--slug feat#b` matched nothing, and a bare slug recorded against
whichever entry came first. Fixed there too, with a fixture assertion. The review offered "fix both or
file the second"; this project has `issue_tracking: off`, so filing produces nothing, and fixing one
instance of a two-instance class is the error this repo has recorded three times. **This is a
deliberate scope call into a file outside the feature** — flagging it rather than burying it.

## MINORs and the QUESTION

- **MINOR-1** — `load_current` guards the *shape* after parsing. A parseable non-mapping now exits 3
  with a readable message instead of an `AttributeError` traceback at exit 1.
- **MINOR-2** — `README.md` lists `/ssd run`.
- **MINOR-3** — the chapter states the rule AC-1 rests on: `preflight` is called **iff** an
  `autonomy:` block is present.
- **MINOR-4** — one timing field became two: `since_start_minutes` (what the wall budget measures)
  and `phase_minutes` (how long the previous phase took — the data D13 actually wants).
- **QUESTION-1** — answered with a rule rather than a tweak. `red` = something judged the work and
  said no; `incomplete` = the run stopped before anything judged it. STOP-3 is `incomplete`: running
  out of budget is not a verdict on the code. Documented as a table in the chapter.
- **SUGGESTION-1** — the mirror fixture exists: a *rails-valid* edge from the wrong phase reports
  STOP-4 **and logs nothing**.

## One thing the harness taught us, recorded so the next person doesn't lose the time

The two new assertions first came back as `[BROKEN ASSERTION — verdict '' is not an integer]`. Cause:
a `{...}` dict literal inside `$(python3 -c "...")` is **brace-expanded by the shell** before python
sees it, and the program arrives split in two. The fixtures now carry a comment saying so.

Two things are worth noting about that. First, the `_assert` integer guard — added after the Feynman
audit's H1 finding that a command substitution producing *nothing* scored as a PASS — is what turned a
silently-green test into a visible failure. It earned its place. Second, the same class of shell-quoting
trap is why this repo bans `ls | grep` and `flock(1)`: the fixture is now the record of a third one.

## Still true from round 1

The two caveats the reviewer was asked to push on are unchanged and still need a human:

1. **The gate has still not seen this change.** `gate-rules.sh` reports `5 pass · 8 skip · 0 fail` and
   the skips are `no diff (vs main)` — nothing is committed. Re-run once a branch exists.
2. **This working tree still mixes two workstreams.** `methodology/gate-rules.sh` and
   `ssd/chapters/enforcement.md` carry the unrelated `adr_dir` change, and `ssd-init/SKILL.md` carries
   edits from both. `methodology/deviation.sh` is now a third file touched outside this feature's
   original manifest, for the reason given above.

---

# Round 3 — closing MINOR-5 and MINOR-6 at ship

Both round-2 MINORs closed before the branches went out, plus the CHANGELOG clause the deploy-readiness
check turned up. **NIT-1 is deliberately left open** — it was not selected, and a redundant local alias
is not worth an unplanned edit to the same function.

**MINOR-5 — a duplicate `(slug, iteration)` is refused, not resolved.** Making the key a pair did not
make the pair unique. `find_workstream` now counts matches and `fail()`s on more than one, and
`deviation.sh` does the same. **Exit 3, not an FM**, because this is hand-edited state corruption — the
provenance the spine describes for duplicate `branch:` values, where it *"emits an error and refuses to
guess rather than picking a first match."* Same corruption, same answer, and now the same answer in
both writers.

**MINOR-6 — the green path is asserted.** Two new assertions: an all-`PASS` gate output yields
`outcome=green gate_result=pass` on stdout, **and** the record says so in its frontmatter. Writing it
surfaced something worth recording: the first attempt asserted against `status --slug`, which does not
call `find_workstream` at all — it walks `active[]` itself and lists what it finds. So `status` reports
a duplicate rather than refusing it, which is correct for a read-only reporter and was invisible until
a test tried to use it as one. The assertion now targets `plan`, which resolves.

**CHANGELOG — the breaking CLI change is stated.** `/ssd ship`'s readiness check caught that
`deviation.sh` accepted a bare `--slug feat` against an iterated workstream in v2.13.0 and refuses in
v2.14.0. Measured against the v2.13.0 blob, not inferred. The entry now says so, including that a
script relying on the old leniency will exit 2.

375/375 assertions, shellcheck clean, gate 9 pass · 4 skip · 0 fail.
