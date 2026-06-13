# SSD Meta-Skill

<!-- License: See /LICENSE -->

**Version:** 1.20.0

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

```
/ssd start         — New project or major feature: Walking Skeleton setup
/ssd feature       — Active development: design → build → review → deploy loop
/ssd design        — Bundled architect + systems-designer pass (single invocation)
/ssd milestone     — Post-sprint consolidation: deep audit + targeted refactor
/ssd verify        — Remediation verification after a milestone refactor (mandatory)
/ssd audit         — Adversarial comparative review (nuclear option)
/ssd gate          — Shippable state check only (code-reviewer + methodology rules)
/ssd ship          — Deploy readiness check only (systems-designer checklist)
/ssd feature new   — (v1.16.0+) start a parallel workstream with branch + scaffold
/ssd switch        — (v1.16.0+) pause current workstream, capture handoff, resume target
/ssd worktree      — (v1.16.0+) explicit worktree lifecycle (add | remove)
```

If no argument is given, the orchestrator **auto-detects state** from `.ssd/current.yml` and
proposes the next action. See § "/ssd (no-arg) — Auto-Detect" below. The explicit phase commands
remain as escape hatches for forcing a specific step, but the user almost never needs them.

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

### `/ssd design` — Bundled Design Pass

`architect` and `systems-designer` always run in sequence with the same inputs in the standard
`/ssd feature` flow. v1.7.0 lets them run as one logical step.

```
/ssd design <slug>
/ssd design <slug>#<iter>
```

The orchestrator:

1. Invokes `architect` first; produces `.ssd/features/<slug>/01-architect.md` (or
   `iterations/<iter>/01-architect.md` for multi-iteration features).
2. Reads the architect output and invokes `systems-designer` with it as input; produces
   `02-systems-designer.md` alongside.
3. Surfaces any architect-spec gaps that systems-designer rejected back to the user as a single
   actionable block (rather than two separate handoffs).

**This does not replace** the individual invocations. `architect` and `systems-designer` remain
independently invocable for ad-hoc design work, milestone redesigns, and external consumers
(e.g., `codebase-skeptic` reading just the architect spec). `/ssd design` is a convenience —
it does not gate or change either skill's contract.

**Skip `/ssd design` when systems-designer is N/A** (e.g., a markdown-only documentation project,
a skills library, an ADR-only PR). The user can invoke `architect` directly.

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

**Multi-round behavior** (since v1.6.0): if `code-reviewer` emits BLOCKER or MAJOR, the gate fails
and the workstream returns to coder. After fixes, re-running `/ssd gate` produces a round-2
review:
- The orchestrator auto-numbers the round by inspecting existing `code-review*` artifacts in the
  relevant directory.
- Output path: `04-code-review-round-2.md` (single-cycle features) or
  `iterations/<iter>/code-review/round-2.md` (multi-iteration features).
- Frontmatter `round: 2` and `closed_from_previous_round: [BLOCKER-1, MAJOR-2, …]` (every closure
  verified against the code, not copied from coder-status).
- `current.yml.active[].gate_rounds` increments. A workstream with `gate_rounds: 3` has been
  through three reviews — useful budget signal.

For small remediations (1–3 finding closures), an inline round-2 update at the bottom of the
existing `04-code-review.md` is permitted in lieu of a separate file. See `code-reviewer/SKILL.md`
§ "Multi-Round Gates."

---

### `/ssd ship` — Deploy Readiness Check

Invoke `systems-designer` deploy checklist for the feature about to ship.

Invoke `systems-designer` to produce the platform-appropriate deploy checklist. The checklist is defined and maintained by that skill — do not duplicate it here. The systems-designer skill covers web, mobile (iOS/Android), and macOS desktop deployment readiness.

**Tag the release (after PR merge).** Once the release PR merges to `main`, tag the merge commit
so the release history stays navigable (the missing-tags drift the post-v1.19 milestone fixed):

```bash
git tag -a v<version> <merge-sha> -m "v<version> — <one-line summary>"
git push origin v<version>
```

This should be done by hand or via a release script; the orchestrator does **not** auto-tag,
because tagging pushes to the remote and outward-facing actions stay under explicit human
control. This step closes the post-merge half of the `core.md` §4 ratchet ("tag every release").
(Refactor R7, post-v1.19 milestone.)

---

## Workstream Lifecycle Commands

(added v1.16.0, see [ADR-0007](../docs/decisions/ADR-0007-parallel-features.md))

These three commands manage **parallel feature workstreams** — branch creation, context switch,
and worktree lifecycle. They are independently invocable; nothing else in the orchestrator depends
on them. A user happy with single-feature flow never needs them.

All three commands shell out to `git` for state changes; none introduces a daemon, lock file, or
custom protocol. Failures surface as normal git errors and are recoverable with normal git
tooling.

### `/ssd feature new <slug> [--branch <name>] [--worktree] [--from <ref>] [--allow-dirty]`

**Purpose:** start a new feature workstream, end-to-end scaffolded (branch + optional worktree +
brief stub + `current.yml` entry), in one step.

**Iteration syntax:** the `<slug>` argument may carry a `#<iter>` suffix (e.g.,
`/ssd feature new parallel-features#c`) per the existing iterations model
(§ "Iterations Inside a Feature"). When `#<iter>` is present, the orchestrator creates an
iteration on an existing or new feature rather than a wholly new feature — see step 3 below.

**Behavior (orchestrator executes in order):**

1. **Validate slug.** Reject if `<slug>` doesn't match `[a-z0-9][a-z0-9-]*` (or, with `#<iter>`,
   if `<iter>` doesn't match `[A-Za-z0-9_-]+`). Reject if the resulting
   `(slug, iteration)` pair already exists in `current.yml.active[]` (FM-3).

2. **Resolve branch name.** Use `--branch <name>` if given. Otherwise apply
   `project.yml.ssd.branch_pattern` (default `add-{slug}`) substituted with the slug. If
   `<iter>` is present, append `-<iter>` to the substituted name (default
   `add-<slug>-<iter>`, e.g., `add-parallel-features-c`). The convention is advisory; the
   orchestrator does not enforce it on subsequent state writes.

