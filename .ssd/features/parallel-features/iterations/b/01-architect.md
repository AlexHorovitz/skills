---
skill: architect
version: 1.2.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features iteration B — orchestrator-command documentation
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: true               # inherited from epic-level 01-architect.md
  data_model: true                       # inherited (schema additions shipped in iter A)
  api_contract: true                     # this iteration refines the iter-A command contracts
  integration_contract: true             # inherited (git shell-outs)
  adrs: []                               # ADR-0007 covers all three iterations; no new ADR
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: inherited
quality_gate_pass: true
---

# Architect Spec — Iteration B (parallel-features)

## Status

This is a refinement-and-delta spec over the epic-level architect doc
([01-architect.md](../../01-architect.md)). All design decisions there remain in force. This
document only:

1. Confirms what iteration B implements vs. what iter A and iter C cover.
2. Resolves edge cases that emerged after iter A shipped (auto-detect for iteration-suffixed
   branches; `/ssd feature new` interaction with the iterations model from ADR-0001).
3. Specifies the exact prose conventions the coder must follow when writing the new SKILL.md
   command docs (so the LLM-driven orchestrator can execute the commands reliably).

No new ADRs. ADR-0007 covers iter A, B, and C.

## What iter B ships (binding scope)

| Component | Location | Iter A status | Iter B delta |
|---|---|---|---|
| `/ssd feature new` doc | `ssd/SKILL.md` new § "Workstream Lifecycle Commands" | designed | full prose spec |
| `/ssd switch` doc | same § | designed | full prose spec |
| `/ssd worktree` doc | same § | designed | full prose spec |
| `ssd-init` defaults write | `ssd-init/SKILL.md` Step 6 (project.yml write) | not touched | add 4 keys + concurrent-workstream note |
| Rails non-rail annotation | `ssd/rails.md` | not touched | one paragraph |
| Version bump | `VERSION`, `ssd/SKILL.md` banner, CHANGELOG | 1.15.0 | 1.16.0 |

## Edge cases resolved here

### EC-1: Branch naming for iterations

**Open in iter A spec.** Iter A's brief listed Open Q on branch naming convention for the
default workstream branch (`add-<slug>`). The brief did not address what to do when a feature
has multiple iterations.

**Resolution.** The default convention for an iteration's branch is `add-<slug>-<iter>` —
for example, `add-parallel-features-b`. This is documented as a convention, not enforced.
The orchestrator's auto-detect Step 0 already handles this case via the **exact match** path
(no two `active[].branch` values share the same string) — the **pattern match** fallback
(`branch_pattern` prefix-strip → slug lookup) doesn't need to recognize iteration suffixes,
because the active workstream entry's `branch:` field carries the full string.

**Documentation requirement.** SKILL.md's `/ssd feature new` doc must mention this convention
under its branch-resolution step. When the slug contains a `#<iter>` suffix (e.g.,
`/ssd feature new parallel-features#c`), the orchestrator substitutes `<slug>-<iter>` into
`branch_pattern` (yielding `add-parallel-features-c`) unless the user overrides with
`--branch <name>`.

### EC-2: `/ssd feature new` on an existing feature's new iteration

`/ssd feature new <slug>#<iter>` is **valid**. Behavior:

1. If the feature `<slug>` already exists in `.ssd/features/`:
   - If it's flat-layout: prompt to promote to multi-iter layout (per ADR-0001 promotion is
     non-destructive — flat artifacts stay where they are; only `iterations/<iter>/` is created).
   - If it's already multi-iter and `<iter>` doesn't exist: create `iterations/<iter>/`,
     register a new `active[]` entry for it, set `iteration: <iter>` field.
   - If `<iter>` already exists in `current.yml.active[]`: refuse with FM-3 (slug-iter
     collision).
2. The `current.yml.active[]` entry's `slug` field is the feature slug (no `#<iter>`); the
   `iteration:` field carries the iter ID. This matches iter A's schema.
3. The brief artifact lives at `.ssd/features/<slug>/iterations/<iter>/brief.md` (note: no
   `00-` prefix for iteration-nested briefs, per the existing convention from ssd-skill-upgrades
   iter A: epic-level `00-brief.md` at the feature root, iteration-level `brief.md` inside
   `iterations/<iter>/`).

### EC-3: `/ssd switch` and uncommitted-on-same-tree

Iter A's spec covered this (FM-6: dirty tree on same-tree switch refuses unless `--allow-dirty`).
Confirm: the coder must implement the dirty-tree check BEFORE attempting any state mutation. If
the user has uncommitted work and refuses `--allow-dirty`, the orchestrator must leave both
workstreams' state untouched (no half-applied handoff note write).

