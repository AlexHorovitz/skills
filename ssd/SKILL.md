# SSD Meta-Skill

<!-- License: See /LICENSE -->

**Version:** 1.3.0

## Purpose
Orchestrate the full skill chain for Shippable States Development. Every work session ends in a deployable, production-ready state. If you can't ship it right now, you don't have a product — you have a construction site.

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

```
/ssd start      — New project or major feature: Walking Skeleton setup
/ssd feature    — Active development: design → build → review → deploy loop
/ssd milestone  — Post-sprint consolidation: deep audit + targeted refactor
/ssd verify     — Remediation verification after a milestone refactor (mandatory)
/ssd audit      — Adversarial comparative review (nuclear option)
/ssd gate       — Shippable state check only (code-reviewer + methodology rules)
/ssd ship       — Deploy readiness check only (systems-designer checklist)
```

If no argument is given, ask the user which phase they are in.

---

## Phase Playbooks

### `/ssd start` — Walking Skeleton

For new projects or major features requiring end-to-end scaffolding.

**Step 1: Foundation**
Invoke `architect` to design:
- Project structure and app boundaries
- Core data models
- CI/CD pipeline design
- Feature flag system

Then invoke `systems-designer` to produce:
- Day-1 deployment checklist
- Monitoring and observability plan
- Initial failure mode analysis

**Exit gate**: Deploy "Hello World" to the project's distribution channel (production URL, TestFlight, Play Internal Testing, notarized build, or container registry). If deployment takes more than one working day, stop and fix the deployment pipeline first.

**Step 2: First End-to-End Slice**
Invoke `architect` to design the thinnest single user flow (e.g., "user can log in"). Then follow the Feature Loop below for that slice.

**Step 3: Expand**
Every subsequent feature uses `/ssd feature`.

---

### `/ssd feature` — Feature Loop

The standard daily development cycle. Repeat per feature.

1. **Design** — invoke `architect`
   - Data model changes
   - Service layer design
   - API contract
   - Produces a spec for the coder

2. **Production check** — invoke `systems-designer`
   - Identify failure modes for this feature
   - Confirm observability hooks are planned
   - Verify deployment safety (migration strategy, feature flag plan)
   - Produces: production readiness checklist specific to this feature

3. **Build** — invoke `coder` (auto-detects language; loads language-specific reference)
   - Implement from the architect spec
   - All new code goes behind a feature flag unless it's infrastructure
   - Mark uncertainties with `# REVIEW:` comments

4. **Review gate** — invoke `code-reviewer`
   - BLOCKER or MAJOR findings → return to Build, do not proceed
   - Clean review → proceed to deploy

5. **Deploy**
   - CI/CD to staging, then production
   - Feature flag: off (internal only) until verified
   - Monitor for 30 minutes post-deploy

6. **Enable flag**
   - Internal users → beta → 100%
   - Remove flag and dead code once 100% stable

**Shippable state invariant**: At the end of each work session, verify the invariant defined in `methodology/core.md` § "The Shippable State Invariant." The canonical checklist lives there — do not maintain a separate copy here.

---

### `/ssd milestone` — Milestone Audit

Run every 4–8 weeks or after 10+ features land. Always runs *after* shipping, never instead of it.

**Step 0: Snapshot.** Before any analysis:
- Record git SHA → `.ssd/milestones/<milestone>/sha-before`
- Save current coverage / metrics → `.ssd/milestones/<milestone>/metrics-before.yml`

1. **Deep audit** — invoke `codebase-skeptic`
   - Full architectural critique across ten expert voices
   - Output: `.ssd/milestones/<milestone>/skeptic-before.md` (with frontmatter per O2)

2. **Refactor planning** — invoke `refactor`
   - Input: `skeptic-before.md`
   - Each refactor item cites a specific finding ID from skeptic-before.md. No cite → not in scope.
   - Output: `.ssd/milestones/<milestone>/refactor-plan.md`
   - Start with high complexity + high churn areas
   - Write tests first if coverage is insufficient
   - Small, independently deployable commits only
   - Each refactor is a separate PR from feature work

