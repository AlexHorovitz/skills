---
skill: architect
version: 1.1.1
produced_at: 2026-04-28T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-skill-upgrades (epic — 9 deliverables across 6 skill files)
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0005]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: true
quality_gate_pass: true
---

# Epic Architecture: SSD Skill Upgrades

## Problem Statement

The `/ssd` orchestrator was designed for a one-feature → one-cycle model. Real working sessions in
the `athena` project produced 17 artifacts under a single feature directory because users invented
filename suffixes (`-3b`, `-3c`, `-round-2`) for concepts SSD lacks first-class support for. The
upgrades plan ([source](../../../real-world-artifacts/ssd-upgrades-plan.md)) proposes 7 engine
upgrades plus 2 strategic items (`rails.md`, profile/teaching mode) to push the discovered
complexity from human filename conventions into orchestrator-managed schema.

This epic sequences those 9 deliverables into 9 independently-shippable iterations, each landing on
`main` without breaking the existing skill chain. systems-designer is **not applicable** for this
work — the artifact under change is a markdown skills library consumed by Claude Code, not a
runtime system with deploys, observability, or failure modes.

## Current Scale Baseline

| Dimension | Current (1x) | Target (10x) |
|---|---|---|
| Repos using SSD as their orchestrator | 1 (athena, dogfooding) | 10 |
| Active maintainers | 1 | 3–5 |
| Skills in the chain | 13 | ~13 (additive only — no new sub-skills planned) |
| Active workstreams per repo | 1–2 | 5+ (motivates iterations substrate) |
| Review rounds per feature (observed median in athena) | 2.3 | 1.5 (motivates discipline, not capacity) |

The 10x target is not "more skills." It's **more projects safely concurrent on a single team's SSD
discipline.** The upgrades collectively address the pain points that block reaching 10x: hand-rolled
filenames don't scale to 5+ active workstreams; gate automation that requires manual `git log` doesn't
scale to a team; rails.md doesn't matter to a dogfooding solo user but becomes existential when novices
join.

## Component Diagram (skill chain — what each iteration touches)

```
                       ┌──────────────────────┐
                       │  /ssd (orchestrator) │  ← P1.1, P1.2, P1.3, P1.4, P1.6, P2.A, P2.B
                       │  ssd/SKILL.md        │
                       └──────────┬───────────┘
                                  │ reads/writes
                                  ▼
              ┌───────────────────────────────────────┐
              │   .ssd/  (working tree)               │
              │   project.yml ──────── ← P2.B (profile)│
              │   current.yml ──────── ← P1.7 (split) │
              │   current.notes.yml ── ← P1.7 (new)   │
              │   features/<slug>/                    │
              │     iterations/<id>/  ← P1.1 (new)    │
              │       deferred.yml    ← P1.5 (new)    │
              │       code-review/round-N.md ← P1.2   │
              └───────────────────────────────────────┘
                                  ▲
            ┌─────────────────────┼─────────────────────┐
            │                     │                     │
       ┌────┴───────┐       ┌─────┴──────┐       ┌──────┴────────┐
       │ ssd-init   │       │ architect  │       │ code-reviewer │
       │ ← P1.7,    │       │  ← P1.4    │       │   ← P1.2, P1.5│
       │   P1.1,    │       │            │       │               │
       │   P1.5     │       └────────────┘       └───────────────┘
       └────────────┘             ▲
                                  │ co-invoked
                            ┌─────┴────────────┐
                            │ systems-designer │
                            │   ← P1.4         │
                            └──────────────────┘

    ┌────────────────────────┐
    │ methodology/core.md    │  ← P1.6 (executable gate rules)
    └────────────────────────┘

    ┌────────────────────────┐
    │ ssd/rails.md  (NEW)    │  ← P2.A
    └────────────────────────┘
```

## Data Model (artifact-tree schema additions)

Five additive schema changes, no destructive migrations. Existing `.ssd/` trees continue to parse.

### `.ssd/current.yml` (v2 — machine-managed only) — P1.7

```yaml
# v2: every key here is orchestrator-owned. Free-form notes move to current.notes.yml.
schema_version: 2
active:
  - slug: <feature-slug>
    phase: brief|design|code|review|gate|deploy|done
    iteration: <iter-id>|null      # P1.1 — null for legacy single-cycle
    started: <ISO-8601>
    last_touched: <ISO-8601>
    budget_hours: <number>|null
    elapsed_hours: <number>
    gate_rounds: <int>             # P1.2 — counter, default 0
    rail_deviations: []            # P2.A — list of {step, reason, ts}
    blockers: []
archived: []
```