### EC-4: `/ssd switch` and detached HEAD

Not covered in iter A. Resolution: if the current branch is detached HEAD, the orchestrator
cannot identify the "source" workstream (Step 0 auto-detect returns None on detached HEAD).
Switch proceeds without capturing a handoff note for "source" — there is no source. Log a
warning that no handoff note was captured. Optional: the user may use `/ssd workstream
handoff <slug>` (deferred to iter D) to write one manually later.

### EC-5: `/ssd worktree remove` when worktree was deleted manually

Iter A's FM-10 specified: proceed with `git worktree prune`-equivalent. The coder must implement
this via `git worktree prune` (not `--force` — that would force-remove an existing dir; prune
only removes administrative state for missing worktrees). After prune, clear the workstream's
`worktree:` field to null and emit a non-error log line.

## Prose conventions for the new SKILL.md section

The coder must follow these conventions so the LLM-driven orchestrator can execute the commands
reliably.

### Convention 1: Each command is a contract, not a description

For each of the three new commands, the SKILL.md sub-section MUST include, in order:

1. **Signature line** with all args and flags.
2. **Purpose** (one sentence).
3. **Numbered behavior steps** that the orchestrator executes in order. Each step that involves
   git or filesystem mutation includes the exact command (e.g., `git checkout -b <branch>
   <base-ref>`).
4. **Failure modes** numbered FM-1, FM-2, …, each with: trigger condition, refusal message,
   suggested fix, bypass flag if any.
5. **Side-effect summary** at the end listing every file the command writes/modifies.

This is the same structure iter A's architect § "API Contract — New Orchestrator Commands"
already uses. Coder copies that structure verbatim into SKILL.md.

### Convention 2: Profile-aware behavior is explicit, not assumed

Where a command's default depends on `developer_profile`, the doc must say so explicitly with a
literal table reference, e.g., *"Default is `prompt` (novice/standard) or `auto` (expert) per
the Profile-aware defaults table in § 'Developer Profile + Teaching Mode.'"* This lets the LLM
execute the right behavior without re-deriving it from the profile table.

### Convention 3: All git shell-outs are explicit

Don't say "the orchestrator creates the branch." Say `git checkout -b <branch> <base-ref>` (or
the exact two-command variant for worktree-create). The LLM must run the exact commands; vague
verbs force re-derivation and risk drift.

### Convention 4: Cross-references to iter A's schema

Every reference to `current.yml.active[]` fields uses the exact field names from iter A's
schema additions (`branch`, `worktree`, `touches`). Same for the four `project.yml.ssd.*` knobs
(`branch_pattern`, `worktree_root`, `worktree_name_pattern`, `switch_note_default`).

### Convention 5: No iter-C functionality

The new SKILL.md prose must NOT reference cross-workstream overlap warnings, the `touches:`
diff backfill behavior on gate, or `gate-rules.sh` workstream-aware base detection. Those ship
in iter C. The field is recorded; consumption is deferred.

## Implementation breakdown for coder

### `ssd/SKILL.md` edits

**New section** (inserted between existing `/ssd ship` and "Developer Profile + Teaching Mode"
sections):

```
## Workstream Lifecycle Commands

(added v1.16.0, see ADR-0007 § "API Contract — New Orchestrator Commands")

These three commands manage parallel feature workstreams. They are independently invocable;
nothing else in the orchestrator depends on them. A user happy with single-feature flow never
needs them.

### `/ssd feature new <slug> [--branch <name>] [--worktree] [--from <ref>]`

[Full spec per Convention 1, ~70-100 lines]

### `/ssd switch <slug> [--no-note | --auto-note | --allow-dirty]`

[Full spec per Convention 1, ~80-110 lines]

### `/ssd worktree <slug> add|remove [--path <path>]`

[Full spec per Convention 1, ~60-80 lines]
```

**Cross-reference updates** (existing sections):

- `/ssd` (no-arg) — Auto-Detect § Step 0 closing paragraph: add "see § Workstream Lifecycle
  Commands for `/ssd feature new` and `/ssd switch` which write `branch:` directly."
