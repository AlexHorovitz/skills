---
skill: code-reviewer
version: 2.14.0
produced_at: 2026-09-21T21:20:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-autonomy (working tree, uncommitted)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 2
  question: 0
  suggestion: 0
  nit: 1
gate_pass: true
remediation_mode: true
round: 2
closed_from_previous_round: [MAJOR-1, MAJOR-2, MINOR-1, MINOR-2, MINOR-3, MINOR-4, QUESTION-1, SUGGESTION-1]
---

# Code Review — ssd-autonomy (round 2)

## Phase 1.5 — prior findings, by status

Every closure verified by re-running round 1's own reproduction, not by reading the coder status.

| ID | Claim | Status | How verified |
|---|---|---|---|
| MAJOR-1 | `--from` unchecked against recorded phase | **closed** | `transition --from code --to review` against a workstream at `design` now returns `state=stop reason=STOP-4` and logs nothing. The loop-budget bypass is structurally gone: reaching `review → code` requires `phase: review`, so the counter cannot be dodged by relabelling |
| MAJOR-2 | resolution ignores `iteration` | **closed** | Round 1's exact fixture re-run: `feat#a` (at ceiling, 97h over) is refused **on its own phase**; `feat#b` starts; the lock lands on b's entry with the record under `iterations/b/`. `--slug flat#z` and a bare `--slug feat` both refuse with a qualified `Active:` list |
| — | same defect in `deviation.sh` | **closed** | `deviation.sh record --slug feat#a` writes to iteration a's entry and leaves b's empty; fixture asserts it |
| MINOR-1 | wrong-shaped `current.yml` → traceback, exit 1 | **closed** | `printf -- '- not\n- a mapping\n'` now exits **3** with a readable message |
| MINOR-2 | `README.md` omits `/ssd run` | **closed** | present in the verb block |
| MINOR-3 | chapter omits the rule AC-1 rests on | **closed** | `chapters/autonomy.md` states `preflight` is called **iff** a block is present, in the `advance` section |
| MINOR-4 | `elapsed_minutes` conflated two meanings | **closed** | entries now carry `since_start_minutes` **and** `phase_minutes`; fixture key-set assertion updated |
| QUESTION-1 | is a budget stop really `red`? | **closed, with a rule** | `red` = something judged the work and said no; `incomplete` = the run stopped before anything judged it. STOP-3 is now `incomplete`. Documented as a table in the chapter |
| SUGGESTION-1 | no fixture for a rails-valid edge from the wrong place | **closed** | the mirror assertion exists and asserts **both** the STOP-4 and that nothing was logged |

**No finding is silent.** All eight are addressed in the diff, and the two MAJORs are closed at the
right granularity — the `deviation.sh` sweep is the part that makes that true rather than nominal.

## Phase 3.5 — the fixes are new code, reviewed as new code

Six probes against the defensive branches this round added. Four came back clean; two produced the
findings below.

- **`--from` check, absent phase.** `entry.get("phase") or "brief"` — a workstream with no `phase`
  and an announced `--from design` stops rather than proceeding. Correct.
- **STOP-4 vs STOP-2 ordering.** The new check runs before the successor-table check, so an edge that
  is *both* off-rails and from the wrong place reports STOP-4. Both remain reachable — verified
  separately (`--from design --to review` → STOP-2; `--from code --to review` → STOP-4). No finding.
- **Interrupted phase.** If a phase fails (STOP-6) the orchestrator never writes `phase`, so the next
  run's first transition stops at STOP-4. That is the loud behavior, not a regression.
- **`_block_iteration` vs nested keys.** The textual probe anchors on exact indentation
  (`^ {field_indent}iteration:`), so an `iteration:` nested deeper inside a workstream cannot match.
  Correct, and it agrees with the PyYAML path.
- **Duplicate `(slug, iteration)`** → MINOR-5 below.
- **The green path** → MINOR-6 below.

---

## 🟡 MINOR-5 — a duplicate `(slug, iteration)` silently resolves to the first match

[`methodology/autorun.sh:292-306`](../../../methodology/autorun.sh) · same shape in
[`methodology/deviation.sh`](../../../methodology/deviation.sh)

Round 1's fix made the key a pair. It did not make the pair *unique*. Traced:

```yaml
active:
  - {slug: feat, iteration: a, phase: design}
  - {slug: feat, iteration: a, phase: gate}     # same pair
```
```
$ autorun.sh start --slug feat#a --mode run --until gate
state=ok reason=- … from_phase=design
```

