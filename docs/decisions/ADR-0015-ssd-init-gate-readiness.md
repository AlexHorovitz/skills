# ADR-0015: `ssd-init` must leave the gate *functional*, not merely present

## Status
Accepted — 2026-08-05. Drives the `ssd-init-gate-readiness` feature
([00-brief.md](../../.ssd/features/ssd-init-gate-readiness/00-brief.md)). Recorded under the
[ADR-0011](ADR-0011-decision-record-doctrine.md) decision-record doctrine. Target skill: `ssd-init`
(v1.10.0), with companion changes in `methodology/gate-rules.sh` and
`methodology/hooks/pre-commit-no-leaky-state.sh`. Observed during the SSD adoption of
`cryostat_chip_console` (2026-08-03 → 2026-08-05); the source proposal's evidence is preserved in
§ "Appendix: provenance of every claim".

## Context

A greenfield adoption of SSD on a real project ran `/ssd-init`, cleared the CI/CD and feature-flag
blockers it reported, shipped a defect fix, and then ran `/ssd gate`. The gate **exited 0**.

Of the nine rules in that run, **one** had actually verified anything. Reconstructed:

| Rule | Reported | Why |
|---|---|---|
| `tests-pass` | SKIP | `no test_command in .ssd/project.yml` — `ssd-init` never wrote it |
| `feature-flag-present` | SKIP | `no feature_flag_marker in .ssd/project.yml` — likewise |
| `frontmatter-valid` | SKIP | `validator not found at methodology/frontmatter-validate.py` |
| `skill-version-sync` | SKIP | same lookup, same miss |
| `adr-delta` | SKIP | staged-mode diff range empty (see P4) |
| `wip-commits` | SKIP | staged mode has no commits to grep |
| `migration-manifest-current` | SKIP | correctly N/A outside the library repo |
| `issue-sync-current` | SKIP | correctly N/A, tracking off |
| `no-leaky-state` | **PASS** | the only rule that ran |

Exit 0 is a truthful summary of "no rule FAILed." It is a misleading summary of "this change was
gated." Every SKIP above except the last two is a **configuration or installation defect**, not an
inapplicable rule — and nothing in the output distinguishes those two categories.

Running the validator by hand from the library path immediately found a real defect the gate had
passed over: a `03-coder-status.md` missing eight required schema fields.

This is the failure mode SSD exists to prevent, occurring in SSD's own tooling: a green signal that
attests to less than the reader believes. It is worse than a red signal, because it is trusted.

### The five root causes

**P1 — `ssd-init` does not write the gate's inputs.** `gate-rules.sh` reads `test_command`
(`gate-rules.sh:266`) and `feature_flag_marker` (`:286`) from `.ssd/project.yml`. The Step 6
`project.yml` template (`ssd-init/SKILL.md:279`) writes neither. Both rules therefore SKIP from the
moment a project is initialized, and nothing in the init log says so. Two of the eight gate rules are
inert by default, in every project SSD has ever initialized.

**P2 — the gate's inputs are gitignored, so they cannot travel.** `.ssd/project.yml` is machine state
under the ADR-0008 selective-commit split. Adding the P1 keys locally fixes one workstation.
Verified on a clean clone of the same repo: `SKIP tests-pass :: no test_command in …/.ssd/project.yml`.
So gate configuration is per-checkout, silently, and a second contributor gets a weaker gate than the
first with no indication.

**P3 — the library is assumed to live at the repo root.** Three places hard-code it:

- `pre-commit-no-leaky-state.sh` resolves `"$PROJECT_ROOT/methodology/gate-rules.sh"`.
- `gate-rules.sh` looks for `methodology/frontmatter-validate.py` relative to the project root
  (hence the two SKIPs above).
- `ssd-init` Step 5.5 (`:232`) prints `ln -s ../../methodology/hooks/… .git/hooks/pre-commit`.

