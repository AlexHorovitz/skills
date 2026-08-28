---
skill: coder
version: 1.4.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-private-mode
consumed_by: [code-reviewer]
files_touched:
  - methodology/private.gitignore
  - methodology/gate-rules.sh
  - methodology/issue-sync.sh
  - methodology/migrate.sh
  - methodology/SKILL.md
  - ssd-init/SKILL.md
  - ssd/SKILL.md
  - ssd/chapters/artifacts.md
  - ssd/chapters/enforcement.md
  - docs/decisions/ADR-0017-private-mode.md
  - docs/decisions/ADR-0015-ssd-init-gate-readiness.md
  - README.md
  - CHANGELOG.md
  - VERSION
  - scripts/parity-test.sh
tests_added:
  - scripts/parity-test.sh::test_fixture_private_gitignore_sentinel
  - scripts/parity-test.sh::test_fixture_private_deny_list_mirrors_pattern
  - scripts/parity-test.sh::test_fixture_private_no_leaky_state
  - scripts/parity-test.sh::test_fixture_unrecognized_gitignore_mode
  - scripts/parity-test.sh::test_fixture_adr_delta_private_no_deadlock
  - scripts/parity-test.sh::test_fixture_frontmatter_valid_private_walks_tree
  - scripts/parity-test.sh::test_fixture_feynman_clean_private_worktree
  - scripts/parity-test.sh::test_fixture_issue_sync_refuses_private
  - scripts/parity-test.sh::test_fixture_migrate_private_na_entries
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: |
    fixture: private-gitignore-sentinel
    fixture: deny-list-mirrors-pattern-file
    fixture: no-leaky-state-private
    fixture: unrecognized-gitignore-mode
    fixture: adr-delta-private-no-deadlock
    fixture: frontmatter-valid-private-walks-tree
    fixture: feynman-clean-private-worktree
    fixture: issue-sync-refuses-private
    fixture: migrate-private-na-entries
    ================================================================
    PASS — 120/120 assertions
lint_results:
  command: "shellcheck -S warning methodology/*.sh scripts/parity-test.sh"
  exit_code: 127
type_check_results:
  command: "bash -n (all four modified shell scripts)"
  exit_code: 0
feature_flag:
  name: "project.yml.ssd.gitignore_mode: private"
  default: off
spec_drift: true
---

# Coder Status — ssd-private-mode (iteration A)

Iteration A of [ADR-0017](../../../docs/decisions/ADR-0017-private-mode.md) per
[01-architect.md](01-architect.md) §8. Greenfield private mode works end to end; retrofit is iter B.

## Test / lint / typecheck

| | Command | Result |
|---|---|---|
| Test | `bash scripts/parity-test.sh` | **exit 0 — 120/120** (was 83/83; +37 assertions) |
| Typecheck | `bash -n` on all four modified shell scripts | exit 0 |
| Lint | `shellcheck` | **exit 127 — not installed.** Pre-existing environment gap, recorded identically in the `github-issue-tracking` iter-B status. Not introduced here and not resolvable from inside this workstream. |

**Regression floor held.** All 83 pre-existing assertions still pass. `/ssd gate` on this repo
(`selective`) is unchanged: 5 pass · 5 skip · 0 fail.

## What was built

**1. `methodology/private.gitignore`** — new canonical single source (sibling of
`selective.gitignore`). Ignores `.ssd/`, `docs/decisions/`, `docs/runbooks/`, `docs/architecture/`.
Contains **no `!` negation of any kind**, and carries the `# ssd:gitignore-mode=private` sentinel.

**2. `gate-rules.sh`** — three new helpers and three touched rules:
- `gitignore_mode()` — single mode reader, defaults `selective`.
- `artifact_scope()` — `worktree` under private, `diff` otherwise.
- `base_commit_epoch()` + `file_mtime()` — portable mtime probe (see Drift 1).
- `no-leaky-state`: accepts `private` with an expanded deny-list mirroring the pattern file;
  **unrecognized values now FAIL** instead of SKIP.
- `adr-delta`: worktree fallback — the deadlock fix.
- `feynman-clean`: worktree glob; its `find` `-o` group is now parenthesized so the implicit
  `-print` binds to both alternatives rather than only the last.
- `frontmatter-valid`: **unchanged** — its existing no-diff branch already walks the tree. Pinned by
  a fixture so a future refactor cannot silently blind private projects.

**3. `issue-sync.sh`** — `preflight` refuses under private mode (`exit 4`, `state=refused`,
`reason=private-mode`) **before any `gh` call**.

**4. `migrate.sh`** — `is_private_mode()`; `committed-gate-yml` and `strict-selective-gitignore`
report satisfied under private; `apply_gate_inputs_present` writes to `project.yml` (see Drift 2).

**5. `ssd-init/SKILL.md`** — `--private` flag and the privacy offer; Step 5 short-circuit + §"Private
mode"; Step 5.5 three-way detection with the order made explicit; Step 6 template; Step 3 note;
Step 8 skip; interface row; idempotency rule.

**6. Docs + records** — ADR-0017 (new, Proposed); ADR-0015 addendum; `chapters/artifacts.md`
three-mode comparison table; `chapters/enforcement.md` rule rows + a diff-vs-worktree-scope note;
README §"Private mode (optional)"; `methodology/SKILL.md` catalog rows for **both** pattern files;
CHANGELOG 2.8.0; `VERSION` → 2.8.0; banners (`ssd` 2.8.0, `ssd-init` 1.12.0, `methodology` 1.8.0).

