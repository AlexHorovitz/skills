---
skill: architect
version: 1.2.0
produced_at: 2026-05-21T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: true
  adrs: [ADR-0007]
  risk_assessment: true
  feature_flag: not_applicable    # markdown skills library; releases gated by version tag
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — Parallel Features

## Platform Note

This is a **headless markdown skills library** (per `.ssd/project.yml`: framework
`claude-skills`, platform `headless`). The architecture artifact below adapts the standard
SSD architect deliverables to a workflow-tooling domain:

| Standard architect deliverable | Realized as |
|---|---|
| Component diagram | Orchestrator state/command flow diagram |
| Data model | `current.yml` v2 / `project.yml` schema additions |
| API contract | Orchestrator command syntax + behavior contracts |
| Integration contract | git operations (the orchestrator's only external integration) |

`systems-designer` is N/A for this feature (no runtime, no monitoring, no production
service) and is intentionally skipped per `ssd/SKILL.md` § "Skip `/ssd design` when
systems-designer is N/A."

---

## Current Scale Baseline

| Dimension | Today | 10x target |
|---|---|---|
| Concurrent active workstreams (per-user, single project) | typically 1, occasionally 2 (manual stash dance) | 10 — but the actual ceiling we design for is **4** (see ADR-0007 § Consequences). |
| SSD-managed projects per user | ~5 (this user) | 50 |
| Workstreams per project per quarter | ~15 (this project: 9-iter epic + 1 ADR + this feature) | 150 |
| Worktree-equipped workstreams (today: 0) | 0 | 4 simultaneously per project |
| `/ssd` invocations per day (heavy user) | ~20 | 200 |

Implication: we design for **4 concurrent active workstreams per project**, not 10 or
more. Above 4 the cognitive overhead exceeds the parallelism benefit; the orchestrator
will surface a warning (not a block) when `len(current.yml.active) > 4`.

---

## Open Questions — Resolved

### Q1: Branch naming convention → `add-<slug>` (default, advisory, configurable)

**Decision:** the canonical convention is `add-<slug>`, matching existing repo history
(`add-adr-0006`, `add-parallel-features`). The orchestrator **defaults to this pattern
when creating branches** but **never enforces it** — a workstream may declare any branch
name in `current.yml.active[].branch`.

The pattern is configurable in `project.yml`:

```yaml
# .ssd/project.yml
ssd:
  branch_pattern: "add-{slug}"   # default
```

Alternatives offered: `feature/{slug}`, `ssd/{slug}`, `{slug}` (no prefix). Teams pick at
project-init time or change later by editing `project.yml`. The orchestrator does **string
substitution only**, no validation of the slug content beyond the existing slug regex
(`[a-z0-9][a-z0-9-]*`).

**Rationale:** `add-<slug>` matches what this project already uses, reads naturally in
commit logs and PR titles, and avoids the `feature/`-namespace collision risk for projects
that use GitFlow conventions on the same remote. Making it configurable defangs the "but
my team uses X" objection at near-zero cost.

**Auto-detect impact:** branch-name → slug resolution (§ Auto-Detection) reverses the
substitution: strip the prefix, match against `current.yml.active[].slug`. If no match,
fall back to matching `current.yml.active[].branch` exactly.

### Q2: Worktree location default → sibling-of-repo, configurable

**Decision:** worktrees default to `<repo-parent>/<repo-name>-<slug>/`. For this repo
that's `/Users/ahorovit/Development/insanelygreat/skills-parallel-features/`.
Configurable in `project.yml`:

```yaml
# .ssd/project.yml
ssd:
  worktree_root: "../"               # default: parent of repo root
  worktree_name_pattern: "{repo}-{slug}"   # default
```

`worktree_root` accepts absolute paths or paths relative to the repo root.
`worktree_name_pattern` accepts `{repo}` and `{slug}` placeholders.

**Rationale:** the sibling convention is the de-facto idiom in git tooling (`git worktree
add ../foo-branch`). Centralizing worktrees under a single parent directory
(`~/worktrees/`) is a power-user preference best served by config rather than the default.
Putting worktrees **inside** the repo root is rejected — they'd shadow the main checkout
and break recursive globs.

### Q3: Handoff-note capture on `/ssd switch` → hybrid (orchestrator drafts, user confirms)

**Decision:** when `/ssd switch <target>` is invoked from an active workstream, the
orchestrator:

1. Inspects the last N tool calls in conversation (or the recent git diff if invoked
   fresh) to draft a 2–4-line handoff note candidate.
2. Surfaces the draft to the user and asks "save this as the handoff note, edit, or
   skip?" (single-prompt, three options).
3. Writes the chosen text to `current.notes.yml.features.<source-slug>.handoff_notes`
   (overwriting the existing field — there's only one current handoff note per
   workstream).
4. Proceeds to the switch.

Bypass for hurried users: `/ssd switch <target> --no-note` skips steps 1–3 entirely and
leaves the existing handoff note untouched. `/ssd switch <target> --auto-note` accepts
the draft without prompting.

**Rationale:** purely automated drafts get stale or wrong; purely manual prompts get
skipped under time pressure. The hybrid keeps the friction low (3-key Enter accepts the
draft) while making sloppy notes opt-in rather than default. Profile-aware default:
**novice** profile gets the prompt by default; **expert** profile gets `--auto-note` by
default (configurable per-project via `project.yml.ssd.switch_note_default:
prompt|auto|skip`).

### Q4: `touches:` population → both architect (intent) and coder (actual)

**Decision:** `touches:` is populated in two passes:

1. **Architect pass** (forward-looking, declarative). When architect writes the spec,
   it produces a `touches_planned:` list in its frontmatter — file globs the design
   targets. This is written into `current.yml.active[].touches` as the initial value.
2. **Coder pass** (descriptive, observed). On every coder gate cycle (i.e., before
   `/ssd gate` is invoked), the orchestrator runs `git diff --name-only <base>...HEAD`
   on the workstream's branch and **merges** the actual touched paths into
   `current.yml.active[].touches`. New paths are appended; existing entries are
   preserved (so an architect-intended path that hasn't been touched yet still warns
   if a parallel workstream lands on it).

The merge is union, not replacement, because we want overlap warnings to surface even
for paths the design intends to touch but hasn't yet.

**Rationale:** intent-only (architect) misses paths the coder discovered along the way.
Diff-only (coder) misses paths the design will touch but hasn't yet — and one of the
main values of overlap detection is catching it **before** code lands. Both, unioned,
covers the cases that matter.

### Q5: Parallel iterations of the same feature → out of scope

**Confirmed:** the `<slug>#<iter>` syntax handles in-feature iteration sequencing per
ADR-0001. Parallel iterations of the same feature (`#3a` and `#3b` open simultaneously)
would require a deeper rethink of the iteration model (what does "current iteration"
even mean if two are open?) and the brief explicitly defers it. We keep this out of
scope; if it becomes a real need, write ADR-0010+ for it.

The current model: one iteration of a feature is active at a time; multiple **features**
(each with one active iteration or none) run in parallel.

---

## Component Diagram — Orchestrator Command Flow

```
                      ┌─────────────────────────────────────────┐
                      │ User                                    │
                      └────────────────────┬────────────────────┘
                                           │
                  ╔════════════════════════▼════════════════════════╗
                  ║   /ssd (orchestrator) — reads .ssd/current.yml  ║
                  ╚═══╤═══════════╤═══════════╤═══════════╤═════════╝
                      │           │           │           │
              ┌───────▼───┐  ┌────▼─────┐  ┌─▼───────┐  ┌▼──────────┐
              │ no-arg    │  │ feature  │  │ switch  │  │ worktree  │
              │ auto-     │  │ new      │  │ <slug>  │  │ <slug>    │
              │ detect    │  │ <slug>   │  │         │  │ add|rm    │
              └─────┬─────┘  └────┬─────┘  └────┬────┘  └─────┬─────┘
                    │             │             │             │
        ┌───────────┼─────────────┼─────────────┼─────────────┼──────────┐
        │           │             │             │             │          │
        │  ┌────────▼─────┐  ┌────▼─────┐  ┌────▼──────┐  ┌──▼───────┐  │
        │  │ detect       │  │ git      │  │ capture   │  │ git      │  │
        │  │ branch →     │  │ branch + │  │ handoff   │  │ worktree │  │
        │  │ slug         │  │ optional │  │ note +    │  │ add /    │  │
        │  │              │  │ worktree │  │ checkout  │  │ remove   │  │
        │  └──────┬───────┘  └────┬─────┘  └────┬──────┘  └──────────┘  │
        │         │               │             │                       │
        │         └───────────────┴─────────────┴───── writes ──────────┤
        │                                                               │
        │                  current.yml         current.notes.yml        │
        │                  (active[].branch,   (handoff_notes per       │
        │                   .worktree,         active slug)             │
        │                   .touches)                                   │
        └───────────────────────────────────────────────────────────────┘

External integration: git (CLI shell-out). No locks. No daemons. No bg processes.
```

---

## Data Model — Schema Additions

### `current.yml` v2 — additive, backward-compatible

Three new fields on `active[]`:

```yaml
schema_version: 2
active:
  - slug: parallel-features
    phase: code
    iteration: null
    started: 2026-05-21T00:00:00Z
    last_touched: 2026-05-21T00:00:00Z
    budget_hours: 16
    elapsed_hours: 4.5
    gate_rounds: 0
    rail_deviations: []
    blockers: []

    # NEW — parallel-features (ADR-0007)
    branch: add-parallel-features     # string; defaults from branch_pattern
    worktree: null                    # null | absolute path; null = main tree
    touches: []                       # list of glob strings (POSIX shell globs)
```

**Field semantics:**

- `branch` (string, required-on-create) — the git branch this workstream lives on.
  Validated only as a non-empty string; the orchestrator does not parse refspecs.
- `worktree` (string-or-null, optional, default null) — absolute filesystem path to the
  worktree directory if the workstream uses one. `null` means the workstream uses the
  main checkout.
- `touches` (list of strings, optional, default []) — POSIX shell globs (e.g.,
  `src/foo/**/*.ts`, `docs/*.md`). Used only for overlap warnings; never executed.

**Backward-compat strategy:**

- Existing `current.yml` files lacking these fields parse cleanly: schema additions are
  optional with sensible defaults (`branch: null`, `worktree: null`, `touches: []`).
- On **next touch** of an active entry (any orchestrator action that writes to it), the
  orchestrator **lazily backfills** `branch:` with the current `git symbolic-ref --short
  HEAD` if and only if exactly one active entry has `branch: null`. If two or more entries
  have `branch: null`, the orchestrator declines to guess and writes nothing — the user
  must specify with `/ssd workstream set-branch <slug> <branch>` (new sub-command, scoped
  to backfill only, NOT part of the main UX).
- The validator in `methodology/schema-validator.sh` (per ADR-0006) gains optional
  field-presence checks gated on `schema_version: 2`; no FAIL on absence, MINOR on
  partial population.

### `project.yml` — three new optional keys

```yaml
ssd:
  # existing keys unchanged
  branch_pattern: "add-{slug}"           # NEW — default for /ssd feature new
  worktree_root: "../"                   # NEW — default for /ssd worktree add
  worktree_name_pattern: "{repo}-{slug}" # NEW — default for /ssd worktree add
  switch_note_default: prompt            # NEW — prompt|auto|skip
```

All four keys are optional with the defaults shown. Missing keys behave exactly as if
the default were declared.

### `current.notes.yml` — no schema change

The existing `features.<slug>.handoff_notes` field is reused. Continues to be free-form
YAML, never schema-validated. `/ssd switch` writes here.

---

## API Contract — New Orchestrator Commands

### `/ssd feature new <slug> [--branch <name>] [--worktree] [--from <ref>]`

**Purpose:** start a new feature workstream, end-to-end scaffolded, in one step.

**Behavior (steps in order):**

1. Validate `<slug>` matches `[a-z0-9][a-z0-9-]*` and is not already in `current.yml.active[].slug`.
2. Resolve branch name: `--branch <name>` wins, otherwise `branch_pattern` substitution
   (default `add-<slug>`).
3. Validate git working tree is **clean** on the current branch. If dirty → fail with a
   FAILURE-MODE-1 message (below). Bypass: `--allow-dirty` (logs a `rail_deviations` entry).
4. Determine base ref: `--from <ref>` wins, otherwise the repo's main branch (resolved as
   `git rev-parse --abbrev-ref origin/HEAD` or fallback to `main`).