- Invocation table at top of SKILL.md: add three new rows.
- Sub-Skill Reference table: no change (the new commands aren't sub-skills).

**Changelog entry**: v1.16.0 entry matching the tone/length of 1.10.0/1.15.0.

**Version banner**: 1.15.0 → 1.16.0.

### `ssd-init/SKILL.md` edits

**Step 6 — Detect Project Shape**, in the `.ssd/project.yml` write block (around line 255-272),
add the four new keys with defaults:

```yaml
ssd:
  version: 1.0.0
  initialized_at: <ISO-8601>
  artifact_root: .ssd/

  # Parallel-features defaults (v1.16.0, ADR-0007). Override per-project as needed.
  branch_pattern: "add-{slug}"
  worktree_root: "../"
  worktree_name_pattern: "{repo}-{slug}"
  switch_note_default: prompt    # novice/standard default; expert auto-detected from profile
```

**Workflow text addition** (after Step 6's existing write): one short paragraph noting
"`ssd-init` writes the four parallel-features defaults so the orchestrator can resolve
`/ssd feature new` / `/ssd switch` / `/ssd worktree` without prompting on each invocation. See
[ADR-0007](../docs/decisions/ADR-0007-parallel-features.md)."

**Version banner**: 1.5.0 → 1.6.0 (independent skill version bump).

### `ssd/rails.md` edits

One new paragraph under whichever section discusses non-rail workflow ergonomics (coder picks
the best fit; if unclear, add a new "Non-rail workflow commands" sub-section near the bottom):

> The `/ssd switch` and `/ssd worktree` commands (v1.16.0+) are intentionally non-rail. They
> manage workflow ergonomics — pause/resume of parallel workstreams, git worktree lifecycle —
> rather than methodology steps. A workstream using `/ssd switch` mid-iteration does not record
> a `rail_deviation` because pausing and resuming is not a rail step at all. The eight-step
> canonical sequence (brief → design → code → review → gate → deploy → rollout-advance →
> flag-removal) is per-workstream; the lifecycle commands operate on the workstream container,
> not its steps.

### `CHANGELOG.md` entry

v1.16.0 entry at top, matching v1.15.0's format. Sections: New commands (with brief description
of each), ssd-init / rails updates, no schema changes (iter A already shipped those), deferred
to iter C (the three iter-C items).

### `VERSION` bump

1.15.0 → 1.16.0.

## Iteration plan (intra-iter B)

Single cycle: brief → architect (this doc) → code → review → gate → ship. No sub-iterations
within iter B.

## Risk assessment (iter B specific)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| LLM executing `/ssd feature new` ambiguously interprets the prose and skips a step | M | M | Convention 1 (numbered steps with exact commands); coder includes a "Self-verification" block at the end of each command's section that the LLM reads before reporting completion |
| `/ssd switch` writes the handoff note then fails on git checkout, leaving the note overwritten | M | M | Convention requires dirty-check FIRST (FM-6) before any state mutation; coder makes this Step 1 not Step 3 |
| User runs `/ssd feature new foo#3a` on a flat-layout feature and is confused by promotion behavior | L | M | Convention 1 includes a "Prompts the user when …" line for each command's interactive behavior. Profile-aware: novice gets the prompt, expert may get `--promote` shorthand |
| EC-1 branch convention (`add-<slug>-<iter>`) is documented but not auto-derived by users | M | L | The orchestrator does the substitution; users just see the resulting branch name. Document explicitly so power-users know what to expect |
| `worktree prune` clears state when worktree dir is missing — but if the dir was simply moved (not deleted), this corrupts state | L | M | Convention: coder's `worktree remove` doc says prune is only on missing-dir, not on every invocation. If the dir exists but is in an unexpected location, prompt rather than prune |

## Quality Gate

| Item | Status |
|---|---|
| Platform applied | ✓ markdown skills library; no platform-specific adaptation needed |
| ADRs | ✓ inherited (ADR-0007); no new ADRs |
| Data model | ✓ inherited (iter A's schema additions); no new schema fields |
| API contract | ✓ this doc plus iter A's API Contract section together specify all three commands fully |
| Auth | N/A (single-user local tool) |
| Async | N/A (synchronous git shell-out) |
| Feature flag | N/A (markdown library; ships via versioned release) |
| CI/CD | N/A (markdown library) |
| Risk assessment | ✓ above |
| Scale baseline | inherited from iter A |
| Walking Skeleton deployable | ✓ each command is independently usable; iter B ships as v1.16.0 |

## Handoff to coder

Next step: invoke coder on this iter B scope. Coder reads:
- This doc (iter B architect)
- The parent doc ([../../01-architect.md](../../01-architect.md)) for the API Contract / Integration
  Contract sections that this doc refines
- The iter B brief ([./brief.md](./brief.md)) for the binding acceptance criteria

Coder produces:
- `ssd/SKILL.md` edits per § "Implementation breakdown" above
- `ssd-init/SKILL.md` edits per same
- `ssd/rails.md` edits per same
- `CHANGELOG.md` v1.16.0 entry
- `VERSION` bump to 1.16.0
- `.ssd/features/parallel-features/iterations/b/coder-status.md` (note: no `03-` prefix per
  iter-nested convention)

No code, no tests, no scripts. All markdown.
