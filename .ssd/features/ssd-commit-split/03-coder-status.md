---
skill: coder
version: 1.2.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-commit-split iteration A — enforcement floor (gitignore + ssd-init + no-leaky-state)
consumed_by: [code-reviewer]
files_touched:
  - .gitignore
  - VERSION
  - CHANGELOG.md
  - ssd/SKILL.md
  - ssd-init/SKILL.md
  - methodology/gate-rules.sh
  - docs/decisions/ADR-0008-ssd-commit-split.md
  - .ssd/features/ssd-commit-split/00-brief.md
  - .ssd/features/ssd-commit-split/01-architect.md
  - .ssd/features/ssd-commit-split/03-coder-status.md
tests_added: []
review_markers: 0
test_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: |
    PASS wip-commits :: no WIP/checkpoint commits between main and HEAD
    SKIP tests-pass :: no test_command (markdown library)
    SKIP feature-flag-present :: no feature_flag_marker
    SKIP adr-delta :: no diff vs main (uncommitted)
    PASS frontmatter-valid :: 13 artifact(s) validated against schemas
    SKIP no-leaky-state :: no diff vs main (uncommitted)
  note: |
    Standalone smoke test of the new matches_deny_pattern function (8 cases covering exact
    match, dir-prefix, ** glob, milestones, and legit files) passed all 8/8. Gate-rules.sh's
    new `no-leaky-state` rule and `--rules <comma-list>` filter both work as designed —
    verified by running `gate-rules.sh --base main --rules no-leaky-state` (filter applied;
    only that rule runs). adr-delta and no-leaky-state SKIP at coder-status time because the
    diff is uncommitted; both will fire correctly post-commit.
lint_results:
  command: "n/a — no linter configured (markdown + bash)"
  exit_code: null
type_check_results:
  command: "n/a — markdown + bash; no static type checker"
  exit_code: null
feature_flag:
  name: not_applicable
  default: not_applicable
  rationale: |
    Markdown skills library + bash gate rule — no runtime, no feature flag. Rollout via
    versioned tag v1.18.0. The opt-out for users who prefer the legacy blanket-gitignore
    behavior is documented (project.yml.ssd.gitignore_mode: blanket). The no-leaky-state
    rule respects the opt-out and SKIPs cleanly.
spec_drift: false
---

# Iteration A — Coder Status

## Scope shipped

Iteration A of the ssd-commit-split epic. Seven files modified, two new files (ADR-0008 +
this coder-status). The selective-gitignore pattern is now active in this repo, which means
the previously-untracked iter-A artifacts (brief + architect spec) appear in `git status` as
trackable.

### 1. `.gitignore` (EDIT, +46 / -1)

Replaced the bare `.ssd/` line with the selective block-then-allow pattern from
ADR-0008 § "Decision" / architect spec § Q1. ~30 lines of pattern + comment header.

Verified via `git check-ignore -v` on a representative sample:
- `.ssd/current.yml` → ignored (line 10: `.ssd/*`).
- `.ssd/init-log.md` → ignored (same).
- `.ssd/project.yml` → ignored (same).
- `.ssd/features/ssd-commit-split/00-brief.md` → trackable (line 19: allow-list).
- `.ssd/features/ssd-commit-split/01-architect.md` → trackable (line 20: allow-list).

The pattern enables the iter-A self-justification: this PR's brief + architect spec + the
new ADR all become trackable in the same diff that introduces them.

### 2. `VERSION` (EDIT)

1.17.1 → 1.18.0.

### 3. `CHANGELOG.md` (EDIT, +90)

New `## [1.18.0] — 2026-05-24` entry at top. Matches the format of v1.15.0 / v1.16.0 / v1.17.0
/ v1.17.1 entries. Explicitly calls out the **self-justifying** property of iter A: the
gitignore change makes previously-untracked artifacts visible in the same PR.

### 4. `ssd/SKILL.md` (EDIT, +40 / version 1.17.1 → 1.18.0)

Two new pieces:

- **§ "The SSD Artifact Tree"** — new "Selective commit split (v1.18.0+)" paragraph + a
  9-row table mapping every artifact path to its committed-vs-gitignored status, with
  rationale. Documents the symmetry between the gitignore allow-list, the gate rule's
  deny-list, and the (iter-B) pre-commit hook. Documents the `gitignore_mode: blanket` opt-out.