3. **Determine feature layout.**
   - **No `#<iter>` in slug, feature doesn't exist yet:** flat layout. Will create
     `.ssd/features/<slug>/`.
   - **No `#<iter>`, feature exists flat:** new workstream entry for the same feature; the
     brief stub lands at `.ssd/features/<slug>/00-brief.md` — refuse if that already exists
     (FM-11).
   - **`#<iter>` in slug, feature doesn't exist:** create both `.ssd/features/<slug>/` and
     `.ssd/features/<slug>/iterations/<iter>/`. The brief lands at
     `iterations/<iter>/brief.md` (no `00-` prefix per iteration-nested convention).
   - **`#<iter>` in slug, feature exists flat:** prompt to promote (per
     § "Iterations Inside a Feature" — promotion is non-destructive; flat artifacts stay
     in place). On `developer_profile: expert`, also accept `--promote` to skip the prompt.
   - **`#<iter>` in slug, feature already multi-iter, `<iter>` doesn't exist yet:** create
     `iterations/<iter>/`. Refuse if `<iter>` already exists (FM-12).

4. **Verify git working tree is clean** on the current branch via `git status --porcelain`.
   If dirty and `--allow-dirty` not set, refuse with FM-1. With `--allow-dirty`, proceed and
   log a `rail_deviations` entry: `{step: "feature-new", reason: "dirty-tree", ts: <now>}`.

5. **Determine base ref** for the new branch. Use `--from <ref>` if given. Otherwise resolve
   the repo's main branch via `git rev-parse --abbrev-ref origin/HEAD 2>/dev/null` (typical
   output: `origin/main`); fallback to `main` if that's empty.

6. **Create the branch.**
   - Without `--worktree`: `git checkout -b <branch> <base-ref>`. This both creates the branch
     and switches to it.
   - With `--worktree`: `git branch <branch> <base-ref>` (create without checkout — the branch
     must exist before `git worktree add` can use it).
   - If the branch already exists, refuse with FM-2.

7. **If `--worktree`:** compute the worktree path as `<worktree_root>/<repo>-<slug>` (with
   `<slug>` including `-<iter>` if applicable), substituting `worktree_root` and
   `worktree_name_pattern` from `project.yml.ssd.*` (defaults: `../` and `{repo}-{slug}`).
   Resolve relative `worktree_root` against the **main repo's** root (`git rev-parse
   --path-format=absolute --git-common-dir` then take its parent — see § "The SSD Artifact
   Tree" worktree note; falls back to `realpath "$(git rev-parse --git-common-dir)"` on
   git < 2.31). Run `git worktree add <path> <branch>`. If the path already exists on disk,
   refuse with FM-4. Record the absolute worktree path in the workstream entry's `worktree:`
   field.

8. **Seed the brief stub.** Write a placeholder `00-brief.md` (flat) or `brief.md` (iteration)
   at the appropriate path, with required frontmatter (`skill`, `version`, `produced_at`,
   `produced_by`, `project`, `scope`, `consumed_by: [architect, coder, code-reviewer]`) and a
   `# Brief — <slug>` heading. The user fills in the body.

9. **Append to `current.yml.active[]`** with:
   ```yaml
   - slug: <slug>
     phase: brief
     iteration: <iter> | null
     started: <now>
     last_touched: <now>
     budget_hours: 8                # default; user adjusts
     elapsed_hours: 0
     gate_rounds: 0
     rail_deviations: []            # populated if --allow-dirty fired in step 4
     blockers: []
     branch: <name>
     worktree: <abs-path or null>
     touches: []
   ```

10. **Initialize `current.notes.yml.features.<slug>`** (or extend existing) with an empty
    `handoff_notes:` block. Don't overwrite if the slug already has notes from a prior
    iteration.

11. **Emit summary** to the user:
    - Branch created: `<branch>` off `<base-ref>`.
    - Worktree path (if any): `<path>` plus a literal `cd <path>` line the user must run.
    - Next-step proposal: typically `/ssd design <slug>[#<iter>]` (or just `architect <slug>`
      for skills-library-style markdown projects per § "/ssd design" Skip clause).

**Failure modes:**

- **FM-1: dirty working tree.** Trigger: `git status --porcelain` non-empty in step 4. Refusal
  message: `"working tree has uncommitted changes; stash or commit, or use --allow-dirty."`
  Bypass: `--allow-dirty` (records a `rail_deviations` entry).
- **FM-2: branch already exists.** Trigger: `git rev-parse --verify <branch>` succeeds in
  step 6. Refusal message: `"branch <branch> already exists; use --branch <other-name>."`
  No bypass — refusing to silently switch to an existing branch is intentional.
- **FM-3: slug or (slug,iteration) collision.** Trigger: matching entry already in
  `current.yml.active[]` in step 1. Refusal message names the collision.
- **FM-4: worktree path collision.** Trigger: `<path>` exists on disk in step 7. Refusal
  message prints the colliding path; user adjusts `project.yml.ssd.worktree_root` or
  `worktree_name_pattern`.
- **FM-11: brief file already exists.** Trigger: `00-brief.md` exists for a non-iteration
  workstream that the user is trying to register as new. Refusal: this is almost certainly
  a state-file desync; tell the user to either delete the brief or add the existing feature
  to `current.yml.active[]` manually.
- **FM-12: iteration ID collision within a feature.** Trigger: `iterations/<iter>/` exists.
  Refusal message names the colliding iter ID.

**Side effects (in order):**
1. New git branch (and optionally new worktree dir).
2. New `.ssd/features/<slug>/00-brief.md` (flat) or `.ssd/features/<slug>/iterations/<iter>/brief.md` (iteration).
3. New entry in `current.yml.active[]`.
4. New (or extended) section in `current.notes.yml.features.<slug>`.

**Partial-failure recovery.** If any of steps 6–10 fails after a prior step's mutation
succeeded (e.g., disk full mid-`git worktree add`, permission denied on the brief write, file
lock on `current.yml`), the orchestrator (a) does NOT continue with subsequent steps, (b) emits
an explicit summary of what state exists vs. what's missing, and (c) suggests the recovery
action — typically: `git branch -D <branch>` to undo step 6, `git worktree remove <path>` to
undo step 7, `rm <brief-path>` to undo step 8. The orchestrator does NOT auto-rollback because
a partial failure often indicates a deeper resource issue (disk full, permissions) that
rollback could compound. Auto-rollback would also mask the underlying problem.

### `/ssd switch <slug>[#<iter>] [--no-note | --auto-note | --allow-dirty]`