3. **Validate** — invoke `code-reviewer` on each refactoring PR
   - `remediation_mode: true` in frontmatter
   - Same gate as feature work: no BLOCKER/MAJOR
   - Record PR list → `.ssd/milestones/<milestone>/refactor-prs.md`

4. **Deploy** and confirm production health post-refactor

5. **Verify (mandatory)** — invoke `/ssd verify` (see below). The milestone is complete only when
   verification passes.

**Constraint**: Scope cuts and refactors are not failure — they are engineering judgment. Reducing scope to maintain shippable state is correct behavior.

---

### `/ssd verify` — Remediation Verification

Mandatory after milestone refactors. Before the next feature cycle begins, run verification:

1. **Re-invoke `codebase-skeptic`** with scope = same as `skeptic-before.md`. Its output goes to
   `.ssd/milestones/<milestone>/skeptic-after.md` (with frontmatter).

2. **Diff the frontmatter** against `skeptic-before.md`. For each original finding, mark its status:
   - ✅ closed / 🔄 partial / ❌ unaddressed / 🆕 new-regression
   New findings that weren't in the "before" run are surfaced separately.

3. **Re-invoke `code-reviewer`** on the refactor diff with explicit `remediation_mode: true` (triggers
   Phase 1.5 + Phase 3.5).

4. **Verification passes if:**
   - All original BLOCKER / 🔴 / 💀 findings are ✅ closed
   - No 🆕 new-regression is BLOCKER severity
   - Code review on the remediation diff has no BLOCKERs

   Output: `.ssd/milestones/<milestone>/verification.md`.

If verification fails, the milestone is NOT complete. Return to refactor.

Verification is not optional. A refactor that claims to close findings without verification is
indistinguishable from wishful thinking.

---

### `/ssd audit` — Nuclear Audit

For adversarial evaluation: comparing approaches, legacy onboarding, vendor selection, or when you need an uncomfortable honest assessment.

Invoke `software-standards`.

Output: comparative scored report with Hard Truth section.
Use findings to inform architect redesign or refactor priorities.

Do not invoke this routinely. It is for adversarial contexts, not everyday review.

---

### `/ssd gate` — Shippable State Check

Invoke `code-reviewer` on the current code or PR.

Pass criteria: no BLOCKER or MAJOR findings.
Fail: return to coder before proceeding.

---

### `/ssd ship` — Deploy Readiness Check

Invoke `systems-designer` deploy checklist for the feature about to ship.

Invoke `systems-designer` to produce the platform-appropriate deploy checklist. The checklist is defined and maintained by that skill — do not duplicate it here. The systems-designer skill covers web, mobile (iOS/Android), and macOS desktop deployment readiness.

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

---

## The SSD Artifact Tree

Every SSD invocation produces artifacts at well-known paths relative to the project root. Sub-skills
read from and write to this tree. This is the mechanism that lets a session resume, a reviewer verify,
and a team member onboard.

```
<project-root>/
├── docs/
│   ├── decisions/                       # ADRs from architect (committed)
│   │   ├── ADR-0001-database-choice.md
│   │   └── ...
│   ├── runbooks/                        # Runbooks from systems-designer (committed)
│   │   └── <feature>.md
│   └── architecture/                    # Component diagrams, data models (committed)
│       └── <feature>.md
└── .ssd/                                 # SSD orchestrator state — gitignored by default
    ├── project.yml                      # Project shape: language, framework, platform
    ├── current.yml                      # Active features / milestones pointer
    ├── features/
    │   └── <feature-slug>/
    │       ├── 00-brief.md              # User's original brief
    │       ├── 01-architect.md          # architect spec (5 standard deliverables)
    │       ├── 02-systems-designer.md   # production readiness checklist
    │       ├── 03-coder-status.md       # files touched, tests added, REVIEW markers, test output
    │       ├── 04-code-review.md        # code-reviewer output with frontmatter
    │       └── 05-deploy.md             # deployment log: when, flags, verification
    ├── milestones/
    │   └── YYYY-MM-DD-<topic>/
    │       ├── sha-before               # git SHA at milestone start
    │       ├── metrics-before.yml       # coverage, perf, etc.
    │       ├── skeptic-before.md        # codebase-skeptic output pre-refactor
    │       ├── refactor-plan.md         # refactor skill output
    │       ├── refactor-prs.md          # list of PRs + per-PR code-reviewer outputs
    │       ├── skeptic-after.md         # codebase-skeptic output post-refactor
    │       └── verification.md          # /ssd verify summary
    └── archive/                         # closed feature and milestone directories
```