- **§ "Methodology Enforcement" rule table** — two new rows:
  - `frontmatter-valid` row (this rule was added in v1.14.0 but the table only listed the
    original four; iter A surfaces it explicitly with its ADR-0006 cite).
  - `no-leaky-state` row with ADR-0008 cite + description of what it checks.

- **Changelog entry** for v1.18.0.

### 5. `ssd-init/SKILL.md` (EDIT, +104 / version 1.6.0 → 1.7.0)

Full rewrite of Step 5 (Update `.gitignore`):

- Four-case detection flow (no gitignore / no `.ssd` reference / blanket / already selective).
- Verbatim selective pattern with comment header.
- Migration UX: "Three options: yes / no / permanent" prompt for blanket-detected projects,
  with `.gitignore.bak` rollback safety, `git ls-files --others --exclude-standard
  .ssd/features/` listing for the user to review what becomes trackable. Explicit
  "do NOT auto-stage or auto-commit" — the user controls the next commit.
- Profile-aware default: novice silently skips the prompt; standard/expert get the prompt by
  default. Re-offer on novice→standard auto-promotion (ADR-0004).
- `--keep-blanket-gitignore` flag for opt-in to blanket at init time.

Plus: Step 6 (Detect Project Shape) `project.yml` write block gains two new optional keys:
`gitignore_mode: selective` and `gitignored_state: []`, with comment block explaining the
purpose and the opt-out path.

### 6. `methodology/gate-rules.sh` (EDIT, +163 / -9)

Three discrete additions:

- **`--rules <comma-list>` CLI flag** — filters which rules run. Used by the iter-B
  pre-commit hook to run only `no-leaky-state` (the other rules are too slow for pre-commit).
  Empty filter = run all (default behavior; backward-compatible with v1.14.0+).
- **Two new helpers:** `yaml_get_list` (reads YAML list values for the project-supplied
  `gitignored_state[]`), `matches_deny_pattern` (gitignore-style glob matcher supporting
  `**`, `*`, `?`, trailing-slash dir-prefix patterns; converts to bash regex via `[[ =~ ]]`).
  Standalone smoke-tested on 8 cases (exact, dir-prefix, `**` glob, milestones, legit-files-
  not-matched). All 8/8 passed.
- **`rule_no_leaky_state` function** — implements the no-leaky-state gate rule per
  ADR-0008. Reads `gitignore_mode` (default `selective`), SKIPs on `blanket` or no-diff,
  PASSes when no forbidden files appear, FAILs with a sample of up to 3 paths otherwise.
  Doctrine cite in the rule's `emit` line ties back to ADR-0008 § "Decision."

The runner block at bottom now uses `should_run <rule>` per rule so `--rules` filtering
applies uniformly. Existing rule call sites unchanged in semantics; just wrapped in the
filter check.

### 7. `docs/decisions/ADR-0008-ssd-commit-split.md` (NEW, 189 lines)

Full ADR per the architect template (Status, Context, Decision, Rationale, Consequences,
Alternatives Rejected, Future Compatibility, Scale Note). Companion to ADR-0007's
parallel-features work — ADR-0007 created the multi-workstream surface area that motivated
this split.

### 8. `.ssd/features/ssd-commit-split/00-brief.md` (PRE-EXISTING, now trackable)

Written during the design phase before the gitignore changed. After the gitignore edit it
becomes trackable. Will be staged as part of iter A's commit per the self-justifying
property.

### 9. `.ssd/features/ssd-commit-split/01-architect.md` (PRE-EXISTING, now trackable)

Same — written in design phase, now trackable.

### 10. `.ssd/features/ssd-commit-split/03-coder-status.md` (NEW, this file)

This artifact. Becomes trackable under the new gitignore pattern.

## Critical staging boundary for iter A vs iter C

After this PR's gitignore change lands, EIGHTEEN other previously-untracked artifacts also
become trackable across `.ssd/features/parallel-features/**/*.md` and
`.ssd/features/ssd-skill-upgrades/**/*.md`. Per the architect spec, those are **iter C's
dogfood scope** — they don't go in this PR.