**Purpose:** pause the current workstream (capturing a handoff note), then resume the target
workstream by checking out its branch (or `cd`ing into its worktree).

**Behavior (validate-all-first, then mutate):**

1. **Identify the current workstream.** Run § "/ssd (no-arg) — Auto-Detect" Step 0:
   - If a current workstream resolves (exact match on `branch:` or pattern match), call it
     `source`.
   - If no current workstream resolves (detached HEAD, no match), `source` is `null`; skip
     the handoff capture in step 4 and log: `"no source workstream resolved; switching
     without a handoff capture."`

2. **Validate target workstream exists.** Parse `<slug>[#<iter>]`. Look up in
   `current.yml.active[]`. No match → FM-5 (refuse now, before any mutation). Match → call it
   `target`.

3. **Validate switch safety (no mutations yet):**
   - If `target.worktree` is null (will check out in current tree):
     - Check `git status --porcelain`. Non-empty → refuse with FM-6 unless `--allow-dirty`.
     - Verify `target.branch` exists locally: `git rev-parse --verify <target.branch>`.
       Failure → FM-7.
   - If `target.worktree: <path>`:
     - Verify `<path>` exists on disk. Missing → FM-10 (worktree dir gone); recover via
       `/ssd worktree <slug> remove --path <path>` then `/ssd worktree <slug> add` or
       refuse and tell the user.
     - Verify the worktree's HEAD matches the recorded branch:
       `git -C <path> symbolic-ref --short HEAD` returns `target.branch`. Mismatch →
       FM-14 (worktree-branch drift); the user manually checked out a different branch
       inside the worktree.

   All validations pass → proceed to mutating steps 4–6. If any validation fails, NO state
   change occurs (handoff note not written, no `last_touched` update, no `rail_deviations`
   entry).

4. **Capture handoff note for source** (only if `source` is non-null). Behavior depends on:
   - `--no-note` set, OR `project.yml.ssd.switch_note_default: skip`: skip capture entirely;
     existing `handoff_notes:` is preserved untouched.
   - `--auto-note` set, OR `switch_note_default: auto`: orchestrator drafts a 2–4-line note
     from recent activity (last few tool calls / recent git diff / current architect or coder
     status) and writes it to
     `current.notes.yml.features.<source-slug>.handoff_notes`, overwriting any existing note.
   - Default behavior — used when either (a) `project.yml.ssd.switch_note_default: prompt`
     is set explicitly, or (b) `switch_note_default` is unset AND `developer_profile` is
     `novice` or `standard` (per § "Profile-aware defaults" table's `switch_note_default`
     column). The orchestrator drafts a 2–4-line note from recent activity, then **blocks**
     waiting for a binding user choice (use `AskUserQuestion` with three options, or the
     conversational-surface equivalent — narrate-without-blocking is insufficient):
     **save** (accept draft as-is), **edit** (user provides replacement text), **skip**
     (don't write). Write to `current.notes.yml.features.<source-slug>.handoff_notes` per
     the chosen option.

5. **Execute the switch:**
   - **`target.worktree: <path>` (worktree):** the orchestrator cannot `cd` for the user (the
     shell context doesn't cross the tool boundary). Emit a clear summary including a literal
     `cd <path>` line as the LAST line of output. Do NOT run `git checkout` (the target lives
     in its own worktree).
   - **`target.worktree: null` (same tree):** run `git checkout <target.branch>`. This is
     guaranteed safe because step 3 verified the branch exists and the working tree is clean
     (or `--allow-dirty` was set, in which case proceed and accept the risk).

6. **Update workstream state.** Only after step 5 succeeds:
   - `current.yml.active[<target>].last_touched = <now>`.
   - If `--allow-dirty` triggered in step 3: append a `rail_deviations` entry on `source`
     (not `target`) with `{step: "switch", reason: "dirty-tree", ts: <now>}`.

7. **Render starting context for target.** Print:
   - The most recent artifact path under `.ssd/features/<slug>/` (or `iterations/<iter>/`).
   - The `current.notes.yml.features.<slug>.handoff_notes` content as a quoted block.
   - The workstream's `phase:` and the proposed next command per the no-arg auto-detect
     decision tree.

**Failure modes:**

- **FM-5: target slug not in active list.** Refusal message + list of active slugs +
  suggestion to use `/ssd feature new`.
- **FM-6: dirty tree on same-tree switch.** Refusal message: `"working tree has uncommitted
  changes; commit, stash, or use --allow-dirty."` Bypass: `--allow-dirty` (records deviation).
- **FM-7: target branch doesn't exist locally.** Refusal message names the branch and provides
  recovery options (`git branch <branch> <ref>` to recreate, or `/ssd workstream set-branch`
  deferred to iter D).
- **FM-10: target worktree directory missing on disk.** Trigger: `target.worktree: <path>`
  recorded but the path doesn't exist (user `rm`'d the directory). Refuse with: `"workstream
  <slug>'s worktree at <path> is gone; run /ssd worktree <slug> remove to clear the stale
  reference, then /ssd worktree <slug> add to recreate."` Does not auto-recover (the recovery
  might mask other intent — e.g., the user moved the worktree).
- **FM-14: worktree-branch drift.** Trigger: `target.worktree: <path>` exists on disk but its
  HEAD doesn't match `target.branch` (user manually checked out a different branch inside the
  worktree). Refuse with: `"workstream <slug>'s recorded branch is <recorded>, but the
  worktree at <path> is currently on <actual>. Either run \`git -C <path> checkout <recorded>\`
  to restore the worktree, or (when /ssd workstream set-branch ships in iter D) update the
  recorded branch to match."` Does not auto-update the recorded branch — silently rewriting
  state on drift would hide the user's manual change.

**Side effects** (all conditional, no mutation if step 3 validation failed):
1. Possibly: handoff-note write to `current.notes.yml.features.<source-slug>` (depends on
   step 4 choice).
2. Possibly: `git checkout <target.branch>` on the current tree (same-tree switch only).
3. `current.yml.active[<target>].last_touched` updated to `<now>`.
4. If `--allow-dirty` triggered in step 3: one `rail_deviations` entry on `source`.

### `/ssd worktree <slug>[#<iter>] add|remove [--path <path>]`

**Purpose:** explicit worktree lifecycle for a workstream, decoupled from `/ssd feature new`.