## Live dogfood (throwaway repo, not this one)

Per §11 rollout stage 2, on a scratch repo initialized to private mode by hand, running a full
feature cycle (brief, architect spec, ADR, 254 architectural lines, coder-status):

```
$ git show --stat HEAD          # what actually landed
 app.py          |   4 +
 auth_service.py | 250 +++++++++++++++++++++++++++++++++
 2 files changed, 254 insertions(+)          ← zero SSD artifacts

$ gate-rules.sh --base main
PASS adr-delta       :: 1 ADR file(s) modified since base for 254 architectural lines
                        (private mode: worktree mtime probe, weaker than a diff)
PASS frontmatter-valid :: 1 artifact(s) validated against schemas
PASS no-leaky-state  :: private mode — no SSD artifact tracked in diff (vs main)
PASS tests-pass · PASS wip-commits
GATE 5 pass · 5 skip · 0 fail          EXIT=0
```

The `adr-delta` PASS is the acceptance criterion: **254 architectural lines, an untracked ADR, gate
exit 0.** Under naive diff-scoping this is the exact case that deadlocks.

All four negative paths verified on the same repo:

| Scenario | Result |
|---|---|
| Force-add an ADR (`git add -f`) | `FAIL no-leaky-state :: private mode — 1 SSD file(s) tracked but must not be` · gate exit 1 |
| `issue_tracking` present with private | `REFUSED preflight :: state=refused private-mode …` · exit 4 |
| Typo `gitignore_mode: privat` | `FAIL no-leaky-state :: unrecognized gitignore_mode … leak detection is NOT running` |
| Gate inputs promoted to `project.yml` | `PASS tests-pass` · `PASS feature-flag-present` (both would SKIP without the promotion) |

## Spec drift (`spec_drift: true`)

Both amended into [01-architect.md](01-architect.md) rather than left as a silent mismatch.

**Drift 1 — `find -newermt` replaced with a portable `stat` probe.** §6 named
`git log -1 --format=%cI` piped to `find -newermt`. **That mechanism is broken on macOS:** BSD `find`
rejects the `@epoch` form outright (`Can't parse date/time`), so the probe would have been a
permanent FAIL on every private macOS project — trading the deadlock for a different unpassable gate.
Shipped as a portable `stat -f %m` / `stat -c %Y` read over a plain glob, plus **one second of slack**
because mtimes are second-granular while `-newermt`/`-nt` are strictly-greater (an ADR written in the
same second as the base commit would not have counted). Contract unchanged; mechanism only.

**Worth stating plainly:** this bug was invisible during design because the interactive shell has a
GNU-compatible `find` shim. Only the fixture — which runs under `bash`, where `/usr/bin/find` is what
you get — exposed it. The design phase asserted this mechanism from knowledge; the test caught it.

**Drift 2 — `apply_gate_inputs_present` made private-aware (added scope).** Not in §8's iter-A list.
Without it, `migrate.sh` writes gate inputs to `.ssd/gate.yml` while `ssd-init` writes them to
`project.yml` — two writers disagreeing about the same config, which is the dual-source drift
ADR-0013's extraction work exists to prevent — and `--apply` would create a `.ssd/gate.yml` that
ADR-0017 states cannot exist in this mode. Small and in-scope; a reviewer would have flagged the
absence as MAJOR.

**One unplanned fix, not drift.** `issue-sync.sh`'s `emit()` hard-coded an `OK ` prefix, so the new
refusal printed `OK preflight :: … state=refused`. A refusal announcing itself as OK is precisely the
misleading-green-signal class ADR-0015 exists to eliminate. Now `REFUSED` for `state=refused` only;
every other state keeps `OK`, so no existing caller or fixture is affected.

## Deliberately NOT built (iteration B)

`migrations.yml` `private-mode` entry · `detect_private_mode()` / `apply_private_mode()` · the
itemized-consent interlock before any `git rm --cached` · the history-not-rewritten warning ·
`branch_pattern` plumbing in `chapters/workstreams.md`.

`ssd/chapters/workstreams.md` and `methodology/migrations.yml` appear in `current.yml.touches` but
were **not** modified — both are iter-B surface. `touches` should be trimmed at gate time or left as
the epic-level intent; flagging so the reviewer's overlap check does not read it as missing work.

**Iteration A never runs `git rm --cached`.** The one destructive operation is quarantined behind its
own review cycle — the boundary rationale from §8, honored.

## For the reviewer

1. **`private_baseline` in `gate-rules.sh` vs `private.gitignore`** — the same set in two syntaxes.
   Fixture `deny-list-mirrors-pattern-file` asserts agreement, but it checks the four *current*
   entries; adding a fifth to one file only would need the fixture updated too. This is ADR-0008's
   documented dual-maintenance trap and the highest-value thing to scrutinize.
2. **The mtime probe is weaker than a diff, by design.** An mtime is touchable. The detail string says
   so. The alternative was an unpassable gate; if you disagree with that trade, §6 is the place.
3. **`no-leaky-state` FAIL on an unrecognized mode is a behavior change for existing projects** — a
   project with a pre-existing typo that used to SKIP will now FAIL. Intended (that SKIP was silently
   disabling leak detection), but it is not purely additive and belongs in the release notes. It is in
   the CHANGELOG.
4. **No `# REVIEW:` markers.** Nothing in this diff is a genuine open uncertainty: the two design
   questions that were open (H2, the four-rule analysis) were resolved by measurement and by reading
   the rule bodies, and both mechanisms have failing-then-passing fixtures behind them.