5. Run `git checkout -b <branch> <base-ref>` (or `git branch <branch> <base-ref>` if
   `--worktree` — branch must exist before `git worktree add` can use it).
6. If `--worktree`:
   - Compute worktree path via `worktree_root` + `worktree_name_pattern`.
   - Run `git worktree add <path> <branch>`.
   - Switch the orchestrator's working-directory context to that path for subsequent
     writes (so the brief lands in the worktree's `.ssd/`, not the main tree's).
   - **Wait — important:** `.ssd/` is gitignored but lives per-checkout. The orchestrator
     writes the brief to the **main repo's** `.ssd/`, not the worktree's, because the
     authoritative `current.yml` is the main tree's. The worktree shares the git index
     but not the working files. See § Risk #1.
7. Write `.ssd/features/<slug>/00-brief.md` stub (with frontmatter; user fills in the
   body via the architect or by editing directly).
8. Append entry to `.ssd/current.yml.active[]` with `phase: brief`, `branch: <name>`,
   `worktree: <path or null>`.
9. Initialize `.ssd/current.notes.yml.features.<slug>` with an empty `handoff_notes:`
   block.
10. Emit a summary: branch created, worktree path (if any), next-step proposal (run
    `/ssd design <slug>` or `architect <slug>`).

**Failure modes:**

