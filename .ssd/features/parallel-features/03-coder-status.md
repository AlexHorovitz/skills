---
skill: coder
version: 1.2.0
produced_at: 2026-05-21T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features / iteration A (schema substrate + read-only auto-detect)
consumed_by: [code-reviewer]
files_touched:
  - docs/decisions/ADR-0007-parallel-features.md
  - ssd/SKILL.md
  - CHANGELOG.md
  - VERSION
  - .ssd/project.yml
tests_added: []
review_markers: 0
test_results:
  command: "bash methodology/gate-rules.sh --base origin/main"
  exit_code: 0
  stdout_tail: |
    PASS wip-commits :: no WIP/checkpoint commits between origin/main and HEAD
    SKIP tests-pass :: no test_command in /Users/.../skills/.ssd/project.yml
    SKIP feature-flag-present :: no feature_flag_marker in /Users/.../skills/.ssd/project.yml
    SKIP adr-delta :: no diff vs origin/main
    PASS frontmatter-valid :: 4 artifact(s) validated against schemas
  note: |
    `adr-delta` SKIPs because diff is uncommitted at the time of this artifact; after
    commit the rule will see ADR-0007-parallel-features.md and PASS. The other SKIPs
    are intentional for a markdown-only skills library (no test command, no flag marker).
lint_results:
  command: "n/a — no linter configured in this skills-library repo"
  exit_code: null
type_check_results:
  command: "n/a — markdown + bash; no static type checker applies"
  exit_code: null
feature_flag:
  name: not_applicable
  default: not_applicable
  rationale: |
    Skills library has no runtime — "feature flags" don't exist as a concept here. Rollout
    is via versioned releases. Iteration A ships as v1.15.0; iterations B and C ship as
    v1.16.0 and v1.17.0 respectively. Each iteration is shippable on its own per ADR-0007.
spec_drift: true
spec_drift_summary: |
  One scope item dropped: the architect spec instructed the coder to extend
  `methodology/schema-validator.sh` with optional-field checks. No such file exists —
  the actual validator (`methodology/frontmatter-validate.py`, introduced in v1.14.0 / ADR-0006)
  validates artifact frontmatter (under `.ssd/features/<slug>/*.md`), not `current.yml`.
  The new `branch`/`worktree`/`touches` fields live on `current.yml.active[]`, which has no
  separate validator script. Iteration A drops the validator change; the fields are
  optional and the orchestrator reads them tolerantly. See § "Spec drift" below for the
  full rationale.
---

# Iteration A — Coder Status

## Scope shipped

Iteration A of the parallel-features epic: **schema substrate + read-only branch→workstream
auto-detection**. Five files touched, one new ADR.

### 1. ADR-0007 (NEW)

`docs/decisions/ADR-0007-parallel-features.md` — full ADR per the architect spec's outline.
Sections: Status, Context, Decision, Rationale, Consequences, Alternatives Rejected, Future
Compatibility, Scale Note. Length and tone match the existing ADR-0001..ADR-0005 series.
Alternatives section rejects six explicit candidates (no-tooling-just-docs, required-worktree-
per-workstream, in-orchestrator-branch-protocol, MAJOR-tier-overlap, schema-version-3-bump,
branch-name-enforcement, single-all-or-nothing-release). Decision section explicitly slices the
work into iterations A/B/C with what ships in each.