This is the **prescribed** layout. Teams may extend it but may not rename these files — sub-skills load
them by name. If the project already has `docs/decisions/`, `.ssd/` sits alongside it.

The `.ssd/` directory (and its `.gitignore` entry) is created by the `ssd-init` skill, which runs once
at the start of any SSD-managed project. `ssd-init` is a prerequisite for any `/ssd` phase; the
orchestrator checks for `.ssd/project.yml` on invocation and prompts the user to run `ssd-init` if
absent.

---

## Structured Output Requirements

Every SSD sub-skill's primary output file MUST open with a YAML frontmatter block containing
machine-readable metadata. Free-form prose follows the frontmatter.

**Required fields (all skills):**
```yaml
---
skill: <skill-name>            # e.g., "code-reviewer"
version: <skill-version>       # semver
produced_at: <ISO-8601>
produced_by: <agent-name>      # claude-sonnet-4-6, claude-opus-4-7, human, etc.
project: <project-name>
scope: <branch|feature|commit-range|files>
consumed_by: [<skill>, ...]    # which skills will read this
---
```

**Review-specific fields (`code-reviewer`, `codebase-skeptic`):**
```yaml
finding_counts:
  blocker: 0
  major: 2
  minor: 5
  question: 2
  suggestion: 3
  nit: 1
gate_pass: true                # computed: blocker=0 AND major=0
```

**Design-specific fields (`architect`, `systems-designer`):**
```yaml
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  adrs: [ADR-0005, ADR-0006]
  risk_assessment: true
  readiness_checklist: complete|partial|not_applicable
```

Rationale: `/ssd gate` should not have to parse prose Markdown to answer "are there BLOCKER findings."
A single field in frontmatter makes the gate reliable. Same for milestone verification — compare two
skeptic runs' frontmatter to see which findings closed.

---

## Session Continuity

On invocation, `/ssd` reads `.ssd/current.yml` to determine state:

```yaml
# .ssd/current.yml
active:
  - slug: goal-approval-flow
    phase: coder       # current sub-skill
    started: 2026-04-18T10:00:00Z
    last_touched: 2026-04-18T14:30:00Z
    budget_hours: 8
    elapsed_hours: 4.5
    blockers: []
  - slug: billing-migration
    phase: code-reviewer
    started: 2026-04-17T09:00:00Z
    last_touched: 2026-04-17T17:00:00Z
    budget_hours: 16
    elapsed_hours: 14
    blockers: ["code-reviewer found 2 BLOCKERs, returned to coder"]
```

If `.ssd/current.yml` has active entries, the orchestrator:

1. Surfaces them to the user: "You have 2 active workstreams. Resume one, or start new?"
2. Flags any entry where `elapsed_hours > budget_hours`: "billing-migration is over budget — suggest
   scope reduction, not more work."
3. Flags any entry with `last_touched > 3 days ago`: stale work that may need a fresh audit before
   continuing.

Closing a workstream (after successful deploy + verify) removes it from `current.yml` and archives
artifacts under `.ssd/archive/features/<slug>/`.

---

## Methodology Enforcement (runs on /ssd gate)

Before `/ssd gate` passes, verify these doctrine rules mechanically. Each maps to a principle in
`methodology/core.md`.