Back-compat: a v1 `current.yml` (no `schema_version`, mixed notes) is read by detecting absence of
`schema_version` and presented as v1; the orchestrator offers a one-shot migration to v2 (separating
hand-written keys into `current.notes.yml`). No silent rewrite.

### `.ssd/current.notes.yml` (NEW, v1) — P1.7

```yaml
# Free-form. Loaded as context but never schema-validated.
# Anything in here is information for the next session, not state for the orchestrator.
features:
  <feature-slug>:
    handoff_notes: |
      <free-form prose>
    scope_changes: []
    questions_for_next_session: []
```

### `.ssd/features/<slug>/iterations/<iter-id>/` (NEW) — P1.1

```
iterations/
  <iter-id>/                       # e.g., 3a, 3b, phase4-round-2
    brief.md                       # what this iteration adds
    coder-status.md                # outputs unchanged from existing 03-coder-status.md
    code-review/                   # P1.2
      round-1.md
      round-2.md
      ...
    deferred.yml                   # P1.5
    deploy.md
```

Iteration-id syntax: `<slug>#<iter-id>` (e.g., `talentos-reimagined-phase3-ui#3b`). Both forms
resolve via the orchestrator. Iteration-less features remain valid: if no `iterations/` exists,
the feature is single-cycle and uses the existing flat `01-architect.md ... 05-deploy.md` layout.

### `.ssd/features/<slug>/iterations/<iter-id>/deferred.yml` (NEW) — P1.5

```yaml
schema_version: 1
findings:
  - id: <severity>-<n>             # e.g., MINOR-N1
    summary: <one-line>
    source: <relative-path-to-source-review>
    raised_in_iteration: <iter-id>
    target_iteration: <iter-id>|null    # null = unscheduled
    status: open|closed|rolled-forward
    closed_in: <code-review-path>|null  # set when status=closed
```

Auto-load contract: when `coder` enters iteration `X`, the orchestrator concatenates all entries with
`target_iteration: X` and `status: open` into a "Deferred from prior iterations" section in the
coder's input context. When `code-reviewer` runs on iteration `X`, it auto-checks each entry's
`closed_in` field — if a deferred MINOR remains open after its target iteration, the reviewer
upgrades it to a Question in the new round's frontmatter.

### `.ssd/project.yml` (additive) — P2.B

```yaml
developer_profile: novice|standard|expert    # default: standard
teaching_mode:
  enabled: true|false                        # auto-set true for first 5 invocations
  invocations_remaining: <int>               # decay counter
```

Missing `developer_profile` defaults to `standard`. Missing `teaching_mode` block defaults to
disabled (older projects skip narration overhead). No migration required.

## API / Interface Contract (orchestrator command surface)

The plan defines two surfaces over one engine. Per-iteration changes:

| Iteration | Command-surface change | Conversational-surface change |
|---|---|---|
| 1 (P1.6, P1.7) | `/ssd gate` actually executes rules; `/ssd state get|set <path>` for current.yml field access | `/ssd` no-arg unaffected this iteration |
| 2 (P1.1) | `/ssd <phase> <slug>#<iter>` syntax accepted | n/a until iter 6 |
| 3 (P1.2) | `/ssd review` writes to `code-review/round-N.md`; auto-detects round number | n/a |
| 4 (P1.5) | `/ssd defer <finding-id> --to <iter>` direct-edit affordance | Coder phase prepends auto-loaded deferred items |
| 5 (P1.4) | `/ssd design <slug>` invokes architect + systems-designer | n/a |
| 6 (P1.3) | unchanged (escape-hatch commands continue) | `/ssd` no-arg surfaces active workstream + proposes next action |
| 7 (P2.A) | `/ssd rails show` dumps `ssd/rails.md` | Conversational surface walks the rails by default |
| 8 (P2.B) | `--narrate`, `--explain`, `--raw`, `--teach` flags | Profile-aware defaults, teaching narration |
| 9 (parity) | `/ssd test --parity <feature>` runs the harness | n/a |

Each iteration adds commands; none remove or rename existing commands. The existing `/ssd start`,
`/ssd feature`, `/ssd milestone`, `/ssd verify`, `/ssd gate`, `/ssd ship`, `/ssd audit` remain as
escape hatches.

## Decision Log

Five ADRs are required across this epic. Each iteration that lands authors its own ADR(s) in
`docs/decisions/`. Pre-numbered here for predictability:

| ADR | Topic | Owning iteration |
|---|---|---|
| ADR-0001 | Iterations as schema substrate (`<slug>#<iter>` resolution, opt-in subtree) | Iteration 2 (P1.1) |
| ADR-0002 | `current.yml` v2 schema split + `current.notes.yml` sidecar (back-compat detection) | Iteration 1 (P1.7) |
| ADR-0003 | `rails.md` as canonical opinionated path; conversational surface walks it; deviations logged | Iteration 7 (P2.A) |
| ADR-0004 | `developer_profile` semantics: hint not gate; auto-promote signal; teaching-mode decay | Iteration 8 (P2.B) |
| ADR-0005 | Gate automation execution model: bash routine invoked from orchestrator vs. inline checks | Iteration 1 (P1.6) |

ADR template lives at `architect/SKILL.md` § "Architecture Decision Records." Each ADR follows
context → decision → rationale → consequences → alternatives format.

Two of the eight always-ADR topics from `architect/SKILL.md` apply non-trivially here:

- **Schema migration strategy** (ADR-0002): how does athena's v1 `current.yml` reach v2 without
  silent corruption? Decision recorded in iteration 1.
- **Sync vs async boundary** (ADR-0005): is gate automation a synchronous bash subroutine the
  orchestrator awaits, or an asynchronous status the user re-queries? Decision in iteration 1.

The other six always-ADR topics (database, auth, monolith vs services, deployment target,
third-party vs build, licensing) are not applicable — this is a markdown library with no runtime.

## Iteration Sequence (the dependency graph)

```
       ┌─────────────────────────────────────────────────┐
       │  Iteration 1: Foundation                        │
       │  P1.7 (split current.yml) + P1.6 (real gate)   │  ← no deps; ship first
       └────────────────────┬────────────────────────────┘
                            │
                            ▼
       ┌─────────────────────────────────────────────────┐
       │  Iteration 2: Iterations substrate              │
       │  P1.1 (first-class iterations)                  │  ← depends on 1
       └────────────────────┬────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
   ┌─────────────────────┐   ┌─────────────────────┐
   │ Iteration 3: P1.2   │   │ Iteration 4: P1.5   │
   │ Multi-round gates   │   │ Deferred ledger     │   ← parallel-safe
   └──────────┬──────────┘   └──────────┬──────────┘
              │                         │
              └────────────┬────────────┘
                           ▼
       ┌─────────────────────────────────────────────────┐
       │  Iteration 5: P1.4 (bundled design pass)        │  ← could ship anytime; ordered here
       │                                                 │     because schema work settles first
       └────────────────────┬────────────────────────────┘
                            │
                            ▼
       ┌─────────────────────────────────────────────────┐
       │  Iteration 6: P1.3 (no-arg /ssd)                │  ← needs P1.7 + P1.1
       └────────────────────┬────────────────────────────┘
                            │
                            ▼
       ┌─────────────────────────────────────────────────┐
       │  Iteration 7: P2.A (rails.md)                   │  ← needs engine settled
       └────────────────────┬────────────────────────────┘
                            │
                            ▼
       ┌─────────────────────────────────────────────────┐
       │  Iteration 8: P2.B (profile + teaching mode)    │  ← needs rails.md
       └────────────────────┬────────────────────────────┘
                            │
                            ▼
       ┌─────────────────────────────────────────────────┐
       │  Iteration 9: parity test harness               │  ← verification of the whole epic
       └─────────────────────────────────────────────────┘
```

### Per-iteration scope and exit criteria

**Iteration 1 — Foundation (P1.6 + P1.7)**
- Files touched: `ssd/SKILL.md`, `methodology/core.md`, `ssd-init/SKILL.md`
- New artifacts: `methodology/gate-rules.sh` (or equivalent reference implementation),
  `current.notes.yml` template
- Exit: `current.yml` v2 schema documented; `ssd-init` writes both files; `/ssd gate` runs
  executable rules and emits structured pass/fail with cited rule; ADR-0002 + ADR-0005 written;
  athena's v1 `current.yml` parses without error (back-compat verified)
- Why first: zero dependencies on other iterations; both halves are localized; sets schema
  discipline for everything after

**Iteration 2 — Iterations substrate (P1.1)**
- Files touched: `ssd/SKILL.md`, `ssd-init/SKILL.md`
- New artifacts: `iterations/<iter-id>/` directory schema; `<slug>#<iter>` resolver in orchestrator
- Exit: orchestrator accepts iteration syntax; `ssd-init` creates iteration subtrees on demand;
  legacy flat-layout features continue to work; ADR-0001 written
- Risk: schema reach — every downstream iteration reads from this. Test thoroughly.

