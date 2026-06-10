---
skill: architect
version: 1.2.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-commit-split (3-iter epic)
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: true
  adrs: [ADR-0008]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — `.ssd/` Commit Split

## Platform note

Markdown skills library. Standard sections (component diagram, data model, API contract) are
realized as orchestrator-behavior flows, gitignore patterns, and gate-rule definitions per
the iter-A architect of parallel-features. Same adaptation; no surprises.

`systems-designer` is N/A.

## Current Scale Baseline

| Dimension | Today | 10x target |
|---|---|---|
| `.ssd/features/*` artifacts per project per quarter | ~15 in this repo's last 3 months | 150 |
| Committed durable artifacts per feature | 0 (blanket gitignored) | 4–6 (brief + architect + coder-status + code-review + deploy + optional systems-designer) |
| Active workstreams per project (post parallel-features) | up to 4 (advisory ceiling per ADR-0007) | unchanged |
| Lines of committed markdown per feature | 0 | ~500–1500 |
| Lines of committed markdown per project lifetime (50 features) | 0 | ~25k–75k |

Design implication: the committed-artifact volume per project lifetime is comparable to a
moderately-documented monorepo's `docs/`. No special handling needed for scale.

## Open Questions — Resolved

### Q1: Per-file vs per-directory gitignore patterns

**Decision: directory-rooted patterns with explicit allow-lists for known artifact files.**

The exact gitignore pattern (Layer 1):

```gitignore
# SSD working directory — selective commit (ADR-0008)
# Block everything under .ssd/ by default…
.ssd/*

# …then allow the durable artifact tree.
!.ssd/features/
!.ssd/milestones/

# Inside features/, allow durable design docs and reviews.
# (Negation requires the parent dir to be re-included first per gitignore semantics.)
!.ssd/features/**/

# Per-file allow-list inside features/.
!.ssd/features/**/00-brief.md
!.ssd/features/**/01-architect.md
!.ssd/features/**/02-systems-designer.md
!.ssd/features/**/03-coder-status.md
!.ssd/features/**/04-code-review*.md
!.ssd/features/**/05-deploy.md
!.ssd/features/**/iterations/**/brief.md
!.ssd/features/**/iterations/**/coder-status.md
!.ssd/features/**/iterations/**/code-review/round-*.md
!.ssd/features/**/iterations/**/deploy.md

# Block machine-managed state even when nested inside features/.
.ssd/features/**/iterations/**/deferred.yml
.ssd/features/**/current.yml.bak

# Inside milestones/, allow durable artifacts; block snapshot machinery.
!.ssd/milestones/**/
!.ssd/milestones/**/skeptic-before.md
!.ssd/milestones/**/skeptic-after.md
!.ssd/milestones/**/refactor-plan.md
!.ssd/milestones/**/refactor-prs.md
!.ssd/milestones/**/verification.md
.ssd/milestones/**/sha-before
.ssd/milestones/**/metrics-before.yml

# Audits stay gitignored entirely (often sensitive — vendor names, internal opinions).
.ssd/audits/
```

**Rationale.** Block-then-allow is the gitignore idiom for selective patterns. The explicit
per-file allow-list (rather than `!.ssd/features/**/*.md`) keeps the pattern auditable: a
reader can verify which artifact types are tracked. Future artifact types added to SSD
require both adding to this pattern AND adding to the `no-leaky-state` deny-list — that
symmetry is intentional.

**Edge case: archive/.** `.ssd/archive/` stays gitignored. Workstreams that ship and archive
keep their already-committed artifacts in `.ssd/features/<slug>/` (those tracked files don't
move to archive on the filesystem). The archive directory itself holds machine-managed state
about closed workstreams; no need to commit it.

### Q2: `ssd-init` migration default

**Decision: prompted migration by default for `developer_profile: standard` and `expert`;
default to keeping the blanket for `novice`.**

`ssd-init` runs idempotently. On invocation:

1. Read existing `.gitignore`. If it contains a blanket `.ssd/` line (heuristic: an exact
   line `.ssd/` or `.ssd` not preceded by `!`), the project is on the v1.3.0+ blanket
   convention.