ADR-0006 is referenced in the architect spec but doesn't exist on this branch (origin/main).
The retroactive ADR-0006 lives on the `add-adr-0006` branch — a parallel workstream that is
itself the empirical motivation for this feature. Sequential numbering is preserved (ADR-0007
follows the documented ADR-0006 even though origin/main hasn't seen ADR-0006 yet) on the
assumption that `add-adr-0006` merges before or alongside `add-parallel-features`. If
add-adr-0006 doesn't merge, ADR-0007 should be renumbered to ADR-0006 at merge time. Flagged
for the code-reviewer.

### 2. `ssd/SKILL.md` (EDIT)

Four targeted edits, version banner bumped `1.10.0 → 1.15.0` (re-aligning SKILL.md version with
the library version; both have drifted apart since v1.11–v1.14 didn't touch this file):

- **§ "/ssd (no-arg) — Auto-Detect"** → new "Step 0" prepended to the decision tree.
  Documents branch → workstream resolution: (1) exact match against `active[].branch`,
  (2) pattern match via `branch_pattern` prefix strip, (3) fall through to existing
  multi-workstream prompt. Explicitly read-only; doesn't advance phase silently.
- **§ "The SSD Artifact Tree"** → new "Worktree note" paragraph after the closing prose
  block. Documents the invariant that `.ssd/` lives in the main checkout even when a
  workstream uses a sibling worktree. Calls out the implementation mechanism
  (`git rev-parse --path-format=absolute --git-common-dir`) so iteration B's commands
  have a documented pattern to follow.
- **§ "Session Continuity" / `current.yml` v2 schema example** → three new optional
  fields added inline with comments noting they're optional/defaulted and linking to
  ADR-0007. New paragraph below the existing forward-compat note explaining that the
  v1.15.0 fields are strictly additive and that v2 `current.yml` files without them
  continue to parse identically. Lazy-backfill rule documented: only fires when exactly
  one active workstream has no `branch:` field.
- **§ "Changelog"** → new top entry **1.15.0 (2026-05-21)** matching the length and tone
  of the existing 1.10.0 / 1.13.0 entries. Explicitly notes that this iteration is
  intentionally read-only at the orchestrator surface; commands ship in B/C.

No other sections touched in iteration A. Per spec, `ssd/rails.md` and `ssd-init/SKILL.md`
edits are deferred to iteration B; `code-reviewer/SKILL.md` and `methodology/gate-rules.sh`
edits to iteration C.

### 3. `CHANGELOG.md` (EDIT)

New `## [1.15.0] — 2026-05-21` entry at top, matching the format of existing entries (header
hierarchy, narrative paragraph, bulleted sections for schema/config/orchestrator changes,
explicit "Spec drift" subsection documenting the validator-script drop, explicit "Deferred
to iteration B" and "Deferred to iteration C" sections so the next iterations have a
verbatim handoff list.

### 4. `VERSION` (EDIT)

`1.14.0 → 1.15.0`. Single-line file. Matches the convention of bumping per shippable iteration.

### 5. `.ssd/project.yml` (EDIT — non-committed)

Added four new optional `ssd.*` keys explicitly with their default values
(`branch_pattern: "add-{slug}"`, `worktree_root: "../"`,
`worktree_name_pattern: "{repo}-{slug}"`, `switch_note_default: auto`) modeling the
convention. Used `switch_note_default: auto` rather than `prompt` because this project's
`developer_profile: expert` (already declared in project.yml) — picking the expert default
explicitly so the value is visible.

Bumped `ssd.version: 1.14.0 → 1.15.0` to match VERSION.

This file is gitignored (`.ssd/` in `.gitignore`); the edit is local-only and won't appear
in the PR diff. It serves as dogfooding for downstream projects to copy.

## Spec drift

**One material drift from the architect spec.**

Spec § "Files in Scope (binding)" listed `methodology/schema-validator.sh` as an Iteration A
target with the instruction: *"recognize new optional fields, emit MINOR on partial
population."* That file does not exist in the repo. The closest existing artifacts are:

- `methodology/frontmatter-validate.py` (v1.14.0, ADR-0006) — validates YAML frontmatter on
  `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md` artifacts against per-skill
  schemas. Does not parse `current.yml`.
- `methodology/schemas/*.yml` — per-skill frontmatter schemas (architect, coder,
  code-reviewer, systems-designer).
- `methodology/gate-rules.sh` — the five gate rules. Does not parse `current.yml` shape; one
  rule (`wip-commits`) reads `--base`, others read `.ssd/project.yml` heuristically.

The new `branch:`/`worktree:`/`touches:` fields live on `current.yml.active[]`. There is no
existing executable validator for `current.yml` itself — its schema is documented in
`ssd/SKILL.md` § "Session Continuity" and parsed ad-hoc by the orchestrator.

**Coder's call:** drop the validator change from iteration A. Justification:

- The new fields are optional with sensible defaults; absence is valid by design.
- The orchestrator reads them tolerantly (lazy backfill on `branch:` absence, treats
  empty/absent `touches:` as "no overlap data," treats absent `worktree:` as null).
- No downstream consumer in iteration A inspects these fields programmatically (iteration B
  consumes them; iteration C uses them).
- Building a dedicated `current.yml` validator would itself be a non-trivial ADR-worthy
  change (separate validator script vs. extending `frontmatter-validate.py` vs. inlining
  in the orchestrator). Inappropriate to bundle into iteration A.

**What should happen instead.** If `current.yml` schema validation becomes load-bearing
(i.e., the orchestrator depends on field types being correct rather than tolerantly
parsing them), iteration B or C should introduce a separate `current-yml-validate.py` (or
similar) following the precedent of `frontmatter-validate.py`. The fifth gate rule
(`current-yml-valid`) would mirror `frontmatter-valid`. Until that need arises, the absence
is the right answer.

This drift is logged in the CHANGELOG entry for v1.15.0 so the next-iteration handoff has
the explanation in writing.

## Out-of-scope (deferred to B/C)

Untouched in this iteration, listed verbatim from the architect spec:

- New orchestrator commands (`/ssd feature new`, `/ssd switch`, `/ssd worktree`) — **iter B**.
- `ssd-init/SKILL.md` mention of concurrent-workstream support; ssd-init writing the new
  `project.yml.ssd.*` defaults at init time — **iter B**.
- `ssd/rails.md` brief annotation that `pause`/`switch` are intentionally non-rail — **iter B**.
- Coder-pass `touches:` backfill on gate runs — **iter C**.
- Cross-workstream overlap check in `code-reviewer/SKILL.md` (new `OVERLAP-N` finding) — **iter C**.
- `methodology/gate-rules.sh` workstream-aware base-branch detection — **iter C**.

## Items for the code-reviewer to confirm

(REVIEW markers as prose, not code comments, since markdown library)

1. **ADR-0007 numbering vs add-adr-0006 branch.** ADR-0007 references a sibling ADR-0006
   that exists on the `add-adr-0006` branch but not on `origin/main` (the base for this
   branch). Verify the merge-order plan: either `add-adr-0006` lands first (then ADR-0007's
   number is correct on merge) or `add-parallel-features` lands first and renumbers
   ADR-0007 to ADR-0006 at merge. Coder picked ADR-0007 on the assumption of normal
   chronological merging.
2. **SKILL.md version jump (1.10 → 1.15).** Iteration A is the first SSD-orchestrator-skill
   change since v1.10.0 — the orchestrator SKILL.md version has been frozen while library
   versions 1.11–1.14 bumped for other skills. Coder aligned SKILL.md to the library version
   per the architect spec. Verify this is the desired convention (alternative: SKILL.md
   versions independent of library version, would bump 1.10 → 1.11 here).
3. **Lazy-backfill rule scope.** SKILL.md states the orchestrator backfills `branch:` lazily
   only when **exactly one** active workstream is ambiguous. Architect spec said: *"if and
   only if exactly one active entry has `branch: null`."* Coder kept this constraint as-is.
   Verify this is sufficient for real-world cases — e.g., a user with two active workstreams,
   both pre-1.15.0 (both `branch: null`), runs `/ssd` from one of them. Resolution: orchestrator
   declines to guess and prompts. (Documented in CHANGELOG.)
4. **Worktree resolution mechanism.** The artifact-tree note says sub-skills resolve the
   main checkout via `git rev-parse --path-format=absolute --git-common-dir` and take the
   parent. This is correct for linked worktrees but for the main checkout, `--git-common-dir`
   returns `.git` (relative) — `realpath` or `--path-format=absolute` is needed for both
   to produce a consistent absolute path. Verify the chosen invocation in actual iteration B
   implementation.
5. **`switch_note_default: auto` for expert profile.** Dogfood `.ssd/project.yml` sets
   `switch_note_default: auto` to model the expert behavior. ADR-0007 says the default for
   expert profile is `auto`. Verify the convention is that the profile-default-mapping is
   documented in SKILL.md (it currently isn't explicitly in §" Profile-aware defaults"
   table); iteration B will likely need to add it.

## Self-verification

1. **Did I actually run gate-rules.sh?** Yes. Recorded above. `adr-delta` SKIPs because
   the changes are uncommitted; will PASS after commit.
2. **REVIEW marker count.** 0 in the diff (markdown library; no inline `# REVIEW:` markers
   to embed). Items requiring reviewer attention are in § "Items for the code-reviewer to
   confirm" above.
3. **Did I compare implementation to spec for drift?** Yes. One material drift (validator
   script); documented at length above and in CHANGELOG.
4. **Feature flag wired?** N/A — markdown library, no runtime.
5. **Cross-language?** N/A — Markdown only in this iteration.

## Handoff to code-reviewer

Diff scope: 4 committed files + 1 new ADR. Total ~200 lines changed across documentation
and one new markdown ADR. Net additive (no deletions of existing content).

Gate expectations:
- `wip-commits`: PASS (no WIP commits).
- `tests-pass`: SKIP (no `test_command` in `.ssd/project.yml`).
- `feature-flag-present`: SKIP (no `feature_flag_marker` in `.ssd/project.yml`).
- `adr-delta`: PASS post-commit (ADR-0007 is the new ADR justifying the architectural delta).
- `frontmatter-valid`: PASS (all `.ssd/features/parallel-features/*.md` artifacts validate
  against their respective schemas).

Iteration B is independently runnable after this merges. Architect spec already lays out
iter-B scope; coder will need a fresh iteration entry under
`.ssd/features/parallel-features/iterations/b/` if the user opts to promote this feature
to multi-iteration layout, or stay flat and overwrite `03-coder-status.md` for iter B (less
historical clarity, more git-blame churn).
