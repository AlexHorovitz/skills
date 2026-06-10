---
skill: coder
version: 1.2.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features iteration B — orchestrator-command documentation
consumed_by: [code-reviewer]
files_touched:
  - ssd/SKILL.md
  - ssd-init/SKILL.md
  - ssd/rails.md
  - CHANGELOG.md
  - VERSION
tests_added: []
review_markers: 0
test_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: |
    PASS wip-commits :: no WIP/checkpoint commits between main and HEAD
    SKIP tests-pass :: no test_command in /Users/.../skills/.ssd/project.yml
    SKIP feature-flag-present :: no feature_flag_marker in /Users/.../skills/.ssd/project.yml
    SKIP adr-delta :: no diff vs main
    PASS frontmatter-valid :: 7 artifact(s) validated against schemas
  note: |
    adr-delta SKIPs because diff is uncommitted at the time of this artifact. No new ADR
    needed (ADR-0007 covers all three iterations). frontmatter-valid PASSes for the
    iteration B architect + this coder-status.
lint_results:
  command: "n/a — no linter configured (markdown library)"
  exit_code: null
type_check_results:
  command: "n/a — markdown + bash; no static type checker applies"
  exit_code: null
feature_flag:
  name: not_applicable
  default: not_applicable
  rationale: |
    Markdown skills library — no runtime, no feature flag. Rollout via versioned tag
    (v1.16.0). Single-feature flow is unchanged; concurrent-workstream commands are
    opt-in.
spec_drift: false
---

# Iteration B — Coder Status

## Scope shipped

Iteration B of the parallel-features epic: full documentation of the three new orchestrator
commands designed in iteration A's architect spec, plus the supporting `ssd-init` and `rails.md`
edits the spec called out. Five files touched, no new ADR (ADR-0007 covers all three iterations).

### 1. `ssd/SKILL.md` (EDIT, +~290 lines)

**Version banner:** 1.15.0 → 1.16.0.

**Invocation table** at top of file: added three rows for the new commands with `(v1.16.0+)`
markers so users browsing the table see they're new.

**§ "/ssd (no-arg) — Auto-Detect" Step 0** closing paragraph: appended cross-reference to
§ "Workstream Lifecycle Commands" so the LLM (or a human reader) knows where to find the
commands that actually write the new `branch:` and `worktree:` fields.

**NEW § "Workstream Lifecycle Commands"** between `/ssd ship` and "Developer Profile + Teaching
Mode" (~270 lines). Three sub-sections, each following iter B architect spec's Convention 1
(signature, purpose, numbered behavior steps with exact git commands, numbered failure modes,
side-effects summary):

- `/ssd feature new` — 11 numbered behavior steps; FM-1 through FM-12 (with gaps where FMs are
  shared with other commands, e.g., FM-4 worktree collision is also a failure for `feature new`
  with `--worktree`). Handles `<slug>#<iter>` syntax for creating iterations.