2. If on blanket AND `developer_profile` ∈ {`standard`, `expert`}: surface the migration
   offer. *"This project is on the legacy blanket-gitignore convention (everything under
   `.ssd/` is ignored). The v1.18.0+ default is selective: briefs, architect specs, code
   reviews, and similar design docs get committed; machine state stays local. See ADR-0008.
   Migrate now?"* Three options: yes (perform migration), no (keep blanket for this session;
   ask again next time), permanent (set `project.yml.ssd.gitignore_mode: blanket` and stop
   asking).
3. If on blanket AND `developer_profile: novice`: skip the prompt; keep blanket. Novices
   shouldn't have to think about this.
4. If already selective: no migration needed.

**Migration mechanics** (when user accepts):

1. Write `.gitignore.bak` (refuse if `.gitignore.bak` already exists — don't clobber).
2. Replace the blanket `.ssd/` line with the selective pattern from Q1.
3. Print a summary of the now-trackable files: `git status .ssd/features/` will show
   previously-ignored files as untracked.
4. Recommend: `git add .ssd/features/ .ssd/milestones/` to stage them, then commit as
   "ssd: backfill durable artifacts under new commit-split convention" (or per the user's
   preference).

The user is responsible for the backfill commit. `ssd-init` does NOT auto-stage or
auto-commit — too presumptuous for a working tree that may have other in-flight edits.

### Q3: `no-leaky-state` deny-list source

**Decision: hard-coded baseline in `gate-rules.sh` + optional project-level override.**

The rule's baseline deny-list is hard-coded in the script (the same set as Q1's gitignore
pattern's "block" side). Projects with additional patterns to deny add them via
`.ssd/project.yml`:

```yaml
ssd:
  gitignored_state:                # additional patterns the no-leaky-state rule denies
    - .env.local
    - secrets/**
    - .vscode/launch.json
```

**Rationale.** Hard-coded covers the universal SSD set; the override slot lets projects
extend without modifying the script. The override is *additive only* — projects cannot
shrink the baseline. (SSD's invariant: no shrinking of doctrine via project config.)

The rule reads `project.yml.ssd.gitignored_state` if present; if missing or empty, only the
baseline applies.

### Q4: Pre-commit hook install mechanism

**Decision: plain symlink, no framework dependency.**

`methodology/hooks/pre-commit-no-leaky-state.sh` is a bash script that calls
`bash methodology/gate-rules.sh --base HEAD --rules no-leaky-state` (the gate-rules.sh gains
a `--rules <comma-list>` arg in iter A to support this; without it, the hook would run all
five+ existing rules pre-commit, which is too slow).

Install:

```bash
ln -s ../../methodology/hooks/pre-commit-no-leaky-state.sh .git/hooks/pre-commit
```

Or, for projects that already have a `pre-commit` hook: copy or invoke from the existing
hook. `methodology/hooks/README.md` documents both patterns.

**Rationale.** Plain symlink matches `gate-rules.sh`'s no-framework precedent. No husky, no
pre-commit.com config. Bash + git is all the user needs. Projects that want husky/etc. can
wrap the script themselves; we don't mandate the wrapper.

### Q5: `.ssd/audits/` — committed or not?

**Decision: stay gitignored.**

Audits often name vendors, include side-by-side comparisons, and surface opinions that
shouldn't be public (vendor selection notes, "this commercial product is worse than the
open-source one for these reasons"). The audit consumer is typically a small internal
audience, not the broader project. Committing audits would create chilling effects on the
audit's candor.

If a project wants to commit audits explicitly, they can extend the gitignore pattern locally
(opt-in). The SSD default is to keep them local.

### Q6: `.ssd/milestones/` — committed or not?

**Decision: committed (matches the durable-artifact reasoning).**

Milestone artifacts — `skeptic-before.md`, `refactor-plan.md`, `verification.md` — are durable
design records of post-sprint consolidation work. Same class as architect specs. Commit.

The `sha-before` and `metrics-before.yml` snapshot files stay gitignored (snapshot machinery,
not design docs).

## Component Diagram — Enforcement Layers

```
                  ┌─────────────────────────────────────────┐
                  │ User edits files / stages a commit      │
                  └────────────────────┬────────────────────┘
                                       │
                                       ▼
              ┌──────────────────────────────────────────────┐
              │ Layer 1: .gitignore                          │
              │ Selective pattern blocks current.yml etc.   │
              │ before they reach the staging area.         │
              └────────────────────┬─────────────────────────┘
                                   │ (blocked files don't get here)
                                   ▼
              ┌──────────────────────────────────────────────┐
              │ Layer 4 (optional): pre-commit hook          │
              │ Runs no-leaky-state rule against staged diff │
              │ before commit lands. Bypassable (--no-verify)│
              │ but doctrine forbids that.                   │
              └────────────────────┬─────────────────────────┘
                                   │
                                   ▼
              ┌──────────────────────────────────────────────┐
              │ Layer 3: /ssd gate                           │
              │ no-leaky-state rule runs on the branch diff. │
              │ FAILs the gate if forbidden files staged.    │
              │ Catches force-add and edited-gitignore cases.│
              └────────────────────┬─────────────────────────┘
                                   │
                                   ▼
              ┌──────────────────────────────────────────────┐
              │ Layer 5 (optional, CI): same gate-rules.sh   │
              │ invocation in CI catches local-hook bypass.  │
              └──────────────────────────────────────────────┘

  Layer 2 (ssd-init) is orthogonal — it WRITES the right Layer 1 pattern at init time
  and during migration, so the floor is correct without user effort.
```

## Data Model — Configuration

### `.ssd/project.yml` additions

```yaml
ssd:
  # existing keys unchanged
  gitignore_mode: selective              # NEW — selective | blanket. Default: selective for v1.18.0+
                                         # projects; blanket for projects migrated from v1.3.0–v1.17.x
                                         # that decline migration.
  gitignored_state:                      # NEW — optional additional deny-list for no-leaky-state rule
    - <path-or-glob>
    - ...
```

Both keys are optional. Defaults: `gitignore_mode: selective`, `gitignored_state: []`.

### Compatibility

- Existing projects with no `gitignore_mode` key: treated as `blanket` until migrated (the
  `ssd-init` prompt flow). Migration sets the key to `selective`.
- The `no-leaky-state` rule's behavior is gated on `gitignore_mode`:
  - `selective`: run with the full baseline deny-list + project overrides.
  - `blanket`: rule SKIPs cleanly with detail "project on blanket gitignore mode."

## API Contract — `no-leaky-state` Rule

### Rule signature

```
PASS|FAIL|SKIP no-leaky-state :: <detail>
```

### Logic

```
1. If git is unavailable OR --base ref doesn't resolve: SKIP "git/base unavailable"
2. Read project.yml.ssd.gitignore_mode (default: selective if absent).
3. If gitignore_mode == "blanket": SKIP "project on blanket gitignore mode"
4. Build deny_list = BASELINE_DENY_LIST + project.yml.ssd.gitignored_state[]
5. Compute changed = git diff --name-only <base>...HEAD
6. forbidden = changed ∩ deny_list  (using fnmatch-style glob matching)
7. If forbidden is empty: PASS
   Otherwise: FAIL "<N> file(s) gitignored by policy but tracked: <paths>"
```

`BASELINE_DENY_LIST` (hard-coded in the script):

```
.ssd/current.yml
.ssd/current.notes.yml
.ssd/init-log.md
.ssd/project.yml
.ssd/archive/**
.ssd/audits/**
.ssd/features/**/iterations/**/deferred.yml
.ssd/features/**/current.yml.bak
.ssd/milestones/**/sha-before
.ssd/milestones/**/metrics-before.yml
```

### `--rules` argument (new on `gate-rules.sh`)

Add an optional `--rules <comma-list>` arg to filter which rules run:

```bash
bash methodology/gate-rules.sh --base HEAD --rules no-leaky-state
```

Use case: the pre-commit hook (Layer 4) runs *only* `no-leaky-state` (the other rules are
too slow for pre-commit). Default behavior (no `--rules`) runs all rules — unchanged from
v1.14.0.

### Failure modes

- **FM-1: gitignore_mode unset on a v1.17.x project.** Treat as blanket → rule SKIPs. User
  receives advisory message: *"Project on blanket gitignore mode. Run `ssd-init` to migrate
  to selective."*
- **FM-2: `.gitignore` removed or edited to delete protections.** Layer 1 fails (files are
  no longer blocked); Layer 3 (this rule) catches them. The rule has no way to detect that
  `.gitignore` was edited; it only checks the resulting diff. This is acceptable — the
  diff is what gets shipped.
- **FM-3: force-add via `git add -f`.** Same as FM-2 — rule catches the staged file.

## Integration Contract — Layer Composition

| Layer | Mechanism | Bypassable? | Catches |
|---|---|---|---|
| 1 | `.gitignore` | Yes (`git add -f`) | Routine `git add` of gitignored files |
| 2 | `ssd-init` migration | N/A — runs once | Wrong gitignore at init time |
| 3 | `gate-rules.sh no-leaky-state` | No (refusing to override is doctrine) | Anything that reached the staged diff |
| 4 | pre-commit hook | Yes (`--no-verify`; doctrine forbids) | Anything Layer 1 didn't block, before commit |
| 5 | CI runs `gate-rules.sh` | No (CI is the backstop) | Anything that bypassed local layers |

The contract: **Layer 3 is mandatory; Layers 1, 2, 4, 5 are floors and ceilings around it.**
A project running Layer 3 (which is just `/ssd gate`) cannot ship a leaky-state PR even if
Layers 1, 2, 4 are misconfigured.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Migration step misses some existing-projects' `.gitignore` quirks (comments, ordering) | M | M | Migration prints a diff before writing; user reviews. `.gitignore.bak` provides rollback. |
| Users on `developer_profile: novice` never get the split because the prompt is suppressed | M | L | Auto-promotion path: when novice → standard transition happens (per ADR-0004), re-offer the migration. Document. |
| Project adds an artifact type to SSD (e.g., `06-postmortem.md`) but doesn't update the gitignore pattern AND the deny-list | M | M | Document the dual-update requirement in `ssd/SKILL.md`. The frontmatter validator (ADR-0006) will catch the wrong file type; the new file just stays gitignored until added. |
| `no-leaky-state` deny-list and `.gitignore` allow-list drift out of sync | M | M | The architect spec and ADR-0008 are explicit that they're symmetric. A new gate rule (out of scope this epic) could validate the symmetry. |
| Solo developer on `gitignore_mode: blanket` doesn't realize they can opt back into selective | L | L | Document in CHANGELOG and in `ssd-init` re-run output: "currently blanket; run `ssd-init --migrate-gitignore` to switch." |
| Existing untracked files in `.ssd/features/` get auto-staged when gitignore changes | H | M | This is by design (migration intent), but document explicitly in the migration prompt: "X new files will become trackable. Stage them with `git add .ssd/features/` after the migration; review before committing." |

**Top 3 risks:** drift between deny-list and gitignore (mitigated by doctrine), migration
miss on `.gitignore` quirks (mitigated by `.gitignore.bak` rollback), and surprise staging on
migration (mitigated by explicit user-driven staging step).

## Iteration Plan

### Iter A (v1.18.0) — Enforcement floor

**Scope:**

- Write ADR-0008 ✓ (done in this branch).
- Update `.gitignore` in this repo to the selective pattern (yes, dogfood at iter A — the
  brief, architect spec, and ADR are valuable to commit immediately; iter A self-justifies).
- Update `ssd-init/SKILL.md` Step 5 (Gitignore) with the new selective pattern as default
  AND the migration flow.
- Add `gitignore_mode` and `gitignored_state` keys to the `project.yml` template.
- Add `no-leaky-state` rule + `--rules` arg to `methodology/gate-rules.sh`.
- Update `ssd/SKILL.md`:
  - § "The SSD Artifact Tree" — annotate which artifacts are committed vs. gitignored.
  - § "Methodology Enforcement" — add `no-leaky-state` to the rule table.
- `CHANGELOG.md` v1.18.0 entry.
- `VERSION` 1.17.1 → 1.18.0.

**Acceptance criteria** (from brief): AC-1, AC-2, AC-3, AC-4, AC-6, AC-8.

**Ship:** tag v1.18.0.

### Iter B (v1.19.0) — Optional hook + docs polish

**Scope:**

- New `methodology/hooks/pre-commit-no-leaky-state.sh` (calls
  `gate-rules.sh --rules no-leaky-state`).
- New `methodology/hooks/README.md` documenting symlink install + alternative integration.
- `ssd-init/SKILL.md` mention of the optional hook (offer install during init for `expert`
  profile).
- `CHANGELOG.md` v1.19.0 entry.
- `VERSION` 1.18.0 → 1.19.0.

**Acceptance criteria:** AC-5.

**Ship:** tag v1.19.0.

### Iter C (v1.20.0) — Dogfood the convention

**Scope:**

- Verify this repo's `.gitignore` is on the selective pattern (set in iter A).
- Stage all previously-untracked `.ssd/features/{ssd-skill-upgrades, parallel-features,
  ssd-commit-split}/**/*.md` files. Plus `.ssd/milestones/**/*.md` if any.
- Commit as "ssd: backfill durable artifacts under ADR-0008 commit-split convention."
- Update README.md to mention that the repo's own SSD artifacts are tracked.
- `CHANGELOG.md` v1.20.0 entry — "the SSD methodology now publicly cites its own work
  product."
- `VERSION` 1.19.0 → 1.20.0.

**Acceptance criteria:** AC-7.

**Ship:** tag v1.20.0. Epic complete.

## Files in Scope (binding)

| File | Iter | Change |
|---|---|---|
| `docs/decisions/ADR-0008-ssd-commit-split.md` | A | NEW (committed via iter A's PR) |
| `.gitignore` (this repo) | A | EDIT — blanket → selective |
| `ssd-init/SKILL.md` | A | EDIT — Step 5 gitignore + migration flow |
| `methodology/gate-rules.sh` | A | EDIT — `no-leaky-state` rule + `--rules` arg |
| `ssd/SKILL.md` | A | EDIT — Artifact Tree annotation + Methodology Enforcement rule row |
| `CHANGELOG.md` | A, B, C | EDIT — per-iteration entries |
| `VERSION` | A, B, C | EDIT |
| `methodology/hooks/pre-commit-no-leaky-state.sh` | B | NEW |
| `methodology/hooks/README.md` | B | NEW |
| `.ssd/features/{ssd-skill-upgrades, parallel-features, ssd-commit-split}/**/*.md` | C | Become tracked (gitignore changed in iter A; staging happens in iter C) |

## Quality Gate

| Item | Status |
|---|---|
| Platform | ✓ markdown skills library |
| ADRs | ✓ ADR-0008 |
| Data model | ✓ project.yml additions + gitignore pattern + deny-list |
| API contract | ✓ `no-leaky-state` rule + `--rules` arg |
| Auth | N/A |
| Async | N/A |
| Feature flag | N/A — markdown library; rollout via tags |
| CI/CD | N/A in this repo; documented as Layer 5 option |
| Risk assessment | ✓ |
| Scale baseline | ✓ |
| Walking Skeleton deployable | ✓ each iter ships independently |

## Handoff to coder

Coder reads this doc, the brief, and ADR-0008. Implements iter A scope. Produces
`.ssd/features/ssd-commit-split/iterations/a/coder-status.md` (now that the layout will be
multi-iter; promote on iter A start) OR keeps flat-layout for iter A. Architect recommendation:
**stay flat for iter A**; promote to multi-iter at iter B start (matches what
parallel-features did and respects ADR-0001 non-destructive promotion).

Coder also writes the selective `.gitignore` pattern itself — that file lives in the same
branch as iter A's commits. Take care: changing `.gitignore` mid-branch will cause previously-
ignored `.ssd/features/ssd-commit-split/*` files (this brief, this architect spec) to become
tracked. That's correct and intentional. The iter A PR will be larger than usual because it
contains both the new rules AND the first batch of artifacts becoming tracked.

The PR description should explain this — "Iter A's diff is large because the gitignore change
in this PR makes previously-untracked artifacts visible; this is the intended outcome of
ADR-0008."
