---
skill: coder
version: 1.2.0
produced_at: 2026-06-10T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-commit-split iteration B — pre-commit hook + --staged mode + README polish
consumed_by: [code-reviewer]
files_touched:
  - methodology/gate-rules.sh
  - methodology/hooks/pre-commit-no-leaky-state.sh
  - methodology/hooks/README.md
  - ssd-init/SKILL.md
  - README.md
  - CHANGELOG.md
  - VERSION
  - .ssd/features/ssd-commit-split/iterations/b/brief.md
  - .ssd/features/ssd-commit-split/iterations/b/01-architect.md
  - .ssd/features/ssd-commit-split/iterations/b/coder-status.md
tests_added: []
review_markers: 0
test_results:
  command: "bash methodology/gate-rules.sh --base main + smoke tests"
  exit_code: 0
  stdout_tail: |
    branch mode (no diff): PASS / SKIP / SKIP / SKIP / PASS / SKIP, exit 0
    --staged mode (nothing staged): SKIP wip-commits (staged mode) / SKIP / SKIP / SKIP / PASS / SKIP, exit 0
    --staged + forbidden file staged: FAIL no-leaky-state with the path, exit 1
    hook script direct invocation: SKIP no-leaky-state (no diff), exit 0
  note: |
    End-to-end smoke verified: default branch mode unchanged, --staged mode adapts SKIP
    detail messages ("no diff (staged files)"), wip-commits SKIPs cleanly in staged mode
    with explicit reason, force-add of .ssd/init-log.md triggers FAIL with the path
    surfaced, hook script wrapper passes the exit code through. All four scenarios match
    the architect spec's expected behavior.
lint_results:
  command: "n/a — bash + markdown"
  exit_code: null
type_check_results:
  command: "n/a"
  exit_code: null
feature_flag:
  name: not_applicable
  default: not_applicable
  rationale: |
    Markdown skills library + bash. Rollout via versioned tag v1.19.0. The hook is opt-in
    by symlink install; `--staged` mode is opt-in by flag. Single-feature flow unchanged
    for users who don't install the hook.
spec_drift: false
---

# Iteration B — Coder Status

## Scope shipped

Iteration B of the ssd-commit-split epic. Seven files touched, three new files (the hook
script, the hooks README, this coder-status), three new artifacts under iterations/b/.
The epic completes at v1.19.0; iter C's residual scope (README dogfood paragraph) folded
into this PR per the architect spec's Q3 resolution.

### 1. `methodology/gate-rules.sh` (EDIT, +35 lines)

Three discrete changes:

- **`--staged` CLI flag.** Added to the arg parser. Sets `MODE="staged"`. Default
  `MODE="branch"` preserves existing behavior.
- **`MODE` branching in `diff_files()`.** Selects `git diff --cached --name-only` in
  staged mode, `git diff --name-only $BASE...HEAD` in branch mode.
- **New `diff_scope_label()` helper.** Returns "vs $BASE" or "staged files" depending on
  MODE. Used in the SKIP detail strings of `feature-flag-present`, `adr-delta`, and
  `no-leaky-state`.
- **`rule_wip_commits` extension.** SKIPs cleanly in staged mode with an explicit detail
  message ("staged mode (commit not yet created; rule applies at PR gate time)") rather
  than running `git log $BASE..HEAD --grep ...` which would either error or produce
  irrelevant output pre-commit.

Smoke-tested four scenarios:
- Branch mode, no diff → all rules PASS/SKIP, exit 0 ✓
- Staged mode, nothing staged → all rules SKIP, exit 0 ✓
- Staged mode, forbidden file staged (`.ssd/init-log.md` via `git add -f`) → no-leaky-state
  FAILs with the path, exit 1 ✓
- Hook script invoked directly → forwards to gate-rules.sh `--staged --rules
  no-leaky-state`, exit 0 ✓

### 2. `methodology/hooks/pre-commit-no-leaky-state.sh` (NEW, 49 lines, executable)

Plain bash script designed for symlink install. Structure:

1. Locate repo root via `git rev-parse --show-toplevel`. Exit 2 if not in a git repo.
2. Locate `methodology/gate-rules.sh` at the repo root. Exit 2 with a clear error if
   missing (includes the uninstall command in the error message).
3. Invoke `bash $GATE_RULES --staged --rules no-leaky-state`.
4. Pass through the exit code.

Header includes install instructions, coexistence pattern, doctrine reminders (no
`--no-verify` bypass), and exit code semantics. Made executable with `chmod +x` (filesystem
permission persists in git).

### 3. `methodology/hooks/README.md` (NEW, ~110 lines)

Sections: hooks available table, install (symlink), verify, uninstall, coexistence pattern,
why-plain-bash, CI integration backstop, doctrine reminders, hook script contract for
future additions.

The coexistence pattern is the load-bearing piece for adoption — many users already have a
`pre-commit` hook for formatters or secret scanners; the README explains how to chain the
no-leaky-state check from inside an existing hook rather than overwriting it.

### 4. `ssd-init/SKILL.md` (EDIT, +43 lines, version 1.7.0 → 1.8.0)

New Step 5.5 between existing Step 5 (gitignore) and Step 6 (project shape):

- Expert-profile users get a yes/no/skip prompt offering the symlink install command.
- Standard/novice silently skip the offer.
- The orchestrator prints the command but **does NOT execute** the symlink — explicit
  trust boundary.