- `/ssd switch` — 7 numbered behavior steps in **validate-all-first then mutate** order. Step 3
  performs all validations; steps 4–6 perform all mutations. This guarantees that a failure in
  the checkout step doesn't leave a handoff note written without the switch completing — the
  ordering issue I caught during self-review while writing the section (see § "Spec changes
  during coding" below).
- `/ssd worktree add|remove` — separate behavior blocks for `add` and `remove`. The `remove`
  block specifies the `git worktree prune` recovery path for missing dirs (EC-5 from iter B
  architect).

**Self-verification block at section end:** four-point checklist the LLM-executing orchestrator
must apply before reporting completion — verifies (1) all FM checks ran, (2) git invocations
matched the docs verbatim, (3) atomic writes for current.yml/current.notes.yml, (4) ordering
discipline on `/ssd switch` (dirty-check BEFORE state mutation).

**Changelog entry:** v1.16.0, ~30 lines, matching the v1.15.0 entry's tone/length.

### 2. `ssd-init/SKILL.md` (EDIT, +~12 lines)

**Version banner:** 1.5.0 → 1.6.0.

**Step 6 (Detect Project Shape) project.yml write block:** added four new optional keys with
their defaults inside the `ssd:` map:
- `branch_pattern: "add-{slug}"`
- `worktree_root: "../"`
- `worktree_name_pattern: "{repo}-{slug}"`
- `switch_note_default: prompt`

**Explanatory paragraph after the write block:** one paragraph noting that `ssd-init` writes
these defaults so the v1.16.0+ workstream lifecycle commands can resolve without per-invocation
prompting. References ADR-0007 and `ssd/SKILL.md` § "Workstream Lifecycle Commands."

### 3. `ssd/rails.md` (EDIT, +~10 lines)

**Version banner:** 1.0.0 → 1.1.0.

**§ "What This Is NOT" new bullet:** clarifies that `/ssd feature new` / `/ssd switch` /
`/ssd worktree` are intentionally non-rail. They manage workflow ergonomics on the workstream
**container**, not methodology on the workstream's eight rail **steps**. Pausing/switching
mid-iteration does NOT log a `rail_deviation` because pausing isn't a rail step at all.

**Changelog entry:** v1.1.0.

### 4. `CHANGELOG.md` (EDIT, +~75 lines)

New `## [1.16.0] — 2026-05-24` entry at top, matching the format of existing entries. Sections
covering: new commands (with one-paragraph summaries of each), touched skills (with version
bumps), edge cases resolved (EC-1 through EC-5 from iter B architect), schema (no changes),
deferred-to-iter-C list, deferred-to-iter-D list.

### 5. `VERSION` (EDIT)

1.15.0 → 1.16.0.

## Spec changes during coding

One real change I caught while writing: the iter B architect spec's `/ssd switch` behavior had
an implicit ordering risk where the handoff note could be written before a checkout that then
fails, leaving the source workstream's handoff overwritten without the switch having completed.
I restructured the steps to **validate-all-first** (step 3) before any mutating step (steps
4-6). This is documented in iter B architect EC-3, but iter B architect didn't enforce a step
ordering — the SKILL.md prose now does.

I left this as the canonical specification in the SKILL.md. The iter B architect spec stays
unchanged (its EC-3 was sufficient at the architect level; the ordering is an implementation
concern that belongs in the coder's prose).

No other deviations. The spec's conventions 1–5 are all followed.

## What is deliberately NOT shipped (deferred to iter C)

Verified that nothing from iter C leaked in:

- No `touches:` backfill on gate runs (iter C — added to `code-reviewer/SKILL.md` then).
- No `OVERLAP-N` finding category in `code-reviewer/SKILL.md` (iter C).
- No workstream-aware base-branch detection in `methodology/gate-rules.sh` (iter C).
- The `/ssd switch` doc references `current.notes.yml.features.<slug>.handoff_notes` but does
  not reference any iter-C-only field.

## Items for the code-reviewer to confirm

1. **`/ssd switch` step 5 — `cd <path>` line as LAST output line.** The doc requires the
   `cd <path>` directive be the last line of output for the user to see. The LLM-executing
   orchestrator must respect this — verify the SKILL.md prose is unambiguous on this.
2. **`/ssd feature new` step 7 worktree path resolution** uses
   `git rev-parse --path-format=absolute --git-common-dir | xargs dirname` (paraphrased in
   the prose). Iter A's worktree footnote documented this and provided the git 2.31+ fallback.
   Verify the prose in `/ssd feature new` step 7 cross-references that footnote.
3. **`/ssd feature new` slug-iteration handling** prompts the user when promoting flat → multi-iter
   layout (step 3, third bullet). On expert profile the prose mentions `--promote` to skip the
   prompt. Verify this matches the profile-aware-defaults pattern from existing skills.
4. **FM number consistency** between iter A architect and iter B SKILL.md prose. Iter A
   enumerated FM-1 through FM-10; iter B adds FM-11 (brief file collision), FM-12 (iteration
   collision), and FM-13 (`worktree remove` with no worktree). All three new FMs are
   `/ssd feature new` or `/ssd worktree` specific. Verify the numbering is coherent and no
   FM is referenced without being defined.
5. **`ssd-init` writes the four new keys unconditionally on a fresh init.** This means
   existing projects that ran `ssd-init` before v1.6.0 don't get the keys (unless they re-run
   init). Is this acceptable? The architect spec said the keys are optional with sensible
   defaults — so the orchestrator falls back to defaults if the keys are missing, meaning
   re-init is not required. Verify this fallback path is explicit somewhere readable.

## Self-verification

1. **Did I actually run gate-rules.sh?** Yes — recorded above. All applicable rules PASS or
   SKIP cleanly.
2. **REVIEW marker count.** 0. Markdown library, no inline review markers; items needing
   reviewer attention are in § "Items for the code-reviewer to confirm" above.
3. **Spec drift checked?** Yes — one substantive change documented (the validate-all-first
   step reordering in `/ssd switch`). Recorded as not technically drift from the architect
   spec (it strengthens EC-3's intent), but called out explicitly.
4. **Feature flag wired?** N/A — markdown library.
5. **Cross-language?** N/A — markdown.

## Handoff to code-reviewer

Diff scope: 5 files modified, no new files. ~390 lines added net (mostly the new SKILL.md
section and the CHANGELOG entry). Adheres to iter B architect's "Convention 1: each command is
a contract" structure.

Gate expectations after commit:
- `wip-commits`: PASS.
- `tests-pass`: SKIP.
- `feature-flag-present`: SKIP.
- `adr-delta`: SKIP (no new ADR; the architectural diff is documentation prose, not
  doctrine-level).
- `frontmatter-valid`: PASS (all 7 `.ssd/features/parallel-features/**` artifacts validate).

Iter C is independently runnable after this merges. The iter C scope is locked by the iter A
architect spec; coder can pick it up directly.
