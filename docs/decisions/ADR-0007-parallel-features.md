# ADR-0007: Parallel features as first-class workstream artifacts

## Status
Accepted — 2026-05-21 — landed in iteration A of the parallel-features epic ([01-architect.md](../../.ssd/features/parallel-features/01-architect.md)).

## Context

`.ssd/current.yml.active` has been a list since v1.4.0 ([ADR-0002](ADR-0002-current-yml-split.md)
formalized the v2 schema and confirmed the list shape), and `/ssd` (no-arg) auto-detect since
v1.8.0 (P1.3) has surfaced multiple active workstreams to the user.
The *schema* has supported parallel features for some time. The *operational ergonomics*
have not.

Today's failure modes, observed on this project's own usage and on athena's:

- One working tree → one branch → one feature edit at a time. Switching mid-flight
  requires `git stash` / `git checkout` / `git stash pop`. The friction is high enough
  that users serialize work by default — even when the schema would let them parallelize.
- Branch ↔ workstream mapping lives only in the user's head. The orchestrator reading
  `current.yml` can't tell which active workstream the current branch corresponds to,
  so multi-workstream sessions either guess or prompt.
- No "pause + switch" ergonomics. `current.notes.yml.features.<slug>.handoff_notes`
  exists, but there's no command that captures one before context-switching, so the
  field gets stale.
- No conflict awareness. Two features touching the same files don't surface that overlap
  until rebase time, often after both have invested code.
- No worktree lifecycle integration. A user who *does* want isolated working directories
  has to set them up by hand (`git worktree add ...`) and remember to clean them up.

Two design candidates surfaced:

- **Document the manual git workflow in SKILL.md and call it done.** Cheap. But the
  empirical evidence (14 versions of this library, zero observed parallel sessions) says
  documentation alone doesn't shift the behavior.
- **Promote branch + worktree + touched-files to first-class workstream fields and add
  three orchestrator commands.** Moderate cost, real ergonomic payoff.

## Decision

Promote three concerns to first-class workstream artifacts via additive schema changes
and three new orchestrator commands. **Iterate in three independently shippable steps**
(A: schema + ADR + read-only auto-detect; B: new commands; C: cross-workstream overlap
detection at gate time).

**Schema additions** to `.ssd/current.yml.active[]` (all optional, defaulted):

- `branch: <string>` — the git branch this workstream lives on.
- `worktree: <absolute-path-or-null>` — opt-in: where the workstream's working tree
  lives if it uses a separate worktree. `null` (default) means the main checkout.
- `touches: [<glob>, ...]` — file globs the workstream is known to modify. Populated
  in two passes: architect declares intent at design time; coder unions actual diff
  paths into the list at each gate cycle.

**Configuration additions** to `.ssd/project.yml.ssd`:

- `branch_pattern: "add-{slug}"` — default for `/ssd feature new`. Configurable but the
  orchestrator does not enforce it; it's a hint, not a gate.
- `worktree_root: "../"` — default parent directory for new worktrees, relative to
  repo root or absolute.
- `worktree_name_pattern: "{repo}-{slug}"` — default name for the worktree directory.
- `switch_note_default: prompt | auto | skip` — controls handoff-note capture behavior
  on `/ssd switch`. Profile-aware default: `novice` gets `prompt`, `expert` gets `auto`.

**New orchestrator commands** (ship in iteration B):

- `/ssd feature new <slug> [--branch <name>] [--worktree] [--from <ref>]` — creates the
  branch (and optional worktree), seeds the brief, registers the workstream in one step.
- `/ssd switch <slug> [--no-note | --auto-note]` — pauses the current workstream
  (captures handoff note per `switch_note_default`), checks out the target.
- `/ssd worktree <slug> add|remove [--path <path>]` — explicit worktree lifecycle,
  decoupled from `feature new`.

**Branch-name → slug auto-detection** (ships in iteration A, read-only): the orchestrator
on `/ssd` (no-arg) or `/ssd switch` resolves the current branch to a workstream by
(1) exact match against any `active[].branch`, falling back to (2) pattern-based match
via `branch_pattern` substitution, falling back to (3) prompting the user.

**Cross-workstream overlap detection** (ships in iteration C): at `/ssd gate` time, the
orchestrator intersects the gated workstream's `touches:` with every other active
workstream's `touches:`. Non-empty intersections surface as **SUGGESTION-tier** code
review findings (`OVERLAP-N`), never BLOCKER or MAJOR. The gate still passes; the user
gets a heads-up that a parallel workstream is editing overlapping files.

**Practical concurrency ceiling: 4 active workstreams per project.** Above 4 the
orchestrator emits a non-blocking advisory. No hard limit.

## Rationale

- **Additive schema beats a v3 bump.** The new fields are optional with defaults; an
  existing v2 `current.yml` without them parses and behaves identically. No migration
  tooling, no two-schema-version maintenance burden, no `current.yml.bak`.
- **Shell-out to git beats reimplementation.** `git worktree`, `git checkout`, and
  `git status --porcelain` are already on every Unix machine the audience uses. Failures
  surface as normal git errors; recovery uses normal git tooling. There is no orchestrator
  lock file, no daemon, no bespoke state machine to debug.