**Iteration 3 — Multi-round gates (P1.2)**
- Files touched: `code-reviewer/SKILL.md`, `ssd/SKILL.md`
- New artifacts: `code-review/round-N.md` auto-numbering; `closed_from_previous_round:` frontmatter
- Exit: synthetic BLOCKER produces `round-1.md`; fix-and-rereview produces `round-2.md` with
  `closed: [BLOCKER-1]`; `current.yml.gate_rounds` increments

**Iteration 4 — Deferred ledger (P1.5)**
- Files touched: `code-reviewer/SKILL.md`, `coder/SKILL.md`, `ssd-init/SKILL.md`
- New artifacts: `deferred.yml` template + auto-load contract documented in `coder/SKILL.md`
- Exit: defer-and-pickup test passes — minor finding deferred from iter X is auto-loaded as coder
  context in iter X+1; reviewer in iter X+1 auto-checks closure status

**Iteration 5 — Bundled design (P1.4)**
- Files touched: `ssd/SKILL.md`, `architect/SKILL.md`, `systems-designer/SKILL.md`
- New artifacts: `/ssd design <slug>` phase that invokes both back-to-back
- Exit: single invocation produces both `01-architect.md` and `02-systems-designer.md`; individual
  invocations of either skill remain valid

**Iteration 6 — No-arg /ssd (P1.3)**
- Files touched: `ssd/SKILL.md`
- New artifacts: phase auto-detection logic (reads `current.yml`, identifies next action)
- Exit: `/ssd` with no argument surfaces active workstreams, proposes next action without phase
  vocabulary; explicit phase commands remain as escape hatches

**Iteration 7 — rails.md (P2.A)**
- Files touched: `ssd/SKILL.md` (point to rails); new file `ssd/rails.md`
- New artifacts: canonical sequence document; `rail_deviations:` field semantics
- Exit: ADR-0003; `rails.md` enumerates the 8 critic-grade invariants from the plan; `/ssd rails
  show` command works

**Iteration 8 — Profile + teaching mode (P2.B)**
- Files touched: `ssd/SKILL.md`, `ssd-init/SKILL.md`, `project.yml` schema
- New artifacts: `developer_profile` field, teaching-mode decay counter, `--teach` / `--narrate` /
  `--explain` / `--raw` flag semantics
- Exit: ADR-0004; novice walkthrough produces all 8 critic-grade invariants without user seeing
  YAML; teaching-mode decay verified after 5 invocations

**Iteration 9 — Parity test harness**
- Files touched: new harness script (location TBD — likely `scripts/parity-test.sh`)
- New artifacts: synthetic feature run through both surfaces, tree-diff assertion
- Exit: harness runs in CI (or locally — this repo has no CI); diff is empty modulo timestamps; any
  future change to a SKILL.md re-runs this and blocks merge on divergence

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Self-bootstrapping: using single-cycle SSD to ship iteration-aware SSD | H | M | Iterations 1–2 use existing flat layout. Iteration 3+ can use the new substrate (eat dogfood as soon as available). Document this self-reference in iteration 2's ADR. |
| Schema drift across iterations: athena's `current.yml` survives iter 1 but breaks at iter 2 | M | H | Design iter 1 schema (`current.yml` v2) to already accommodate iter 2 fields (`iteration`, `gate_rounds`, `rail_deviations`) as nullable. v2 ships forward-compatible with all later iterations. |
| Skill version churn confusing the chain (every iter bumps multiple skills) | M | L | One CHANGELOG entry per iteration. Minor bump on each touched skill. CHANGELOG cross-references the iteration's ADRs. |
| Iteration-id collisions (two features both want `#3a`) | L | M | Iter-id is scoped to its feature (path is `features/<slug>/iterations/<id>/`). Document explicitly in ADR-0001. |
| `current.yml` v1 → v2 migration corrupts athena's hand-written notes | M | H | Migration is one-shot, prompted, and writes a `.bak` file. No silent rewrites. Detected by absence of `schema_version` field. |
| Rails-vs-deviation logic gets gamed (every step skipped becomes a `rail_deviation`) | L | M | Rails are documentation, not enforcement. Deviation count is a reviewer signal, not a gate. ADR-0003 makes this explicit. |
| Teaching mode is annoying to expert users on first install | L | L | Default `developer_profile: standard` (teaching off). `ssd-init` infers expert from existing repo activity (e.g., presence of `.ssd/archive/` entries) and skips teaching for known-experienced repos. |
| Parity test (iter 9) finds the surfaces have already drifted | M | H | Harness is exit criteria for iter 9, but each prior iteration must demonstrate parity for its own changes — not deferred to the end. |
| The plan's own scope creeps during implementation (someone wants iter 10) | M | M | This architect doc is the contract. New ideas land as their own future feature, not bolted onto this epic. |

