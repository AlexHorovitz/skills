---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: working-tree diff on add-ssd-private-mode-b (13 paths) + round-1 closures
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 0
  suggestion: 0
  nit: 0
gate_pass: true
remediation_mode: true
round: 2
closed_from_previous_round: [MAJOR-1, MAJOR-2, MINOR-1, MINOR-2, SUGGESTION-1]
---

# Code Review — ssd-private-mode#b, round 2

**Verdict: `gate_pass: true`.** All five round-1 findings closed, each verified by reverting the fix and
confirming the guarding fixture fires. Parity **176 → 188** (+12). No new findings.

## Phase 1.5 — prior-round follow-up

| ID | Claim | Status | How verified |
|---|---|---|---|
| MAJOR-1 | `git ls-files` C-quoting breaks classification and `git rm` | **closed** | Reverted `-z` → `elect-handles-unusual-filenames` fails (2 assertions, incl. "every SSD path is untracked") |
| MAJOR-2 | Config written before the destructive step is validated | **closed** | Moved the config write back above the pre-flight → the ordering assertion fires |
| MINOR-1 | `set_yaml_scalar` unscoped | **closed** | Removed the block scoping → the decoy assertion fires |
| MINOR-2 | No fixture covers unusual filenames | **closed** | The fixture now exists and was red before the `-z` fix |
| SUGGESTION-1 | `--confirm` inert outside `--elect` | **closed** | Now `exit 2` with a corrective message |

No finding was left silent. `deferred.yml` absent → phase not applicable.

---

## MAJOR-1 — closed

`tracked_ssd_paths` is now `git ls-files -z … | sort -z`, and all four consumers read with
`read -r -d ''`: the classifier, the `rm` array, and the post-action re-verify. The contract change is
documented on the function with the reason (*"`-z` IS LOAD-BEARING, not hygiene"*) and the three
distinct consequences enumerated.

Verified live on a repo with an accented ADR, which pre-fix made the retrofit impossible:

```
SSD-owned artifacts to be untracked (3):
  .ssd/features/auth/00-brief.md
  docs/decisions/ADR-0001-café-auth.md      ← correctly classified now
  docs/runbooks/auth.md
--confirm → rc=0 · tracked after: .gitignore app.py · file still on disk: yes
```

The apostrophe and space cases still pass, so the fix did not trade one filename class for another.

## MAJOR-2 — closed, and independent of MAJOR-1 as required

The destructive step is pre-flighted with `git rm --cached --dry-run` **before** any write:

```
dry-run pre-flight → apply_private_mode_config → git rm --cached → re-verify
```

Round 1 asked for the fix to be independent of MAJOR-1's, and it is — the pre-flight validates every
pathspec regardless of *why* one might be bad, so a cause nobody has thought of still aborts with the
repo untouched. Both failure branches now say **"NOTHING has been changed"**, and the post-`rm` branch
says *"AFTER the dry-run passed … this should not happen"*, which is the right register for a state
that should now be unreachable.

**On the fixture:** once `-z` landed, the only failure this fixture could previously trigger stopped
failing, and every remaining runtime failure needs injection the harness cannot do. The fixture is
therefore honest about mixing kinds — one behavioral assertion on the reachable failure (no `ssd:`
block → nothing changed) plus a **structural** assertion that the pre-flight precedes the config write
— and the comment says why. Confirmed the structural assertion fires when the order is swapped, so it
is not decoration.

## MINOR-1 — closed

`set_yaml_scalar` takes a block argument and scopes the rewrite between `^<block>:` and the next
top-level key, matching `bump_recorded_version`'s hardening. Call sites: `ssd` for `gitignore_mode` and
`branch_pattern`, `integrations` for `issue_tracking`.

The fixture now seeds a **decoy** `gitignore_mode` under an earlier top-level block and asserts it is
left alone, and asserts `issue_tracking` is still found inside `integrations:` despite living in a list
item. Verified on a dogfood `project.yml` carrying both a `- type: jira` and a `- type: github` entry:
only github's key was rewritten.

## MINOR-2 / SUGGESTION-1 — closed

The unusual-filenames fixture exists and was genuinely red. `--confirm` without `--elect` now exits 2
with *"Did you mean: --elect private-mode --confirm?"* — verified.

---

## A note on how MAJOR-1 got through

Worth recording, because the coder-status was right to be proud of the red-first discipline and MAJOR-1
does not contradict that — it qualifies it. Ten fixtures were written, several genuinely red, and every
guard was reversion-verified. All of them used ASCII filenames.

**Red-first on the cases you thought of is not coverage.** The bug was not in logic the tests exercised
badly; it was in an input class the tests never produced. This is the same family as the five instances
already logged in this workstream — a check that cannot fail — but the mechanism is different: not a
broken assertion, a missing *input*. Two smaller instances of the older mechanism also appeared during
this round and were fixed before landing:

- The first MAJOR-2 fixture chose a failure trigger (`no ssd: block`) that aborts *before* the writes,
  so it tested a path that was already safe.
- The first MAJOR-1 assertion grepped for `héllo` in output that renders it as `h\303\251llo`, so it
  could not have failed.

Both were caught by asking "would this fail if the bug were present?" rather than by running the suite.

## Re-verified after the fixes

| Claim | How |
|---|---|
| Regression floor | 188/188; all 128 pre-existing pass |
| Sweep safety unchanged | Full-window `--apply` on a team repo: index byte-identical, mode still `selective` |
| Two-layer guarantee intact | Both layers still present and asserted |
| Idempotency | Second `--confirm` → "already private; nothing to do", exit 0, no duplicated pattern |
| Files survive | Non-ASCII ADR confirmed on disk after untracking |
| `issue-sync` refuses post-retrofit | `REFUSED`, exit 4 (measured without a pipe) |
| Dry-run still dry | `elect-dry-run-mutates-nothing` remains a real test (shown to fail when the dry-run mutates) |

## Self-verification

Read every function cited; line-anchored claims re-checked after the edits. Both MAJOR closures were
verified by execution — reverting each fix and watching the specific fixture fail — not by reading the
change. The one place I corrected my own round-1 reasoning is MAJOR-2's mitigation: I had written that
the half-migrated state would be "loud", then checked and found `no-leaky-state` SKIPs without a diff,
so the finding says *conditionally* loud. No sub-agents.

**Gate: PASS.** Clear to proceed to `/ssd gate`.