- **Soft warnings beat hard gates for overlap.** Overlap can be intentional (layered
  features, one workstream extends a file the other added). Forcing serialization
  defeats the purpose. The orchestrator surfaces; the user judges.
- **Convention over enforcement for branch names.** Defaulting to `add-{slug}` matches
  existing repo habits without forbidding alternatives. Teams with established conventions
  (`feature/foo`, GitFlow, etc.) set `branch_pattern` in `project.yml` and move on.
- **Opt-in worktrees.** Users on small, fast features shouldn't be forced into a
  multi-directory mental model. The single-tree workflow remains the default.
- **Hybrid handoff capture.** Purely automated drafts get stale or wrong; purely manual
  prompts get skipped under time pressure. The hybrid (draft + confirm) keeps friction
  low while making sloppy notes opt-in rather than default. Profile-aware default
  surfaces the right behavior for each audience without separate code paths.
- **Three iterations beats one big drop.** Each iteration is independently shippable
  and useful: iteration A alone (schema + auto-detect) reduces "which workstream am I
  on?" friction without introducing new commands. Iteration B alone (commands) handles
  branch creation and switching. Iteration C alone (overlap) catches collisions early.
  Shipping in order means each merge is reviewable.

## Consequences

**Easier:**
- Parallel work without the manual stash dance.
- Clear handoff state when stepping away from a workstream.
- Early warning when two features collide on the same files.
- `/ssd` (no-arg) on any branch resolves to the right workstream without prompting,
  reducing the per-invocation overhead.

**Harder:**
- Users must learn three new commands (iteration B). The conversational surface mitigates
  this — novices can describe intent ("start a new feature") and the orchestrator routes.
- Multi-worktree users juggle multiple shell `cd` contexts. The orchestrator cannot
  chdir on the user's behalf across the tool boundary; it always prints the `cd <path>`
  explicitly and the user runs it. Documented in SKILL.md as a known constraint.
- The `touches:` field can drift if the architect's design changes but the spec isn't
  updated. The coder-pass union keeps it broadly correct, but a stale spec produces
  stale warnings. Acceptable: overlap warnings fail open (empty intersection = no
  warning), so staleness produces false negatives, not false positives.

**What we give up:**
- A single source of truth for "what am I working on right now." With multiple
  workstreams, the current branch alone no longer disambiguates — the orchestrator
  cross-references `current.yml.active`. This is the unavoidable cost of parallel
  workflows. The alternative (one-branch-per-feature, no exceptions, ever) over-constrains
  realistic git usage.
- The implied invariant from earlier ADRs that one repo checkout corresponds to one
  workstream. Worktrees explicitly break this. Documented in iteration A's SKILL.md
  edits.

## Alternatives Rejected

- **No tooling, just documentation.** Document the manual git workflow in SKILL.md and
  call it done. Rejected: the empirical evidence shows documentation alone doesn't shift
  behavior. Fourteen versions of this library, zero observed parallel sessions on this
  project (despite the schema technically supporting it since v1.4.0).
- **Required worktree per workstream.** Force every active workstream into its own
  worktree. Rejected: too heavy for small or quick features. Punishes the simple case
  to make the complex case fractionally easier.
- **In-orchestrator branch protocol** (no git shell-out). Maintain workstream state in
  a custom YAML mapped to git via hooks. Rejected: reinvents git, fragile, no payoff.
  Every existing git tool (gh, lazygit, magit, IDE integrations) bypasses the protocol.
- **MAJOR-tier overlap warnings.** Block the gate on cross-workstream file overlap.
  Rejected: would block merges in exactly the cases where overlap is intentional. The
  orchestrator has no way to distinguish intentional from accidental overlap; the user
  always does.
- **`schema_version: 3` bump.** Treat the new fields as a breaking change. Rejected:
  the additions are strictly additive with backward-compat defaults. That's the precise
  case `schema_version` is supposed to preserve compatibility for. Bumping forces
  migration tooling for no semantic gain.
- **Branch-name convention enforcement.** Require the `branch_pattern` match for all
  workstream branches. Rejected: too prescriptive. Teams have legitimate conventions
  the orchestrator shouldn't override. Default + override + fall-through-to-prompt is
  the right trade-off.
- **Single all-or-nothing release.** Ship A + B + C as one PR. Rejected: each iteration
  is reviewable on its own and produces user-visible value on its own. Holding them all
  for a single merge makes the diff harder to review and delays the parts that already
  work.

## Future Compatibility

- The `branch`/`worktree`/`touches` fields remain optional in any future schema bump.
  Removing them would be a breaking change requiring `schema_version: 3`.
- The OVERLAP-N finding format (iteration C) follows the existing code-reviewer
  finding-tier ladder. New finding categories can be added under the same SUGGESTION
  tier without further schema work.
- A future `/ssd workstream adopt <slug> <branch>` command (claiming an existing branch
  as a workstream) and `/ssd workstream set-branch <slug> <branch>` (rename/repair)
  are deliberately deferred to "iteration D, only if real friction emerges." The
  current commands cover the common case.

## Scale Note

Designed for **up to 4 concurrent active workstreams per project per user**. Above 4
the orchestrator emits a non-blocking advisory; the cognitive overhead of more parallel
work typically exceeds the throughput benefit. The schema and commands handle more than
4 fine — the ceiling is doctrine, not technical limit.
