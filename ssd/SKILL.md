# SSD Meta-Skill

<!-- License: See /LICENSE -->

**Version:** 2.4.0

> **On skill-version vs. library-version (banner-lag pattern).** A skill's `**Version:**` banner
> tracks the **library** version *at the point this skill last changed*. When a release touches
> other skills but not this one, this banner intentionally diverges from the library `VERSION` and
> re-aligns on the next change to *this* file. So a banner lagging the library version is expected,
> not a bug — it records when the skill itself last moved. (Refactor R7, post-v1.19 milestone.)

**Canonical methodology**: [Shippable States Development at insanelygreat.com/ssd.html](https://insanelygreat.com/ssd.html). For doctrine questions, the in-repo source of truth is `methodology/core.md`; for end-user-facing language and external citations, the website is authoritative.

## Purpose
Orchestrate the full skill chain for Shippable States Development (SSD), the engineering discipline originated by [Alex Horovitz](https://insanelygreat.com/about.html). Every work session ends in a deployable, production-ready state. If you can't ship it right now, you don't have a product — you have a construction site.

## When to Use
Invoke this skill when starting a session and you want to follow the SSD workflow. It selects and sequences sub-skills based on the phase argument you provide.

## Prerequisite: `ssd-init`

Before any `/ssd` phase can run, the project must be initialized. On invocation, `/ssd` checks for
`.ssd/project.yml` at the project root:

- **Missing:** refuse to proceed and tell the user to run `/ssd-init` first. Do NOT auto-run init —
  the user decides when to commit to the SSD convention.
- **Present:** read it for stack / framework / platform metadata and proceed with the requested phase.

`ssd-init` creates the `.ssd/` working directory (gitignored), populates `project.yml` + `current.yml`,
creates `docs/decisions/`, `docs/runbooks/`, `docs/architecture/`, and runs SSD prerequisite checks
(CI/CD, test harness, flag system, deployed hello-world). It is idempotent — safe to re-run.

## Interface

| | |
|---|---|
| **Input** | Phase argument (`start`, `feature`, `milestone`, `audit`, `gate`, `ship`) + project context |
| **Output** | Orchestrated session: invokes the appropriate sub-skills in sequence and enforces the shippable state invariant |
| **Consumed by** | None — top-level orchestrator |
| **SSD Phase** | All phases |

---

## Invocation

SSD has **one surface, progressively disclosed.** The everyday path is the bare command — it reads
your project state and proposes the next action, naming the explicit step it's taking so you never
have to memorize the verb set:

```
/ssd               — auto-detect state and propose the next action (the path you use)
/ssd start         — bootstrap a new project (Walking Skeleton) when there's no state to detect yet
```

That is all most sessions need; `/ssd` walks the canonical rails for you (see
§ "/ssd (no-arg) — Auto-Detect" below for exactly what it proposes).

The **full verb set** stays a first-class escape hatch — every phase, audit, and lifecycle command
is still directly invokable, just documented in the chapters rather than taught first:

| To… | Verb(s) | Chapter |
|---|---|---|
| force a specific phase | `start` · `feature` · `design` · `milestone` · `verify` · `audit` · `gate` · `ship` | [`chapters/phases.md`](chapters/phases.md) |
| migrate a project to the latest SSD conventions | `upgrade` | [`chapters/upgrade.md`](chapters/upgrade.md) |
| run parallel workstreams | `feature new` · `switch` · `worktree` | [`chapters/workstreams.md`](chapters/workstreams.md) |

The command path is a **thin alias** that lowers into the conversational path — a power-user
shorthand, **not** a co-equal surface with its own state. Everything a command does, `/ssd` can
propose; nothing is reachable only by command ([ADR-0012](../docs/decisions/ADR-0012-ssd-2.0-architecture.md)
Pillar 3).

---

## Phase Playbooks

### `/ssd` (no-arg) — Auto-Detect

The default invocation. The orchestrator reads `.ssd/current.yml` and `.ssd/current.notes.yml`,
surfaces active workstreams, and proposes the next action without forcing the user to know which
phase command to type.

**Step 0: Branch → workstream resolution (added v1.15.0, see [ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)).**
Before walking the decision tree below, the orchestrator attempts to resolve the current git
branch to a specific active workstream:

1. Read the current branch via `git symbolic-ref --short HEAD`. If detached or git is unavailable,
   skip Step 0 and fall through to the decision tree.
2. **Exact match.** If any `current.yml.active[].branch` equals the current branch, that workstream
   is the resolved target. Treat the session as "one active workstream" for the rest of the no-arg
   flow regardless of how many other workstreams are also active. By construction, no two `active[]`
   entries should share a `branch:` value — iteration B's `/ssd feature new` enforces this on
   creation. If the orchestrator encounters duplicate branches (a state corruption from manual
   YAML editing), it emits an error and refuses to guess rather than picking a first match.
3. **Pattern match.** Otherwise, strip the `branch_pattern` prefix (from
   `.ssd/project.yml.ssd.branch_pattern`, default `add-{slug}`) and look up the remainder against
   `active[].slug`. If found, resolve to that workstream and lazily backfill its `branch:` field
   on the next state write.
4. **No match.** Fall through to the decision tree below — auto-detect cannot determine which
   workstream is in scope from the branch alone, so the user gets the standard multi-workstream
   prompt (case 3 below).

Step 0 is **read-only and never silently advances a phase**. It only changes which workstream the
existing decision tree operates on; the proposal itself still has to be accepted. To **start** a
new workstream, **switch** between workstreams, or manage **worktrees**, see § "Workstream
Lifecycle Commands" (v1.16.0+) — those commands write `branch:` and `worktree:` directly.

**Decision tree:**

1. **No active workstreams** in `current.yml.active`:
   - Empty repo or fresh start → propose `/ssd start` (Walking Skeleton).
   - Existing repo, no active features → ask: "start a new feature, or audit (`/ssd milestone`,
     `/ssd audit`)?"

2. **One active workstream**:
   - Surface its slug, current iteration (if any), phase, and time-since-last-touched.
   - Read its `phase` field and the latest artifact under `.ssd/features/<slug>/` (or
     `iterations/<iter>/`). Propose the next action:
     - `phase: brief` → propose `/ssd design <slug>[#<iter>]`.
     - `phase: design` → propose `/ssd code <slug>[#<iter>]`.
     - `phase: code` → propose `/ssd review <slug>[#<iter>]` (i.e., `/ssd gate`).
     - `phase: review` with last review's `gate_pass: false` → propose `/ssd code <slug>[#<iter>]`
       again (return to coder, with closed-finding count).
     - `phase: review` with `gate_pass: true` → propose `/ssd ship <slug>[#<iter>]`.
     - `phase: gate` (post-pass) → propose deploy.
     - `phase: done` → ask if the workstream should archive.
   - Render `current.notes.yml.features.<slug>.handoff_notes` as starting context.

3. **Multiple active workstreams**: list each with phase/last-touched/blockers, ask which to
   resume or whether to start new. Flag any with `elapsed_hours > budget_hours` ("over budget —
   suggest scope cut, not more work") or `last_touched > 3 days ago` ("stale — fresh audit before
   continuing?").

**Never silently advances a phase.** The orchestrator proposes; the user accepts or redirects.
The proposal text always names the explicit command being proposed so a power user can copy it.

**Falls back to "ask"** for ambiguous states. If `current.yml` exists but is malformed, surface
the parse error and refuse to guess.

---

### Explicit phase commands

The eight phase playbooks — `/ssd start`, `/ssd feature`, `/ssd design`, `/ssd milestone`,
`/ssd verify`, `/ssd audit`, `/ssd gate`, `/ssd ship` — are detailed in
**[`chapters/phases.md`](chapters/phases.md)**. The no-arg Auto-Detect above proposes the right one;
load that chapter when running or forcing a specific phase.

### `/ssd upgrade` — Keep the Project on the Latest SSD Approach

**→ Full text: [`chapters/upgrade.md`](chapters/upgrade.md)** (v1.21.0+, [ADR-0013](../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)).
Detect/`--apply`/`--adopt` SSD convention drift; migrate a project forward idempotently.

---

## Workstream Lifecycle Commands

**→ Full text: [`chapters/workstreams.md`](chapters/workstreams.md)** (v1.16.0+, [ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)).
`/ssd feature new`, `/ssd switch`, `/ssd worktree` — parallel-workstream lifecycle (branch + optional
worktree + handoff note + `current.yml` entry), with numbered failure modes. Escape-hatch commands; a
user happy with single-feature flow never needs them.

---

## The Rails — Canonical Opinionated Path

The eight-step canonical sequence (brief → design → code → review → gate → deploy →
rollout-advance → flag-removal) lives in `ssd/rails.md`. That file is the single source of truth
for what the orchestrator's no-arg auto-detect proposes, what `code-reviewer` and
`codebase-skeptic` audit against, and what the eight critic-grade invariants are.

A workstream that skips a step (or runs them out of order) records the deviation in
`current.yml.active[].rail_deviations`. Deviations are not failures — they are engineering
judgment captured for the record. The orchestrator does not block based on deviation count.

A team with genuinely different needs forks `rails.md` (e.g., `rails-mobile.md`) and points
`project.yml.rails:` at the fork. The default is `rails.md` if no override.

See [ADR-0003](../docs/decisions/ADR-0003-rails-as-canonical-path.md) for the rationale on why
the rails are a first-class artifact rather than folklore scattered across files.

---

## Hard Rules (Invariants)

These are not suggestions. Violating them breaks SSD.

The canonical hard rules are defined in `methodology/core.md` (§ "Core Principles" and § "The Engineering Mindset"). Load that file for the full doctrine. Summary for quick reference:

1. **No merge without a clean `/ssd gate`** — no BLOCKER or MAJOR findings
2. **No incomplete work on main without a feature flag** — WIP commits are banned
3. **Tests must pass before and after every change**
4. **Refactor only after shipping** — separate PRs, never mixed with feature work
5. **Deploy beats perfection** — reduce scope rather than delay a deploy
6. **Production parity from day one** — deploy to your distribution channel before anything else

**Enforcement is warnings, not walls** (see [ADR-0012](../docs/decisions/ADR-0012-ssd-2.0-architecture.md)
Pillar 5). "Hard rule" means *strongly discouraged and loud when broken* — the gate surfaces
violations unmissably and an override (`/ssd ship --force`) is logged — and, per
[ADR-0012](../docs/decisions/ADR-0012-ssd-2.0-architecture.md) Pillar 5, is *intended* to leave a
durable `rail_deviations` trace (that wiring is tracked 2.0 work, not yet shipped) — **not** that
the system physically blocks the merge. SSD trusts the developer and
keeps a record; it does not lock the door. The one genuinely silent failure SSD forbids is the
orchestrator advancing a phase *without surfacing the decision* — that's rule-zero, and it is the
only thing here that is truly inviolable.

---

## The SSD Artifact Tree

**→ Full text: [`chapters/artifacts.md`](chapters/artifacts.md).** The well-known `.ssd/` + `docs/`
paths every invocation reads/writes, the v1.18.0+ selective-commit split table, and the worktree note.

---

## Structured Output Requirements

**→ Full text: [`chapters/state.md`](chapters/state.md).** Required YAML frontmatter on every sub-skill
output (machine-readable metadata the gate reads instead of parsing prose).

---

## Iterations Inside a Feature

**→ Full text: [`chapters/state.md`](chapters/state.md)** ([ADR-0001](../docs/decisions/ADR-0001-iterations-as-schema-substrate.md)).
The `<slug>#<iter-id>` syntax, resolution rules, nested vs flat layout, iter-id collisions.

---

## Session Continuity

**→ Full text: [`chapters/state.md`](chapters/state.md)** ([ADR-0002](../docs/decisions/ADR-0002-current-yml-split.md)).
Covers § "current.yml v2 schema", § "current.notes.yml (free-form)", v1 detection, orchestrator
behavior on active entries, and § "Concurrency: one Claude session per project at a time".

---

## Methodology Enforcement (runs on /ssd gate)

**→ Full text: [`chapters/enforcement.md`](chapters/enforcement.md)** ([ADR-0005](../docs/decisions/ADR-0005-gate-execution-model.md)).
The executable `gate-rules.sh` rule table (`wip-commits`, `tests-pass`, `feature-flag-present`,
`adr-delta`, `frontmatter-valid`, `no-leaky-state`, `skill-version-sync`, `migration-manifest-current`),
the cross-workstream overlap check, and workstream-aware base detection.

---

## Sub-Skill Reference

**→ Full text: [`chapters/skills.md`](chapters/skills.md).** The sub-skill role/phase table.

---

## Review Tier Selection

**→ Full text: [`chapters/skills.md`](chapters/skills.md).** `code-reviewer` vs `codebase-skeptic` vs
`software-standards` — never chain all three.

---

## Resolving Skill Overlap

**→ Full text: [`chapters/skills.md`](chapters/skills.md).** The 8 known overlap pairs (substitution +
coordination) and the priority/coordination rule for each.

---

## Chapters (load on demand)

This spine carries the always-needed front matter: Purpose, Prerequisite, Invocation, the no-arg
Auto-Detect behavior (the progressive-disclosure core), The Rails, and the Hard Rules. Everything else
lives in `ssd/chapters/` and loads when the relevant work begins:

| Chapter | Contents |
|---|---|
| [`chapters/phases.md`](chapters/phases.md) | the eight phase playbooks (start → ship) |
| [`chapters/upgrade.md`](chapters/upgrade.md) | `/ssd upgrade` (drift report · `--apply` · `--adopt`) |
| [`chapters/workstreams.md`](chapters/workstreams.md) | `/ssd feature new` · `switch` · `worktree` |
| [`chapters/artifacts.md`](chapters/artifacts.md) | the `.ssd/` artifact tree + selective-commit split |
| [`chapters/state.md`](chapters/state.md) | structured output + iterations + session continuity |
| [`chapters/enforcement.md`](chapters/enforcement.md) | `gate-rules.sh` enforcement table |
| [`chapters/skills.md`](chapters/skills.md) | sub-skill reference + review tiers + overlap |
| [`rails.md`](rails.md) | the eight-step canonical path + critic-grade invariants |

The chapter-split (v1.25.0) is the [ADR-0012](../docs/decisions/ADR-0012-ssd-2.0-architecture.md) P1
prerequisite, done as a behavior-preserving 1.x refactor (path A) ahead of the contested 2.0 cuts.

---

## Changelog

The full per-version changelog lives in the repository **[`CHANGELOG.md`](../CHANGELOG.md)** (moved out
of this file in v1.25.0 — it was duplicative and added ~180 lines to the spine). The `**Version:**`
banner at the top of this file tracks the library version at this skill's last change (banner-lag note).