- **FM-1: dirty tree** — refuse. Suggest: `git stash` first, or `--allow-dirty` (which
  logs a deviation).
- **FM-2: branch exists** — refuse. Suggest: `--branch <other-name>` or
  `/ssd workstream adopt <slug> <branch>` (future; not in v1).
- **FM-3: slug collision** — refuse. Suggest a fresh slug.
- **FM-4: worktree path collides with existing directory** — refuse. Print the colliding
  path; suggest a path override (no flag; user adjusts `project.yml`).

### `/ssd switch <slug> [--no-note | --auto-note]`

**Purpose:** pause the current workstream, capture a handoff note, resume the target
workstream.

**Behavior:**

1. Identify the **current** workstream: branch ↔ slug auto-detect (§ Auto-Detection). If
   no current workstream identified, skip steps 2–3.
2. Capture handoff note for current workstream:
   - Default (`switch_note_default: prompt`): orchestrator drafts a 2–4-line note from
     recent activity, presents it, user accepts/edits/skips.
   - `--no-note` or `switch_note_default: skip`: skip capture, leave existing note.
   - `--auto-note` or `switch_note_default: auto`: accept the draft silently.
3. Write the note to `current.notes.yml.features.<current-slug>.handoff_notes` (overwrite).
4. Resolve target workstream from `<slug>`. Refuse with FM-5 if not in active list.
5. If target has `worktree: <path>`:
   - Print `cd <path>` and the path. Orchestrator **does not** chdir on behalf of the
     user; it cannot persist that across the tool boundary. Tells the user explicitly.