The run starts against the first entry, and the FM-1 message elsewhere in the same session prints
`Active: feat#a, feat#a, flat` — so the corruption is *visible* to the code and acted on anyway.

This matters because the library already has a documented stance on the analogous corruption. From the
spine, on duplicate `branch:` values: *"If the orchestrator encounters duplicate branches (a state
corruption from manual YAML editing), it emits an error and refuses to guess rather than picking a
first match."* `/ssd feature new` FM-3 rejects creating a duplicate pair, so this can only arise from
hand-editing — exactly the provenance that sentence describes.

**Fix:** count matches in `find_workstream`; more than one ⇒ refuse (exit 2) naming the duplicate.
Cheap, and it makes the new pair-matching consistent with the rule the spine already states.

## 🟡 MINOR-6 — no fixture asserts `outcome: green`

The suite asserts `outcome=red` (ceiling reached on a failing gate) and `outcome=incomplete` (STOP-3).
Grepping the suite for a green assertion returns **zero**. The terminal state the entire feature exists
to produce — a delegated run that reaches the gate and passes it — is unprotected by any test.

I verified by hand that it works:

```
$ autorun.sh finish --slug flat --stop STOP-7 --phase-reached gate --gate-output green.txt
state=ok reason=STOP-7 outcome=green gate_result=pass phase_reached=gate
  gate verdict from output file: 2 PASS rule(s), 0 FAIL in green.txt
```

That it works today is not the point; nothing stops the next edit to the outcome mapping from breaking
it silently. The round-1 mapping was `red` for everything that was not explicitly green, and the
rewrite inverted the structure — a change of exactly the kind a green assertion exists to catch.

**Fix:** extend the referee fixture's final phase — an all-`PASS` gate-output file, assert
`outcome=green gate_result=pass`. Three lines next to the existing red assertion.

## 📝 NIT-1

[`methodology/autorun.sh`](../../../methodology/autorun.sh), wall-clock check:
`elapsed_minutes = since_start_minutes` is a redundant alias introduced by the MINOR-4 rename and used
twice immediately below. Use `since_start_minutes` directly.

---

## Both referees

- **`code-reviewer`** (this review): `gate_pass: true` — 0 BLOCKER, 0 MAJOR.
- **`gate-rules.sh`**: `5 pass · 8 skip · 0 fail`, **and the eight skips are still `no diff (vs main)`.**

Unchanged from round 1 and worth restating because it is the single most misleading number in this
workstream: **the executable gate has not seen this change.** Nothing is committed, so `adr-delta`,
`no-leaky-state`, `rails-walked`, `deviations-recorded` and `feynman-clean` have had nothing to
inspect across two review rounds. A green `code-reviewer` verdict plus eight "no diff" skips is not a
passed gate; it is half a gate.

Cross-workstream overlap check: **skipped** — one active workstream.

## On the incident in this round's diff

The coder status records that a debug command with an empty `cd` overwrote `.ssd/project.yml` and
`.ssd/current.yml` in the real repo, and that both were restored by hand from the session transcript.
I verified the restored files parse under PyYAML **and** under the gate's own
`parse_active_workstreams`, and that `.ssd/features/` is back to 15 entries with no stray `feat/`.

Two observations, neither a finding against the diff:

1. **It was self-reported.** The failure mode this library keeps finding in itself is the *unrecorded*
   one. This was written down in the handoff notes, including the detail that matters.
2. **`current.yml.bak` was useless**, because the damage came from `cat >` rather than from a script
   that backs up before writing. The runbook's Step 3 ("restore") assumes a `.bak` written by the
   tool that did the damage. That assumption now has a counterexample, and
   [`docs/runbooks/ssd-state-recovery.md`](../../../docs/runbooks/ssd-state-recovery.md) § "Step 5 —
   no `.bak` exists" is the section that should say so. **Not blocking, and not this feature's job** —
   filed here so it is on the record rather than in a terminal scrollback.

---

## Verdict

**`gate_pass: true`.** Two MINORs and a NIT, none blocking. Round 1's two MAJORs are closed at the
right granularity, including the `deviation.sh` instance of the same class — which is the part that
distinguishes a fix from a patch.

**Before `/ssd ship`:** commit to a branch and re-run `bash methodology/gate-rules.sh`. The eight
skipped rules are the ones that check rails invariants, ADR proportionality and state leakage — the
gate's actual job. Neither review round could substitute for them, and neither claimed to.