**`add` behavior:**

1. **Validate target.** Resolve `<slug>[#<iter>]` in `current.yml.active[]`. Refuse with FM-5
   if not found.
2. **Validate workstream doesn't already have a worktree.** Refuse with FM-8 if
   `worktree: <path>` is non-null.
3. **Resolve worktree path.** Use `--path <path>` if given. Otherwise apply
   `worktree_root` + `worktree_name_pattern` per `/ssd feature new` step 7.
4. **Refuse if path already exists on disk** (FM-4).
5. **Create the worktree:** `git worktree add <path> <branch>` where `<branch>` is the
   workstream's recorded `branch:` field.
6. **Update workstream entry:** `current.yml.active[<slug>].worktree = <abs-path>`.
7. **Emit summary** with the path and a literal `cd <path>` line.

**`remove` behavior:**

1. **Validate target.** Same as `add` step 1.
2. **Validate workstream has a worktree.** Refuse with FM-13 if `worktree:` is null —
   nothing to remove.
3. **Check worktree path on disk:**
   - **Path exists, working tree dirty:** refuse with FM-9 unless `--allow-dirty` (which is
     dangerous here — uncommitted work in the worktree gets thrown out). Default refusal.
   - **Path exists, working tree clean:** `git worktree remove <path>`.
   - **Path doesn't exist on disk** (user deleted it manually): run `git worktree prune` to
     clear administrative state, log a non-error warning, then proceed to step 4.
4. **Update workstream entry:** `current.yml.active[<slug>].worktree = null`.
5. **Note:** the branch is NOT deleted by `worktree remove`. The branch remains for use in
   the main checkout via `git checkout <branch>`.

**Failure modes:**

- **FM-8: workstream already has a worktree.** Refusal: `"workstream <slug> already has
  worktree at <path>; use /ssd worktree <slug> remove first."`
- **FM-9: dirty worktree on remove.** Refusal: `"worktree at <path> has uncommitted changes;
  commit or stash, or use --allow-dirty (will discard)."`
- **FM-13: workstream has no worktree to remove.** Refusal: `"workstream <slug> has no
  worktree (worktree: null); nothing to remove."`

**Side effects (`add`):**
1. New git worktree at `<path>`.
2. `current.yml.active[<slug>].worktree` set.

**Side effects (`remove`):**
1. Git worktree dir removed (or pruned if missing).
2. `current.yml.active[<slug>].worktree` cleared to null.

### Self-verification for the LLM executing any of these commands

Before reporting completion, the orchestrator must verify:

1. Every failure-mode check named above was actually run (not skipped).
2. Every git invocation matched the documented command verbatim (no improvised flags).
3. `current.yml` and `current.notes.yml` writes are atomic (write to a temp file + rename, OR
   prepare the full new content in memory before writing — never partial-write).
4. For `/ssd switch`: the dirty-tree check ran BEFORE any state mutation. A failure in step 5
   (checkout) must not leave the handoff note written without the switch having succeeded —
   if step 5 fails post-handoff-write, the orchestrator must roll back the handoff note
   write or surface the inconsistency to the user.

---

## Developer Profile + Teaching Mode

Two audiences use SSD: newcomers who want the system to decide for them, and experienced
engineers who want every step explicit. The `developer_profile` field in `.ssd/project.yml`
adjusts defaults without forking the product. See
[ADR-0004](../docs/decisions/ADR-0004-developer-profile-and-teaching-mode.md) for the rationale.

### Profile values

```yaml
# .ssd/project.yml
developer_profile: novice | standard | expert    # default: standard
teaching_mode:
  enabled: true|false                            # auto-true for first 5 invocations
  invocations_remaining: <int>                   # decay counter; default 5
```

**Profile is a hint, not a gate.** A novice can always invoke any command an expert can; the
orchestrator only adjusts defaults (confirmations, narration verbosity, prompt-for-or-skip).
Discoverability via `/ssd --explain "<intent>"`, never gatekeeping.

### Profile-aware defaults

| Profile | Default surface | Phase commands | Confirmations | Narration | YAML editing | `switch_note_default` |
|---|---|---|---|---|---|---|
| novice   | conversational | rejected with hint | yes, on irreversible steps | full | discouraged (`current.notes.yml` only) | `prompt` |
| standard | conversational | accepted           | only on destructive ops      | concise | allowed | `prompt` |
| expert   | command (or conversational, user choice) | accepted | none | minimal | expected | `auto` |

The `switch_note_default` column (added v1.15.0, [ADR-0007](../docs/decisions/ADR-0007-parallel-features.md))
controls the handoff-note capture behavior of `/ssd switch <slug>` (iteration B). The per-profile
default can be overridden in `.ssd/project.yml.ssd.switch_note_default` (values: `prompt | auto | skip`).

### Profile-aware sub-skill behavior

The table above is the **orchestrator's** profile knobs. The sub-skills are profile-aware only where
profile changes output *substance* (which markers, findings, voices, or checklist items are
produced) — never mere tone, which stays the orchestrator's job. See
[ADR-0010](../docs/decisions/ADR-0010-profile-aware-subskills.md) for the boundary rule. This table
is the single source of truth; each sub-skill's SKILL.md points back here.

**How a sub-skill learns the profile:** when the orchestrator invokes a profile-aware sub-skill, it
states the active `developer_profile` (read from `.ssd/project.yml`) in the invocation context. This
is a prose contract, like the rest of the methodology — there is no separate machine parameter. A
sub-skill invoked ad hoc (outside the orchestrator) defaults to `standard` behavior.