6. Else (target has `worktree: null`):
   - Validate current working tree is clean. If dirty → FM-6 (dirty switch). Bypass:
     `--allow-dirty` (deviation).
   - Run `git checkout <target.branch>`.
7. Update `current.yml.active[<target>].last_touched`.
8. Render target's starting context:
   - Most recent artifact path under `.ssd/features/<slug>/`.
   - `current.notes.yml.features.<slug>.handoff_notes`.
   - Phase + proposed next command.

**Failure modes:**

- **FM-5: target slug not in active list** — refuse. Suggest `/ssd feature new <slug>`
  or list active slugs.
- **FM-6: dirty tree on same-tree switch** — refuse. Suggest stash, commit, or
  `--allow-dirty`.
- **FM-7: branch doesn't exist** (e.g., `current.yml` references a branch that was
  manually deleted) — fail loudly. Suggest `git branch <branch> <ref>` to recreate, or
  `/ssd workstream set-branch <slug>` to point at a different branch.

### `/ssd worktree <slug> add|remove [--path <path>]`

**Purpose:** explicit worktree lifecycle, decoupled from `feature new`.

**`add` behavior:**

1. Validate `<slug>` is in `current.yml.active[]`.
2. Validate the slug's `worktree:` field is currently `null` (else FM-8).
3. Resolve path: `--path <path>` wins, otherwise `worktree_root` +
   `worktree_name_pattern` substitution.
4. Run `git worktree add <path> <branch>` where `<branch>` comes from the slug's entry.
5. Update `current.yml.active[<slug>].worktree = <path>`.
6. Print the path and a `cd <path>` line.

**`remove` behavior:**

1. Validate `<slug>` is in `current.yml.active[]` and has `worktree: <path>` not null.
2. Validate the worktree's working tree is clean (`git -C <path> status --porcelain`
   empty). If dirty → FM-9.
3. Run `git worktree remove <path>`.
4. Update `current.yml.active[<slug>].worktree = null`.
5. Note: the branch is **not** deleted. `worktree remove` only removes the worktree dir.

**Failure modes:**

- **FM-8: workstream already has a worktree** — refuse. Print existing path; suggest
  `remove` first.
- **FM-9: dirty worktree on remove** — refuse. Tell the user to commit or stash.
- **FM-10: worktree path doesn't exist on disk** (manual deletion) — proceed with
  `git worktree prune`-equivalent, clear the `worktree:` field, log a warning.

---

## Integration Contract — Git Operations

The orchestrator shells out to git for all branch and worktree operations. This is the
only external integration in scope.

| Operation | git command | Failure mode |
|---|---|---|
| Branch creation | `git checkout -b <branch> <base>` | FM-2 (branch exists) |
| Branch (without checkout, for worktree) | `git branch <branch> <base>` | FM-2 |
| Worktree add | `git worktree add <path> <branch>` | FM-4 (path collides) |
| Worktree remove | `git worktree remove <path>` | FM-9 (dirty) |
| Worktree prune (recovery) | `git worktree prune` | non-fatal |
| Branch checkout | `git checkout <branch>` | FM-7 (no such branch) |
| Dirty check | `git status --porcelain` empty? | FM-1, FM-6 |
| Current branch | `git symbolic-ref --short HEAD` | (treated as "detached HEAD") |
| Diff for `touches:` backfill | `git diff --name-only <base>...HEAD` | non-fatal (skip) |