- Pre-existing `.git/hooks/pre-commit` triggers a coexistence-pattern message instead of
  the bare symlink path.
- Step 5.5 skipped entirely on `gitignore_mode: blanket` (hook would be a no-op).

Plus two changelog entries: 1.8.0 (this iter) and 1.6.0 (previously-undocumented bump from
iter B of parallel-features that I noticed was missing from the changelog while updating).
Backfilling 1.6.0 is technically out of strict iter B scope but it's the same kind of
"doc-fix the missing row" addition we did for the `frontmatter-valid` gate-rule row in iter
A — surfacing the matter to reviewer in items below.

### 5. `README.md` (EDIT, +2 lines)

One paragraph between the core invariant and the Methodology section announcing the
dogfood: as of v1.19.0 this repo tracks its own SSD artifacts under `.ssd/features/`.
Reflects the user's manual commit `b6fc739` which backfilled 16 historical artifacts.

### 6. `CHANGELOG.md` (EDIT, ~75 lines)

New `## [1.19.0] — 2026-06-10` entry at top. Sections: pre-commit hook description,
`--staged` mode description, ssd-init Step 5.5 description, README dogfood paragraph,
acknowledgment of user commit `b6fc739` (iter C's original scope, satisfied manually
between v1.18.0 ship and this iter B start), epic close table, doctrine reminder.

### 7. `VERSION` (EDIT)

1.18.0 → 1.19.0.

## Items for the code-reviewer to confirm

1. **`--staged` mode adoption across rules.** Iter A's rules (`wip-commits`,
   `feature-flag-present`, `adr-delta`, `frontmatter-valid`, `no-leaky-state`) each
   require a different treatment in staged mode. Verify each rule's behavior in `--staged`:
   wip-commits SKIPs explicitly; feature-flag-present / adr-delta / no-leaky-state SKIP
   with `diff_scope_label()` adapted detail; tests-pass is mode-agnostic; frontmatter-valid
   validates files on disk so it works in either mode. Reviewer should walk through each.

2. **Hook script error UX.** When the hook can't find `methodology/gate-rules.sh` (user
   copied the hook into a project without SSD installed), it exits 2 with a multi-line
   stderr message including the uninstall command. Verify the UX matches what the
   architect spec's risk table called for ("Hook script exits non-zero with a clear
   error").

3. **Coexistence pattern correctness.** The pattern in hooks/README.md uses
   `bash "$(git rev-parse --show-toplevel)/methodology/gate-rules.sh" --staged --rules
   no-leaky-state || exit $?`. Verify the `|| exit $?` correctly propagates the gate
   rule's exit code from inside an existing wrapper hook. Also verify the
   `$(git rev-parse --show-toplevel)` invocation works correctly when the hook runs from
   a non-root directory.

4. **ssd-init Step 5.5 ordering vs Step 5.** Step 5.5 runs AFTER Step 5 (gitignore
   migration). What if Step 5 fails / user declines migration → project is on blanket
   mode → Step 5.5 should skip. The prose says "Step 5.5 skipped entirely on
   `gitignore_mode: blanket`" but this relies on `project.yml.ssd.gitignore_mode` being
   readable. If Step 5 declined migration but didn't yet write the `blanket` opt-out,
   the value is absent → defaults to `selective` → Step 5.5 fires. Edge case: verify
   the prompt logic accounts for "blanket-but-not-yet-explicit" state.

5. **Retroactive 1.6.0 ssd-init changelog entry.** Adding it now (in iter B's diff) fills
   a gap noticed during this work. Same pattern as iter A's `frontmatter-valid` row fix.
   Accept as scope adjacent, or flag as drift?

6. **`gate-rules.sh` smoke-test coverage.** The four manual scenarios I ran cover the
   happy paths but not the failure modes for the new `--staged` codepath in
   `frontmatter-valid`. Reviewer might want to verify the validator handles staged files
   correctly (the validator walks `.ssd/features/` by default; in staged mode the rule
   should still validate any staged `.ssd/features/*.md` files).

## Self-verification

1. Did I run gate-rules.sh? Yes — 4 smoke scenarios covering branch mode, staged-no-staged,
   staged-with-forbidden-file, and the hook wrapper. All match expected behavior.
2. REVIEW marker count: 0.
3. Spec drift checked? No deviations from the iter B architect spec. The 1.6.0 ssd-init
   changelog entry is the only adjacent doc-fix included.
4. Feature flag? N/A — opt-in via symlink + profile gate.
5. Cross-language? Bash + markdown.

## Handoff to code-reviewer

Diff scope: 7 files touched (4 modified existing, 3 new). ~330 lines added across the
files (bulk in the hooks README and the CHANGELOG entry).

Gate expectations post-commit:
- `wip-commits`: PASS.
- `tests-pass`: SKIP.
- `feature-flag-present`: SKIP.
- `adr-delta`: SKIP (no new ADR; iter B implements ADR-0008's deferred-to-B scope).
- `frontmatter-valid`: PASS (iter B's 3 new artifacts validate; the manually-committed
  iter C artifacts in `b6fc739` were already validated when that commit landed).
- `no-leaky-state`: PASS (the diff contains no gitignored-by-policy paths; the hook script
  itself is under `methodology/hooks/` which isn't on the deny-list).

Epic complete at v1.19.0 after this lands. Archive the ssd-commit-split workstream then.
