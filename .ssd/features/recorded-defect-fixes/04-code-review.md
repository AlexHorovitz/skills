---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: branch fix-recorded-defect-fixes (PR #41) vs add-ssd-private-mode-b
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 1
  suggestion: 1
  nit: 0
gate_pass: true
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — recorded-defect-fixes (PR #41), round 1

**Verdict: `gate_pass: true`** — 0 BLOCKER, 0 MAJOR. One MINOR found **and fixed during this review**
(a tolerance regression in my own fix), one QUESTION carried as a documented limitation.

**Why this artifact exists.** `/ssd gate` was invoked and the mechanical rules passed, but PR #41 had
**no review artifact and no workstream entry** — so the review half of the gate had never run. Two
recorded defects were fixed and pushed with the rails' step 4 undocumented. Declaring that gate clean
would have been the same false-green this workstream has caught five times. This closes it.

## Phase 2 — design

Both fixes are minimal and correctly scoped. Neither is part of private mode, and keeping them out of
#36/#40 was right under hard rule 4. Stacking on `add-ssd-private-mode-b` rather than branching from
`main` is also right: all three of `migrate.sh`, `parity-test.sh` and `CHANGELOG.md` are touched by
both, and the base ref mechanically enforces merge order — #41 cannot reach `main` without #40 first.
Verified: `gh pr list` shows `#41 → add-ssd-private-mode-b`, `#40 → main`.

## 🟡 MINOR-1 — the fragmentation fix narrowed field-indent tolerance (found and fixed in this review)

The first implementation read workstream scalars only at exactly `bnd + 2`:

```awk
!have || ind != bnd + 2 { next }
```

Probed adversarially with a file using non-canonical field indent (fields at `bnd + 4` under a `bnd`
list item — unusual but valid YAML):

```
[gamma||]      <- slug survived, phase and issue LOST
```

The **previous** parser matched `/^[[:space:]]+phase:/` at any indent and handled that file correctly.
So the fix traded one defect for a narrower one: `issue:` goes empty, `bindings` is empty, and the rule
degrades to `SKIP … no active workstream has an issue binding`. Honest rather than a false PASS, which
is why this is MINOR and not MAJOR — but it is a needless regression.

**Fixed in this review.** The boundary rule (`ind == bnd`) is what fixes fragmentation; the field rule
does not need to be strict as well. Fields are now accepted at any depth inside the workstream
(`ind > bnd`), which handles all four probed cases:

| Case | Result |
|---|---|
| `active: []` inline empty | no output ✓ |
| two workstreams, both with nested lists | `[alpha\|code\|11]` `[beta\|review\|22]` ✓ |
| non-canonical `bnd+4` field indent | `[gamma\|code\|33]` ✓ (was `[gamma\|\|]`) |
| this repo's real `current.yml` | `[ssd-private-mode\|deploy\|39]` ✓ |

Safe against the documented schema: the only keys nested deeper inside a workstream are the
`rail_deviations` item fields (`step`/`reason`/`ts`) plus bare-string list items — none collide with
`slug`/`phase`/`issue`. Pinned by `parse-active-workstreams-indent-tolerance`, verified to fail against
the strict rule.

## 💭 QUESTION-1 — inconsistent list indent inside one `active:` block

`bnd` is set by the **first** list item. A hand-edited `current.yml` whose later items sit at a
different indent would have those workstreams **silently skipped** rather than fragmented. Both
behaviors are wrong on malformed input; a silent skip could let real mirror drift go unreported.

Left as a documented limitation rather than fixed, for two reasons: `current.yml` is machine-written
with consistent indent, and `chapters/state.md` already assigns malformed-`current.yml` handling to the
**orchestrator** ("surfaces the parse error and refuses to guess"), not to this parser. Raising it here
so the boundary is a recorded decision. If it ever matters, the fix is for the orchestrator to validate
before the rule runs — not for the parser to guess.

## Phase 3.5 — the Q2 fix as new defensive code

Each new guard reviewed as new code:

| Guard | Checked |
|---|---|
| `apply_committed_gate_yml` returns 8 before `ensure_gate_yml_header` | Correct, and deliberate: guarding *first* means no half-created `gate.yml`. Verified `gate.yml` still gets created by `gate-inputs-present` in the same sweep — a different convention, legitimately applied. |
| `apply_strict_selective_gitignore`'s two guards return 8 not 1 | No caller treats 1 specially; the loop dispatches on 8/9/0/other. |
| Could 8 mask a real failure? | Yes, narrowly: an unreadable `.gitignore` would fail `grep` and report "does not carry the selective block" rather than a permissions error. Misdiagnosis, not data loss, on a state neither code path handled before. Not worth a finding. |
| Control arms exist | Both fixtures assert the migrations still APPLY with the pattern present. A fix that made them unconditionally NOOP would be worse than the bug, and the suite would now catch it. |

## What I verified and did not flag

| Claim | How |
|---|---|
| The parser fix is real | Reverted the boundary rule → 5 assertions fail. On this repo the rule now PASSes for the first time. |
| The rule kept its teeth | Fixture asserts label/phase drift still FAILs, and names the slug — a fix that made the rule always pass would be worse than the bug. |
| The fixture can actually fail | With `gh` absent the rule SKIPs before the loop, so buggy and fixed code look identical — the first version of this fixture passed for exactly that reason. It now drives the rule through the mock-gh shim. |
| Q2's rejected alternative | Verified empirically: with `gitignore_mode: selective` present and no `.gitignore`, a `requires: selective-gitignore` guard reads "satisfied" while the real precondition is absent. The rejection is evidence-based and recorded in the CHANGELOG. |
| Merge order is enforced | #41's base is #40's branch, so #41 cannot merge to `main` first. Not a finding. |
| CHANGELOG's parity claim | Said 188 → 200; now 202 after MINOR-1's fixture. **Corrected in this commit.** |
| Tag backfill correctness | Each of v2.0.0/v2.5.0/v2.6.0/v2.7.0 verified three ways before tagging: `VERSION` at the commit, matching `CHANGELOG` top entry, ancestor of `main`. |
| No skill banner bumped | Correct — no `SKILL.md` content changed, so the banner-lag pattern says leave them. `skill-version-sync` passes. |

## 🔗 OVERLAP-1 — shares three files with `ssd-private-mode`

Two active workstreams now declare non-empty `touches`, so the cross-workstream overlap check runs
(first time this session — it was correctly skipped while only one workstream was active).

| Path | also modified by |
|---|---|
| `VERSION` | `ssd-private-mode` (phase `deploy`, branch `add-ssd-private-mode-b`) |
| `methodology/migrate.sh` | same |
| `scripts/parity-test.sh` | same |

**Intentional, and already serialized.** This overlap is the reason #41 is stacked on
`add-ssd-private-mode-b` rather than branched from `main`: the base ref mechanically prevents #41 from
reaching `main` before #40. Per [ADR-0007](../../../docs/decisions/ADR-0007-parallel-features.md)
§ "Alternatives Rejected", `OVERLAP-N` is **SUGGESTION tier and never blocks** — overlap is often the
intent, and it is here. Recorded so the serialization is a visible decision rather than an accident.

## Self-verification

Read every function changed. MINOR-1 was found by **probing the parser with inputs the fixtures did not
contain** — the same technique that found iteration B's two MAJORs, applied to my own fix this time. It
is also the sixth instance of this workstream's recurring theme, and the second of the *newer*
mechanism: not a check that cannot fail, but an input class never produced. No sub-agents.

**Gate: PASS.** The review half of #41's gate is now run and recorded.
