---
skill: ssd (orchestrator, /ssd feature, iteration b)
version: 1.18.0
produced_at: 2026-06-10T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-commit-split iteration B — optional pre-commit hook + docs polish
consumed_by: [coder, code-reviewer]
---

# Brief — Iteration B: optional pre-commit hook

## What is being asked

Second of three iterations of the ssd-commit-split epic. Iter A (v1.18.0) shipped the
enforcement floor: selective `.gitignore` pattern + `ssd-init` migration flow + the
`no-leaky-state` gate rule that catches force-add bypasses and edited-gitignore regressions
at `/ssd gate` time. Iter B adds the **optional pre-commit hook** that catches the same
class of issues *before* the commit lands, plus polish on the migration UX.

## What ships in iter B

1. **`methodology/hooks/pre-commit-no-leaky-state.sh`** — bash hook script that calls
   `gate-rules.sh --rules no-leaky-state` against the staged diff. Fires before the commit
   lands. Bypassable via `--no-verify` but SSD doctrine forbids that.
2. **`methodology/hooks/README.md`** — installation docs. Symlink convention (no husky /
   pre-commit.com framework dependency, matches `gate-rules.sh`'s no-framework precedent).
   Cover: install, upgrade, uninstall, integration with existing pre-commit hooks.
3. **`ssd-init/SKILL.md` update** — mention the hook as an optional install during init for
   `developer_profile: expert`. The prompt is opt-in (default skip); novices and standards
   don't see it unless they ask.
4. **CHANGELOG.md v1.19.0 entry + VERSION bump.**

## What does NOT ship in this iteration

- **Dogfood backfill of historical artifacts.** Already done by the user in commit
  `b6fc739 added features stuff` (between v1.18.0 ship and this iter B start). All 16
  artifacts under `.ssd/features/parallel-features/` and `.ssd/features/ssd-skill-upgrades/`
  are now tracked. Iter C's original dogfood scope is satisfied by that commit; iter C
  becomes optional follow-up (README update + any polish).
- **Pre-commit framework integration** (husky, pre-commit.com). Out of scope per the iter A
  architect spec § Q4 — plain symlink is the SSD convention.
- **CI integration recipes.** Documented as recommended elsewhere; not added in this PR.
- **Auto-install of the hook on `ssd-init`.** Hook install is always opt-in and explicit;
  `ssd-init` *offers* but never *runs* the install. The user controls their git hooks.

## Acceptance criteria

1. **Hook script runs correctly.** Symlinking
   `methodology/hooks/pre-commit-no-leaky-state.sh` to `.git/hooks/pre-commit` and then
   running `git commit` on a staged forbidden file (e.g., force-added `.ssd/current.yml`)
   exits non-zero with the same FAIL message format as the gate rule.
2. **Clean commits pass through unchanged.** Same symlink, normal commit of allowed files —
   the hook exits 0 silently (no output unless something is wrong, per standard hook
   convention).
3. **README explains the install path.** A user reading `methodology/hooks/README.md` can
   install the hook in <5 minutes with one `ln -s` command, no framework setup.
4. **ssd-init prompt is opt-in.** A novice or standard profile user running `ssd-init` does
   NOT see the hook-install prompt. An expert profile user does, with a clear "yes / no /
   skip" choice. The prompt offers install but never auto-installs.
5. **Existing pre-commit hook coexistence.** A user who already has a `pre-commit` hook can
   add the no-leaky-state check by invoking the script from inside their existing hook.
   README documents this path.
6. **No-regression.** The `no-leaky-state` gate rule (iter A) is unchanged; the hook is a
   client of that rule via `gate-rules.sh --rules no-leaky-state`.

## Files in scope

| File | Change |
|---|---|
| `methodology/hooks/pre-commit-no-leaky-state.sh` | NEW — ~30 line bash hook |
| `methodology/hooks/README.md` | NEW — install / uninstall / coexistence docs |
| `ssd-init/SKILL.md` | EDIT — Step 5 closing prompt or new Step 5.5 with optional hook install offer |
| `CHANGELOG.md` | EDIT — v1.19.0 entry |
| `VERSION` | EDIT — 1.18.0 → 1.19.0 |
| `.ssd/features/ssd-commit-split/iterations/b/` | NEW — brief, architect spec, coder-status, code-review |

## Out-of-scope

- Auto-install of the hook (always opt-in by symlink)
- Husky / pre-commit.com framework integration
- CI integration recipes (documented but not implemented here)
- Iter C polish (README update mentioning this repo dogfoods its own artifacts — small,
  could be its own follow-up or rolled into iter B if time permits)

## Open questions for architect

1. **Hook script: stage-diff or commit-diff?** Iter A's `gate-rules.sh --base main` uses
   `git diff --name-only $BASE...HEAD` — that's commit-to-commit. The pre-commit hook
   needs to check the **staged** diff (what's about to be committed), which is
   `git diff --cached --name-only`. Resolution: introduce a `--staged` flag on
   `gate-rules.sh` that switches to `git diff --cached --name-only`? Or have the hook
   compute the staged file list separately and pass it some other way?
2. **ssd-init prompt placement.** Step 5 currently handles `.gitignore` migration; the hook
   install is a related but distinct optional. Inline in Step 5 (after migration), or new
   Step 5.5? Recommend: new Step 5.5 keeps responsibilities clean.
3. **Iter C scope.** Now that user has backfilled the 16 artifacts manually in commit
   `b6fc739`, iter C's original "stage all historical artifacts" scope is satisfied. Does
   iter C still ship as v1.20.0 with the README update + retro on the commit-split rollout?
   Or roll the README update into iter B (this PR) and declare the epic complete at v1.19.0?
   Recommend: roll README update into iter B; epic complete at v1.19.0.
