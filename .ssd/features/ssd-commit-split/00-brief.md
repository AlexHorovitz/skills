---
skill: ssd (orchestrator, /ssd feature)
version: 1.17.1
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: split .ssd/ between committed durable artifacts and gitignored working state
consumed_by: [architect, coder, code-reviewer]
---

# Brief — `.ssd/` commit split

## What is being asked

Today `.ssd/` is fully gitignored. With parallel-features (v1.15–v1.17) shipped, the SSD
workflow now supports multiple workstreams per user — and teams are starting to use SSD
across multiple contributors. The all-or-nothing gitignore is in tension with two real
needs:

1. **Durable artifacts (briefs, architect specs, code reviews) deserve git history.** They
   describe the work. Today they're invisible to PR review, milestone audits, and external
   onboarding.
2. **Working state (`current.yml`, `current.notes.yml`, `init-log.md`, archive) must stay
   local.** It contains absolute paths, per-user profile settings, draft handoff notes,
   and machine-managed state that can't safely be shared.

Move from blanket `.ssd/` gitignore to a **selective split**: durable artifacts get committed,
working state stays gitignored. Enforce the split with layered defenses (gitignore + `ssd-init`
migration + new gate rule), document the boundary clearly, and dogfood by committing this
repo's own `.ssd/features/*` artifacts.

## Source

Conversation thread from 2026-05-24 (parallel-features epic close), where the question "now
that we're allowing multiple people to work on multiple things, what are the pros and cons
of having `.ssd/` in the repo" was discussed. The answer surfaced as a split design with
recommended layered enforcement (Layers 1–3 mandatory, 4–5 optional). This epic implements
that recommendation.

## Goal

A user-visible outcome at the end of three iterations:

- A new project initialized with `ssd-init` gets a `.gitignore` pattern that allows briefs,
  architect specs, coder-status, code-review, and deploy artifacts to land in PRs, while
  blocking `current.yml`, `current.notes.yml`, `init-log.md`, `archive/`, `audits/`, and any
  other machine-managed or per-user state.
- Existing projects (including this one) can migrate via `ssd-init --migrate-gitignore`
  prompted, with `.bak` backup, same UX pattern as ADR-0002's v1→v2 migration.
- `/ssd gate` includes a sixth rule, `no-leaky-state`, that fails the gate if any
  gitignored-by-policy file appears in the staged diff. Catches force-add and edited-gitignore
  cases.
- A documented, optional pre-commit hook is available for teams that want pre-commit
  enforcement on top of the gate rule.
- This repo's own `.ssd/features/ssd-skill-upgrades/`, `.ssd/features/parallel-features/`,
  and `.ssd/features/ssd-commit-split/` artifacts are tracked in git after iter C ships,
  giving SSD's own history a permanent record.

## Non-goals

- **Multi-machine state synchronization for the same user.** Out of scope. `current.yml` is
  per-checkout by design; users who want cross-machine continuity can manually copy.
- **Locking on shared `current.yml`.** If multiple users edit it simultaneously, git's normal
  conflict resolution handles it. No bespoke locking protocol.
- **Hiding the gitignore implementation from users.** The split is *visible* — anyone reading
  `.gitignore` sees what's in vs. out. No magic.
- **Retroactive commit of historical archive entries.** `.ssd/archive/` stays gitignored;
  only currently-active workstreams' artifacts get tracked.
- **Forcing the split on solo-developer projects.** Single-user projects that prefer the
  blanket gitignore opt out via `ssd-init --keep-blanket-gitignore` or by editing the
  `.gitignore` to restore the blanket. The split is the default; the blanket is a one-flag
  override.

## Likely deliverables (subject to architect refinement)

- **ADR-0008:** `.ssd/` selective commit split.
- **Updated `.gitignore` pattern** for new projects (and a migration path for existing ones).
- **`ssd-init` migration** (`--migrate-gitignore` flag, prompted, idempotent).
- **New gate rule** `no-leaky-state` in `methodology/gate-rules.sh`.
- **Optional pre-commit hook** in `methodology/hooks/`.
- **Documentation updates** to `ssd/SKILL.md` § "The SSD Artifact Tree", `ssd-init/SKILL.md`,
  and a new `.ssd/README.md` template that explains the split.