For a **user-level install** (`~/.claude/skills/`, the default for a developer using SSD across many
projects) all three are wrong. The consequence was not subtle: the install command `ssd-init` printed
produced a hook that exited 2 and **blocked the user's first commit** with "methodology/gate-rules.sh
not found." Symlinking the script cannot fix it, because the script resolves the library from the
*repo* root regardless of where the script itself lives. The user had to hand-write a wrapper.

`ssd-init` currently has no concept of where the library is, so it cannot warn, adapt, or record it.

**P4 — no CI-usable validation path.** A CI runner has neither the library nor its schemas.
`frontmatter-validate.py` is ideal for CI — Python 3 stdlib only, exit 1 on FAIL, exit 0 on absent
paths — but its schemas resolve as `Path(__file__).resolve().parent / "schemas"`
(`frontmatter-validate.py:53`), so script and schemas must travel together. `ssd-init` offers no path
to that, so artifact validation ends up local-only and therefore optional in practice. Adopting it
required hand-vendoring five files (463 lines).

Related but out of scope for `ssd-init`: `feature-flag-present` and `adr-delta` compute
`git diff "$BASE...HEAD"` unconditionally (`:311`, `:340`), so under `--staged` — the mode the
pre-commit hook and any pre-commit workflow uses — that range is empty by construction and both rules
can only SKIP. Listed here because it produced two more of the SKIPs above and because the fix is a
documented workflow rule `ssd-init` should emit (see Decision 5).

**P5 — Step 9's prerequisite checks never test the gate.** Step 9 (`:493`) checks CI/CD, test harness,
linter, flag system, deployed hello-world, secrets, README. All are checks on the *project*. None asks
the one question that mattered: *can `/ssd gate` actually execute its rules here?* `ssd-init` writes
the gate's configuration and then never verifies its own output.

## Decision

Six changes. Five to `ssd-init`; one is a companion change elsewhere that `ssd-init` alone cannot
deliver — called out explicitly because "modify `ssd-init`" is not sufficient for P3.

### 1. Step 6 detects and writes `test_command` (fixes P1)

Extend the Step 6 `project.yml` template with a `ssd.test_command`, populated by detection rather
than left absent:

| Signal | Value |
|---|---|
| `Makefile` with a `test:` target | `make test` |
| `package.json` with `scripts.test` | `npm test` |
| `pyproject.toml` / `pytest.ini` / `tests/` + pytest dep | `pytest` |
| `go.mod` | `go test ./...` |
| `Cargo.toml` | `cargo test` |
| `*.xcodeproj` / `Package.swift` | `xcodebuild test …` / `swift test` |

Detection order is most-specific-first; a `Makefile` `test:` target wins over a language default
because it is the project's own declared entry point. Ambiguity is **prompted**, never guessed
silently.

If nothing is detected, write the key **commented out** with a one-line explanation. `gate-rules.sh`'s
YAML reader already skips comment lines (`# test_command: pytest` is documentation, not a value), so a
commented placeholder degrades to today's SKIP — no regression — while making the missing piece
visible in the file the user will actually open. Record it in the init log at **MAJOR**, per Decision 4.

`feature_flag_marker` cannot be detected before a flag mechanism exists. Write it when a known library
is present (`unleash`, `launchdarkly`, `growthbook` — their documented call markers); otherwise leave
it commented and tie the follow-up to the flag-system BLOCKER Step 9 already reports. The two are the
same task: whoever establishes the flag mechanism sets the marker. Saying so in one place is the
change.

### 2. A committed gate-input file (fixes P2)

Introduce `.ssd/gate.yml` — committed, holding **only** portable gate inputs:

```yaml
# .ssd/gate.yml — committed gate inputs. Portable across clones and CI.
# Machine-specific state stays in .ssd/project.yml (gitignored).
test_command: make test
feature_flag_marker: flag(
```

