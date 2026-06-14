<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

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

## Iterations Inside a Feature

A "feature" defaults to a one-cycle workstream (one design → one build → one review → one deploy).
Real features sometimes ship as multiple iterations — `phase3-ui#3a`, `#3b`, `#3c` — each with its
own brief, code, review, and deploy. As of v1.5.0, this is a first-class concept rather than a
filename convention. See [ADR-0001](../../docs/decisions/ADR-0001-iterations-as-schema-substrate.md).

### Iteration syntax

The orchestrator accepts a `<slug>#<iter-id>` suffix on any phase command:

```
/ssd code talentos-reimagined-phase3-ui#3b
/ssd review talentos-reimagined-phase3-ui#3b
/ssd ship talentos-reimagined-phase3-ui#3b
```

Iter-id matches `[A-Za-z0-9_-]+`. Common conventions: short numeric (`3a`, `3b`), descriptive
(`auth-flow`), sequential (`1`, `2`). The orchestrator does not enforce a format. Quote the slug in
shells that interpret `#` (e.g., `/ssd code 'foo#3b'` in zsh with `extended_glob`).

### Resolution

When the orchestrator receives a slug:

1. **Slug contains `#`**: split into `<feature-slug>` + `<iter-id>`. Operate on
   `.ssd/features/<feature-slug>/iterations/<iter-id>/`. If that subdirectory doesn't exist and the
   user is in a phase that creates artifacts (coder, design), prompt: *"feature is flat-layout —
   create new iteration `<iter-id>`?"* The first `#iter` reference promotes the feature to
   multi-iteration; subsequent ones skip the prompt.
2. **Slug has no `#` and feature has an `iterations/` subdir**: orchestrator surfaces active
   iterations from `.ssd/current.yml` and asks which to operate on (or to create a new one).
3. **Slug has no `#` and feature is flat-layout**: single-cycle path. Read/write the flat
   layout under `.ssd/features/<feature-slug>/`.

### Layout (recap)

- **Flat (single-cycle, default)**: `.ssd/features/<slug>/{00-brief, 01-architect, …, 05-deploy}.md`.
- **Nested (multi-iteration)**: epic-level docs at the feature root; per-iteration docs under
  `iterations/<iter-id>/`. Promotion is non-destructive — the orchestrator does not move existing
  flat artifacts into the first iteration.

### Iteration-id collisions

The iter-id namespace is scoped to the feature path
(`features/<slug>/iterations/<id>/`). Two different features can both have `#3a` without
conflict. Within a feature, the orchestrator refuses to create a duplicate iter-id.

---

## Session Continuity

On invocation, `/ssd` reads two files:

- `.ssd/current.yml` — schema-validated machine state (v2). The orchestrator owns it.
- `.ssd/current.notes.yml` — free-form human/agent context. Loaded but not validated.

See [ADR-0002](../../docs/decisions/ADR-0002-current-yml-split.md) for the rationale on splitting these.

### `current.yml` v2 schema

```yaml
schema_version: 2
active:
  - slug: goal-approval-flow         # feature slug; matches .ssd/features/<slug>/
    phase: brief|design|code|review|gate|deploy|done
    iteration: null                  # iter-id (e.g., "3a") or null for single-cycle; see ADR-0001
    started: 2026-04-18T10:00:00Z
    last_touched: 2026-04-18T14:30:00Z
    budget_hours: 8
    elapsed_hours: 4.5
    gate_rounds: 0                   # incremented per code-review round; populated by future iter
    rail_deviations: []              # list of {step, reason, ts}; populated by future iter
    blockers: []

    # Parallel-features fields (v1.15.0, see ADR-0007). All optional; absence is valid.
    branch: add-goal-approval-flow   # git branch for this workstream; defaults from project.yml.ssd.branch_pattern
    worktree: null                   # null = main checkout; string = absolute path to git worktree
    touches: []                      # list of file globs the workstream is known to modify; populated
                                     #   by architect (intent at design time) and unioned by coder
                                     #   (v1.17.0+: `git diff --name-only <base>...HEAD` at each /ssd
                                     #   gate run). Read by code-reviewer to emit OVERLAP-N findings
                                     #   on cross-workstream file overlap — see code-reviewer/SKILL.md
                                     #   § "Cross-Workstream Overlap Check".

    # GitHub issue-tracking fields (ADR-0014). All optional; present only when
    # project.yml integrations.github.issue_tracking is on. Lazy-cached on first sync.
    epic: null                       # parent epic issue number (the workstream's ADR, via adrs_authored)
    issue: null                      # this workstream's `ssd:feature` issue number
archived: []
```

