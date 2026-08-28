---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: working-tree diff on add-ssd-private-mode (16 paths) + round-1 closures
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 1
  suggestion: 1
  nit: 0
gate_pass: true
remediation_mode: true
round: 2
closed_from_previous_round: [MAJOR-1, MAJOR-2, MINOR-1, MINOR-2, NIT-1]
---

# Code Review — ssd-private-mode (iteration A), round 2

**Verdict: `gate_pass: true`.** All five round-1 findings closed and **independently verified by
reverting each fix and confirming the new fixture fails** — not by reading the closure claim. One
QUESTION (pre-existing, out of scope) and one SUGGESTION (optional) carry forward; neither blocks.

Parity: **83 → 127 assertions** (+44). Live dogfood re-run on the fixed code: **6 pass · 4 skip ·
0 fail**, gate exit 0.

## Phase 1.5 — prior-review follow-up

| ID | Claim | Status | How verified |
|---|---|---|---|
| MAJOR-1 | `file_mtime` BSD-first emits garbage on GNU | **closed** | Reverted to BSD-first → new fixture fails on **both** assertions. Restored → passes. |
| MAJOR-2 | private branch drops `gitignored_state` | **closed** | Reverted the union → `private-honors-gitignored-state` fails (`expected FAIL, got 'PASS'` — the exact silent-miss). Also confirmed live. |
| MINOR-1 | worktree feynman glob broader than diff scope | **closed** | Reverted the glob → `feynman-private-scope-mirrors-diff` fails (`expected SKIP, got 'FAIL'`). |
| MINOR-2 | missing `^ssd:` guard in `apply_gate_inputs_present` | **closed** | Guard present at [migrate.sh:302](../../../methodology/migrate.sh#L302); matches both siblings. |
| NIT-1 | misplaced comment before `done` | **closed** | Comment block moved above the `while`. |

No finding was left silent. `deferred.yml` is absent (single-cycle iteration), so the
Deferred-Findings phase does not apply and `deferred_handled` is correctly omitted.

---

## MAJOR-1 — closed, and the fix is stronger than the one I proposed

[gate-rules.sh:177-196](../../../methodology/gate-rules.sh#L177) now tries GNU first **and**
validates the result is a bare integer:

```bash
file_mtime() {
  local v
  v=$(stat -c %Y "$1" 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; return; }
  v=$(stat -f %m "$1" 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; return; }
  echo ""
}
```

Reversion test — BSD-first restored, both assertions fail:

```
· file-mtime-portability: GNU form (stat -c %Y) is attempted before BSD (stat -f %m)
· file-mtime-portability: file_mtime validates its output is a bare integer
```

**Worth recording: the first version of this fixture passed for the wrong reason.** Its ordering
check grepped the whole file, so it matched the *explanatory comment* above `file_mtime` — which
names both forms — rather than the code. Against the reverted BSD-first implementation it stayed
green, and only the validation assertion caught the regression. The fixture now scopes the grep to
the function body via `awk '/^file_mtime\(\)/,/^}/'`, and the comment in the fixture records why.

That is the third instance of the same root cause in this workstream: **a check that cannot fail
looks identical to a check that passes.** `find -newermt` (coder phase), BSD-first `stat` (round 1),
and a comment-matching assertion (round 2) were all invisible until something forced them to fail.
The two `-ge` comparison sites now cannot silently consume a non-integer.

The `unreadable` counter at [gate-rules.sh:441](../../../methodology/gate-rules.sh#L441) converts an
empty return into `SKIP … mtime unreadable` — honest, and never a false FAIL.

## MAJOR-2 — closed, and factored so the drift cannot recur

The `gitignored_state` read is hoisted **above** the mode branch
([gate-rules.sh:588-598](../../../methodology/gate-rules.sh#L588)) and unioned into both deny-lists.
The private branch uses `"${private_baseline[@]}" ${additional[@]+"${additional[@]}"}` — the same
`${arr[@]+…}` empty-array guard the selective path already used, correct under `set -u`.

This is the structurally right fix rather than the minimum one. Round 1 offered "hoist it or read it
inside the branch"; hoisting means there is now **one** deny-list assembly for both modes, so the
two call sites that drifted no longer exist independently. Verified live on the dogfood repo:

```
FAIL no-leaky-state :: private mode — 1 SSD file(s) tracked but must not be: .env.local|
```

with `gitignored_state: [.env.local]` declared in a private project — previously a silent PASS.

## MINOR-1 — closed; scopes now recognize the same artifact set

Worktree scope is two `find` calls ([gate-rules.sh:833-836](../../../methodology/gate-rules.sh#L833)):
bare `feynman.md` under `.ssd/features` + `.ssd/milestones`, and `feynman-*.md` under `docs/audits/`
only — mirroring the diff-scoped case patterns exactly. `.ssd/features/f1/feynman-draft.md` with
`contradicted: 9` now SKIPs (correct: not a report in either scope), while a bare `feynman.md` with
`contradicted: 1` still FAILs. Both arms asserted.

Splitting into two `find` invocations instead of one `-path`-filtered expression is the right call
here — `-path`/`-prune` portability across BSD and GNU is exactly the class of assumption that
produced MAJOR-1.

## MINOR-2 / NIT-1 — closed

`grep -qE '^ssd:' "$pj" || return 1` added, with a comment citing the traced consequence (a no-op
insert surfacing as a vague `ERROR` rather than an actionable `return 1`). Now consistent with
[migrate.sh:220](../../../methodology/migrate.sh#L220) and [:234](../../../methodology/migrate.sh#L234).
Comment relocated above the `while`.

---

## Carried forward (non-blocking)

**💭 QUESTION-1 — pre-existing, unchanged.** A commented `test_command` placeholder can never satisfy
`detect gate-inputs-present`, so "no test framework detected" reports `ERROR` rather than a clean
PENDING. Reachable on `selective` at v2.7.0; the private branch inherits the shape without worsening
it. Belongs on its own issue, not this workstream.

**💡 SUGGESTION-1 — partially superseded, still open.** `deny-list-mirrors-pattern-file` remains a
spot-check of four known values rather than a set-equality test. MAJOR-2 turned out to be the more
dangerous drift — between *code paths*, not between the two files — and hoisting closed that class
structurally. The file-vs-file check is now the weaker of the two risks, but it is still the one
guarding the pattern the privacy promise rests on. Reasonable to defer to iteration B, which touches
`private.gitignore` again for the retrofit.

---

## Re-verified after the fixes

| Claim | How |
|---|---|
| Regression floor intact | All 83 pre-existing assertions pass; 127/127 total. |
| Selective mode untouched | `/ssd gate` on this repo unchanged. Every change sits inside a `mode == "private"` branch or above it in shared setup. |
| Each new fixture can actually fail | Reverted all three fixes individually; each produced exactly one failing fixture (two assertions for MAJOR-1). This is the check round 1 demanded. |
| Deadlock still fixed after refactor | Dogfood: 254 arch lines, untracked ADR → `PASS adr-delta`, gate exit 0. Confirmed the ADR is genuinely untracked (`git ls-files --error-unmatch` errors) and `git status --untracked-files=all` is empty. |
| Promoted gate inputs work | With `test_command` + `feature_flag_marker` in `project.yml`, both rules PASS — 6 verifying rules under private mode, against the 1-of-9 baseline that motivated ADR-0015. |

## Self-verification

Read every file cited and confirmed the line numbers resolve after the edits. Both MAJORs were
verified by execution — reverting the fix and watching the fixture fail — not by tracing alone. No
sub-agents were used, so no unverified escalation. The one speculative claim in round 1 (GNU `stat`
behavior, which I could not execute here) was stated as an inference from `-f` = `--file-system` and
is now defended by output validation that holds regardless of which variant runs — the fix does not
depend on my inference being right.

**Gate: PASS.** Clear to proceed to `/ssd gate` and ship iteration A.