**Idempotency:** the orchestrator never re-runs a git command after partial failure. If
a step fails, the user fixes the underlying issue (stash, delete a branch, etc.) and
re-runs the command. The orchestrator does not maintain transactional state across
shell-outs.

**Schema evolution / versioning:** git itself has no payload schema concerns. The
orchestrator's own state (`current.yml`) is versioned via `schema_version:` — adding
`branch`/`worktree`/`touches` is a v2-compatible additive change (see ADR-0007 §
Consequences for why this doesn't bump to v3).

**Ordering / async:** all git operations are synchronous CLI calls. There is no async
work. There is no DLQ. There is no broker. (Trivially satisfied — listed for the
checklist.)

---

## Auto-Detection — branch-name → slug

Invoked by `/ssd` (no-arg) and `/ssd switch` (to identify the current workstream).

**Algorithm:**

```
1. current_branch = git symbolic-ref --short HEAD  (or "DETACHED" if detached)

2. For each entry in current.yml.active:
     if entry.branch == current_branch:
       return entry.slug    # exact match — preferred

3. If no exact match:
     prefix = project.yml.ssd.branch_pattern.split('{slug}')[0]   # e.g., "add-"
     if current_branch.startswith(prefix):
       candidate_slug = current_branch[len(prefix):]
       for entry in current.yml.active:
         if entry.slug == candidate_slug:
           return entry.slug    # pattern-based match — backfill entry.branch lazily

4. If still no match:
     return None    # caller prompts user

5. If detached HEAD or git not available:
     return None    # caller prompts user
```

**Failure / ambiguity behaviors:**

- **No match** (case 4): `/ssd` (no-arg) prompts: "Current branch `<name>` doesn't
  correspond to any active workstream. Options: (a) pick from active list, (b)
  `/ssd feature new <slug>` to register a new one, (c) abort." `/ssd switch` requires
  an explicit target so this is moot for switch.
- **Multiple matches** (case 2 collision — two entries declare the same `branch:`):
  impossible by construction; `/ssd feature new` refuses duplicate branches, and
  `set-branch` validates uniqueness. The orchestrator emits an internal error if it
  finds two — that's a bug, not a user state.
- **Detached HEAD**: treat as case 4.

---

## Overlap Warning — How `touches:` Surfaces at Gate Time

**Trigger:** `/ssd gate` invocation on workstream X.

**Algorithm:**

```
1. own_touches = current.yml.active[X].touches
2. For each Y in current.yml.active where Y.slug != X.slug:
     overlap = glob_intersect(own_touches, Y.touches)
     if overlap is non-empty:
       emit OVERLAP-N finding
```

**Glob intersection (`glob_intersect`):**

- Two glob strings overlap if there exists at least one path matching both. The
  orchestrator approximates this via the **resolved file set**: it expands each glob
  against the current working tree (via `git ls-files <glob>`) and computes the
  intersection of the resulting file sets. This is exact for the current tree; it can
  miss future-only matches but those are exactly the cases that don't matter yet.
- An empty `touches` on either side is treated as "unknown" — no warning. (Workstreams
  early in their lifecycle won't trigger spurious warnings.)

**Finding format (added to `04-code-review.md` frontmatter):**

```yaml
findings:
  - id: OVERLAP-1
    severity: suggestion         # NOT blocker/major — purely informational
    category: cross-workstream-overlap
    title: "Touches files modified by parallel workstream `<other-slug>`"
    files:
      - path: src/foo/bar.ts
        also_modified_by: [other-workstream-slug]
    suggestion: |
      Consider serializing with `<other-slug>` (currently in `phase: <phase>`,
      branch `<branch>`) or rebasing onto its merge before this gate passes.
      This is not a blocker — the gate still passes if `findings.blocker == 0
      && findings.major == 0`.
```

**Tier rationale:** SUGGESTION-tier (per code-reviewer's existing tier ladder:
BLOCKER > MAJOR > MINOR > QUESTION > SUGGESTION > NIT). Specifically **not** MAJOR
because:

- The overlap may be intentional (e.g., one workstream extends a file the other
  added).
- Forcing serialization defeats the purpose of parallel work.
- The user has full context to judge; the orchestrator only surfaces.

**Implementation:** the overlap check is added to `code-reviewer/SKILL.md` § "Review
Phase 2: Cross-Cutting Concerns" (or wherever the existing per-finding-emission lives)
as a new check. It's data-only: it reads `current.yml` and ls-files; no judgment, no
LLM call.

---

## Decision Log — ADR-0007 Outline

**File:** `docs/decisions/ADR-0007-parallel-features.md`

```markdown
# ADR-0007: Parallel Features as First-Class Workstream Artifacts

## Status
Proposed → Accepted (on merge of this iteration)

## Context
SSD's current.yml.active is already a list, and the no-arg orchestrator surfaces
multiple workstreams. But operationally, only one feature can be edited at a time:
one working tree, one branch, stash/checkout dance to switch. Heavy users (this
project itself) have hit this and worked around it manually. Branch ↔ workstream
mapping lives in the user's head; overlap between parallel features doesn't surface
until rebase time.

## Decision
1. Add three optional fields to current.yml.active[]: `branch`, `worktree`, `touches`.
   All optional with sensible defaults; backward-compatible with existing v2 files.
2. Add three new orchestrator commands: `/ssd feature new`, `/ssd switch`,
   `/ssd worktree`. Each shells out to git for state changes; none introduces a daemon
   or lock file.
3. Branch ↔ slug auto-detection via configurable `branch_pattern` (default `add-{slug}`).
4. Cross-workstream `touches:` overlap surfaces as a SUGGESTION-tier code-review
   finding at gate time. Non-blocking.
5. Worktrees are opt-in per workstream, default to sibling-of-repo, fully configurable.
6. Practical concurrency ceiling: 4 active workstreams per project (soft warning above).

## Rationale
- **Additive schema beats v3 bump.** Optional fields with defaults let old current.yml
  files keep working without migration logic.
- **Shell-out beats reimplementation.** Reusing git worktree avoids inventing a lock
  protocol. Failures are visible and recoverable with normal git tooling.
- **Soft warnings beat hard gates.** Overlap is not always a problem. The user has
  context the orchestrator doesn't.
- **Convention over enforcement.** Defaulting to `add-{slug}` matches existing repo
  habits without forbidding alternatives. Teams with established conventions override.
- **Opt-in worktrees.** Users on small features in fast-iterate mode shouldn't be
  forced into a multi-directory mental model.

## Consequences
- **Easier:** parallel work without manual stash dance; clear handoff state on switch;
  early warning when two features collide on the same files.
- **Harder:** users must learn three new commands; multi-worktree users juggle multiple
  shell `cd` contexts (orchestrator can't chdir for them).
- **Given up:** a single source of truth for "what am I working on right now" — the
  current branch alone no longer disambiguates; the orchestrator queries
  `current.yml.active` cross-referenced with branch. This is acceptable because the
  alternative (forcing one branch = one feature, no exceptions) over-constrains.
- **Ceiling at 4:** above 4 active workstreams, cognitive overhead exceeds benefit. The
  orchestrator emits a non-blocking advisory.

## Alternatives Rejected
1. **No tooling, just docs.** Document the git stash workflow in SKILL.md and call it
   done. → Rejected: the friction is high enough that users won't do it (this user
   hasn't, in 14 versions of the library).
2. **Required worktree per workstream.** Force a worktree for every active feature.
   → Rejected: too heavy for small/quick features; punishes the simple case.
3. **In-orchestrator branch protocol** (no git shell-out). Manage branches via a
   custom YAML that maps to git via a hook. → Rejected: reinvents git, fragile, no
   payoff.
4. **MAJOR-tier overlap warnings** instead of SUGGESTION. → Rejected: would block
   merges in cases where overlap is the *intent* (e.g., layered changes). Surfacing
   beats blocking.
5. **`schema_version: 3` bump.** → Rejected: additive optional fields are exactly
   what schema_version preserves compatibility for. Bumping would force migration
   tooling for no semantic gain.
```

(The full ADR follows the standard template — coder writes the prose; this outline is
the directive.)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Worktrees fall out of sync with `current.yml` (manual `git worktree remove`, dir deleted) | M | M | `/ssd worktree remove` recovers via `git worktree prune`; auto-detect treats missing path as null. Document the recovery in SKILL.md. |
| `/ssd switch` cannot chdir on behalf of the user — they end up running commands in the wrong tree | M | H | Always print the `cd <path>` line as the **last** line of switch output; lint for it in tests. Document in SKILL.md as a known constraint. Long-term mitigation: shell wrapper (out of scope). |
| Branch-pattern collisions across projects sharing a remote (`add-foo` exists upstream) | L | M | The orchestrator only operates locally; upstream collisions surface at push time as the normal git error. Document. |
| `touches:` globs get stale (no longer match real files) | M | L | Empty intersections never warn — staleness fails open. Coder pass refreshes from `git diff` each gate cycle. |
| User edits `current.yml` manually and breaks the new fields | M | M | Schema validator (ADR-0006) gains optional checks for `branch`/`worktree`/`touches` — MINOR severity, never blocks. |
| Worktree disk usage (4 worktrees × repo size) | L | L | Document. This repo is markdown; ~5MB per worktree. Not a real concern for the skills library; flag for projects with large repos. |

**Top 3 (for systems-designer attention — N/A this round, recorded for future audits):**

1. `cd` boundary (orchestrator → user shell context). Bears the most UX risk.
2. Worktree drift (filesystem state mismatching `current.yml`).
3. Branch collisions on shared remotes.

---

## Feature Flag Plan

**Not applicable.** This is a markdown skills library — `.ssd/project.yml` declares no
`feature_flag_marker` (per the project notes: "this is a markdown library with no
runtime"). The standard SSD `feature-flag-present` gate rule SKIPs for this project.

**Rollout strategy in lieu of a flag:** each iteration of this epic ships as a tagged
release (v1.15.0 → v1.16.0 → v1.17.0). Users who don't want the new commands simply
don't invoke them; the new schema fields are no-ops when absent. Backwards-compat is
the rollout mechanism.

---

## Files in Scope (binding)

| File | Change | Iteration |
|---|---|---|
| `docs/decisions/ADR-0007-parallel-features.md` | NEW — full ADR per outline above | A |
| `ssd/SKILL.md` | EDIT — see § SKILL.md Edits below | A, B, C |
| `ssd/rails.md` | EDIT — add brief annotation about switch/pause as non-rail | B |
| `.ssd/project.yml` (this project's own) | EDIT — declare the four new optional ssd.* keys explicitly to model the convention | A |
| `methodology/schema-validator.sh` | EDIT — recognize new optional fields, emit MINOR on partial population | A |
| `methodology/gate-rules.sh` | EDIT — base detection: when on a workstream branch, default `--base` to the workstream's recorded base (currently main). Optional, fail open. | C |
| `code-reviewer/SKILL.md` | EDIT — new § "Cross-Workstream Overlap Check" with OVERLAP-N finding template | C |
| `ssd-init/SKILL.md` | EDIT — mention parallel-workstream support in the init narrative; ssd-init writes the new optional project.yml.ssd.* defaults | B |
| `CHANGELOG.md` | EDIT — v1.15.0, v1.16.0, v1.17.0 entries (one per iteration) | A, B, C |

No new shell scripts. All git shell-outs are inline in the orchestrator behavior (i.e.,
the LLM issues `git` commands via the Bash tool per the existing pattern in
`/ssd gate`).

---

## SKILL.md Edits — Section-by-Section

### Iteration A edits

1. **§ "The SSD Artifact Tree"** — add a footnote that the artifact tree may live under
   a sibling worktree directory for workstreams with `worktree:` set.
2. **§ "Session Continuity" / `current.yml` v2 schema** — add the three new fields to
   the schema example with inline comments.
3. **§ "Hard Rules (Invariants)"** — no change. (Single tree per feature is no longer
   true, but the invariants don't depend on it.)
4. **Changelog** — add v1.15.0 entry: "Iteration A of parallel-features epic — ADR-0007,
   schema additions for `branch`/`worktree`/`touches`, auto-detect branch → slug."

### Iteration B edits

5. **§ "Phase Playbooks"** — add new sub-section "Workstream Lifecycle Commands"
   between "/ssd ship" and "Developer Profile" with the three new commands documented.
6. **§ "/ssd (no-arg) — Auto-Detect"** — add a step 0: "If the current git branch maps
   to an active workstream's `branch:` (exact match) or matches `branch_pattern`
   substitution, auto-resolve that workstream and skip the "which workstream?" prompt.
   Otherwise fall through to existing behavior."
7. **§ "Sub-Skill Reference"** — no row changes; document is unchanged.
8. **Changelog** — v1.16.0: "Iteration B of parallel-features — `/ssd feature new`,
   `/ssd switch`, `/ssd worktree` commands."

### Iteration C edits

9. **§ "Methodology Enforcement"** — note that `gate-rules.sh` now respects
   workstream-recorded base branches.
10. **§ "Resolving Skill Overlap"** — no change.
11. **Changelog** — v1.17.0: "Iteration C of parallel-features — cross-workstream
    overlap detection at gate time."

---

## Iteration Plan

A 3-iteration epic. Each ships independently behind a tagged release.

### Iteration A — Schema + ADR + auto-detect (Foundation)

**Slug:** `parallel-features#a` (or stay flat — single iteration so far; promote on B)

**Scope:**
- Write ADR-0007 in full.
- Add `branch:`, `worktree:`, `touches:` fields to `current.yml.active[]` (optional,
  defaulted).
- Add `branch_pattern`, `worktree_root`, `worktree_name_pattern`,
  `switch_note_default` keys to `project.yml.ssd`.
- Extend `schema-validator.sh` to recognize the new optional fields.
- Implement branch-name → slug auto-detection in the orchestrator (read-only — no
  commands change yet).
- Update `ssd/SKILL.md` Session Continuity + Changelog.
- Update **this project's own** `.ssd/project.yml` to declare the new keys explicitly
  (modeling the convention).
- Backfill `branch: add-parallel-features` into the active entry for this very
  workstream (lazy backfill demonstrated).

**Acceptance:** existing `current.yml` files still parse (no-regression test). Running
`/ssd` (no-arg) on `add-parallel-features` resolves to the parallel-features workstream
without prompting (auto-detect test).

**Ship:** tag v1.15.0.

### Iteration B — New commands (`/ssd feature new`, `/ssd switch`, `/ssd worktree`)

**Scope:**
- Implement the three new commands per the API contract above.
- Add the "Workstream Lifecycle Commands" section to `ssd/SKILL.md`.
- Add brief note in `ssd/rails.md` that pause/switch is intentionally non-rail (it's
  workflow ergonomics, not a methodology step).
- Update `ssd-init/SKILL.md` to mention concurrent workstream support and write the
  new project.yml.ssd.* defaults at init time.
- Update Changelog.

**Acceptance:**
- AC-1 (two workstreams concurrent), AC-2 (switch), AC-5 (worktree opt-in) from brief.
- A novice profile user invokes `/ssd feature new` and is walked through with
  confirmations.
- An expert profile user invokes `/ssd switch foo --auto-note` and gets silent
  acceptance.

**Ship:** tag v1.16.0.

### Iteration C — Overlap warning + gate-rules base detection

**Scope:**
- Coder-pass `touches:` backfill on gate runs.
- Cross-workstream overlap check in `code-reviewer/SKILL.md`. New finding category
  OVERLAP-N at SUGGESTION tier.
- `methodology/gate-rules.sh` reads workstream-recorded base branch when present
  (replaces the hard-coded `--base main` default for that workstream).
- Update Changelog.

**Acceptance:**
- AC-4 (overlap warning) from brief. Two synthetic active entries both declaring
  `touches: [foo.md]` produce a SUGGESTION-tier finding on each gate, no
  BLOCKER/MAJOR/MINOR.
- AC-6 (backward-compat) — entries with `touches: []` produce no findings.

**Ship:** tag v1.17.0.

### Iteration D (deferred — only if real friction emerges)

Reserved for things that surface during iterations A–C:
- `/ssd workstream adopt <slug> <branch>` (claim an existing branch as a workstream)
- `/ssd workstream set-branch <slug> <branch>` (rename, or fix a wrong backfill)
- Tab-complete / `--explain` plumbing for new commands

These are not in scope unless a real-world incident motivates them.

---

## Self-Verification (Architect Quality Gate)

| Gate item | Status |
|---|---|
| Platform guide applied | ✓ — adapted headless conventions to workflow-tooling domain (documented in Platform Note) |
| Major decisions are ADRs | ✓ — ADR-0007 outlined; no other in-scope decisions warrant separate ADRs |
| Data model reviewed | ✓ — current.yml + project.yml schemas, fields, defaults, backward-compat |
| API/interface contract defined | ✓ — three commands fully specified with behavior + FMs |
| Auth/authorization specified | N/A — single-user local tool |
| Async/background work identified | N/A — all sync shell-out |
| Feature flag strategy defined | N/A (documented) — rollout via versioned tags |
| CI/CD and deployment path sketched | N/A — markdown library, no CI deploy |
| Top 3 risks identified with mitigations | ✓ — Risk Assessment table |
| Current Scale Baseline + 10x target | ✓ — explicit, designed for practical ceiling of 4 |
| Walking Skeleton deployable today | ✓ — Iteration A is independently shippable as v1.15.0 |

---

## Handoff to Coder

**Next step:** invoke `coder` on Iteration A.

The coder should:
1. Read this spec end-to-end.
2. Implement the Iteration A scope (ADR + schema + auto-detect + SKILL.md edits + this
   project's own project.yml update).
3. Mark any spec gaps with `# REVIEW:` comments (per coder skill convention).
4. Produce `.ssd/features/parallel-features/03-coder-status.md` (single-cycle layout
   for now; promote to `iterations/a/` if iteration B branches off before A ships).

The coder should NOT yet implement Iterations B or C. Each is a separate gate + ship
cycle.
