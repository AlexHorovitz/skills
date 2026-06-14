<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

## Workstream Lifecycle Commands

(added v1.16.0, see [ADR-0007](../../docs/decisions/ADR-0007-parallel-features.md))

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

