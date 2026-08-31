---
skill: coder
version: 1.4.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-store
consumed_by: [code-reviewer]
files_touched:
  - methodology/store.sh
  - methodology/gate-rules.sh
  - methodology/private.gitignore
  - methodology/SKILL.md
  - ssd-init/SKILL.md
  - ssd/SKILL.md
  - ssd/chapters/artifacts.md
  - ssd/chapters/phases.md
  - ssd/chapters/enforcement.md
  - docs/decisions/ADR-0018-ssd-artifact-store.md
  - README.md
  - CHANGELOG.md
  - VERSION
  - scripts/parity-test.sh
tests_added:
  - scripts/parity-test.sh::test_fixture_selective_artifacts_still_committable
  - scripts/parity-test.sh::test_fixture_store_symlink_is_ignored
  - scripts/parity-test.sh::test_fixture_deny_list_catches_symlink
  - scripts/parity-test.sh::test_fixture_store_link_dry_run
  - scripts/parity-test.sh::test_fixture_store_link_confirm
  - scripts/parity-test.sh::test_fixture_store_link_refuses_selective
  - scripts/parity-test.sh::test_fixture_store_link_sane_verdicts
  - scripts/parity-test.sh::test_fixture_store_gitignore_minimal
  - scripts/parity-test.sh::test_fixture_store_commit_local_only
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: |
    fixture: selective-artifacts-still-committable
    fixture: store-symlink-is-ignored
    fixture: deny-list-catches-symlink
    fixture: store-link-dry-run
    fixture: store-link-confirm
    fixture: store-link-refuses-selective
    fixture: store-link-sane-verdicts
    fixture: store-gitignore-minimal
    fixture: store-commit-local-only
    ================================================================
    PASS — 258/258 assertions
lint_results:
  command: "shellcheck -S warning methodology/store.sh methodology/gate-rules.sh"
  exit_code: 127
type_check_results:
  command: "bash -n (store.sh, gate-rules.sh, parity-test.sh)"
  exit_code: 0
feature_flag:
  name: "project.yml.ssd.store block (absent ⇒ inert)"
  default: off
spec_drift: true
---

# Coder Status — ssd-store

## Test / lint / typecheck

| | Command | Result |
|---|---|---|
| Test | `bash scripts/parity-test.sh` | **exit 0 — 258/258** (was 205; **+53**) |
| Typecheck | `bash -n` × 3 | exit 0 |
| Lint | `shellcheck` | **exit 127 — not installed.** Pre-existing environment gap, recorded identically in every prior workstream. |

All 205 pre-existing assertions still pass. `/ssd gate` on this branch: 6 pass · 5 skip · 0 fail.

## Red-first, and what could not go red

Three fixtures were written before any implementation, per the spec's handoff note. **8 assertions were
genuinely red:**

| Fixture | Red? |
|---|---|
| `store-symlink-is-ignored` (4) | ✅ against the real `private.gitignore` |
| `deny-list-catches-symlink` (2 of 4) | ✅ against the real `matches_deny_pattern` |
| `store-link-dry-run` (2 of 5) | ✅ `store.sh` did not exist |

Every later fix was verified by **reversion**: reverting the bare `.ssd` line fails 3 assertions;
reverting the `mv` fix fails 6; re-adding the bare `.ssd` to `selective.gitignore` fails 7.

## The three safety layers (§5 of the spec)

The mechanism is one symlink; the *feature* is the protection around it. Verified before writing code
that a symlinked `.ssd` defeated **both** existing layers — `.gitignore` (trailing-slash patterns match
directories only; to git a symlink is a file) and `no-leaky-state` (`matches_deny_pattern ".ssd"
".ssd/"` is a non-match). Unaddressed, the feature would commit the user's home path into the
repository they are keeping private.

## Spec drift (`spec_drift: true`)

Both amended into [01-architect.md](01-architect.md) and [ADR-0018](../../../docs/decisions/ADR-0018-ssd-artifact-store.md).

**Drift 1 — the store is incompatible with `selective` mode, and both the spec and the ADR said the
opposite.** They claimed the store was independent of private mode and that *both* pattern files should
gain a bare `.ssd`. One test settled it:

```
$ git add .ssd/features/f1/00-brief.md
fatal: pathspec '.ssd/features/f1/00-brief.md' is beyond a symbolic link
```

**Git cannot track files through a directory symlink at all.** Selective mode's entire purpose becomes
silently impossible. `link` now refuses on `selective`, `store-link-sane` FAILs on it, and both records
carry the correction.

**Drift 2 — the bare `.ssd` line must not go into `selective.gitignore`.** I put it there first. A bare
pattern excludes the *directory*, and gitignore cannot re-include a file under an excluded parent, so
every `!.ssd/features/**/…` negation went inert and a selective project committed **nothing** under
`.ssd/` — `git add -A` staged only `.gitignore`. **The full 205-assertion suite passed while that was
true.** No fixture asserted selective mode's core promise; `selective-artifacts-still-committable` now
does, and it is the fourth instance in this epic of a suite that could not see a shape it never built.

## Two bugs the live dogfood found that the fixtures had not

1. **`mv src dest` with an existing `dest` moves src *inside* it.** `init` pre-creates `<root>/<dir>`,
   so the happy path produced `<dest>/.ssd/…`. The clobber guard only fired on a *non-empty*
   destination, so an empty pre-created directory walked straight into the trap. `link` now `rmdir`s an
   empty destination first and refuses if anything else is there.
2. **Verifying that the link *resolves* is not enough.** A misplaced move leaves a symlink to a real
   directory whose content is one level too deep — healthy-looking until a file is opened. `link` now
   verifies a file that was actually moved, and `store-link-sane` reports `MISPLACED-CONTENT` instead of
   the bogus `SELECTIVE-MODE` it had inferred from an unreadable `project.yml`.

**And one bug in my own fixtures**, worth recording because it is a harness trap others will hit:
`bash "$GATE_SCRIPT" … | grep -q …` does not work under this suite's `set -o pipefail` — the gate exits
1 whenever a rule FAILs, and pipefail propagates that, defeating the `&&` even when grep matched. Six
assertions silently reported failure for that reason. Capture first, then grep the variable. Noted in
the fixture so the next author does not repeat it.

## Live dogfood

Throwaway private-mode project with real SSD history:

```
store init                     → repo + minimal .gitignore + README
store link (dry run)           → lists 4 files, exit 10, NOTHING moved
store link --confirm           → .ssd -> …/private-ssd/proj, 4 files moved, .gitignore updated
read through the link          → brief, nested iteration brief, project.yml all readable
git check-ignore .ssd          → IGNORED ✓     git add -A → staged []
gate store-link-sane           → PASS (repo …/private-ssd)
store commit -m "code: auth"   → 0e41207 (local; not pushed)
store commit --auto (again)    → exit 0, no commit, silent
store history                  → 1 commit containing current.yml, project.yml, both briefs
```

## For the reviewer

1. **`store.sh do_link` is the only destructive path.** Scrutinise the ordering: refuse-to-clobber →
   enumerate → dry-run → `rmdir` empty dest → `mv` → verify-through-link → `.gitignore`. Specifically
   whether any input could move content without the user having seen it listed.
2. **The cross-device fallback deliberately does not delete the original** and returns 3 without creating
   the symlink, telling the user to verify and re-run. That leaves a duplicate on purpose — losing
   artifacts is worse than leaving one.
3. **`store-link-sane` reads `project.yml` through the link.** If the link is misplaced, the mode reads
   as `selective` by default; the rule checks reachability *first* so it reports the real cause. Confirm
   that ordering is right.
4. **No `# REVIEW:` markers.** The two design questions the brief reserved (layout, commit policy) were
   user-ratified; the three hazards were closed by testing, not assumption.

## Deliberately not built

Worktree fan-out (each linked worktree needs its own `.ssd` symlink — documented in ADR-0018, not
automated), an `unlink` verb (reversing is `mv` back plus `rm` the link; automating it would add a
second destructive path for no gain), and a `migrations.yml` entry for the store (it is an elective
posture like private mode, and `store.sh link` already is the retrofit).