`ssd-init` writes it in Step 6 and adds `!.ssd/gate.yml` to the selective-gitignore block in Step 5
(a new line in `methodology/selective.gitignore`, the single source both `ssd-init` and
`migrate.sh` consume).

Companion change: `gate-rules.sh`'s `yaml_get` gains a fallback chain — `.ssd/project.yml` first (so a
developer can override locally), then `.ssd/gate.yml`. Precedence in that order keeps local override
possible while making the committed file the floor.

This is what makes the gate **reproducible**: every clone and every CI run inherits the same rule
configuration, which is the property P2 currently denies.

> **Decision 1 ↔ 2 reconciliation (iter-A implementation, 2026-08-06).** Decision 1 as written puts a
> live `ssd.test_command` in `project.yml`; Decision 2 puts it in `gate.yml`. Writing the same value
> *live* in both a gitignored and a committed file is redundant and ambiguous about which is
> authoritative. Iter A resolves this: the detected value is authoritative in the **committed
> `gate.yml`**, and `project.yml` carries only a **commented override stub** (uncomment to override
> locally). The fallback precedence (project.yml → gate.yml) is unchanged, and P1/P2 are both still
> fixed. This is the reading the acceptance criteria assume (AC1: "produces a `project.yml` *and*
> `gate.yml` for which `tests-pass` PASSes" — the committed floor is what survives a clone in AC3).

### 3. Record where the library actually is (P3, `ssd-init` half)

Step 1 already locates the project root. Add: locate the **library** root and record it.

```yaml
ssd:
  library_root: ~/.claude/skills/methodology   # or: methodology/ (vendored at repo root)
  library_version: 2.4.0
```

Resolution order: `$SSD_LIB` → repo-root `methodology/` → the directory the running skill was loaded
from → prompt. Recording `library_version` also gives `/ssd upgrade` (ADR-0013) a concrete baseline
instead of inferring drift.

Step 5.5's printed install command then uses the **resolved absolute path**, or emits a wrapper hook
when the library is not at the repo root — so the command `ssd-init` prints is one that works in the
environment it was printed for. The current text is correct only for the library's own repo and for
projects that vendor it, which is the minority case.

### 4. Step 9 gains a Gate Readiness check that *runs the gate* (fixes P5)

Execute `gate-rules.sh` at init time and report per-rule status in the init log, classified into three
buckets — the distinction the current output lacks:

| Bucket | Meaning | Init-log severity |
|---|---|---|
| **PASS** | rule ran and verified | — |
| **SKIP (not applicable)** | genuinely N/A: no `migrations.yml`, tracking off, no `SKILL.md` | INFO |
| **SKIP (misconfigured)** | rule *should* apply but cannot run: missing `test_command`, validator not found, library unresolved | **MAJOR** |

The third bucket is the entire proposal in one row. A rule that cannot run must be as loud as a rule
that fails, because operationally it is worse: a FAIL stops you, an unnoticed SKIP does not.

Step 11's recommendation becomes conditional on it: if any rule is in bucket three, the recommended
next step is *fix the gate*, not `/ssd start` or `/ssd feature`. A project whose gate cannot run has
no shippable-state check, which per `methodology/core.md` means it is not doing SSD yet.

`gate-rules.sh` should additionally print the bucket-three count in its own summary line, so the
distinction survives outside `ssd-init`.

### 5. Emit the workflow rules the tooling cannot enforce (P4, partial)

`ssd-init` writes `CLAUDE.md` (Step 8) and can write a runbook. Two facts belong there because no
amount of configuration prevents them:

- **Gate a committed branch, not a staged tree.** Under `--staged`, `feature-flag-present` and
  `adr-delta` cannot function. A staged run is a useful pre-commit smoke test and is **not** a gate.
- **Which rules this project structurally cannot run**, and why — so a future reader can tell a
  legitimately-N/A rule from a broken one without re-deriving it.

### 6. Offer to vendor the validator for CI (fixes P4)

New optional step, offered **only** when Decision 3 resolves the library somewhere a CI runner cannot
reach (i.e. not at the repo root): copy `frontmatter-validate.py` + `schemas/` into `tools/ssd/`
(committed), with a provenance header recording source version and refresh instructions, plus a drift
check comparing the copy against the installed library.

Opt-in, never automatic — vendoring is a maintenance commitment and only the user can accept it. But
it is the only way artifact validation becomes unbypassable, and it is cheap: 463 lines, stdlib only,
no runner setup.

## Scope and degradation

- **Projects that vendor the library at the repo root** see no behaviour change from Decision 3 and
  are not offered Decision 6. Everything already resolves for them.
- **Projects with no CI** still get Decisions 1–5; Decision 6 is moot without a runner.
- **A project that declines every prompt** ends up exactly where today's `ssd-init` leaves it, except
  that the init log now says so at MAJOR instead of silently. That is the minimum acceptable outcome:
  **informed** inertness rather than invisible inertness.
- **Idempotency is preserved.** Every change is additive to `project.yml` or a new file. Re-running
  `ssd-init` on an initialized project reads existing values and reports drift, per the existing
  contract in § "Idempotency Rules" — it never overwrites.
- **No new dependencies.** Detection is filesystem inspection; the vendored validator is stdlib.

## Consequences

**Good**

- The gate verifies something on day one instead of on the day someone audits it.
- Gate configuration becomes a property of the repository rather than of one workstation.
- The hook-install command `ssd-init` prints works in the environment it is printed for.
- Artifact validation becomes CI-enforceable, which is what makes it real.
- "Cannot run" is separated from "did not apply" — a distinction the current output collapses, and the
  direct cause of the misread in Context.

**Costs, accepted**

- `ssd-init` gets longer and prompts more. Mitigated by detection: prompts appear only where detection
  is genuinely ambiguous.
- `.ssd/gate.yml` is a new committed file and a new gitignore exception — a small increase in the
  surface ADR-0008 has to explain.
- Running the gate during init makes init slower, bounded by `test_command`. Offer `--skip-gate-check`
  for the impatient, and note that a slow test suite discovered at init is itself useful information.
- Vendoring introduces drift. Bounded by the provenance header, the drift check, and an explicit
  refresh command.

## Alternatives rejected

**Commit `.ssd/project.yml` wholesale instead of adding `gate.yml`.** Simpler, and wrong: it carries an
absolute `project.root`, `initialized_at`, and machine-local paths. ADR-0008 classifies it as machine
state deliberately. A narrow committed file for the portable subset respects that boundary; committing
the whole thing erases it.

**Make `gate-rules.sh` fail instead of SKIP on missing config.** Tempting — it would have surfaced
this immediately. Rejected: it converts "SSD not fully configured yet" into "your gate is red," which
punishes incremental adoption and trains people to ignore red. The reporting fix (Decision 4) gets the
visibility without the false failure. SKIP is the right *status*; invisibility is the bug.

**Teach `ssd-init` to vendor the whole library.** Fixes P3 and P4 in one move and is what the current
docs implicitly assume. Rejected: it makes every project carry the library, multiplies drift by the
number of projects, and defeats the point of a user-level install. Decision 3 (resolve and record)
plus Decision 6 (vendor one stdlib script, opt-in) gets the same coverage at a fraction of the
maintenance.

**Do nothing; document the sharp edges.** This proposal *is* partly documentation (Decision 5), but
documentation alone leaves the default state broken. The project in Context had read the init log,
cleared its blockers, and still gated nothing — because the failure was in what the log did not say.
A default that requires reading a caveat to be safe is not a safe default.

## Migration (ADR-0013)

Append to `methodology/migrations.yml`. All `applies_to: project`, so `/ssd upgrade` picks them up:

| `id` | `kind` | `detect` | `apply` |
|---|---|---|---|
| `gate-inputs-present` | mechanical | `project.yml` or `gate.yml` defines `test_command` | run Decision 1 detection; write it, or write the commented placeholder |
| `committed-gate-yml` | mechanical | `.ssd/gate.yml` exists and `selective.gitignore` has `!.ssd/gate.yml` | create the file from existing `project.yml` values; add the exception |
| `library-root-recorded` | mechanical | `project.yml` defines `ssd.library_root` | resolve per Decision 3 and write it |
| `gate-readiness-reported` | guided | — | re-run `ssd-init`, or `make gate`, and act on any bucket-three rule |
| `ci-artifact-validation` | guided | — | adopt Decision 6 if the library is unreachable from CI |

`gate-inputs-present` and `library-root-recorded` are the ones existing projects most need: every
project initialized before this change has two inert gate rules and an unrecorded library location.

## Acceptance criteria

1. A fresh `ssd-init` on a project with a detectable test command produces a `project.yml` (and
   `gate.yml`) for which `tests-pass` **PASSes** on the next gate.
2. A fresh `ssd-init` where the library is **not** at the repo root prints a hook-install command that,
   run verbatim, produces a hook that exits 0 on a clean commit. *(Regression test for the concrete
   failure in P3: a blocked first commit.)*
3. Cloning an initialized project and gating it yields the same rule set as the original checkout —
   no rule SKIPs for want of configuration.
4. `ssd-init`'s log lists every rule in one of the three buckets, and any bucket-three rule appears at
   MAJOR with a named remedy.
5. Step 11 recommends fixing the gate — not `/ssd start` / `/ssd feature` — while any bucket-three
   rule remains.
6. Re-running `ssd-init` on a project already satisfying 1–5 changes no file.
7. `/ssd upgrade` on a pre-change project detects and applies `gate-inputs-present`,
   `committed-gate-yml`, and `library-root-recorded` idempotently.

## Addendum (2026-08-28) — `gitignore_mode: private` knowingly reopens root cause P2

Added by the `ssd-private-mode` workstream ([ADR-0017](ADR-0017-private-mode.md), library v2.8.0).
Recorded here rather than left for a future reader to discover as a contradiction.

**What this ADR decided.** Decision 2 moved the portable gate inputs (`test_command`,
`feature_flag_marker`) out of gitignored `.ssd/project.yml` and into a **committed** `.ssd/gate.yml`,
with a `!.ssd/gate.yml` negation in the selective `.gitignore`. That fixed root cause **P2**: *"those
inputs live in gitignored `project.yml`, so gate config is per-checkout: a second contributor silently
gets a weaker gate."*

**What private mode does to it.** Private mode tracks nothing SSD produces, so **no committed
`.ssd/gate.yml` can exist** — `methodology/private.gitignore` deliberately contains no `!` negation of
any kind. P2 is therefore reopened for private projects, by construction and on purpose.

**Verified graceful, not accidental.** `gate_input()` reads `project.yml` **first**, then `gate.yml`, so
an absent `gate.yml` degrades to `project.yml` rather than erroring. This is why `ssd-init` under private
mode writes `test_command` and `feature_flag_marker` as **real keys** in `project.yml` instead of the
commented placeholders it writes for selective projects. Omitting that promotion would leave
`tests-pass` and `feature-flag-present` permanently SKIPped — turning a privacy choice into a silently
weaker gate, which is the failure this ADR exists to prevent.

**The trade, stated plainly.** A private project's gate configuration **does not travel** to a second
clone or a CI runner. For private mode's actual audience — a solo or personal practice inside someone
else's repo — P2's blast radius is close to nil, because there is no second contributor to silently
receive a weaker gate. That is the trade: P2's cost is proportional to the number of collaborators, and
private mode's premise is that there are none.

**What is NOT conceded.** Private mode does not weaken the *rules*. ADR-0017 fixes an `adr-delta`
deadlock and a `feynman-clean` blind spot that diff-scoping would otherwise have introduced, precisely
so private mode cannot become the hollow green gate described in this ADR's Context. A mode that
silently stopped verifying would have reproduced this ADR's own root cause one release after fixing it.

**Second addendum item — `NOOP` vs `ERROR` in `/ssd upgrade --apply`.** Decision 1 specified a
commented `test_command` placeholder when no framework is detected, and the manifest's `detect` probe
deliberately does **not** match a commented key (a commented key does not define the input). Those two
correct decisions combined into a defect in `migrate.sh`: the apply returned success, `detect` then
reported absent, and the engine emitted `ERROR :: apply ran but convention still absent` and **exited 3
— on every project that simply has no test framework yet.** A blameless project state was reported as a
broken upgrade engine.

`migrate.sh` now distinguishes **`NOOP`** ("cannot apply — precondition genuinely absent"; convention
stays outstanding, recorded version does not advance, exit 0) from **`ERROR`** ("apply ran and failed";
exit 3). This is the same distinction this ADR drew for gate rules — *a rule that cannot run must be as
loud as a rule that fails, and must not be mistaken for one that passed* — applied to the migration
engine, which had the inverse bug: a state that could not apply was reported as a failure. Fixed in
v2.8.0 alongside private mode, which is where the defect surfaced.

**Revisit when:** SSD gains a mechanism for gate config that is portable without being committed — e.g.
an `ssd-init`-emitted CI snippet carrying the inputs inline, or a `gate.yml` location outside the
repo. That would close P2 for private projects and this addendum could be retired.

---

## Revisit when

- `gate-rules.sh` gains real `--staged` support for `feature-flag-present` / `adr-delta` — Decision 5's
  first workflow rule becomes obsolete and should be retired via `obsoleted_in`.
- SSD ships as an installable package with a stable discoverable root — Decisions 3 and 6 collapse
  into "ask the package where it is."
- A project needs per-workstream gate configuration — `gate.yml` would need to grow structure, and
  flat key/value would stop being sufficient.

---

## Appendix: provenance of every claim

Reproduced during the adoption described in Context; no claim here is from inspection alone.

| Claim | How it was established |
|---|---|
| Two rules inert by default | `gate-rules.sh --staged` on a real changeset: `SKIP tests-pass :: no test_command`, `SKIP feature-flag-present :: no feature_flag_marker` |
| Adding the keys fixes it | Same command after editing `project.yml`: `PASS tests-pass :: make test exit 0` |
| Config does not travel | `gate-rules.sh --base origin/main` in a clean clone: `SKIP tests-pass :: no test_command in …/gate-proof/.ssd/project.yml` |
| Printed hook command fails | User's first `git commit` blocked, exit 2, `methodology/gate-rules.sh not found at <repo>/methodology/gate-rules.sh` |
| Symlinking cannot fix it | Read `pre-commit-no-leaky-state.sh`: resolves `"$PROJECT_ROOT/methodology/…"`, independent of script location |
| Validators unreachable | `SKIP frontmatter-valid :: validator not found at methodology/frontmatter-validate.py` (same for `skill-version-sync`) |
| Running the validator finds real defects | `FAIL 03-coder-status.md [coder] :: missing required field files_touched; … ×8` |
| `--staged` cannot evaluate two rules | Read `gate-rules.sh:311`, `:340` — `git diff "$BASE...HEAD"` regardless of `MODE`; empty range in staged mode |
| Those rules work on a committed branch | Committed the changeset to a branch in a scratch clone: `PASS adr-delta :: 1 ADR file(s) changed for 530 architectural lines` |
| Validator is CI-viable | Imports are stdlib only; exit 1 on FAIL, 0 on PASS, 0 on absent path (all three exercised) |
| Schemas must travel with the script | `frontmatter-validate.py:53` — `SCHEMAS_DIR = Path(__file__).resolve().parent / "schemas"`; confirmed working after copying both to `tools/ssd/` |
| Vendoring cost | `wc -l`: 378 + 85 across 5 files = 463 lines |