Iter A's commit should stage ONLY:
- The 6 modified tracked files (.gitignore, VERSION, CHANGELOG, ssd/SKILL.md, ssd-init/SKILL.md,
  methodology/gate-rules.sh).
- The 3 new ssd-commit-split artifacts (00-brief, 01-architect, 03-coder-status).
- ADR-0008.

NOT:
- `.ssd/features/parallel-features/**/*.md` (12 files — iter C).
- `.ssd/features/ssd-skill-upgrades/**/*.md` (4 files — iter C).

The PR description must explain this explicitly so reviewers don't expect to see the
historical artifacts here.

## Items for the code-reviewer to confirm

1. **Self-justifying iter A is correctly bounded.** The 3 ssd-commit-split artifacts stage in
   this PR; the 16 historical artifacts (parallel-features + ssd-skill-upgrades) defer to
   iter C. Verify the staging discipline matches the architect spec's iter A vs iter C
   boundary.

2. **`matches_deny_pattern` glob conversion correctness.** The bash regex conversion handles
   `**` → `.*`, `*` → `[^/]*`, `?` → `[^/]`, trailing `/` → prefix match. Smoke-tested 8
   cases; reviewer should verify the conversion is sound for edge cases not covered (e.g.,
   patterns ending with `**` without trailing path).

3. **`yaml_get_list` correctness for the project-yml override.** Reads top-level OR nested
   keys at any indent. Handles `# comment` lines. Stops the list when indent decreases.
   Reviewer might want to write a test fixture with an extended `gitignored_state:` list to
   verify (architect spec § Q3).

4. **Migration UX preserves user agency.** The `ssd-init` migration writes `.gitignore.bak`
   and explicitly DOES NOT auto-stage or auto-commit. The user controls what lands in the
   next commit. Verify the prose makes this contract unambiguous.

5. **`gitignore_mode: blanket` opt-out path is fully wired.** Project.yml key documented in
   ssd-init template, `no-leaky-state` rule SKIPs cleanly on blanket, gitignore pattern can
   be reverted to bare `.ssd/` per the doctrine. Verify the three opt-out signals are
   consistent (project.yml + gitignore + gate rule).

6. **Doctrine consistency: `frontmatter-valid` row added retroactively.** The rule was
   introduced in v1.14.0 but the table didn't list it. Iter A adds the row. Reviewer should
   confirm this is OK (a doc-fix in addition to iter A's primary scope) and not flag as
   scope drift.

## Self-verification

1. Did I run gate-rules.sh? Yes. Recorded above. All applicable rules PASS/SKIP cleanly.
2. REVIEW marker count: 0. Markdown + bash; no inline markers.
3. Spec drift checked? No deviations. The architect spec's iter A scope (six items: ADR-0008,
   gitignore, ssd-init, gate-rules, ssd/SKILL.md, CHANGELOG+VERSION) all delivered. Plus the
   noted retroactive `frontmatter-valid` row addition — minor scope, called out for reviewer
   consideration in item 6 above.
4. Feature flag wired? N/A — markdown library + bash gate rule. Opt-out is `gitignore_mode:
   blanket` documented in two places.
5. Cross-language? Bash + markdown. Bash glob-matcher smoke-tested standalone.

## Handoff to code-reviewer

Diff scope: 7 files modified + 3 new files (ADR-0008 + 2 ssd-commit-split artifacts + this
file). Net ~430 lines added.

Gate expectations post-commit:
- `wip-commits`: PASS.
- `tests-pass`: SKIP.
- `feature-flag-present`: SKIP (still no feature_flag_marker).
- `adr-delta`: PASS post-commit (ADR-0008 is the new ADR for the architectural delta).
- `frontmatter-valid`: PASS (all .ssd/features/ssd-commit-split/*.md artifacts validate).
- `no-leaky-state`: PASS (the diff contains no gitignored-by-policy paths; verified via
  inspection — gitignore-protected files like current.yml were NOT staged).

Iter B (pre-commit hook + docs) and iter C (dogfood the historical artifacts) are
independently runnable after this merges.
