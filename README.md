# InsanelyGreat's SSD — Claude Code Skills

[![CI](https://github.com/AlexHorovitz/skills/actions/workflows/quality.yml/badge.svg)](https://github.com/AlexHorovitz/skills/actions/workflows/quality.yml)
[![Methodology: InsanelyGreat SSD](https://img.shields.io/badge/Methodology-InsanelyGreat%20SSD-0a84ff?style=flat-square)](https://insanelygreat.com/ssd.html)
[![Manifesto: Agile²](https://img.shields.io/badge/Manifesto-Agile%C2%B2-1d1d1f?style=flat-square)](https://insanelygreat.com/agile2.html)
[![Free for personal use](https://img.shields.io/badge/License-Free%20for%20personal%20use-30d158?style=flat-square)](LICENSE)

**Library version:** see [`VERSION`](VERSION) · changelog in [`CHANGELOG.md`](CHANGELOG.md)

A free-for-personal-use skill set for [Claude Code](https://claude.ai/code) that implements **Shippable States Development (SSD)** — a pragmatic engineering discipline for solo developers and small teams, originated by [Alex Horovitz](https://insanelygreat.com/about.html) and published at [insanelygreat.com](https://insanelygreat.com). Platform-adaptive: web, iOS, Android, macOS, and headless.

**Core invariant:** If you can't ship it right now, you don't have a product — you have a construction site.

**Dogfood.** As of v1.19.0 (per [ADR-0008](docs/decisions/ADR-0008-ssd-commit-split.md)) this repo tracks its own SSD artifacts under [`.ssd/features/`](.ssd/features/) — briefs, architect specs, coder-status reports and code-reviews. Read the history of how the methodology
was built using the methodology itself.

Not uniformly: of the 15 feature directories, **four are missing at least one of those four artifact
classes** — `recorded-defect-fixes` has only a code review, `ssd-2.0-greenlight` and
`ssd-init-gate-readiness` and `ssd-skill-chapter-split` have no architect spec. The record is a record
of what happened, including the steps that were skipped. The epics so far:

- [`ssd-skill-upgrades`](.ssd/features/ssd-skill-upgrades/01-architect.md) — 9-iteration epic implementing v1.5–v1.14 (5 ADRs: iterations, `current.yml` split, rails, profiles, gate execution).
- [`parallel-features`](.ssd/features/parallel-features/01-architect.md) — concurrent feature workstreams (3 iterations, v1.15–v1.17; [ADR-0007](docs/decisions/ADR-0007-parallel-features.md)).
- [`ssd-commit-split`](.ssd/features/ssd-commit-split/01-architect.md) — the selective-commit convention that makes this very list visible (2 iterations, v1.18–v1.19; [ADR-0008](docs/decisions/ADR-0008-ssd-commit-split.md)).
- [`ssd-profile-audit`](.ssd/features/ssd-profile-audit/01-architect.md) — made the sub-skills profile-aware on *substance* not tone (v1.20; [ADR-0010](docs/decisions/ADR-0010-profile-aware-subskills.md)). *Later removed wholesale by SSD 2.0 — see below; the dogfood record keeps the reversal honest.*
- [`ssd-upgrade`](.ssd/features/ssd-upgrade/01-architect.md) — `/ssd upgrade`: detect SSD convention drift and migrate a project forward idempotently (4 iterations, v1.21–v1.24; [ADR-0013](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)).
- [`ssd-skill-chapter-split`](.ssd/features/ssd-skill-chapter-split/00-brief.md) — split the `ssd/SKILL.md` monolith into a thin spine + on-demand chapters (v1.25; the [ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) 2.0 prerequisite P1).
- [`ssd-2.0-cuts`](.ssd/features/ssd-2.0-cuts/01-architect.md) — **SSD 2.0**, the subtractive milestone ([ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md), greenlit via [`ssd-2.0-greenlight`](.ssd/features/ssd-2.0-greenlight/00-brief.md)). Three iterations: (A) remove the `developer_profile`/`teaching_mode` concept library-wide — BREAKING, v2.0.0; (B) collapse to **one surface, progressively disclosed** — v2.1.0; (C) the `/ssd upgrade` deprecation path via the `obsoleted_in` manifest field — v2.2.0.
- [`ssd-private-mode`](.ssd/features/ssd-private-mode/01-architect.md) — `gitignore_mode: private`: run SSD with **no paper trail in git** ([ADR-0017](docs/decisions/ADR-0017-private-mode.md)). Nothing SSD produces is tracked — `.ssd/` plus the `docs/decisions/`, `docs/runbooks/`, `docs/architecture/` trees — while every rail step and gate rule still runs. Iteration A ships the mode (v2.8.0); iteration B adds the `/ssd upgrade` retrofit. Opt-in at `ssd-init --private`; absent ⇒ byte-identical behavior. See [Private mode](#private-mode-optional) below.
- [`ssd-store`](.ssd/features/ssd-store/01-architect.md) — the private artifact store ([ADR-0018](docs/decisions/ADR-0018-ssd-artifact-store.md)): `.ssd` becomes a symlink into a separate private git repo, so the methodology record is version-controlled **outside** the project that keeps it private (v2.10.0). Found and fixed the leak the naive version would have shipped — a symlinked `.ssd` was ignored by neither `.gitignore` nor `no-leaky-state`.
- [`github-issue-tracking`](.ssd/features/github-issue-tracking/01-architect.md) — opt-in, one-way mirror of workstream state to GitHub issues (ADR=epic, workstream=feature issue, `ssd:phase/*` labels; [ADR-0014](docs/decisions/ADR-0014-github-issue-state-tracking.md)). Two iterations: (A) the additive mirror — `ensure-epic`/`ensure-feature`/`set-phase` + auto-sync on phase advance, v2.3.0; (B) the close lifecycle (`close-feature`/`close-epic` behind `auto_close`) + the informational `issue-sync-current` gate rule, v2.4.0. Default-off — zero behavior change until a project opts in. See [GitHub Issue Tracking](#github-issue-tracking-optional) below.
- [`ssd-init-gate-readiness`](.ssd/features/ssd-init-gate-readiness/00-brief.md) — the committed [`.ssd/gate.yml`](.ssd/gate.yml): gate inputs (`test_command`, `feature_flag_marker`) that travel to every clone and CI runner instead of living in a gitignored `project.yml` (v2.5.0; [ADR-0015](docs/decisions/ADR-0015-ssd-init-gate-readiness.md)).
- [`rail-deviations`](.ssd/features/rail-deviations/01-architect.md) — `rail_deviations` is **written** by something and **read** by something ([ADR-0019](docs/decisions/ADR-0019-rail-deviation-records.md), v2.13.0). `rails.md` had promised since v1.15.0 that "every skipped step appears in `rail_deviations:`"; measured on 2026-09-01 there were **zero** such fields across 15 workstreams and no script wrote one. `methodology/deviation.sh` is the writer, the `deviations-recorded` gate rule is the reader, and they shipped together on purpose.
- [`ssd-autonomy`](.ssd/features/ssd-autonomy/01-architect.md) — the **autonomy ladder** ([ADR-0020](docs/decisions/ADR-0020-autonomy-ladder.md), v2.14.0): two opt-in rungs above propose-and-wait, with `methodology/autorun.sh` as an executable referee and a durable record written *before* each phase runs. See [Autonomy ladder](#autonomy-ladder-optional) below.

## Methodology

This repository is the official Claude Code skill implementation of **Shippable States Development**. The canonical methodology pages are:

- 📘 [Shippable States Development (SSD)](https://insanelygreat.com/ssd.html) — the methodology in full
- 📗 [The InsanelyGreat Guide](https://insanelygreat.com/guide.html) — practical implementation
- 📙 [Agile²](https://insanelygreat.com/agile2.html) — companion manifesto on process-as-tool
- 📕 [Solo Developer's Engineering Manifesto](https://insanelygreat.com/solo-developer-manifesto.html)
- 📒 [The Ratchet Principle: Code Quality Without a QA Team](https://insanelygreat.com/ratchet-principle.html)

If this skill set has helped you ship better software, a star on this repo and a link back to [insanelygreat.com](https://insanelygreat.com) keeps the methodology discoverable.

Verify your installed version matches the guide at [insanelygreat.com/guide.html](https://insanelygreat.com/guide.html):

```bash
cat ~/.claude/skills/VERSION
```

---

## What Is SSD?

InsanelyGreat's SSD keeps software in a deployable, production-ready state at all times. It synthesizes continuous deployment, trunk-based development, and feature flags into a workflow a single developer can actually maintain — amplified by Claude Code at every step.

Five principles:
1. **Constant Production Parity** — Deploy "Hello World" on Day 1. Deployment is never "the hard part."
2. **The Shippable State Invariant** — Every session ends with passing tests and nothing broken.
3. **Feature Flags Over Feature Branches** — All work on main, behind flags, off by default.
4. **The Ratchet Principle** — Forward progress only. No WIP commits, no "fix tomorrow."
5. **Scope Flexibility Is a Feature** — Cutting scope is engineering judgment, not failure.

---

## Where to Start

**Step 1: `/ssd-init` once per project.** First-run housekeeping — creates the `.ssd/` working
directory (gitignored), writes `.ssd/project.yml` with your stack/framework/platform, creates
`docs/decisions/` + `docs/runbooks/` + `docs/architecture/`, and runs SSD prerequisite checks
(CI/CD, test harness, feature-flag system, deployed hello-world). Idempotent — safe to re-run.
`/ssd` phases refuse to proceed until init has run.

**Step 2: `/ssd` every session.** Since v2.1, SSD has **one surface, progressively disclosed**
([ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) Pillar 3). The everyday path is the bare
command — it reads your project state and proposes the next action, naming the explicit step it takes
so you never have to memorize the verb set.

```
/ssd-init   ← first time only (prerequisite to all /ssd phases)
/ssd        ← auto-detect state and propose the next action (the path you use)
/ssd start  ← bootstrap a new project (Walking Skeleton) when there's no state to detect yet
```

The full verb set (`start`, `feature`, `design`, `gate`, `milestone`, `verify`, `ship`, `audit`,
`upgrade`, `run`)
stays a first-class escape hatch — every phase is still directly invokable. The command path is a
**thin alias** that lowers into the conversational path, not a co-equal surface. See
[The Meta-Skill](#ssd--the-meta-skill) below for the full set.

### Skill Taxonomy

| Type | Skills | When you invoke directly |
|---|---|---|
| Bootstrap | `ssd-init` | Once, at project start (or when `.ssd/` has drifted) |
| Orchestrator | `/ssd` | Always — start here after init |
| Domain | `architect`, `coder`, `systems-designer`, `refactor` | When working outside the SSD workflow |
| Review | `code-reviewer`, `codebase-skeptic`, `software-standards`, `feynman` | On-demand, or proposed by SSD at the milestone / verify / audit / pre-ship points |
| Reference | `methodology` | When you want to understand SSD doctrine |

---

## Skills

### `/ssd-init` — Project Bootstrap

Run once per project (idempotent; safe to re-run). Creates `.ssd/` (gitignored working directory),
`.ssd/project.yml` (detected stack/framework/platform), `.ssd/current.yml` (active workstreams),
`docs/decisions/` / `docs/runbooks/` / `docs/architecture/` (committed decision records), and reports
SSD prerequisite status (CI/CD, tests, flags, deploy).

Flags: `--keep-blanket-gitignore` (legacy all-gitignored `.ssd/`) · `--private` (track nothing SSD
produces — see [Private mode](#private-mode-optional)).

### `/ssd` — The Meta-Skill

The orchestrator. Sequences the right sub-skills for each development phase. Requires `ssd-init` to
have run. The bare `/ssd` auto-detects state and proposes the next action; the explicit verbs below
are the escape hatch when you want to force a specific phase.

```
/ssd            — Auto-detect state and propose the next action (the everyday path)
/ssd start      — New project or major feature: Walking Skeleton setup
/ssd feature    — Active development: design → build → review → deploy loop
/ssd design     — Bundled architect + systems-designer pass (single invocation)
/ssd milestone  — Post-sprint consolidation: deep audit + targeted refactor
/ssd verify     — Remediation verification (mandatory after milestone refactors)
/ssd gate       — Shippable state check only (code-reviewer + methodology rules)
/ssd ship       — Deploy readiness check only (systems-designer checklist)
/ssd audit      — Adversarial comparative review (nuclear option)
/ssd upgrade    — (v1.21+) report/migrate SSD convention drift (--apply · --adopt)
/ssd run <slug> — (v2.14+) walk the rails to a ceiling of `gate`, opt-in (--until · --dry-run)
```

**Parallel workstreams** (v1.16+, [ADR-0007](docs/decisions/ADR-0007-parallel-features.md)) — manage
more than one feature at once:

```
/ssd feature new <slug>   — scaffold a new workstream: branch + (optional) worktree + brief + state entry
/ssd switch <slug>        — pause the current workstream (capture a handoff note), resume the target
/ssd worktree <slug> …    — explicit git-worktree lifecycle (add | remove) for a workstream
```

### Sub-Skills

| Skill | Role |
|---|---|
| `/ssd-init` | First-run housekeeping: creates `.ssd/` tree, writes `project.yml`, runs prerequisite checks (prerequisite to all `/ssd` phases) |
| `/architect` | Design: models, services, API contracts. Platform-adaptive (web, iOS, Android, macOS, headless) |
| `/systems-designer` | Production readiness: reliability, observability, deployment safety |
| `/coder` | Implementation from spec (Python, TypeScript, Swift, Ruby, Java, C#, PHP, Go, Rust, C/C++, Obj-C) |
| `/code-reviewer` | PR gate: BLOCKER or MAJOR findings send the work back to the coder. **Loud, not a wall** — nothing in this repo physically blocks a merge (see [Hard Rules](#hard-rules)) |
| `/codebase-skeptic` | Deep architectural critique through fifteen expert lenses |
| `/feynman` | Epistemic audit: builds a claim ledger and grades what the project believes about itself against evidence. Proposed at `/ssd milestone` Step 0.5, `verify`, `audit`, and pre-`ship`; gated by the `feynman-clean` rule ([ADR-0016](docs/decisions/ADR-0016-feynman-orchestrator-integration.md)) |
| `/software-standards` | Adversarial comparative audit |
| `/refactor` | Post-ship targeted improvement |
| `/methodology` | SSD methodology reference + `/methodology score` self-adherence metric |

---

## Installation

Clone the repo into your Claude Code skills directory:

```bash
git clone https://github.com/AlexHorovitz/skills ~/.claude/skills
```

Then, from your project root, run the bootstrap once:

```
/ssd-init
```

After that, invoke any SSD phase:

```
/ssd feature
/ssd milestone
/ssd gate
```

Or call a sub-skill directly when working outside the SSD workflow:

```
/coder
/code-reviewer
/codebase-skeptic
/feynman
```

---

## Autonomy ladder (optional)

*v2.14.0+ · [ADR-0020](docs/decisions/ADR-0020-autonomy-ladder.md)*

By default `/ssd` **proposes** the next action and waits. Two opt-in rungs sit above that, for
delegating the mechanical middle of a feature — the coder → reviewer → coder loop until the gate
passes.

| Rung | What bare `/ssd` does | Phases per invocation |
|---|---|---|
| `propose` | proposes; waits | 0 — **the default, and the default is absence** |
| `advance` | executes its own top proposal when it is unambiguous | ≤ 1, unconditionally |
| `run` | offers `/ssd run <slug>`, which walks the rails to a ceiling | ≤ `budget_transitions` |

```yaml
# .ssd/project.yml, under ssd:
  autonomy:
    mode: propose              # propose | advance | run
    max_review_loops: 3        # coder<->reviewer rounds before the run stops
    budget_transitions: 12     # phase transitions per invocation
    budget_wall_minutes: 30    # 0 = uncapped
```

With no `autonomy:` block the orchestrator makes **no additional call at all**, so behavior is
identical to v2.13.0. An unrecognized `mode:` is a refusal that quotes the value, never a silent
default.

**Rule-zero forbids silence, not autonomy.** Under a rung, "surfaced" means **announce → log → act**:
the transition is narrated, written to a durable record on disk, and only then executed — so state
lags reality by at most one announced step even when nobody is watching.

**The ceiling is `gate`, and it is not configurable.** A feature is bounded by two human decisions —
the brief before and the ship after — and no rung reaches ship, deploy, rollout, or flag removal.
`--until ship` exits non-zero. That is not a retreat from "SSD trusts the developer": your door is
untouched, and `/ssd ship <slug>` typed by a human works exactly as before.

[`methodology/autorun.sh`](methodology/autorun.sh) is the referee. The orchestrator still executes
phases; the script decides whether it may, and the mode literal, the ceiling, the rails successor
table, the budgets and record-before-act are all **exit codes** rather than prose. An auto-run writes
zero `rail_deviations` **by construction** — it cannot express an off-rails transition, so it cannot
log one, and it cannot act without logging.

Every run leaves `.ssd/features/<slug>/auto-runs/<ts>-run.md`, committed under `selective` mode,
recording each transition, the executable gate's verdict, and an `outcome` of `green`, `red` or
`incomplete`. Full playbook — stop conditions, refusals, the threat model, and stale-lock recovery —
in [`ssd/chapters/autonomy.md`](ssd/chapters/autonomy.md).

---

## GitHub Issue Tracking (optional)

SSD can mirror workstream state to GitHub issues so teammates, reviewers, and future-you see live
progress without a local checkout ([ADR-0014](docs/decisions/ADR-0014-github-issue-state-tracking.md)).
It is **opt-in and one-way** — local `.ssd/` is always the source of truth; SSD never reads issue
state back to mutate a workstream.

**The convention:**

| | Maps to | Label | Title |
|---|---|---|---|
| An **ADR** | an **epic** issue | `ssd:epic` | `[ADR-NNNN] <decision title>` |
| A **workstream** | a **feature** issue, linked to its epic | `ssd:feature` + one `ssd:phase/<phase>` | `<slug>[#<iter>]: <one-line>` |

On each phase advance the orchestrator ensures the epic + feature issues exist, swaps the
`ssd:phase/*` label, and refreshes a machine-managed body block. On `done` it closes the feature
issue; the epic closes once its last child closes **and** no further iteration is planned.

**Enable it** in `.ssd/project.yml`:

```yaml
integrations:
  - type: github
    enabled: true
    issue_tracking: on     # default off → feature dormant, zero network calls
    auto_close: false      # default false → prompt once before closing; true → close automatically
```

Requires the `gh` CLI, authenticated. With the toggle off or `gh` unavailable, the mirror is a silent
no-op (best-effort — a sync failure never blocks SSD work). The mechanism is
[`methodology/issue-sync.sh`](methodology/issue-sync.sh).

Incompatible with [Private mode](#private-mode-optional) — mirroring workstream state to a public
tracker contradicts it outright, so `issue-sync.sh preflight` refuses (`exit 4`) under
`gitignore_mode: private`.

---

## Private mode (optional)

*v2.8.0+ · [ADR-0017](docs/decisions/ADR-0017-private-mode.md)*

SSD can run with **no paper trail in git**. For client work, a shared repo where SSD is your personal
practice rather than a team standard, an OSS contribution, or simply a project whose working notes are
nobody else's business.

```bash
/ssd-init --private
```

Sets `project.yml.ssd.gitignore_mode: private` and writes
[`methodology/private.gitignore`](methodology/private.gitignore), which tracks **nothing** SSD produces:

| | |
|---|---|
| Gitignored | all of `.ssd/` (including `.ssd/gate.yml`), `docs/decisions/`, `docs/runbooks/`, `docs/architecture/` |
| Also suppressed | `add-` branch prefix (branches become plain `{slug}`), GitHub issue tracking (forced off), the `CLAUDE.md` SSD section |
| **Kept** | the `🛠️ Crafted with SSD` commit/PR footer |

**Every rail step and every gate rule is still invoked, and rigor is not reduced** — `no-leaky-state` in
fact becomes *more* load-bearing here than in any other mode, since it is what enforces the boundary.
Privacy is a *storage and visibility* posture.

Two rules can nonetheless **SKIP** under private mode where they would have run elsewhere: `adr-delta`
when the base commit time is unresolvable or ADR mtimes are unreadable, and `feynman-clean` when no
report is on disk. The gate's own footer defines a skip as *"a check that did not run"*, so "still
runs" would be the wrong word for those two. See [Trade-offs](#trade-offs-stated-plainly).

### What "private" does and does not mean

- **Untracked, not encrypted.** Artifacts sit in plaintext on disk.
- **Not anonymous.** The attribution footer is deliberately kept — anyone reading commit trailers can
  still tell SSD was used. That is intended; privacy here means no SSD *mechanics or documentation* in
  the tree. (A separate `--no-attribution` knob would be its own decision.)
- **Cannot un-publish history.** Switching an existing project stops *future* tracking;
  `git rm --cached` does not rewrite what is already pushed.

### Retrofitting an existing project

*v2.9.0+ — iteration B*

```bash
/ssd upgrade --apply private-mode            # DRY RUN — shows everything, changes nothing
/ssd upgrade --apply private-mode --confirm  # applies
```

The dry-run lists **every** tracked path under `.ssd/` and the three SSD `docs/` trees, separates
files SSD demonstrably produced from files it **cannot confirm** it produced (so a doc your team owns
is never quietly untracked), and states plainly that `git rm --cached` stops *future* tracking but
**does not rewrite published history**. Nothing changes until you re-run with `--confirm`.

`private-mode` is an **elective** migration: a plain `/ssd upgrade` never mentions it, and a plain
`/ssd upgrade --apply` never applies it. It is a choice, not drift — see the
[ADR-0013 addendum](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md). Moving back *out*
of private mode is not automated.

### Keeping the record in a separate private repo

*v2.10.0+ · [ADR-0018](docs/decisions/ADR-0018-ssd-artifact-store.md)*

Private mode makes the SSD record invisible to the project — and also to *any* repo, so there is no
history or backup of it. The **artifact store** closes that: `.ssd` becomes a symlink into one separate
private git repo, so the whole methodology record is version-controlled outside the project.

```bash
/ssd store init /path/to/private-ssd            # prepare the private repo (idempotent)
/ssd store link /path/to/private-ssd            # DRY RUN — lists every file that would move
/ssd store link /path/to/private-ssd --confirm  # acts
```

```
private-ssd/            ← ONE git repo, one subdirectory per project
├── skills/             ← that project's .ssd content, fully committed
└── client-x/

project/.ssd -> private-ssd/<name>              ← never committed
```

Everything works identically: every skill and gate rule reads `.ssd/` unchanged, because the symlink is
resolved by the filesystem and no SSD tool ever `cd`s into `.ssd/`.

With `store_auto_commit: true`, each phase advance commits the store. **Committing is local; `push` is
always explicit** — bookkeeping versus an outward action.

**Requires private or blanket mode.** Git cannot track files through a directory symlink, so a
`selective` project with a linked `.ssd` would commit *nothing* under it. `store.sh link` refuses, and
the `store-link-sane` gate rule FAILs on the combination.

**The store is a second repository you must not lose.** It is not a backup *of* the record — it *is*
the record. Clone the project alone and `.ssd` dangles, which `store-link-sane` reports rather than
letting SSD write into nothing.

### Trade-offs, stated plainly

- **Gate config does not travel.** No committed `.ssd/gate.yml` can exist, so `test_command` and
  `feature_flag_marker` live in gitignored `project.yml` and do not reach a second clone or a CI
  runner. This knowingly reopens [ADR-0015](docs/decisions/ADR-0015-ssd-init-gate-readiness.md)'s root
  cause P2 — whose cost is proportional to your number of collaborators, and private mode's premise is
  that there are none. See the ADR-0015 addendum.
- **`adr-delta` and `feynman-clean` use a weaker probe.** ADRs are untracked, so they cannot appear in
  a diff; both rules fall back to inspecting the working tree and say so in their output. Without that
  fallback `adr-delta` would deadlock against `no-leaky-state` and make the gate unpassable.

`selective` (the default) and `blanket` projects are unaffected — every change sits behind a
`private` branch. The three modes are compared in
[`ssd/chapters/artifacts.md`](ssd/chapters/artifacts.md).

---

## Hard Rules

1. **No merge without a clean `/ssd gate`** — No BLOCKER or MAJOR findings.
2. **No incomplete work on main without a feature flag** — WIP commits on main are banned.
3. **Tests must pass before and after every change** — "I'll fix the tests tomorrow" is not a shippable state.
4. **Refactor only after shipping** — Separate PRs, never mixed with feature work.
5. **Deploy beats perfection** — Reduce scope rather than delay a deploy.
6. **Production parity from day one** — If you haven't deployed to production yet, that is your next task.

**"Hard rule" means loud when broken, not physically prevented.** This list used to end rule 1 with
"No exceptions." It has exceptions, and pretending otherwise misdescribes the system:
[ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) Pillar 5 is explicit that enforcement is
*warnings, not walls* — the gate surfaces violations unmissably and exits non-zero, and **it does not
lock the door**. `main` in this repo carries no branch protection; a developer who merges past a
failing gate simply merges. This repo has done it: PR #43 shipped v2.10.0 with **zero review
artifacts** while all eleven checks were green, which is what produced the `rails-walked` rule.

There is also **no override mechanism**. `/ssd ship --force` was described in four documents for
eleven releases and implemented by nothing; v2.11.0 struck the claim. Overriding a red gate means
merging it on purpose and writing down why — by hand, or with
[`methodology/deviation.sh`](methodology/deviation.sh) since v2.13.0.

---

## Contributing

Contributions are welcome. Most of this repo is Markdown, and for a guidance-only change the intended
bar is whether Claude follows it accurately and produces better outcomes than it would without it.
**Nothing measures that** — there is no eval harness in this repo and no before/after comparison, so
treat it as the author's judgement rather than a test you can run. What you *can* run is below.

**There is executable code, and there is a test suite — run it.** The repo ships seven shell scripts
and one Python validator under [`methodology/`](methodology/), and
[`scripts/parity-test.sh`](scripts/parity-test.sh) is 82 fixtures / 375 assertions that
[CI](.github/workflows/quality.yml) runs on every pull request alongside `shellcheck` and the gate
itself:

```bash
bash scripts/parity-test.sh
shellcheck -S warning methodology/*.sh scripts/*.sh
bash methodology/gate-rules.sh --base main
```

A change to anything under `methodology/` or `scripts/` without a fixture is a change the next release
can silently revert.

### What to contribute

- **Fixes** — Incorrect advice, outdated API references, broken examples, typos
- **Additions** — Missing patterns, platforms, or frameworks that belong in an existing guide
- **New platform guides** — A new `architect/` subdirectory for a platform not yet covered (e.g., `watchOS`, `tvOS`, `embedded`, `visionOS`)
- **New framework guides** — A new `architect/web/frameworks/` file for a web framework not yet covered (e.g., `sveltekit`, `remix`, `nestjs`). Copy `architect/web/frameworks/TEMPLATE.md` and fill in each section to ensure structural parity with existing guides
- **New skills** — A complete `SKILL.md` for a workflow not yet covered

### What not to contribute

- Promotional content, vendor recommendations without technical rationale
- Vague or aspirational guidance ("always write clean code") without actionable specifics
- Anything that contradicts the SSD core invariant (shippable state at all times)

### How to submit

1. Fork the repo
2. Make your changes on a branch
3. Open a pull request with a clear description of what changed and why

### Writing style

These files are read by Claude, not rendered as a website. Write for clarity and precision over prose elegance.

- **Be specific.** "Use PostgreSQL" is better than "use a relational database."
- **Give the rule, then the rationale.** State the decision first, explain why second.
- **Include the counter-case.** Every "always do X" is more useful when paired with "except when Y."
- **Concrete examples over abstractions.** A short code block or table beats three paragraphs.
- **Match the existing tone.** Direct, opinionated, no hedging.

### File structure conventions

Each skill or guide follows this pattern:

```
skill-name/
└── SKILL.md          — the skill itself (invoked by /skill-name in Claude Code)

architect/
└── platform/
    └── GUIDE.md      — platform-specific reference, loaded by the architect skill
```

`SKILL.md` and `GUIDE.md` files begin with a one-line license reference: `<!-- License: See /LICENSE -->`. The full license terms live in the `LICENSE` file at the repository root.

---

## Skill Hygiene Contract

Conventions every skill in this directory aims at. **Nothing enforces them.** This section used to say
violations were "flagged by the skill linter (when present) and block `/ssd start` in strict mode" —
there is no linter in this repo and no strict mode anywhere in it. That sentence was the same shape as
the `/ssd ship --force` claim struck in v2.11.0: a mechanism that existed only in the document
describing it. What *is* enforced is listed under [Enforcement](#hard-rules) and runs in
`methodology/gate-rules.sh`.

So the rules below are split by whether the repo currently meets them, measured rather than asserted.

**Held today (11/11 skills):**
- `SKILL.md` begins with `# Skill Name` as the first line. The license pointer
  (`<!-- License: See /LICENSE -->`) and `**Version:** X.Y.Z` follow the title, not precede it.
- Every `SKILL.md` ends with a `## Changelog` section. Each version bump adds a dated entry describing
  what changed and why. Checked by no script; true by habit.
- Every skill has an `## Interface` table. **Ten of eleven** declare explicit input/output *paths*
  (e.g. `.ssd/features/<slug>/01-architect.md`); `ssd/SKILL.md`, the orchestrator, declares a phase
  argument and "an orchestrated session" instead.
- Output frontmatter is the one rule here with an executable check —
  `frontmatter-valid` against [`methodology/schemas/`](methodology/schemas/). Its reach is partial:
  **eight schemas for eleven skills**, so `codebase-skeptic`, `refactor` and `/ssd verify` primary
  outputs match nothing and the rule SKIPs them. At the last run, 111 artifacts validated and **13
  were unvalidated for want of a schema**. A rule that skips what it has no schema for reports PASS
  on silence, so the count matters more than the verdict.

**Aspirations the repo does not currently meet:**
- *Split any `SKILL.md` over 400 lines* into a spine plus `references/*.md`. **Five of eleven exceed
  it**: `ssd-init` (987), `systems-designer` (677), `code-reviewer` (632), `feynman` (490),
  `software-standards` (429). The `ssd/SKILL.md` chapter-split (v1.25.0) is the pattern the rest have
  not followed.
- *Every skill's Purpose carries a "When NOT to use" clause* disambiguating it from overlapping skills.
  **Two of eleven have one.** Until that changes, the working disambiguation is
  [`ssd/chapters/skills.md`](ssd/chapters/skills.md) § "Resolving Skill Overlap", which is complete.

Listing the gap is the point. A contract nothing checks drifts, and the honest version of an unmet
rule is the count of how far it is from being met.

**Header / license ordering:**
- Title-first: `# Skill Name` is line 1.
- Metadata block follows: license pointer, version.
- Content follows metadata.

**Future work:**
- **Contract tests** (`skills/tests/`): fixtures that assert each skill produces output conforming to
  its declared frontmatter schema and required sections. Tests contract, not quality. Not yet
  implemented — intended layer for preventing silent skill regressions.
- **Cross-skill schema contracts**: shared JSON Schema files that both producer and consumer skills
  reference. E.g., `code-reviewer.output.frontmatter ⊇ {finding_counts, gate_pass}`.

---

## License

© 2026 Alex Horovitz. Shareware license — free for personal and internal organizational use. See [LICENSE](LICENSE) for details.

If SSD saved you a death march or helped your team ship with less stress, consider a small donation:
[venmo.com/alex-horovitz](https://venmo.com/alex-horovitz?txn=pay&amount=20&note=SSD-Claude-Skill%20Donation) · $20 suggested · entirely optional