The `iteration`, `gate_rounds`, and `rail_deviations` fields are nullable / default-empty placeholders
populated by later iterations of the SSD-upgrades epic (P1.1, P1.2, P2.A). They are present in v2 from
the start so v2 ships forward-compatible — no second schema bump when those iterations land.

The `branch`, `worktree`, and `touches` fields (v1.15.0) are optional additive extensions per
[ADR-0007](../../docs/decisions/ADR-0007-parallel-features.md). Existing v2 `current.yml` files
without these fields continue to parse and behave identically. When the orchestrator next touches
an active entry whose `branch:` is absent, it lazily backfills `branch:` with the current
checkout's branch — but only when **both** guards hold: (a) exactly one active workstream has
no recorded `branch:` (no guess on multi-ambiguity), and (b) the current branch plausibly
corresponds to that workstream, i.e., the branch is the result of `branch_pattern` substituted
with the workstream's slug (default: `add-<slug>`). The second guard prevents incorrect backfill
when the user is checked out on an unrelated branch (a debug/experiment/hotfix branch). If
either guard fails, the orchestrator leaves `branch:` absent and prompts the user the next time
disambiguation matters.

The `epic` and `issue` fields (ADR-0014) are optional additive extensions, present only when the
project opts into GitHub issue tracking (`project.yml` `integrations.github.issue_tracking: on`).
They cache the workstream's parent epic issue (resolved from `adrs_authored` via the
`[ADR-NNNN]`-titled `ssd:epic` issue) and its own `ssd:feature` issue number, lazily backfilled on
the first sync exactly like `branch:`. Absence is valid and means "not yet synced" (or tracking off).
The cache lets steady-state sync be a single `gh issue edit` with no search. See
[ADR-0014](../../docs/decisions/ADR-0014-github-issue-state-tracking.md) and
`methodology/issue-sync.sh`.

### `current.notes.yml` (free-form)

```yaml
features:
  goal-approval-flow:
    handoff_notes: |
      Refactored the approval state machine into a reducer; the next session
      should re-verify the edge case where a goal is archived mid-approval.
    scope_changes: []
    questions_for_next_session: []
```

Anything that doesn't fit the v2 schema goes here. Not validated; never blocks.

### v1 detection

A `current.yml` lacking `schema_version` is treated as v1 (legacy). The orchestrator continues to
read it in legacy mode and prompts the user (once per session) to migrate via `ssd-init`. Migration
is opt-in, prompted, and writes `current.yml.bak` before splitting. No silent rewrites.

### Orchestrator behavior on active entries

If `.ssd/current.yml` has active entries, the orchestrator:

1. Surfaces them to the user: "You have 2 active workstreams. Resume one, or start new?"
2. Flags any entry where `elapsed_hours > budget_hours`: "billing-migration is over budget — suggest
   scope reduction, not more work."
3. Flags any entry with `last_touched > 3 days ago`: stale work that may need a fresh audit before
   continuing.
4. Renders any `handoff_notes` from `current.notes.yml` for the chosen workstream as starting context.

Closing a workstream (after successful deploy + verify) removes it from `current.yml` and archives
artifacts under `.ssd/archive/features/<slug>/`. Corresponding entries in `current.notes.yml` are
moved to `.ssd/archive/features/<slug>/notes.yml` so the historical context stays with the work.

### Concurrency: one Claude session per project at a time

`current.yml` and `current.notes.yml` have a **single-writer** assumption: at most one Claude
session operates on a given project's `.ssd/` at a time. This is doctrine, not an enforced
runtime guarantee.

- The "atomic write" the lifecycle commands promise (write a temp file + rename, or prepare full
  content in memory before writing — see § "Self-verification") is a **prose contract** that keeps
  a *single* writer from leaving a half-written file. It does **not** coordinate *concurrent*
  writers.
- If two terminals run `/ssd` against the same project simultaneously and both write `current.yml`,
  the second writer silently overwrites the first. No lock detects this.
- **Incident recovery.** Human context is recoverable from the git history of `current.notes.yml`
  (when committed); the `current.yml.bak` written by the ADR-0002 v1→v2 migration is the rollback
  artifact for that path. For a clobbered `current.yml` with no backup, reconstruct from the active
  workstreams' branches and latest artifacts under `.ssd/features/<slug>/`.
- **Future work (ADR-0009-class candidate).** A lockfile or a `writer_token`/version-counter scheme
  would make concurrent sessions safe; deferred until parallel sessions on one project become a
  real use case rather than a hypothetical. (Refactor R8, post-v1.19 milestone; cites Hohpe
  single-writer concurrency + F3.)

---