| Rule | Check | Source |
|---|---|---|
| Tests pass | `<test-command>` exits 0 | core.md §1 |
| No broken features | Covered by tests | core.md §2 |
| Documentation matches implementation | ADRs updated if architecture changed | core.md §2 |
| No WIP commits on main | `git log main --grep="WIP\|checkpoint\|TODO.*tomorrow" -i` is empty | core.md §4 |
| Feature behind flag | If not infra: check `feature_flags` config delta or code-reviewer output | core.md §3 |
| Deployable | CI passes; migration is reversible (from systems-designer check) | core.md §2 |

If any rule fails, `/ssd gate` emits the failure with the doctrine cite and refuses to pass.
"I know better" is not an override — use `/ssd ship --force` (logged) if the team has a deliberate
exception.

---

## Sub-Skill Reference

| Sub-Skill | Role in SSD | Phase |
|---|---|---|
| `ssd-init` | First-run housekeeping: `.ssd/` tree, gitignore, `project.yml`, prerequisite checks | **prerequisite to all phases** |
| `architect` | Design: models, services, API boundaries | start, feature |
| `systems-designer` | Production readiness: reliability, observability, deployment safety | start, feature, ship |
| `coder` | Implementation from spec (language-adaptive) | feature |
| `code-reviewer` | PR gate: BLOCKER/MAJOR findings block merge | feature, milestone, gate |
| `codebase-skeptic` | Deep architectural critique (10 expert voices) | milestone |
| `software-standards` | Adversarial comparative audit | audit |
| `refactor` | Post-ship targeted improvement | milestone |
| `methodology` | SSD doctrine reference + `/methodology score` self-adherence metric | reference / any phase |

`proposal-reviewer` and `software-capitalization` are standalone domain tools and do not participate in the SSD workflow.

---

## Review Tier Selection

Three skills do "review" work. Never chain all three — pick the right tier:

- **`code-reviewer`** — every PR, always, no exceptions
- **`codebase-skeptic`** — milestone reviews and pre-release audits
- **`software-standards`** — comparative/adversarial evaluation only

---

## Resolving Skill Overlap

When two skills could both handle the same request, the orchestrator picks the more specific one —
unless the skill's "When NOT to use" clause disqualifies it. Current known overlaps:

| Generic skill | Specific skill | Priority rule |
|---|---|---|
| `coder` | `python-django-coder` (when present) | If language = Python AND framework = Django, use `python-django-coder`. Otherwise use `coder`. |
| `code-reviewer` | `codebase-skeptic` | `code-reviewer` for PR-level review (≤500 changed lines). `codebase-skeptic` for milestone/architectural review. Never chain both on the same scope. |
| `codebase-skeptic` | `software-standards` | `codebase-skeptic` for continuous stewardship of an owned codebase. `software-standards` for vendor selection / legacy onboarding / pre-acquisition evaluation. Mutually exclusive. |

Each overlapping skill MUST have a "When NOT to use" section naming the other skill(s) and the priority
rule. The orchestrator reads these to decide which skill to invoke when the user's request is
ambiguous. A new skill added alongside an existing one must declare a priority rule at creation — a
skill without a declared priority cannot be promoted past draft.

---

## Changelog

- **1.3.0** (2026-04-28) — Working-tree convention changed from visible `ssd/` to hidden `.ssd/`.
  All artifact-tree paths (`.ssd/project.yml`, `.ssd/current.yml`, `.ssd/features/<slug>/…`,
  `.ssd/milestones/<topic>/…`, `.ssd/archive/…`) are updated. The `/ssd` orchestrator now checks for
  `.ssd/project.yml` on invocation. Reason: the visible `ssd/` directory collided with the
  orchestrator skill source directory in the SSD skills repo itself, and working artifacts are
  better hidden by default.
- **1.2.0** (2026-04-18) — Added SSD artifact tree (O1), structured YAML frontmatter requirement (O2),
  session continuity via `ssd/current.yml` (O8), `/ssd verify` phase with before/after snapshot
  convention (O4/O5), methodology-backed gate enforcement (O9), and skill-overlap priority table (O11).
  Updated `/ssd milestone` playbook to include snapshot step and mandatory verification exit.
- **1.1.0** — Added `/ssd gate`, `/ssd ship`, `/ssd audit`.
- **1.0.0** — Initial release.
