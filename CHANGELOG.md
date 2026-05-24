# Changelog

All notable changes to the InsanelyGreat's SSD skills library are documented here.

Format: `[version] — date — description`

---

## [1.17.1] — 2026-05-24

### Docs — canonical-reference and cross-linking pass

Documentation-only release. No behavior change in any executable skill, gate rule, or validator.

- **methodology/SKILL.md** → 1.5.0. Adds a "canonical methodology pages" line at the top pointing
  to insanelygreat.com (ssd.html, guide.html, agile2.html) and states the website is the
  user-facing reference while this skill set is the in-repo doctrine the orchestrator enforces.
- **methodology/core.md.** Adds a canonical-reference banner. Makes the Continuous-Delivery vs.
  SSD distinction explicit ("CD says *can*; SSD requires *is*"). Names Alex Horovitz as
  originator. Links the Ratchet Principle CI implementation to
  [insanelygreat.com/ratchet-principle.html](https://insanelygreat.com/ratchet-principle.html)
  (which has a working `.github/workflows/quality.yml`).
- **methodology/adoption.md.** Refreshes the methodology-comparison block (date-stamped
  2026-05-24, satisfies the SKILL.md ≤12-month-refresh requirement). Adds Shape Up and Kanban
  comparisons. Adds a team-size × work-shape decision table. Replaces the bare-books "Resources"
  list with a canonical-page section linking the six new long-form articles at
  insanelygreat.com (solo-developer-manifesto, scrum-alternatives, ratchet-principle,
  releases-small-teams, simplest-lifecycle, methodologies-small-teams).
- **methodology/patterns.md.** Pattern 3 (Dark Launching) now cross-links
  [How Small Teams Should Think About Releases](https://insanelygreat.com/releases-small-teams.html)
  for the full deploy/release decoupling treatment.
- **ssd/SKILL.md** → 1.17.1. Canonical-reference banner; Purpose paragraph names Alex Horovitz
  as originator and links the About page.
- **README.md.** Adds shields.io badges (Methodology: InsanelyGreat SSD, Manifesto: Agile²,
  License) and a new "Methodology" section linking the five canonical insanelygreat.com pages.

Motivation: close the citation graph in both directions. The website now links into the skills
repo (badge + README links); the skills repo now links back to the website's canonical pages
(banners + cross-references). This is the inbound-signal half of the LLM-visibility plan.

---

## [1.17.0] — 2026-05-24

### Iteration C — parallel-features overlap detection (epic complete)

Third and final iteration of the parallel-features epic. Iter A (v1.15.0) shipped the schema
substrate (`branch`, `worktree`, `touches`). Iter B (v1.16.0) shipped the orchestrator commands
(`/ssd feature new`, `/ssd switch`, `/ssd worktree`). **Iter C makes iter A's `touches:` field
load-bearing** — the architect-pass intent and coder-pass diff backfill that have been recorded
since v1.15.0 are now actually consumed at gate time.

See [ADR-0007](docs/decisions/ADR-0007-parallel-features.md) — same ADR covers all three
iterations.

**The behavior change.** When `/ssd gate <slug>` runs and `current.yml.active[]` has more than
one workstream, two new things happen:

1. **Touches backfill.** The orchestrator computes `git diff --name-only <base>...HEAD` for
   the gated workstream and unions the result into `current.yml.active[<slug>].touches`. This
   runs BEFORE code-reviewer, so the reviewer sees an up-to-date touch list. Architect-intent
   paths that haven't been touched yet are preserved (union, not replacement).

2. **Cross-workstream overlap check.** `code-reviewer` consults the peer workstreams'
   `touches:` fields, intersects via `git ls-files <glob>`, and emits `OVERLAP-N` findings for
   any non-empty intersections — at **SUGGESTION tier**, never BLOCKER or MAJOR. The gate is
   not blocked by overlap. Per ADR-0007, this is by design: overlap can be intentional, and
   the user has context the orchestrator doesn't.

The new `🔗 OVERLAP:` severity prefix is added to the canonical severity table in
`code-reviewer/SKILL.md`. ADR-0007 § "Alternatives Rejected" explicitly forbids upgrading
OVERLAP-N to MAJOR on speculation.

**Touched skills:**

- `code-reviewer` — v1.4.0 → v1.5.0. New § "Cross-Workstream Overlap Check" (~80 lines) with
  algorithm, finding format, edge cases (`**` globs, untracked files, empty `touches:`,
  self-exclusion guarantee), and explicit no-upgrade rule. New `🔗 OVERLAP:` severity prefix
  row in the severity table.
- `ssd` — v1.16.0 → v1.17.0. § "Methodology Enforcement" gains two paragraphs: one naming the
  cross-workstream overlap check as part of `/ssd gate`, one documenting the workstream-aware
  base detection pattern (orchestrator passes `--base` explicitly; gate-rules.sh remains
  standalone). § "Session Continuity" `touches:` schema comment now documents the gate-time
  union and the OVERLAP-N consumer.

**Tooling:**

- `methodology/gate-rules.sh` — added comment block near `BASE="main"` declaration explaining
  the standalone-vs-orchestrator contract. No behavior change to the script.

**Schema:** unchanged. Iter A's `touches:` field is now actually consumed; no new fields.

**Trigger conditions for the overlap check** (all must hold; if any false, the check skips and
no OVERLAP findings are emitted):

- Review is invoked via `/ssd gate` (not an ad-hoc code-reviewer invocation).
- `current.yml.active[]` has more than one entry.
- The gated workstream's `touches:` is non-empty.
- At least one other active workstream has non-empty `touches:`.

**Out-of-scope for iter C, deferred to iter D (only if real friction emerges):**

- `/ssd workstream adopt <slug> <branch>` — claim an existing branch as a workstream.
- `/ssd workstream set-branch <slug> <branch>` — rename / repair (called out in iter B's
  FM-14 as the eventual remedy for worktree-branch drift).
- `/ssd workstream handoff <slug>` — write a handoff note for a workstream not currently
  resolved as `source` (useful when detached HEAD blocked auto-capture during `/ssd switch`).
- Workstream-base auto-derivation in `gate-rules.sh` — explicit `--base` from the orchestrator
  is the current contract.

**Parallel-features epic status: COMPLETE.**

Three iterations, three ADR-0007-conformant releases, no schema-version bumps. The original
ask ("I would like to be allowed to work on multiple features at once") is now fully
delivered: schema substrate (iter A), ergonomic commands (iter B), cross-workstream
awareness (iter C). The epic-level workstream `parallel-features` archives to
`.ssd/archive/features/parallel-features/` after this release.

---

## [1.16.0] — 2026-05-24

### Iteration B — parallel-features orchestrator commands

Second of three iterations of the parallel-features epic. Ships the three new orchestrator
commands designed in iteration A's architect spec. No new schema fields (iter A shipped those);
this iteration is pure documentation that makes the LLM-driven orchestrator able to *execute*
parallel-workstream lifecycle. See [ADR-0007](docs/decisions/ADR-0007-parallel-features.md).

**New orchestrator commands** (documented in `ssd/SKILL.md` § "Workstream Lifecycle Commands"):

- **`/ssd feature new <slug>[#<iter>] [--branch <name>] [--worktree] [--from <ref>] [--allow-dirty]`**
  — start a new workstream end-to-end. Creates the git branch, optional worktree (sibling-of-repo
  by default), brief stub, `current.yml.active[]` entry, and `current.notes.yml` section in one
  step. Twelve numbered failure modes covering dirty trees, branch collisions, slug/iteration
  collisions, worktree path collisions, brief-file collisions. Handles `<slug>#<iter>` syntax
  per § "Iterations Inside a Feature" — creates iterations on existing features (prompting to
  promote flat-layout features) or new features with their first iteration.

- **`/ssd switch <slug>[#<iter>] [--no-note | --auto-note | --allow-dirty]`** — validates-all-first
  switch. Step 3 verifies target exists, target branch is resolvable, working tree is clean (or
  `--allow-dirty`), worktree path exists if applicable. Only after every validation passes does
  step 4 write the handoff note (per `switch_note_default` / profile — prompt/auto/skip) and
  step 5 run `git checkout` (or surface a literal `cd <path>` line for worktrees). Step-3
  validation guarantees no state mutation on failure — solves the "handoff written then checkout
  fails" race.

- **`/ssd worktree <slug>[#<iter>] add|remove [--path <path>]`** — explicit worktree lifecycle,
  decoupled from `feature new`. `add` resolves the worktree path via the configurable
  `worktree_root` + `worktree_name_pattern` (defaults `../` + `{repo}-{slug}`). `remove` refuses
  on dirty worktrees (FM-9), `git worktree prune`s when the path is missing on disk (recovery
  for manual `rm`), preserves the underlying branch.

**Self-verification block at end of § "Workstream Lifecycle Commands"** — instructs the
LLM-executing orchestrator to verify all failure-mode checks ran, all git invocations matched
the documented commands verbatim, and `current.yml` / `current.notes.yml` writes are atomic
(temp-file-rename or in-memory-prepare-then-write).

**Touched skills:**

- `ssd` — v1.15.0 → v1.16.0. New ~250-line "Workstream Lifecycle Commands" section. Updated
  Invocation table with three new command rows. Step 0 of `/ssd` (no-arg) Auto-Detect now
  cross-references the new commands.
- `ssd-init` — v1.5.0 → v1.6.0. Step 6 (project.yml write) now writes the four
  `project.yml.ssd.*` parallel-features keys with their defaults (`branch_pattern: "add-{slug}"`,
  `worktree_root: "../"`, `worktree_name_pattern: "{repo}-{slug}"`, `switch_note_default: prompt`).
  New paragraph after Step 6 explains the parallel-features defaults and links to ADR-0007.
- `ssd/rails.md` — v1.0.0 → v1.1.0. New "What This Is NOT" bullet clarifying that the
  v1.16.0 workstream lifecycle commands are intentionally non-rail (workflow ergonomics on the
  workstream container, not methodology on the workstream's eight rail steps).

**Edge cases resolved (iter B architect spec EC-1 through EC-5):**

- EC-1: Branch naming for iterations is `add-<slug>-<iter>` (advisory, configurable). The
  orchestrator records the full string in the workstream entry's `branch:` field; auto-detect
  Step 0's exact-match path handles it.
- EC-2: `/ssd feature new <slug>#<iter>` is valid and creates an iteration on an existing or
  new feature; promotion from flat-layout is non-destructive per ADR-0001.
- EC-3: Dirty-tree check runs BEFORE any state mutation (formalized in the validate-all-first
  step 3 of `/ssd switch`).
- EC-4: Detached HEAD on `/ssd switch` means `source` is `null` — handoff capture is skipped,
  warning logged, switch proceeds.
- EC-5: `/ssd worktree remove` on a missing worktree dir runs `git worktree prune` and clears
  state with a warning, rather than failing.

**Schema:** no changes. Iter A's optional `branch` / `worktree` / `touches` fields on
`current.yml.active[]` cover everything iter B needs. The new commands write those fields
directly.

**Deferred to iteration C (v1.17.0):**

- Coder-pass `touches:` backfill on gate runs (`git diff --name-only <base>...HEAD` union into
  the recorded `touches:` list).
- Cross-workstream overlap check at `/ssd gate` time, surfacing as `OVERLAP-N` SUGGESTION-tier
  findings in `code-reviewer/SKILL.md`.
- `methodology/gate-rules.sh` workstream-aware base-branch detection.

**Deferred (iteration D, only if real friction emerges):**

- `/ssd workstream adopt <slug> <branch>` (claim an existing branch as a workstream).
- `/ssd workstream set-branch <slug> <branch>` (rename / repair).
- `/ssd workstream handoff <slug>` (write a handoff note for a workstream not currently
  resolved as the source — useful when detached HEAD blocked auto-capture).

---

## [1.15.0] — 2026-05-21

### Iteration A — parallel-features schema + auto-detect (read-only)

First of three iterations of the parallel-features epic. Promotes branch/worktree/touched-files
to first-class workstream artifacts, enabling concurrent feature workstreams without per-switch
git ceremony. See [ADR-0007](docs/decisions/ADR-0007-parallel-features.md) for the rationale,
the alternatives rejected, and the three-iteration slicing.

**Also bundled in this release:** [ADR-0006](docs/decisions/ADR-0006-frontmatter-validator.md) —
retroactive documentation of the v1.14.0 frontmatter validator. The v1.14.0 release shipped the
validator + 5th gate rule without an ADR; ADR-0006 closes that doctrine debt. Cherry-picked
into this PR rather than shipped on its own branch to avoid an ADR-numbering gap on `main`
(round-1 code-review MAJOR-1 from this iteration).

**This iteration is intentionally read-only at the orchestrator surface** — no new commands
ship, no existing commands change behavior beyond auto-detect. New commands and overlap
detection ship in iterations B (v1.16.0) and C (v1.17.0) respectively.

**Schema additions (`.ssd/current.yml.active[]`, all optional, backward-compatible):**
- `branch: <string>` — git branch for this workstream. Defaults from
  `project.yml.ssd.branch_pattern`.
- `worktree: <absolute-path-or-null>` — opt-in worktree path; `null` = main checkout.
- `touches: [<glob>, ...]` — file globs the workstream is known to modify. Populated by
  architect (intent at design) and unioned by coder (actual diff each gate). Used for
  cross-workstream overlap detection in iteration C — not yet active.

Existing v2 `current.yml` files without these keys parse and behave identically. The
`schema_version: 2` field is unchanged — additions are strictly additive per ADR-0007's
"reject `schema_version: 3` bump" decision.

**Configuration additions (`.ssd/project.yml.ssd`, all optional, defaulted):**
- `branch_pattern: "add-{slug}"` — default for `/ssd feature new` (iteration B).
- `worktree_root: "../"` — default parent directory for new worktrees.
- `worktree_name_pattern: "{repo}-{slug}"` — default worktree directory name.
- `switch_note_default: prompt|auto|skip` — handoff-note capture behavior on
  `/ssd switch` (iteration B). Novice profile defaults to `prompt`; expert to `auto`.

**Orchestrator behavior (`ssd/SKILL.md` v1.15.0):**
- `/ssd` (no-arg) gains **Step 0**: branch → workstream auto-resolution. (1) Exact match
  against any `active[].branch`, (2) pattern match via `branch_pattern` prefix strip,
  (3) fall through to the existing decision tree on no-match. Read-only; the resolution
  changes which workstream the decision tree operates on, but the proposal itself still
  has to be accepted.
- Lazy backfill: on the next state write, an active entry with `branch: <absent>` gets
  the current checkout's branch — but only when exactly one active workstream is
  ambiguous (no guess on multi-ambiguity).

**Touched skills:**
- `ssd` — v1.10.0 → v1.15.0 (re-aligns SKILL.md version with library version). New
  Step 0 in `/ssd` (no-arg). New schema fields documented in Session Continuity.
  New worktree footnote in Artifact Tree.

**Spec drift (recorded for the code-reviewer):**
- The architect spec called for extending `methodology/schema-validator.sh` with optional-field
  checks. No such file exists — the actual validator (`methodology/frontmatter-validate.py`,
  introduced in v1.14.0) validates *artifact frontmatter*, not `current.yml`. The new fields
  live on `current.yml.active[]`, which has no separate schema-validating script. Coder
  dropped the validator change from iteration A. See [.ssd/features/parallel-features/03-coder-status.md](.ssd/features/parallel-features/03-coder-status.md)
  for details. If `current.yml` schema validation becomes load-bearing for the parallel-features
  flow (it currently is not — fields are optional and the orchestrator reads them tolerantly),
  iteration B or C will add a dedicated `current.yml` validator.

**Deferred to iteration B (v1.16.0):**
- New commands: `/ssd feature new`, `/ssd switch`, `/ssd worktree`.
- `ssd-init/SKILL.md` mention of concurrent workstream support + writing the four new
  `project.yml.ssd.*` defaults at init time.
- `ssd/rails.md` brief annotation that `switch`/`pause` are intentionally non-rail.

**Deferred to iteration C (v1.17.0):**
- Coder-pass `touches:` backfill on gate runs.
- Cross-workstream overlap check (`OVERLAP-N` SUGGESTION-tier finding in
  `code-reviewer/SKILL.md`).
- `methodology/gate-rules.sh` workstream-aware base-branch detection.

---

## [1.14.0] — 2026-04-29

### Iter A — frontmatter schema validator

Closes one of the two deferred-but-tractable items from the v1.13.0 ssd-skill-upgrades epic close:
**frontmatter schema validator for `.ssd/features/<slug>/*.md` artifacts.** The other deferred
item (true two-surface parity test) remains open — it requires Agent SDK harness work, not in
scope here.

**New artifacts:**
- `methodology/frontmatter-validate.py` — Python 3 + PyYAML validator. Walks
  `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md`, parses the YAML frontmatter,
  matches each file to its skill schema, validates field presence and top-level type. Supports
  `--json` for structured output. Exits 0 on full pass, 1 on any FAIL.
- `methodology/schemas/architect.yml`, `coder.yml`, `code-reviewer.yml`, `systems-designer.yml`
  — per-skill schemas (deliberately minimal in v1: required fields + top-level types only).
  Sub-field shape and enum/regex constraints documented in each SKILL.md but not yet enforced;
  v2 may tighten.

**New gate rule (5th in `methodology/gate-rules.sh`):**
- `frontmatter-valid` — runs the validator on changed `.ssd/` artifacts (or walks the whole tree
  if no diff). PASSes when every artifact validates against its schema; FAILs on missing required
  fields or wrong types. SKIPs gracefully if Python 3 or PyYAML aren't on the host (matches
  existing precedent for `tests-pass` SKIP-when-precondition-missing).

**Type system** (validator): `string`, `int`, `bool`, `list`, `dict`, `timestamp`. The
`timestamp` type accepts datetime, date, or string — PyYAML auto-parses ISO-8601 strings to
datetime, so the schemas accept either representation.

**Parity-test harness updates** (`scripts/parity-test.sh`):
- 2 new fixtures: `frontmatter-valid` (passes), `frontmatter-invalid` (fails on missing fields).
- Both fixtures symlink the validator + schemas into the fixture's `methodology/` to avoid
  validator-finds-the-real-repo issues (root cause: `Path.cwd()` is now the project root for
  artifact discovery, but `__file__.resolve()` is still used for schema location, so symlinks
  resolve correctly for schemas while artifact discovery stays scoped to the fixture).
- Fixture setup now disables `commit.gpgsign` locally — fixtures in `/tmp` shouldn't and
  generally can't be GPG-signed; the global gitconfig was breaking them in environments where
  signing is on by default.
- Total assertions: 12 → 14, all passing.

**Touched skills:**
- `methodology` — v1.3.1 → v1.4.0 (Reference Files table now lists the validator + schemas;
  Gate Rules table adds `frontmatter-valid`; new "Frontmatter validator" sub-section).

**Deferred (still open):**
- True two-surface parity test (conversational vs command surface produce identical artifact
  trees). Requires Agent SDK harness; deferred until SSD has executable surface drivers.
- v2 schema tightening: per-field enum/regex/format validation, sub-dict shape (e.g.,
  `deliverables.component_diagram` boolean enforcement). Useful but separable iteration.

---

## [1.13.0] — 2026-04-29

### Iteration 9 of the SSD skill-upgrades epic — parity-test harness (final)

The architect doc envisioned a "two-surface parity test" comparing artifact trees produced via
the conversational vs command surface. That test isn't directly buildable from bash because the
surfaces are LLM-driven behaviors, not invokable processes. Iteration 9 ships the achievable
substitute: **structural conformance** for `methodology/gate-rules.sh`, the one piece of the
chain that IS bash and can be regression-tested.

**New file**: `scripts/parity-test.sh` — fast (<5s) test harness that runs `gate-rules.sh`
against 7 synthetic git fixtures and asserts the expected `PASS`/`FAIL`/`SKIP` for each rule:

- `clean-flagged-with-adr` — all rules satisfied (PASS / PASS / PASS / SKIP).
- `wip-commit-fails` — `wip-commits` FAILs on `WIP:` commit.
- `missing-flag-fails` — `feature-flag-present` FAILs on unflagged code addition.
- `docs-only-skips-flag` — `feature-flag-present` SKIPs on doc-only diffs.
- `missing-adr-fails` — `adr-delta` FAILs on 300-line architectural change without ADR.
- `yaml-comment-skip` — regression for round-2 MINOR-1 (commented YAML key not read as value).
- `spaced-path` — regression for round-2 MAJOR-2 (filenames with spaces handled correctly).

Plus 2 assertions on `--base` argument validation (regression for round-2 MINOR-2). Total: **12
assertions**; harness exits 0 on full pass.

**Out of scope (deferred until SSD has executable surface drivers):**
- True two-surface parity test (conversational vs command produce identical artifact trees).
- Frontmatter schema validator for `.ssd/features/<slug>/*.md` artifacts. Useful but separate
  iteration.

**Touched skills:** None — this is a CI-utility script, not a skill update.

**New artifact:** `scripts/parity-test.sh`.

**Iteration sequence:** 9 of 9 done — **the ssd-skill-upgrades epic is complete.** All seven
Part I upgrades plus rails.md (P2.A) and developer profile + teaching mode (P2.B) have shipped.
Part II's "two-surface parity test" remains an open ambition for when SSD gains executable
surface drivers (not in current scope).

---

## [1.12.0] — 2026-04-29

### Iteration 8 of the SSD skill-upgrades epic — developer profile + teaching mode (P2.B, ADR-0004)

Two audiences use SSD: newcomers who want the system to decide for them, and experienced
engineers who want every step explicit. v1.12.0 lets one product serve both without forking.

**New `project.yml` fields:**
```yaml
developer_profile: novice | standard | expert    # default: standard
teaching_mode:
  enabled: true|false                            # auto-true for first 5 invocations
  invocations_remaining: <int>                   # decay counter; default 5
rails: rails.md                                  # default; forkable per ADR-0003
```

**Profile-aware defaults** (hints, not gates — a novice can always invoke any command an expert
can):

| Profile | Default surface | Phase cmds | Confirmations | Narration | YAML editing |
|---|---|---|---|---|---|
| novice   | conversational | rejected with hint | irreversible only | full | discouraged |
| standard | conversational | accepted           | destructive only  | concise | allowed |
| expert   | command (or convo, user choice) | accepted | none | minimal | expected |

**Teaching mode**: decaying narration on conversational turns ("under the hood: I called
architect because phase=design"). Decrements per turn; auto-disables at 0.

**Auto-promotion**: novice→standard on first successful command-surface call;
standard→expert on >2 manual `current.yml` edits. Each prompt asks at most once per project.

**Bridge flags** (every surface reveals the other): `--explain` (conversational dry-run shows
command), `--narrate` (command emits conversational summary), `--raw` (conversational dumps raw
yaml), `--teach` (re-enable teaching).

**Touched skills:**
- `ssd` — v1.9.0 → v1.10.0 (new "Developer Profile + Teaching Mode" section)
- `ssd-init` — v1.4.0 → v1.5.0 (project.yml template updated; existing files fall back to
  defaults)

**New artifact:** `docs/decisions/ADR-0004-developer-profile-and-teaching-mode.md`.

**Iteration sequence:** 8 of 9 done. Next: P2.parity (test harness — final iteration).

---

## [1.11.0] — 2026-04-29

### Iteration 7 of the SSD skill-upgrades epic — `rails.md` as first-class artifact (P2.A, ADR-0003)

The eight-step canonical SSD sequence (brief → design → code → review → gate → deploy →
rollout-advance → flag-removal) was previously folklore scattered across `ssd/SKILL.md`,
per-skill files, and `methodology/core.md`. Iteration 7 names it.

**New file**: `ssd/rails.md` (v1.0.0). The single source of truth for:
- The eight-step canonical sequence.
- The eight critic-grade invariants every shipped feature satisfies.
- The `rail_deviations` logging contract (`current.yml.active[].rail_deviations`).
- The surface-agnostic guarantee: conversational and command surfaces walk the same rails.

**New behavior**: forks. A team with genuinely different needs forks `rails.md`, names the variant,
and points `project.yml.rails:` at it. The default is `rails.md`.

**Touched skills:**
- `ssd` — v1.8.0 → v1.9.0 (new "The Rails" section cross-references rails.md)

**New artifacts:**
- `ssd/rails.md`
- `docs/decisions/ADR-0003-rails-as-canonical-path.md`

**Iteration sequence:** 7 of 9 done. Next: P2.B (profile + teaching mode).

---

## [1.10.0] — 2026-04-29

### Iteration 6 of the SSD skill-upgrades epic — no-arg `/ssd` auto-detect (P1.3)

`/ssd` with no argument is now the **primary** entrypoint. Instead of requiring users to know
which phase command to type, the orchestrator reads state and proposes the next action.

**Behavior**: read `.ssd/current.yml` + `.ssd/current.notes.yml`. Inspect each active workstream's
`phase` field + the latest artifact, then propose the corresponding next phase command (with
slug + iteration suffix where applicable). Never silently advances — proposes and asks.

**Decision tree**: phase=brief → propose design; design → code; code → review; review with
gate_pass=false → return to code; review with gate_pass=true → ship; gate (post-pass) → deploy.
Renders `handoff_notes` from the notes sidecar as starting context.

**Multiple workstreams**: list with phase / last-touched / blockers; flag over-budget and stale
(>3 days untouched) entries. Ask user which to resume.

**Falls back to "ask"** for ambiguous or malformed state. Surfaces parse errors rather than
guessing.

**Touched skills:**
- `ssd` — v1.7.0 → v1.8.0

**Iteration sequence:** 6 of 9 done. Next: P2.A (rails.md).

---

## [1.9.0] — 2026-04-29

### Iteration 5 of the SSD skill-upgrades epic — bundled design pass (P1.4)

`architect` and `systems-designer` always run sequentially with the same inputs in the standard
`/ssd feature` flow. v1.9.0 lets them run as one logical step.

**New phase**: `/ssd design <slug>` (or `/ssd design <slug>#<iter>` for multi-iteration features):
1. Invokes `architect`; produces `01-architect.md`.
2. Reads the architect output, invokes `systems-designer`; produces `02-systems-designer.md`.
3. Surfaces gaps systems-designer rejected back to the user as one actionable block.

**Individual invocations remain valid.** `architect` and `systems-designer` are independently
invocable for ad-hoc design work, milestone redesigns, and external consumers (`codebase-skeptic`
reading just the architect spec). `/ssd design` is a convenience — it does not gate or change either
skill's contract.

**Skip `/ssd design` when systems-designer is N/A** (markdown-only repos, ADR-only PRs, skills
libraries). Invoke `architect` directly.

**Touched skills:**
- `ssd` — v1.6.0 → v1.7.0
- `architect` — v1.1.1 → v1.2.0 (changelog note only)
- `systems-designer` — v1.2.1 → v1.3.0 (changelog note only)

**Iteration sequence:** 5 of 9 done. Next: P1.3 (no-arg `/ssd` auto-detect).

---

## [1.8.0] — 2026-04-29

### Iteration 4 of the SSD skill-upgrades epic — deferred-findings ledger (P1.5)

Carry-over of non-blocking findings between iterations of a multi-iteration feature was previously
encoded as prose bullets in `current.yml` (`carried_to_pr_3c: [...]`). Iteration 4 makes it a
structured ledger with auto-load and auto-verify behavior.

**New artifact:** `.ssd/features/<slug>/iterations/<iter>/deferred.yml` (v1 schema):

```yaml
schema_version: 1
findings:
  - id: <severity>-<n>
    summary: <one-line>
    source: <relative-path-to-source-review>
    raised_in_iteration: <iter-id>
    target_iteration: <iter-id>|null
    status: open|closed|rolled-forward
    closed_in: <code-review-path>|null
```

**Auto-load on coder entry**: when entering coder phase for `<iter>`, the orchestrator pulls
entries with `target_iteration: <iter>` and `status: open` into the coder's input context as a
"Deferred from prior iterations" block. Coder either closes them in the diff or rolls them forward
with rationale.

**Auto-verify on review**: every multi-iteration review reads `deferred.yml` and checks each
entry's status against the diff. New frontmatter block `deferred_handled` with `closed`,
`rolled_forward`, and `silent_findings` (the last MUST be empty — silent findings are themselves a
MAJOR).

**Coder-status frontmatter additions**: `deferred.loaded` (count), `deferred.closed` (IDs),
`deferred.rolled_forward` (IDs).

**Single-cycle features** (no `iterations/` subdirectory) skip the ledger entirely — the schema
stays lean for the common case.

**Touched skills:**
- `coder` — v1.1.1 → v1.2.0
- `code-reviewer` — v1.3.0 → v1.4.0

**Iteration sequence:** 4 of 9 done. Next: P1.4 (bundled design pass).

---

## [1.7.0] — 2026-04-29

### Iteration 3 of the SSD skill-upgrades epic — multi-round gates (P1.2)

A `code-review` round that emits BLOCKER/MAJOR sends the workstream back to coder. The follow-up
review used to be tracked via filename suffixes (`04-code-review-round-2.md` was a manual
convention). It is now a structured concept the orchestrator auto-manages.

**Frontmatter additions to `code-reviewer` output:**
- `round: <int>` — 1 for first review, N for re-reviews. Auto-numbered by inspecting existing
  `code-review*` artifacts in the directory.
- `closed_from_previous_round: [<finding-id>, ...]` — list of finding IDs the reviewer verified
  closed since round N-1. Round 1 reviews use `[]`. Verification is per-claim against the code,
  not a copy from coder-status.

**Output paths by round + context:**
- Single-cycle feature, round 1: `.ssd/features/<slug>/04-code-review.md` (existing convention,
  unchanged).
- Single-cycle feature, round 2+: `.ssd/features/<slug>/04-code-review-round-N.md`.
- Multi-iteration feature: `.ssd/features/<slug>/iterations/<iter>/code-review/round-N.md`.
- Inline round-2 in the existing `04-code-review.md` remains valid for small remediations
  (1–3 closures) — pattern used by iteration 1 of this epic.

**`current.yml.active[].gate_rounds`** (field added in iter 1, populated from this iter): the
orchestrator increments it when a new round is written. Useful budget signal — `gate_rounds: 3`
suggests a contested design, scope cut, or rework.

**Touched skills:**
- `code-reviewer` — v1.2.1 → v1.3.0
- `ssd` — v1.5.0 → v1.6.0

**Iteration sequence:** 3 of 9 done. Next: P1.5 (deferred ledger), parallel-safe with this iter on
the iter-2 substrate.

---

## [1.6.0] — 2026-04-29

### Iteration 2 of the SSD skill-upgrades epic — first-class iterations (P1.1, ADR-0001)

A "feature" in SSD is no longer assumed to be a single design → build → review → deploy cycle.
Multi-iteration features (e.g., athena's `talentos-reimagined-phase3-ui` shipping as 3a / 3b / 3c)
now have a first-class home rather than the filename hack (`-3b`, `-round-2`) that observed usage
had been driving toward.

**Schema additions** (additive; back-compat with single-cycle features is total):
- `<slug>#<iter-id>` syntax accepted on every `/ssd` phase command.
- Opt-in `.ssd/features/<slug>/iterations/<iter-id>/` subtree per feature; epic-level docs
  (`00-brief.md`, `01-architect.md`, `02-systems-designer.md`) stay at the feature root and are
  shared across iterations.
- Per-iteration files: `brief.md`, `coder-status.md`, `code-review/round-N.md` (P1.2 in iter 3),
  `deferred.yml` (P1.5 in iter 4), `deploy.md`.
- `iteration` field in `current.yml` v2 (added in iter 1) is now actively populated.

**Resolution rules** documented in `ssd/SKILL.md` § "Iterations Inside a Feature":
1. Slug with `#`: operate on the iteration subtree; first reference promotes a flat-layout feature
   non-destructively (epic artifacts stay at the root).
2. Slug without `#` on a multi-iteration feature: orchestrator surfaces active iterations and asks.
3. Slug without `#` on a flat-layout feature: single-cycle path, unchanged.

**Touched skills:**
- `ssd` — v1.4.0 → v1.5.0
- `ssd-init` — v1.3.0 → v1.4.0 (documents that `iterations/` subdirs are created by the
  orchestrator on demand, not by init)

**New artifact:** `docs/decisions/ADR-0001-iterations-as-schema-substrate.md`.

**Iteration sequence:** 2 of 9 done. Next: P1.2 (multi-round gates), which builds on this
substrate.

---

## [1.5.0] — 2026-04-28

### Iteration 1 of the SSD skill-upgrades epic

First substantive iteration of the multi-iteration plan documented at
[.ssd/features/ssd-skill-upgrades/01-architect.md](.ssd/features/ssd-skill-upgrades/01-architect.md). Bundled
two engine-level upgrades that have no inter-dependency (P1.6 + P1.7).

**Executable gate rules (P1.6, ADR-0005):**
- New file `methodology/gate-rules.sh` — bash routine implementing four mechanical checks
  (`wip-commits`, `tests-pass`, `feature-flag-present`, `adr-delta`) with `PASS|FAIL|SKIP`
  structured stdout and `--json` mode for CI consumption.
- `ssd/SKILL.md` § "Methodology Enforcement" now invokes the script synchronously and refuses to
  pass the gate on any FAIL with the doctrine cite named.
- `methodology/SKILL.md` (v1.3.0) gains a "Gate Rules — Executable" section describing the script,
  the rule table, and direct-invocation usage for CI.
- Rationale: gate rules that aren't executable are decoration. ADR-0005 documents why bash is the
  right tool versus orchestrator-internal LLM checks (composability, reproducibility, testability,
  speed, fail-loud).

**`current.yml` v2 split + notes sidecar (P1.7, ADR-0002):**
- `.ssd/current.yml` is now schema-validated machine state; carries `schema_version: 2`.
- `.ssd/current.notes.yml` is the new free-form sidecar for handoff notes, scope changes, and
  questions for the next session.
- `ssd-init/SKILL.md` (v1.3.0) Step 7 split into "create both files fresh" and "v1 detected →
  prompted migration with `.bak`" paths. Migration is opt-in. Legacy v1 files continue to parse.
- v2 schema includes nullable `iteration`, `gate_rounds`, `rail_deviations` fields. Populated by
  later iterations (P1.1, P1.2, P2.A); present from v1.5.0 so the schema ships forward-compatible.

**Touched skills:**
- `ssd` — v1.3.0 → v1.4.0
- `methodology` — v1.2.1 → v1.3.0 → **v1.3.1** (round-2 fixes from iteration-1 code review)
- `ssd-init` — v1.2.0 → v1.3.0

**Round-2 fixes** (closed during iteration 1's code-review gate, before merge):
- MAJOR-1: `feature-flag-present` greps the added diff lines (`^+[^+]`) instead of file contents.
  A pre-existing flag marker elsewhere in a file no longer gives unflagged additions a free pass.
- MAJOR-2: both `feature-flag-present` and `adr-delta` build a quoted bash array of changed files
  instead of unquoted command substitution, closing a silent-SKIP on filenames with spaces or
  shell metacharacters.
- MINOR-1: `yaml_get` skips comment lines so `# test_command: pytest` is documentation, not a value.
- MINOR-2: `--base` argument parser rejects missing values and adjacent flags.
- Both MAJORs verified with synthetic git fixtures: file with pre-existing flag + unflagged
  addition → correct FAIL; spaced directory + ADR-less architectural change → correct FAIL.

**New artifacts:**
- `methodology/gate-rules.sh`
- `docs/decisions/ADR-0002-current-yml-split.md`
- `docs/decisions/ADR-0005-gate-execution-model.md`

**Iteration sequence:** This is iteration 1 of 9. Next: P1.1 (first-class iterations substrate). The
remaining iterations will land independently per the epic plan.

---

## [1.4.0] — 2026-04-28

### Working-tree convention: `ssd/` → `.ssd/`

The SSD working directory at the project root is renamed from visible `ssd/` to hidden `.ssd/`. All
path references in skill specs, gitignore guidance, and orchestrator logic are updated in lockstep.

**Why.** Two reasons: (1) in the SSD skills repo itself, a visible `ssd/` directory at the project
root collides with the orchestrator skill source directory, making `/ssd-init` impossible to run
cleanly inside this repo; (2) the working tree is transient state — review reports, design specs,
session-continuity pointers — not source code humans need to browse alongside the rest of the repo.
Hiding it keeps file-tree noise down while remaining fully accessible via `cd .ssd/`, IDE go-to-file,
and `ls -a`.

**Touched skills (path references updated; behavior unchanged):**
- `ssd` (orchestrator) → v1.3.0
- `ssd-init` → v1.2.0
- `architect`, `code-reviewer`, `codebase-skeptic`, `coder`, `methodology`, `refactor`,
  `software-standards`, `systems-designer` — Interface tables and inline path references updated;
  per-skill changelog entries added.

**Touched docs:**
- `README.md` — `Where to Start` and skill table use `.ssd/`.
- `CHANGELOG.md` — this entry; historical entries restored to their original `ssd/` wording (the
  convention they actually shipped under).
- `real-world-artifacts/ssd-upgrades-plan.md` — working-tree references updated; references to the
  orchestrator skill source (`~/.claude/skills/ssd/SKILL.md`) preserved.

`/ssd-init` invocations on existing projects with an `ssd/` working tree should: (a) stop, (b) `mv
ssd .ssd`, (c) re-run `/ssd-init` (idempotent — will detect existing state).

---

## [1.3.0] — 2026-04-18

### Post-v1.2-remediation skill improvements

Executed from `ai_working_directory/claude_skills_improvements/` plan (00-README + 01–04). The
remediation branch for work shipped successfully but fresh critic runs exposed gaps in the skills
themselves — missing operational failure-mode lenses, no loop closure, no structured hand-offs between
skills. This release addresses those gaps.

**New skill — ssd-init (v1.1.0):**
- First-run housekeeping for SSD projects. Creates `ssd/` (gitignored), `ssd/project.yml`,
  `ssd/current.yml`, `docs/decisions/`, `docs/runbooks/`, `docs/architecture/`, and runs SSD
  prerequisite checks (CI/CD, tests, flags, deployed hello-world). Idempotent — safe to re-run.
  Prerequisite to all `/ssd` phases. (Working tree later renamed to `.ssd/` in v1.4.0.)
- v1.1.0 aligns its artifact tree with the feature-centric / milestone-centric layout that every
  other sub-skill now declares: `ssd/features/<slug>/01-architect.md … 05-deploy.md` for features,
  `ssd/milestones/<YYYY-MM-DD-topic>/skeptic-before.md … verification.md` for milestones,
  `ssd/audits/<YYYY-MM-DD-scope>/` for audits. Replaces v1.0.0's per-skill subdirectory layout to
  eliminate the path mismatch that would have broken the chain.

**Orchestrator (ssd v1.2.0):**
- Declared the SSD artifact tree at `ssd/` (gitignored) + `docs/decisions/` (committed) (O1)
- Required YAML frontmatter on every primary output, with finding_counts / gate_pass / deliverables
  fields (O2)
- Added `/ssd verify` phase and mandatory before/after snapshot convention for milestones (O4, O5)
- Session continuity via `ssd/current.yml` (active workstreams, budget, last_touched) (O8)
- Methodology-backed gate enforcement table (O9)
- Skill-overlap priority table (coder vs python-django-coder, code-reviewer vs codebase-skeptic,
  codebase-skeptic vs software-standards) (O11)

**Review skills:**
- **codebase-skeptic (v1.2.0)**: mandatory Phase 2.5 Operational Failure Modes Sweep (C1);
  Forward-Looking Pass in Phase 4 (C4); Remediation Branch mode + self-verification in Operational
  Notes (C2, O6); reciprocal `/code-reviewer` hook table (C7); Incident-Story attestation for Beck,
  Domain-Modeling Stance for Evans, Deployment-Gate Hardening for Humble (C3, C5, C6).
- **code-reviewer (v1.2.0)**: Phase 1.5 Prior-Review Follow-up for remediation branches (R6); Phase 3.5
  Fix-Introduces-Edge-Cases (R2); 12 new Red Flags including LLM prompt injection, IntegrityError
  fetch mismatch, cache-without-race-test, release theatre (R3); Verify-Before-Escalating rule for
  sub-agent parallelization (R4); Severity Discipline (O7); Self-Verification (O6); LLM-specific
  examples, Edge Case Inventory template, Private-state mutation anti-pattern added to examples.md
  (R1, R5, R7).

**Build / design skills:**
- **architect (v1.1.0)**: output path + Quality Gate section mapping (A1, A2); Universal Principle 6
  "Integration Has a First-Class Contract" (A3); eight always-ADR decisions enumerated (A4); Current
  Scale Baseline required deliverable (A5).
- **systems-designer (v1.2.0)**: Phase 0 input validation against architect spec (S1); three-tier
  output with machine-check / human-review / block conditions (S2); new Concerns for AI/LLM
  Integration (S3), Compliance & Data Lifecycle (S4), Cost Observability (S5), Chaos / Failure
  Injection (S6).
- **coder (v1.1.0)**: output artifact `03-coder-status.md` with test/lint/typecheck results (C1, C2);
  Step 6.5 spec-drift check with ADR amendment prompt (C3); feature flag read from architect spec,
  halt if absent (C4); Cross-Language Boundaries section (C5).
- **refactor (v1.2.0)**: per-item finding citation requirement (R1); Step 4.5 Budget Check with
  halt-and-rollback options (R2); Step 5 Loop Closure with per-item re-check (R4); Step 6
  Systems-Designer Coordination trigger (R3).

**Audit / reference skills:**
- **software-standards (v1.1.0)**: two-mode support Comparative / Adversarial Single (ST1); 2–3
  evidence citations required per /10 score (ST2); explicit "When NOT to Use" delineation vs.
  codebase-skeptic (ST3); output path + frontmatter (ST4).
- **methodology (v1.2.0)**: clarified it provides machine-checkable rule source for `/ssd gate` (M1);
  added `/methodology score` self-adherence metric invocation (M2); audience-split expectation for
  adoption.md (M3); date-stamped comparisons with 12-month refresh prompt (M4).

**Cross-cutting:**
- Added "Skill Hygiene Contract" section to README.md (O10): file structure, interface discipline,
  header/license ordering, and future contract-test layer.
- Title-first header ordering enforced across all SKILL.md files (X6).
- License pointer already single-line since v1.2.0; Skill Hygiene Contract now requires it (X1).
- Per-skill `## Changelog` section required + added to all touched skills (X3).

---

## [1.2.0] — 2026-03-27

### Codebase review remediation

Eating own dogfood in real time. Executed findings from `codebase-skeptic` review (`documentation/skills/codebase-review-2026-03-27.md`). Voices activated: Fowler, Uncle Bob, Evans, Jobs, Wozniak.

- **ssd/SKILL.md** (v1.1.0) — replaced duplicated doctrine (shippable state invariant checklist, hard rules) with references to `methodology/core.md`; replaced inline ship checklist with directive to invoke `systems-designer`
- **code-reviewer/** (v1.1.0) — decomposed into orchestrator + `examples.md` sub-file; extracted all code examples (correctness, security, performance, maintainability, testing) and comment-writing examples into reference file; added language-adaptation note
- **refactor/** (v1.1.0) — decomposed into orchestrator + `patterns.md` sub-file; extracted scanning techniques and 6 refactoring patterns into reference file; added language-adaptation note
- **systems-designer/SKILL.md** (v1.1.0) — added language-adaptation note acknowledging Python-centric examples
- **methodology/SKILL.md** (v1.1.0) — version bumped to reflect prior decomposition (was still at 1.0.0)
- **All 37 files** — replaced 12-line per-file license blocks with one-line reference (`<!-- License: See /LICENSE -->`); ~500 tokens recovered per session
- **README** — updated contributing guide to reflect new license convention and framework template
- **architect/web/frameworks/TEMPLATE.md** — new file; structural template for framework guide contributions ensuring section parity across all guides
- **5 skills** — bumped version markers from 1.0.0 to 1.1.0 (ssd, code-reviewer, refactor, systems-designer, methodology)
- **.gitignore** — created; excludes `.DS_Store`

---

## [1.1.1] — 2026-03-27

- **README, CHANGELOG** — corrected brand name from "Insanely Great SSD" to "InsanelyGreat's SSD"

---

## [1.1.0] — 2026-03-27

### Structural improvements (this session)

- **LICENSE** — corrected to match shareware terms stated in all SKILL.md files (was accidentally set to The Unlicense)
- **README** — updated description to "free-for-personal-use"; added "Where to Start" section with canonical entry point (`/ssd`); added Skill Taxonomy table classifying skills as orchestrator / domain / review / reference
- **ssd/SKILL.md** — removed dead reference to local development file (`~/Development/Claude-Skills/ssd-meta-skill-proposal.md`)
- **methodology/** — decomposed 794-line monolith into focused sub-files:
  - `core.md` — Iron Law, Five Principles, Decision Framework, Metrics, Engineering Mindset (stable doctrine)
  - `patterns.md` — Five implementation patterns + Advanced topics (how-to layer)
  - `adoption.md` — Getting started, objections, org adoption, comparisons, resources (human onboarding material)
  - `SKILL.md` — slim orchestrator (~50 lines) that loads the right sub-file based on context
- **All SKILL.md files** — added standardized `## Interface` table (Input / Output / Consumed by / SSD Phase) to all 9 skills
- **All SKILL.md files** — added `**Version:** 1.0.0` marker to each skill header
- **CHANGELOG.md** — created this file

---

## [1.0.0] — 2026-03-25 / 2026-03-26

### Initial release

- `4b97b09` (2026-03-25) — Initial SSD skills: ssd, architect, coder, code-reviewer, systems-designer, refactor, methodology, software-standards, codebase-skeptic
- `f144156` (2026-03-25) — Updated license agreements across all files
- `8d9356b` (2026-03-26) — Made mobile, web, and desktop first-class citizens in SSD methodology; expanded platform coverage
- `abd9841` (2026-03-26) — Added 9 web framework guides (Next.js, Django, FastAPI, Rails, Laravel, Angular, Vue/Nuxt, Spring Boot, ASP.NET Core) and 5 language guides (C, C++, Go, PHP, Obj-C)

---

## Versioning Policy

Each SKILL.md carries its own version marker (`**Version:** x.y.z`). The library version in this changelog tracks the overall collection.

- **Patch** (x.y.**Z**): Corrections, typo fixes, updated code examples
- **Minor** (x.**Y**.z): New guides, new skills, new platform coverage, structural improvements that don't change skill behavior
- **Major** (**X**.y.z): Breaking changes to skill interface contracts or SSD doctrine
