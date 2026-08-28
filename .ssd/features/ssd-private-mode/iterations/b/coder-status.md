---
skill: coder
version: 1.4.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-private-mode#b
consumed_by: [code-reviewer]
files_touched:
  - methodology/migrations.yml
  - methodology/migrate.sh
  - ssd/chapters/upgrade.md
  - ssd/chapters/workstreams.md
  - ssd/SKILL.md
  - methodology/SKILL.md
  - docs/decisions/ADR-0013-project-upgrade-migration-manifest.md
  - docs/decisions/ADR-0017-private-mode.md
  - README.md
  - CHANGELOG.md
  - VERSION
  - scripts/parity-test.sh
tests_added:
  - scripts/parity-test.sh::test_fixture_elective_inert_in_default_sweep
  - scripts/parity-test.sh::test_fixture_elective_not_applied_by_sweep
  - scripts/parity-test.sh::test_fixture_read_manifest_eight_columns
  - scripts/parity-test.sh::test_fixture_read_manifest_empty_middle_field
  - scripts/parity-test.sh::test_fixture_elect_lists_every_tracked_file
  - scripts/parity-test.sh::test_fixture_elect_classifies_docs
  - scripts/parity-test.sh::test_fixture_elect_history_warning_both_runs
  - scripts/parity-test.sh::test_fixture_elect_confirm_untracks
  - scripts/parity-test.sh::test_fixture_elect_validation
  - scripts/parity-test.sh::test_fixture_elect_dry_run_mutates_nothing
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: |
    fixture: elective-inert-in-default-sweep
    fixture: read-manifest-eight-columns
    fixture: read-manifest-empty-middle-field
    fixture: elect-lists-every-tracked-file
    fixture: elect-dry-run-mutates-nothing
    fixture: elective-not-applied-by-sweep
    fixture: elect-classifies-docs
    fixture: elect-history-warning-both-runs
    fixture: elect-confirm-untracks
    fixture: elect-validation
    ================================================================
    PASS — 176/176 assertions
lint_results:
  command: "shellcheck -S warning methodology/migrate.sh scripts/parity-test.sh"
  exit_code: 127
type_check_results:
  command: "bash -n (migrate.sh, gate-rules.sh, issue-sync.sh, parity-test.sh)"
  exit_code: 0
feature_flag:
  name: "migrations.yml private-mode entry (elective — inert until named)"
  default: off
spec_drift: true
---

# Coder Status — ssd-private-mode iteration B (elective retrofit)

No `deferred.yml` for this iteration (verified absent), so the deferred-findings phase does not apply
and `deferred` is correctly omitted from frontmatter.

## Test / lint / typecheck

| | Command | Result |
|---|---|---|
| Test | `bash scripts/parity-test.sh` | **exit 0 — 176/176** (was 128; **+48**) |
| Typecheck | `bash -n` × 4 scripts | exit 0 |
| Lint | `shellcheck` | **exit 127 — not installed.** Pre-existing environment gap, recorded identically in iteration A and in `github-issue-tracking` iter B. |

All 128 pre-existing assertions still pass.

## Red-first discipline — and an honest accounting of what could *not* go red

The handoff note said to write the guard fixtures first and watch them fail. I did, and I want to be
precise about which ones genuinely failed rather than claim a clean red-green sweep:

| Fixture | Red before implementation? |
|---|---|
| `elective-inert-in-default-sweep` (3 assertions) | ✅ **red** — once the manifest entry existed, the sweep listed it and pinned the version |
| `read-manifest-eight-columns` (2) | ✅ **red** — 7-column form |
| `elect-lists-every-tracked-file` (6) | ✅ **red** — `--elect` did not exist |
| `elect-dry-run-mutates-nothing` | ❌ **passed vacuously** — unknown arg exits 2, so nothing mutated. A guard, not a red-green test |
| `elective-not-applied-by-sweep` | ❌ **passed vacuously** — no `apply_private_mode` existed, so a sweep could not untrack either way |

**11 assertions were genuinely red.** The two that could not fail were verified afterwards by
reversion instead (below). Writing a fixture that cannot fail and calling it coverage is the exact
defect this workstream has now produced five times; I am not adding a sixth by mislabelling these.

## Reversion verification

Every guard was checked by breaking the implementation and confirming the fixture fires:

| Reverted | Result |
|---|---|
| Delimiter `\x1f` → tab | `read-manifest-empty-middle-field` fails (2 assertions) |
| Remove the elective `continue` **only** | `elective-inert-in-default-sweep` fails (3) — but **not** the acceptance test |
| Remove the `continue` **and** register `private-mode` in `apply_dispatch`/`detect` | `elective-not-applied-by-sweep` fails (4) — the sweep untracks |

That middle row is a genuine architectural finding, not a test artifact: **the guarantee has two
independent layers.** The report-loop skip is one; elective ids being *absent from the swept
dispatchers* is the other. Removing either alone does not make `--apply` destructive. Both are now
documented in `apply_dispatch`/`detect` and asserted by the acceptance fixture, so neither can be
quietly removed.

## Live dogfood — the retrofit case iteration A could not cover