| Sub-skill | novice | standard (baseline) | expert |
|---|---|---|---|
| `architect` | *profile-invariant* — design rigor is absolute | *(unchanged)* | *(unchanged)* |
| `methodology` | *profile-invariant* — `/methodology score` is an absolute metric | *(unchanged)* | *(unchanged)* |
| `refactor` | *profile-invariant* — the refactor plan is substance; verbosity is the orchestrator's | *(unchanged)* | *(unchanged)* |
| `systems-designer` | full annotated checklist — every item + the "why" | standard checklist | terse: core items only |
| `coder` | more `# REVIEW:` markers — flag every uncertainty | markers on genuine uncertainties | minimal — only blocking unknowns |
| `code-reviewer` | MINOR **and** NIT reported inline (teaching) | MINOR inline, NIT summarized | MINOR/NIT summarized; focus on BLOCKER/MAJOR |
| `codebase-skeptic` | focused voice subset (≤4 most relevant) | relevant voices (today's behavior) | all relevant voices |

**Invariant guarantee (normative).** Profile tunes *teaching breadth*, never correctness. A
`code-reviewer` BLOCKER/MAJOR and a `codebase-skeptic` 💀/🔴 finding surface at **every** profile,
the `gate_pass` computation is profile-independent, `systems-designer` safety-critical gates
(rollback, migration safety, observability) apply at every profile, and `coder` halts handoff on a
genuine blocker at every profile. `standard` behavior is unchanged from pre-v1.20.0 — `novice` and
`expert` are deltas around it. A future skill declares its profile
stance (invariant or which knob) at creation, the same way it declares a priority rule in
§ "Resolving Skill Overlap".

### Teaching mode

When enabled, the orchestrator appends a one-line *"under the hood: I called `architect` because
we're at phase=design"* to every conversational turn. `teaching_mode.invocations_remaining`
decrements per turn; at 0, teaching mode disables itself.

- `/ssd --teach` re-enables (resets counter to 5).
- `/ssd --no-teach` disables permanently for this project.
- Auto-promotion: a successful command-surface invocation while on `novice` triggers a one-time
  prompt to switch to `standard`; >2 manual edits to `current.yml` while on `standard` triggers a
  one-time prompt to switch to `expert`. Each prompt asks at most once per project; decay is
  permanent.

### Bridge flags

Either surface can reveal the other:

| Flag | Surface | Effect |
|---|---|---|
| `--explain` | conversational | Dry-run; emit the exact command sequence the orchestrator would invoke. |
| `--narrate` | command | Emit the conversational summary alongside structured output (good for CI logs). |
| `--raw` | conversational | Dump raw `current.yml` instead of the 3-sentence summary. |
| `--teach` | both | Re-enable teaching mode (resets counter). |

No surface hides anything from the other. No commands exist only in one surface. No state lives
only in one surface.

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
    │       ├── 00-brief.md              # User's original brief (epic-level for multi-iter)
    │       ├── 01-architect.md          # architect spec (epic-level for multi-iter)
    │       ├── 02-systems-designer.md   # production readiness (epic-level for multi-iter)
    │       ├── 03-coder-status.md       # — single-cycle features only
    │       ├── 04-code-review.md        # — single-cycle features only
    │       ├── 05-deploy.md             # — single-cycle features only
    │       └── iterations/              # — multi-iteration features only (opt-in, see ADR-0001)
    │           └── <iter-id>/           # e.g., 3a, 3b, auth-flow
    │               ├── brief.md
    │               ├── coder-status.md
    │               ├── code-review/     # multi-round gates (round-N.md from iter 3 / P1.2)
    │               ├── deferred.yml     # carry-over ledger (iter 4 / P1.5)
    │               └── deploy.md
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

**Selective commit split (v1.18.0+, [ADR-0008](../docs/decisions/ADR-0008-ssd-commit-split.md)).**
Artifacts under `.ssd/` divide along durable-vs-working lines:

| Path / pattern | Committed? | Why |
|---|---|---|
| `.ssd/features/<slug>/00-brief.md`, `01-architect.md`, `02-systems-designer.md`, `03-coder-status.md`, `04-code-review*.md`, `05-deploy.md` | ✅ committed | Durable design records, same class as ADRs |
| `.ssd/features/<slug>/iterations/<iter>/{brief,coder-status,deploy}.md`, `code-review/round-*.md` | ✅ committed | Same — per-iteration variants of the above |
| `.ssd/features/<slug>/iterations/<iter>/deferred.yml` | ❌ gitignored | Machine-managed carry-over ledger |
| `.ssd/milestones/<topic>/{skeptic-before,skeptic-after,refactor-plan,refactor-prs,verification}.md` | ✅ committed | Durable milestone records |
| `.ssd/milestones/<topic>/{sha-before,metrics-before.yml}` | ❌ gitignored | Snapshot machinery, not design docs |
| `.ssd/current.yml`, `.ssd/current.notes.yml`, `.ssd/init-log.md`, `.ssd/project.yml` | ❌ gitignored | Machine-managed state with absolute paths, per-user profile, draft handoff notes |
| `.ssd/archive/` | ❌ gitignored | Historical state of closed workstreams (their durable artifacts stay tracked in `features/<slug>/`) |
| `.ssd/audits/` | ❌ gitignored | Often sensitive — vendor names, internal opinions |

The gitignore pattern, the `no-leaky-state` gate rule (§ "Methodology Enforcement"), and the
optional pre-commit hook all share the same deny-list — they're symmetric layered defenses
around the same boundary. A solo developer who prefers the legacy v1.3.0–v1.17.x blanket
behavior sets `project.yml.ssd.gitignore_mode: blanket` and replaces the selective `.gitignore`
pattern with a bare `.ssd/` line; the `no-leaky-state` rule then SKIPs cleanly.

**Worktree note (v1.15.0, [ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)):** a workstream
with a non-null `worktree:` field has its *working tree* (source files, in-progress edits) at the
recorded sibling path — but the authoritative `.ssd/` directory remains at the main repo checkout.
`current.yml`, `current.notes.yml`, and the `features/<slug>/` artifact tree are read and written
only in the main checkout; linked worktrees share the git index but not the `.ssd/` working files
(`.ssd/` is gitignored). Sub-skills invoked from a linked worktree resolve the main checkout's
path via `git rev-parse --path-format=absolute --git-common-dir` (then take the parent directory)
before touching `.ssd/`. **Requires git 2.31+** (the `--path-format` flag was added in March
2021); on older git, fall back to `realpath "$(git rev-parse --git-common-dir)"` which works
back to git 2.5+ but requires a `realpath` binary (GNU coreutils or BSD/macOS native). The
iteration-B `worktree` and `switch` commands carry this fallback in their git-shell-out helper.

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

## Iterations Inside a Feature

A "feature" defaults to a one-cycle workstream (one design → one build → one review → one deploy).
Real features sometimes ship as multiple iterations — `phase3-ui#3a`, `#3b`, `#3c` — each with its
own brief, code, review, and deploy. As of v1.5.0, this is a first-class concept rather than a
filename convention. See [ADR-0001](../docs/decisions/ADR-0001-iterations-as-schema-substrate.md).

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

See [ADR-0002](../docs/decisions/ADR-0002-current-yml-split.md) for the rationale on splitting these.

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
archived: []
```

The `iteration`, `gate_rounds`, and `rail_deviations` fields are nullable / default-empty placeholders
populated by later iterations of the SSD-upgrades epic (P1.1, P1.2, P2.A). They are present in v2 from
the start so v2 ships forward-compatible — no second schema bump when those iterations land.

The `branch`, `worktree`, and `touches` fields (v1.15.0) are optional additive extensions per
[ADR-0007](../docs/decisions/ADR-0007-parallel-features.md). Existing v2 `current.yml` files
without these fields continue to parse and behave identically. When the orchestrator next touches
an active entry whose `branch:` is absent, it lazily backfills `branch:` with the current
checkout's branch — but only when **both** guards hold: (a) exactly one active workstream has
no recorded `branch:` (no guess on multi-ambiguity), and (b) the current branch plausibly
corresponds to that workstream, i.e., the branch is the result of `branch_pattern` substituted
with the workstream's slug (default: `add-<slug>`). The second guard prevents incorrect backfill
when the user is checked out on an unrelated branch (a debug/experiment/hotfix branch). If
either guard fails, the orchestrator leaves `branch:` absent and prompts the user the next time
disambiguation matters.

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

## Methodology Enforcement (runs on /ssd gate)

Before `/ssd gate` passes, the orchestrator invokes the executable gate-rules script and refuses to
pass on any FAIL:

```bash
bash methodology/gate-rules.sh --base <base-branch> --json
```

The script (defined in `methodology/SKILL.md` § "Gate Rules — Executable") emits structured results
per rule. Each rule maps to a principle in `methodology/core.md`.

| Rule (script) | Doctrine cite | What it checks |
|---|---|---|
| `wip-commits` | core.md §4 | `git log <base>..HEAD --grep='WIP\|checkpoint\|TODO.*tomorrow\|FIXME.*later' -i` is empty |
| `tests-pass` | core.md §1 | Project's `test_command` (from `.ssd/project.yml`) exits 0 |
| `feature-flag-present` | core.md §3 | Project's `feature_flag_marker` appears in non-doc changed files (skipped for documentation/config-only diffs) |
| `adr-delta` | core.md §2 | If architectural diff > 200 lines outside test/doc/migration scope, `docs/decisions/` has a new or modified ADR |
| `frontmatter-valid` | ADR-0006 | Every changed `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md` artifact validates against its skill schema (via `methodology/frontmatter-validate.py`) |
| `no-leaky-state` | [ADR-0008](../docs/decisions/ADR-0008-ssd-commit-split.md) | No file matching the `.ssd/` selective-commit deny-list (machine state: `current.yml`, `init-log.md`, `archive/`, `audits/`, etc., plus project-supplied `project.yml.ssd.gitignored_state`) appears in the diff. Catches force-add and edited-gitignore bypasses. SKIPs cleanly on `gitignore_mode: blanket` projects. |
| `skill-version-sync` | core.md §2 | Each `<project-root>/*/SKILL.md`'s required-frontmatter example `version:` matches that file's `**Version:**` banner (via `frontmatter-validate.py --check-skill-examples`). SKIPs files using a placeholder example or projects with no in-repo SKILL.md example blocks. |

Rule outputs:
- `PASS` — rule applied and verified.
- `SKIP` — rule didn't apply (no test command in `project.yml`, no diff vs base, doc-only change, etc.).
- `FAIL` — rule applied and was violated.

The script exits non-zero on any FAIL. The orchestrator parses the structured output, names the
failing rule with its doctrine cite, and refuses to pass the gate.

"I know better" is not an override — use `/ssd ship --force` (logged) if the team has a deliberate
exception. Direct invocation of the script is supported for CI:

```bash
bash methodology/gate-rules.sh --base main           # text mode
bash methodology/gate-rules.sh --base main --json    # JSON for jq / CI parsing
```

See [ADR-0005](../docs/decisions/ADR-0005-gate-execution-model.md) for why this is a bash script
rather than orchestrator-internal LLM checks.

**Cross-workstream overlap check (v1.17.0+).** When `/ssd gate` runs on a workstream that has
peers in `current.yml.active[]`, the orchestrator additionally (a) updates the gated workstream's
`touches:` by unioning `git diff --name-only <base>...HEAD` into the recorded list, and (b)
invokes `code-reviewer` which consults the peers' `touches:` fields and emits informational
OVERLAP-N findings (SUGGESTION tier) for any file-set intersections. The gate is NOT blocked
by overlap. See [`code-reviewer/SKILL.md`](../code-reviewer/SKILL.md) § "Cross-Workstream Overlap
Check" for the full algorithm and [ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)
for the design rationale.

**Workstream-aware base detection (v1.17.0).** The default `--base main` for `gate-rules.sh`
is kept by design — the script remains standalone and CI-friendly. The orchestrator, when
invoking the script on behalf of a workstream, passes `--base <ref>` explicitly (typically
`origin/main`). Future iteration D's `/ssd workstream` commands may introduce a `base:` field
on the workstream entry; until then the orchestrator computes the appropriate base from the
git context.

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
unless the skill's "When NOT to use" clause disqualifies it. There are **7 known overlap pairs**.
The first three are *substitution* pairs (one skill replaces the other for a request); the last
four are *coordination* pairs (both skills run, but in a fixed order or role, never competing).
Skill A / Skill B below name the two skills; the rule says how they relate.

| Skill A | Skill B | Priority / coordination rule |
|---|---|---|
| `coder` | `python-django-coder` (when present) | If language = Python AND framework = Django, use `python-django-coder`. Otherwise use `coder`. |
| `code-reviewer` | `codebase-skeptic` | `code-reviewer` for PR-level review (≤500 changed lines). `codebase-skeptic` for milestone/architectural review. Never chain both on the same scope. |
| `codebase-skeptic` | `software-standards` | `codebase-skeptic` for continuous stewardship of an owned codebase. `software-standards` for vendor selection / legacy onboarding / pre-acquisition evaluation. Mutually exclusive. |
| `refactor` | `code-reviewer` | Coordination, not substitution. During `/ssd milestone` step 3, `refactor` *produces* the plan and `code-reviewer` *validates* each refactor PR (`remediation_mode: true` triggers Phase 1.5). `refactor` never reviews; `code-reviewer` never plans. A refactor item that no PR closes is surfaced by the milestone playbook ("no cite → not in scope"), not by either skill. |
| `architect` | `systems-designer` | Coordination. In `/ssd design`, `architect` runs first (models, APIs, ADRs); `systems-designer` runs second and is **purely additive** (failure modes, observability, deploy safety). Never substitute one for the other. `systems-designer` is N/A for markdown / docs-only projects, where `architect` runs alone. |
| `methodology` | (all skills) | Reference-tier. `methodology` supplies doctrine + the `/methodology score` self-adherence metric; it is rarely invoked directly in a feature loop. When another skill's behavior is in question, prefer that skill; consult `methodology` only for doctrine adjudication. |
| `codebase-skeptic` | `refactor` | Producer → consumer. In `/ssd milestone` / `/ssd verify`, `codebase-skeptic` *produces* findings (`skeptic-before.md` / `skeptic-after.md`) and `refactor` *consumes* them into a plan. Never the reverse — don't ask `refactor` to audit or `codebase-skeptic` to plan fixes. |

Each *substitution*-pair skill MUST have a "When NOT to use" section naming the other skill(s) and the priority
rule. The orchestrator reads these to decide which skill to invoke when the user's request is
ambiguous. A new skill added alongside an existing one must declare a priority rule at creation — a
skill without a declared priority cannot be promoted past draft.

---

## Changelog

- **1.20.0** (2026-06-13) — Feature ssd-profile-audit (refactor R9; closes the deferred 🔴 P2 +
  F2 from the post-v1.19 milestone). New § "Profile-aware sub-skill behavior" table (single source
  of truth) + normative invariant guarantee, governed by
  [ADR-0010](../docs/decisions/ADR-0010-profile-aware-subskills.md): a sub-skill branches on
  `developer_profile` only when profile changes output *substance*, never tone, and never suppresses
  gate-critical output. 3 skills invariant (architect, methodology, refactor); 4 profile-aware
  (systems-designer checklist depth, coder REVIEW-marker density, code-reviewer MINOR/NIT reporting,
  codebase-skeptic voice breadth). `standard` is the unchanged baseline.
- **1.19.1** (2026-06-11) — Post-v1.19 milestone refactor (doc-tightening; cites
  [skeptic-before.md](../.ssd/milestones/2026-06-10-post-v1.19/skeptic-before.md)). Four doc
  refactors land here: **R5** expands § "Resolving Skill Overlap" from 3 to **7 pairs** (adds the
  four coordination pairs — refactor↔code-reviewer, architect↔systems-designer, methodology↔all,
  codebase-skeptic↔refactor); **R7** adds the banner-lag note (top of file) and a "Tag the release"
  step to § "/ssd ship"; **R8** adds § "Concurrency: one Claude session per project at a time" to
  § "Session Continuity", documenting the single-writer assumption and incident recovery. (R1 CI
  workflow, R2 tag backfill, and R3+R4 version-sync/`skill-version-sync` shipped earlier in the
  same milestone; see [ADR-0009](../docs/decisions/ADR-0009-skill-version-sync.md).)
- **1.18.0** (2026-05-24) — Iteration A of the ssd-commit-split epic
  ([ADR-0008](../docs/decisions/ADR-0008-ssd-commit-split.md)): selective `.ssd/` commit
  split. The blanket-gitignored `.ssd/` convention from v1.3.0–v1.17.x is replaced by a
  durable-vs-working split. Durable artifacts (briefs, architect specs, coder-status, code
  reviews, deploy notes, milestone records) get committed; machine state (`current.yml`,
  `project.yml`, `init-log.md`, `archive/`, `audits/`, snapshot machinery) stays local.
  Layered defenses enforce the boundary: (1) selective `.gitignore` pattern; (2) `ssd-init`
  writes / migrates the pattern with prompt + `.bak` backup, idempotent; (3) new
  `no-leaky-state` gate rule catches force-add and edited-gitignore bypasses. Two new
  `project.yml.ssd.*` keys: `gitignore_mode: selective|blanket` (default `selective` for new
  projects; existing projects on blanket get prompted to migrate), and `gitignored_state: []`
  (additive deny-list extensions — projects can extend, never shrink the baseline). New
  `--rules <comma-list>` arg on `gate-rules.sh` lets the iter-B pre-commit hook run only the
  `no-leaky-state` rule (the other rules are too slow for pre-commit). § "The SSD Artifact
  Tree" gains a committed-vs-gitignored table; § "Methodology Enforcement" gains a
  `no-leaky-state` row (and a `frontmatter-valid` row that was previously implicit).
- **1.17.1** (2026-05-24) — Documentation: canonical-reference banner pointing to
  [insanelygreat.com/ssd.html](https://insanelygreat.com/ssd.html); Purpose paragraph now names
  Alex Horovitz as originator and links the About page. No behavior change. Companion to
  `methodology/SKILL.md` 1.5.0, which refreshed and cross-linked the doctrine files.
- **1.17.0** (2026-05-24) — Iteration C of the parallel-features epic
  ([ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)): cross-workstream overlap
  detection at gate time. Makes iter A's `touches:` field load-bearing. The orchestrator now,
  during `/ssd gate`, (a) unions `git diff --name-only <base>...HEAD` into the gated
  workstream's recorded `touches:` list, and (b) invokes `code-reviewer` which consults peers'
  `touches:` fields and emits OVERLAP-N findings (SUGGESTION tier, never blocks) on
  cross-workstream file intersections. New § "Cross-Workstream Overlap Check" in
  `code-reviewer/SKILL.md` (v1.4.0 → v1.5.0) defines the algorithm and the `🔗 OVERLAP:`
  severity prefix. The `touches:` field schema comment in § "Session Continuity" updated to
  document the coder-pass backfill. § "Methodology Enforcement" gains a paragraph naming the
  overlap check as part of the gate. `methodology/gate-rules.sh` unchanged in default behavior
  — the orchestrator passes `--base <ref>` explicitly for non-main workstreams; future iter D
  may introduce a workstream-base field. With v1.17.0 the parallel-features epic is complete:
  iter A shipped schema (v1.15.0), iter B shipped commands (v1.16.0), iter C ships the overlap
  consumer (v1.17.0).
- **1.16.0** (2026-05-24) — Iteration B of the parallel-features epic
  ([ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)): the three new orchestrator
  commands fully documented. New § "Workstream Lifecycle Commands" between `/ssd ship` and
  Developer Profile, specifying:
  - `/ssd feature new <slug>[#<iter>] [--branch <name>] [--worktree] [--from <ref>] [--allow-dirty]`
    — branch + (optional) worktree + brief stub + `current.yml` entry in one step. Handles the
    `<slug>#<iter>` syntax (per § "Iterations Inside a Feature") to create iterations on existing
    or new features. Twelve numbered failure modes with refusal messages and bypass flags.
  - `/ssd switch <slug>[#<iter>] [--no-note | --auto-note | --allow-dirty]` — validates-all-first
    (target exists, branch resolvable, tree clean), captures handoff per
    `switch_note_default`/profile, then checks out / surfaces `cd <worktree>` instruction. Step-3
    validation guarantees no state mutation on failure.
  - `/ssd worktree <slug>[#<iter>] add|remove [--path <path>]` — explicit worktree lifecycle,
    decoupled from `feature new`. Handles missing-on-disk worktrees via `git worktree prune`.
  Plus: new cross-refs in `/ssd` (no-arg) Step 0 and the Invocation table to surface the
  commands. The new commands ship as v1.16.0; cross-workstream overlap detection at gate time
  (consumes the `touches:` field from iter A) ships in iteration C as v1.17.0.
- **1.15.0** (2026-05-21) — Iteration A of the parallel-features epic
  ([ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)): schema substrate +
  read-only branch→workstream auto-detection. Three new optional fields on
  `current.yml.active[]` — `branch:`, `worktree:`, `touches:` — fully backward-compatible
  with existing v2 files. Four new optional keys on `.ssd/project.yml.ssd` —
  `branch_pattern` (default `add-{slug}`), `worktree_root` (default `../`),
  `worktree_name_pattern` (default `{repo}-{slug}`), `switch_note_default`
  (`prompt|auto|skip`). `/ssd` (no-arg) gains a Step 0 that resolves the current branch
  to a specific active workstream via exact match against `branch:` or pattern match
  against `branch_pattern`, falling through to the existing decision tree on no-match.
  New artifact-tree footnote covers the worktree case (working tree at sibling path,
  authoritative `.ssd/` in main checkout). New orchestrator commands (`/ssd feature new`,
  `/ssd switch`, `/ssd worktree`) and cross-workstream overlap detection ship in
  iterations B (v1.16.0) and C (v1.17.0) respectively.
- **1.10.0** (2026-04-29) — Iteration 8 of the ssd-skill-upgrades epic (P2.B, ADR-0004):
  developer profile + teaching mode. New `developer_profile` field on `.ssd/project.yml`
  (`novice|standard|expert`); profile-aware defaults table; decaying teaching mode (default 5
  invocations); auto-promotion prompts (novice→standard on first command-surface call;
  standard→expert on 3+ manual `current.yml` edits); bridge flags (`--explain`, `--narrate`,
  `--raw`, `--teach`) so each surface can reveal the other. New "Developer Profile + Teaching
  Mode" section.
- **1.9.0** (2026-04-29) — Iteration 7 of the ssd-skill-upgrades epic (P2.A, ADR-0003): rails as
  a first-class artifact. New file `ssd/rails.md` (v1.0.0) documents the eight-step canonical
  sequence, the eight critic-grade invariants, the `rail_deviations` logging contract, and the
  surface-agnostic guarantee. New "The Rails" section in this SKILL.md cross-references it. The
  rails are forkable per-project via `project.yml.rails:`.
- **1.8.0** (2026-04-29) — Iteration 6 of the ssd-skill-upgrades epic (P1.3): no-arg `/ssd`
  auto-detection. The default invocation reads `.ssd/current.yml` + `.ssd/current.notes.yml`,
  surfaces active workstreams (with iteration, phase, last-touched, blockers), and proposes the
  next action by inspecting the latest artifact for each active workstream. Explicit phase
  commands remain as escape hatches. Never silently advances a phase — always proposes; user
  accepts or redirects. New "/ssd (no-arg) — Auto-Detect" section.
- **1.7.0** (2026-04-29) — Iteration 5 of the ssd-skill-upgrades epic (P1.4): bundled design pass.
  New `/ssd design <slug>` phase invokes `architect` and `systems-designer` back-to-back with
  shared inputs, producing both `01-architect.md` and `02-systems-designer.md` in one user-facing
  step. Individual invocations of either skill remain valid; `/ssd design` is a convenience and
  does not gate or change either skill's contract.
- **1.6.0** (2026-04-29) — Iteration 3 of the ssd-skill-upgrades epic (P1.2): multi-round gates as
  a built-in concept. `/ssd gate` (and the `/ssd feature` review step) auto-number rounds, write to
  round-N output paths (single-cycle vs multi-iteration), increment `current.yml.gate_rounds`, and
  require `closed_from_previous_round` discipline on round 2+ reviews. Inline round-2 updates
  remain an option for small remediations. See `code-reviewer/SKILL.md` § "Multi-Round Gates."
- **1.5.0** (2026-04-29) — Iteration 2 of the ssd-skill-upgrades epic (P1.1, ADR-0001):
  first-class iterations inside a feature. `<slug>#<iter-id>` syntax accepted on every phase
  command; opt-in `iterations/<iter-id>/` subdirectory under the feature root; flat single-cycle
  layout remains the default and continues to work unchanged. Resolution rules and promotion
  ergonomics documented in new "Iterations Inside a Feature" section. The `iteration` field added
  to `current.yml` v2 in iter 1 is now actively populated.
- **1.4.0** (2026-04-28) — Iteration 1 of the ssd-skill-upgrades epic landed:
  (a) `current.yml` v2 with schema validation + sidecar `current.notes.yml` for free-form context;
  legacy v1 read-path retained, opt-in prompted migration with `.bak` (P1.7, ADR-0002).
  (b) Methodology Enforcement table now points at the executable
  `methodology/gate-rules.sh` invoked synchronously on `/ssd gate`; rules emit
  `PASS|FAIL|SKIP` with a doctrine cite (P1.6, ADR-0005).
  Forward-compatible v2 schema includes nullable `iteration`, `gate_rounds`, `rail_deviations`
  fields populated by later iterations of the epic.
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