**Top 3 risks** (highlighted for systems-designer review — N/A here, but flagged for `code-reviewer`
attention each iteration):
1. Schema drift across iterations (mitigated by forward-compatible v2)
2. `current.yml` v1 → v2 migration (mitigated by prompted one-shot + .bak)
3. Self-bootstrapping (mitigated by living with flat layout for 2 iterations)

## Feature Flag Plan

**Not applicable.** This is a markdown skills library with no runtime; "feature flags" don't exist
as a concept. The equivalent risk-management mechanism is **per-iteration shippable state**:

- Each iteration lands as its own commit/PR.
- Each iteration leaves the chain in a working state for athena (or any other consumer).
- If an iteration breaks downstream consumers, revert that iteration alone — no flag-flip needed.

The `developer_profile` field shipped in iteration 8 is the closest analog to a flag: it gates
default-behavior changes (teaching mode on/off, profile-aware narration) without changing capability.

## Back-Compat Story

Every iteration must satisfy:

1. **athena's existing `.ssd/` tree continues to parse and operate** after the iteration ships.
2. **Existing skill invocations produce existing output formats** unless the iteration explicitly
   adds frontmatter fields (additive only).
3. **No skill is renamed or removed.** Capabilities can be added; the orchestrator accepts new
   syntax; old syntax still works.
4. **`current.yml` migration is opt-in and reversible.** A user on v1 `current.yml` is prompted
   on first iteration-1 invocation; declining keeps them on v1 (orchestrator falls back to legacy
   read path).
5. **No `ssd/SKILL.md` directive contradicts a prior version's behavior** — only adds new
   behaviors.

The contract: an athena dev who pulls these changes between iterations should see no breakage in
their next `/ssd` session, only new capabilities.

## What's NOT in This Epic (explicit)

Per user decision and the plan's own out-of-scope list:

- **Rollout-advance subcommand** (P1 candidate #8 — `/ssd rollout advance` for `0-deployed-flag-off
  → 1-internal → 2-beta → 3-100pct → 4-flag-removed`). User decision: out of scope. Rationale:
  this skills library has no runtime feature flags; the rollout-advance concept belongs in the
  software products that *use* SSD, not in SSD itself.
- **systems-designer involvement.** Skills library has no production deploy; "deploy" means
  `git push origin main` after `code-reviewer` clears.
- **Plan-mode integration** (per plan's out-of-scope).
- **Replacing `codebase-skeptic` / `software-standards`** (per plan's out-of-scope).
- **Distribution / packaging changes** (per plan's out-of-scope).
- **A new `python-django-coder`-style sub-skill.** All upgrades are edits to existing skills.

## Walking Skeleton Check

Per `architect/SKILL.md` Quality Gate: "Walking Skeleton deployable today." For this skills repo,
"deployable today" means: at the end of any iteration, a user installing the repo into
`~/.claude/skills/` gets a working chain. That criterion holds throughout — every iteration is
designed to ship cleanly.

## Self-Verification

Before handoff to the coder for iteration 1:

1. ✅ Every Quality Gate item has a concrete section above with real content (not stubs).
2. ✅ Guidance adapted to actual stack: this is a markdown skills library; "data model" became
   artifact-tree schema, "API contract" became orchestrator command surface, several gate items
   marked `not_applicable` with stated reason.
3. ✅ Read the relevant guide: `architect/SKILL.md` and `architect/headless/GUIDE.md` (skills are a
   headless artifact). No web/iOS/macOS guide applies.
4. ✅ ADR-0001 through ADR-0005 enumerated with owning iterations; actual ADR files written by each
   iteration when it lands (not pre-written).
5. ✅ Current Scale Baseline declared with real numbers (1x = 1 dogfooding repo / 1 maintainer; 10x
   = 10 repos / 3–5 maintainers).

## Recommended Next Action

**Hand off iteration 1 to `coder`.** Iteration 1 scope:

- Implement P1.6 (executable gate automation) and P1.7 (current.yml v2 split) as a single iteration.
- Author ADR-0002 and ADR-0005.
- Touch `ssd/SKILL.md`, `methodology/core.md`, `ssd-init/SKILL.md`.
- Verify athena's v1 `current.yml` parses post-change.
- Update each touched skill's version + per-skill changelog entry.
- Update repo `CHANGELOG.md` and `VERSION` (next minor: 1.5.0).

Bundled-design pass (P1.4 / iteration 5) would normally invoke `systems-designer` after this
architect doc — for this repo, skip it. Proceed directly to `coder`.