- **Dogfood commit:** this repo's `.ssd/features/{ssd-skill-upgrades, parallel-features,
  ssd-commit-split}/*.md` artifacts get tracked (iter C).

## Acceptance criteria

1. **New-project test.** `ssd-init` on a fresh repo writes the selective gitignore pattern.
   A subsequent `/ssd feature new foo` creates `00-brief.md` that is trackable (`git status`
   shows it as untracked, NOT ignored). `current.yml` remains gitignored.
2. **Existing-project migration test.** `ssd-init --migrate-gitignore` on a repo with the
   blanket `.ssd/` pattern detects the blanket, prompts the user, writes `.gitignore.bak`,
   and replaces with the selective pattern. Idempotent — running again is a no-op.
3. **Gate rule test.** `/ssd gate` on a workstream that has staged `current.yml` (e.g.,
   via `git add -f`) fails with `FAIL no-leaky-state :: current.yml is gitignored by policy
   but staged in the diff`. The orchestrator refuses to pass the gate.
4. **Force-add bypass test.** Even if a user runs `git add -f .ssd/current.yml`, the gate
   rule catches it. No silent merge.
5. **Pre-commit hook test (iter B).** A user who installs the optional hook gets a pre-commit
   failure with the same message as the gate rule. Hook is symlinkable from
   `methodology/hooks/`.
6. **Opt-out test.** A user who runs `ssd-init --keep-blanket-gitignore` (or has it set in
   `.ssd/project.yml`) gets the all-gitignored behavior. No prompts, no migration. The gate
   rule still runs but its deny-list is empty for that project.
7. **Dogfood commit test (iter C).** After iter C lands, this repo's `git ls-files .ssd/`
   returns the brief / architect / coder-status / code-review files for all three completed
   epics. `current.yml`, `init-log.md`, `archive/` remain untracked.
8. **No-regression test.** Existing single-user flow (init, feature loop, gate, ship) is
   unchanged for users who keep the blanket. Single-feature flow is unchanged for users who
   adopt the split (briefs become trackable but nothing else changes).

## Files in scope (preliminary, architect refines)

| File | Iteration | Change |
|---|---|---|
| `docs/decisions/ADR-0008-ssd-commit-split.md` | A | NEW |
| `.gitignore` (this repo, and the pattern in `ssd-init` template) | A | EDIT — selective pattern |
| `ssd-init/SKILL.md` | A | EDIT — Step 5 (gitignore section) + new migration flow |
| `methodology/gate-rules.sh` | A | EDIT — new `no-leaky-state` rule |
| `ssd/SKILL.md` | A | EDIT — § "The SSD Artifact Tree" + § "Methodology Enforcement" gain `no-leaky-state` row |
| `methodology/hooks/pre-commit-no-leaky-state.sh` | B | NEW — optional pre-commit hook |
| `methodology/hooks/README.md` | B | NEW — how to install hooks |
| `ssd-init/SKILL.md` | B | EDIT — mention hook installation as optional |
| `.gitignore` (this repo) | C | EDIT — switch to selective pattern (the dogfood) |
| (existing `.ssd/features/*/*.md` files) | C | Become tracked via the new gitignore pattern |
| `CHANGELOG.md` + `VERSION` | A, B, C | per-iteration bumps |

## Out-of-scope

- Synchronizing `current.yml` across machines (the multi-machine continuity request).
- Bespoke locking on `current.yml` when multiple users edit (git handles it).
- Hiding any of this from users (the split is visible; no magic).
- Retroactive commits of `.ssd/archive/` historical data.
- Migrating the existing `.ssd/audits/` directory (stays gitignored).

## Open questions for architect

1. **Per-file vs per-directory gitignore patterns.** Should we go pattern-by-pattern (verbose
   but explicit: every artifact file named) or directory-by-directory (concise but less
   audit-able)? Recommend: directory-rooted patterns with explicit file allow-lists for
   `features/<slug>/**/*.md`.
2. **`ssd-init` migration default.** When `ssd-init` detects a blanket `.ssd/` pattern, should
   it migrate by default (auto, prompted) or stay blanket (opt-in, requires `--migrate`)?
   Recommend: prompted migration by default for `developer_profile: standard` and `expert`;
   default to keeping the blanket for `novice`.
3. **`no-leaky-state` rule deny-list source.** Hard-coded in the script, or read from
   `.ssd/project.yml`? Hard-coded is simpler; project.yml is more flexible. Recommend:
   hard-coded with a `project.yml.ssd.gitignored_state: [list, of, additional, patterns]`
   override for project-specific extensions.
4. **Pre-commit hook install mechanism.** Symlink from `methodology/hooks/` to
   `.git/hooks/pre-commit`, or copy, or use a hook framework (husky, pre-commit.com)?
   Recommend: plain symlink (no framework dependency, matches existing bash-script
   precedent from `gate-rules.sh`).
5. **What about `.ssd/audits/`?** Currently gitignored. Audits are durable artifacts (they
   describe vendor selection / legacy onboarding decisions). Stay gitignored or move into
   the committed set? Recommend: stay gitignored for this epic (audits are typically
   sensitive — they name vendors, surface internal opinions). Revisit separately if needed.
6. **What about `.ssd/milestones/`?** Currently gitignored. Milestone artifacts (skeptic
   reviews, refactor plans) are arguably more durable than features. Same question:
   committed or not? Recommend: committed (matches the briefs-and-reviews-are-design-docs
   logic). Architect decides.

## Iteration plan (architect confirms / refines)

- **Iter A (v1.18.0):** ADR-0008, gitignore migration, `no-leaky-state` gate rule. The
  enforcement floor.
- **Iter B (v1.19.0):** Pre-commit hook + documentation polish. Optional team-level safety.
- **Iter C (v1.20.0):** Dogfood — commit this repo's own `.ssd/features/*` artifacts.
  Verifies the whole chain works on the project that originated the methodology.