A throwaway **team repo** on selective mode with real committed SSD history plus one team-authored doc
that predates SSD:

```
tracked before: 8 files

STEP 1  plain /ssd upgrade            → private-mode NOT mentioned              ✓
STEP 2  --apply --from 2.0.0 --to 2.9.0 (the dangerous invocation)
        index unchanged: YES · still gitignore_mode: selective                  ✓
STEP 3  --elect private-mode          → 4 SSD-owned + 1 UNCONFIRMED, exit 10    ✓
          SSD-owned:    00-brief.md, 01-architect.md, ADR-0001-auth.md,
                        docs/runbooks/auth.md   ← recognized by FRONTMATTER
          UNCONFIRMED:  docs/architecture/legacy-overview.md  ← the team's doc
STEP 4  --elect private-mode --confirm
        tracked after: .gitignore, Makefile, app.py  (zero SSD paths)           ✓
        files still on disk · gitignore_mode: private · branch_pattern: "{slug}"
        issue_tracking: off · issue-sync preflight → REFUSED exit 4             ✓
        re-run → "already private; nothing to do", exit 0, no duplicate pattern ✓
        /ssd gate → 3 pass · 7 skip · 0 fail
```

Step 2 is the acceptance criterion, and it held on a real repo: **a full-window `--apply` on a project
that never asked for privacy left every tracked SSD artifact tracked.**

One incidental confirmation worth recording: the gate initially FAILed on that repo with
`frontmatter-valid :: no frontmatter found` for a malformed artifact I had written by hand. That was my
fixture's fault, not a defect — but it demonstrates iteration A's tree-walk fallback earning its place,
because the offending file was **untracked** and a diff-scoped rule could never have seen it.

## Spec drift (`spec_drift: true`)

Both amended into [01-architect.md](01-architect.md) rather than left as a silent mismatch.

**Drift 1 — the record delimiter had to change (material).** §3.2 specified appending an 8th column to
the existing **tab**-separated record. That does not work, and it fails *silently*: tab is IFS
whitespace, so bash collapses consecutive tabs and every field after an empty one shifts left. The
7-column form was safe only because its one optional field (`obsoleted_in`) was **last**, where a
trailing empty field is harmless. Appending `elective` after it made every entry lacking an
`obsoleted_in` — **all of them** — read `elective` into the `ob` slot, so `--elect private-mode`
rejected its own manifest entry as *"not an elective migration."*

Shipped with the delimiter changed to `\x1f` (unit separator), verified empirically before adopting.
This widens the change from "append a column" to "the delimiter is part of `read_manifest`'s
contract," so all **three** consumers move together.

**Drift 2 — the docs classifier needed a third signal.** §4.3 step 3 said the flagged group was
"`docs/` files SSD did not create," and named runbooks/architecture as SSD-recognizable. Neither
holds: those filenames are feature-named and indistinguishable from any other doc, so the first
implementation flagged SSD's **own** runbooks. A warning that fires on the tool's own output trains the
user to ignore it — destroying the signal the interlock exists to give. Added an **SSD-frontmatter
probe** (`skill:` in the leading `---` block) and changed the heading to **"UNCONFIRMED as
SSD-produced"**, because the probe cannot establish authorship and the output must not claim more than
it supports.

**Two additions not in the spec, neither material:** `--elect` had to be exempted from the `--from`
requirement (it acts on one named id and exits, exactly like `--adopt`), and `set_yaml_scalar` was
added as a portable in-place YAML setter — **awk + mv, deliberately not `sed -i`**, since BSD requires
`-i ''` and GNU requires a bare `-i`, the same divergence that produced two defects in v2.8.0.

## For the reviewer

1. **`elect_private_mode` is the only destructive code path in `migrate.sh`.** It deserves the
   adversarial pass. Specifically: the enumerate→classify→warn→confirm→act→**re-verify** order, and
   whether any input could cause `git rm --cached` to run on a path the user was not shown.
2. **The classifier is a heuristic and cannot be otherwise.** Runbook/architecture filenames carry no
   SSD marker. The frontmatter probe closes the common case; a file SSD wrote *without* frontmatter
   still lands in UNCONFIRMED. That is the safe direction, but confirm the wording never overclaims.
3. **`.ssd/project.yml` did not appear in the dogfood list** — correct, because selective mode already
   gitignores it, so it was never tracked. Worth confirming that reasoning rather than assuming the
   enumerator missed it.
4. **`--elect` bypasses the version window entirely** (no `--from`, no `--to`). Intended — an elective
   migration is not part of version progression — but it means the recorded version is untouched by a
   retrofit. §7 risk 8 states this as a decision; check you agree it is coherent.
5. **No `# REVIEW:` markers.** Nothing here is a genuine open uncertainty: both design questions the
   brief reserved were resolved by reading the code, and every mechanism has a fixture that has been
   observed to fail.

## Deliberately not built

`parse_active_workstreams` fragmentation and QUESTION-2 remain out (hard rule 4) — both tempting,
since QUESTION-2 lives in `migrate.sh` which this iteration has open. Moving *out* of private mode is
also not built and is stated as such in the ADR-0017 amendment rather than implied by symmetry.
