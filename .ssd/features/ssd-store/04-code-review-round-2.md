---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-31T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: branch fix-store-key-collision vs main (v2.10.1)
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
closed_from_previous_round: [MAJOR-1]
---

# Code Review — ssd-store, round 2

**Verdict: `gate_pass: true`.** MAJOR-1 closed and verified by reversion. Parity **258 → 264**.

## Phase 1.5 — prior-round follow-up

| ID | Claim | Status | How verified |
|---|---|---|---|
| MAJOR-1 | `root`/`dir` collide with `project.root`; DRIFT unreachable and a false FAIL once configured | **closed** | Reverted `gate-rules.sh` to the bare keys → 2 assertions fail, including *"genuine drift IS caught"* |

## MAJOR-1 — closed

Renamed to `store_root` / `store_dir` / `store_auto_commit`: flat, each unique in `project.yml`, both
existing readers unmodified. Call sites updated in `store.sh` (`do_status`, `store_dir_name`) and
`gate-rules.sh` (`rule_store_link_sane`), with the reason recorded inline at both so the next reader
does not "tidy" them back into a nested block.

The fixture asserts three things, deliberately of two kinds:

- **Structural** — neither reader may look up a bare `root`/`dir` key. This is the only way to catch a
  future regression *at the source*, since the behavioural symptom depends on config that most projects
  will not have.
- **Behavioural, positive** — a healthy link with `store_root`/`store_dir` filled in must **PASS** and
  must not report DRIFT. This is the false-FAIL half of the defect, and the fixture builds a
  `project.yml` that carries `project.root` exactly as `ssd-init` writes it.
- **Behavioural, negative** — genuine drift (`store_root` pointing elsewhere) must still **FAIL**. This
  is the assertion that matters most: a "fix" that simply deleted the unreachable check would have
  passed every other test while making the rule permanently blind. It failed against the shipped code,
  which is the evidence the check was dead rather than merely mis-keyed.

Docs updated to match the shipped keys: `ssd-init` template and Step 5.6, `chapters/phases.md`,
`chapters/artifacts.md`, README, and an ADR-0018 addendum recording the correction and why the
block-scoped-getter alternative was rejected.

## Re-verified after the fix

| Claim | How |
|---|---|
| Regression floor | 264/264; all 258 pre-existing pass |
| The three leak layers | Unchanged and still asserted (`store-symlink-is-ignored`, `deny-list-catches-symlink`, `store-link-sane-verdicts`) |
| `link` still non-destructive by default | `store-link-dry-run` and `store-link-confirm` unchanged and green |
| Selective refusal intact | `store-link-refuses-selective` green |
| No new YAML machinery | Both readers untouched; only the key strings changed |

## Self-verification

Read both call sites and the fixture. The closure was verified by **execution** — reverting the rename
and watching the fixture fail — not by reading the change. The one claim I checked rather than assumed
was whether the DRIFT check was merely mis-keyed or genuinely dead: the negative assertion failed
against shipped code, proving dead.

**Gate: PASS.** Ready to ship as v2.10.1.
