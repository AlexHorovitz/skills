---
skill: code-reviewer
version: 1.5.0
produced_at: 2026-06-10T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: branch add-ssd-commit-split-b vs main (uncommitted diff + 3 new artifacts under iterations/b/ that the iter-A gitignore makes trackable + 2 new files in methodology/hooks/)
consumed_by: [coder]
finding_counts:
  blocker: 0
  major: 0
  minor: 2
  question: 0
  suggestion: 1
  nit: 1
gate_pass: true
remediation_mode: false
round: 1
closed_from_previous_round: []
round_2_inline: true
round_2_closed: [MINOR-1, MINOR-2]
round_2_deferred_with_assent: [SUGGESTION-1, NIT-1]
round_2_finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 0
  suggestion: 0
  nit: 0
round_2_gate_pass: true
---

# Iteration B — Code Review (Round 1)

## Scope verified

- **Modified tracked files (5):** `CHANGELOG.md`, `README.md`, `VERSION`,
  `methodology/gate-rules.sh`, `ssd-init/SKILL.md`. ~182 lines net added.
- **New files (5):** `methodology/hooks/pre-commit-no-leaky-state.sh` (executable),
  `methodology/hooks/README.md`, and 3 iter B artifacts under
  `.ssd/features/ssd-commit-split/iterations/b/` that become trackable under the iter-A
  selective gitignore.
- **Gate-rules.sh smoke tests:** 4 scenarios run by coder (branch mode no-diff, staged-no-staged,
  staged-with-forbidden, hook-wrapper) — all match expected behavior.
- **Frontmatter-valid:** 16 artifacts validate.

## Verdict

🟢 **Gate passes.** Zero BLOCKER, zero MAJOR. Two MINORs — one is a real ordering concern in
ssd-init Step 5.5 that an LLM-executing orchestrator could trip on, one is wording polish.
One SUGGESTION (smoke test coverage gap). One NIT (retroactive changelog backfill).

The work is well-scoped and the architect spec's deferred-iter-C-folded-into-B move is
sound. The `--staged` flag is implemented cleanly with a small surface and adapted SKIP
messaging via the new `diff_scope_label()` helper. The hook script and README are
production-quality.

---

## Findings

### 🟡 MINOR-1 — `ssd-init` Step 5.5 has an ordering dependency that could trip the LLM

**Where:** [ssd-init/SKILL.md § "Step 5.5"](../../../../../../ssd-init/SKILL.md)

**Problem.** Step 5.5's closing sentence reads:

> If the project is on `gitignore_mode: blanket`, skip Step 5.5 entirely — the rule SKIPs
> under blanket mode anyway, so installing the hook would be a no-op.

But `gitignore_mode` is written to `.ssd/project.yml` in **Step 6** (Detect Project Shape).
At Step 5.5 execution time, `project.yml` may not yet exist (fresh init) OR the key may
be absent (project on the older v1.7.0 schema where it wasn't yet a key).

**Failure case.** Fresh project, user runs `ssd-init`. Step 5 writes the selective
gitignore pattern (default). Step 5.5 runs — the orchestrator checks for
`gitignore_mode` and finds `project.yml` absent. The default in the gate rule is
`selective`, so Step 5.5 proceeds and offers the hook — correct outcome.

**But:** user declined migration in Step 5 (kept blanket). Step 5.5 runs — `project.yml`
absent again, default is `selective`, prompt fires offering a hook the user has
implicitly rejected. **Wrong outcome.** The user gets prompted to install a hook that
would no-op for their setup.

**Suggested fix.** Gate Step 5.5 on the **outcome of Step 5**, not on `project.yml`. Either:

- (a) Make Step 5 set a variable (in-orchestrator state, not on disk) like
  `SSD_GITIGNORE_DECISION ∈ {selective, blanket}` that Step 5.5 reads.
- (b) Re-detect by reading the actual `.gitignore` file at Step 5.5 start: if it contains
  the selective marker line (`!.ssd/features/**/01-architect.md` is unique enough),
  proceed; if it contains a bare `.ssd/`, skip.

(b) is filesystem-state-grounded and resilient to project.yml absence. Recommend (b).

The fix is a 2-line addition to Step 5.5 prose: "Detect the gitignore mode by reading
`.gitignore` for the selective-pattern marker line. If absent (blanket mode kept), skip
Step 5.5."

**Why MINOR not MAJOR.** The wrong-prompt outcome is mildly annoying, not destructive.
User says "no" to the hook offer and moves on. But it's a real LLM-prompt-execution
ambiguity that the parallel-features architect spec EC-3 (validate-all-first) called out
as the kind of issue worth fixing in prose.

---

### 🟡 MINOR-2 — `wip-commits` staged-mode SKIP detail could be clearer

**Where:** [methodology/gate-rules.sh `rule_wip_commits`](../../../../../../methodology/gate-rules.sh)

**Current text:** `"staged mode (commit not yet created; rule applies at PR gate time)"`

The "rule applies at PR gate time" part is imprecise. The rule applies whenever
`gate-rules.sh` runs in branch mode (which is the default), NOT specifically "PR gate
time" — that's the most common use case but not the only one. A user running
`bash methodology/gate-rules.sh --base main` locally also gets wip-commits run.

**Suggested fix.** Reword to be precise:

```
"staged mode (rule grep'd a commit log; runs in branch mode after commit)"
```

Or simpler:

```
"staged mode (no commits to grep yet)"
```

Either is more accurate.

**Why MINOR.** Pure clarity issue; no behavior impact.

---

### 💡 SUGGESTION-1 — `--staged` mode smoke tests cover happy path; missing two rule-interaction cases

**Where:** [coder-status `test_results`](../../../coder-status.md)

The four smoke scenarios cover the matrix of `MODE = {branch, staged} × diff = {none,
something}` for `no-leaky-state` plus the hook wrapper. Missing:

1. **`adr-delta` in staged mode with staged source code but no staged ADR.** Expected:
   FAIL (above threshold) or SKIP (below threshold). Verify the threshold calculation
   works on staged diff sizes.

2. **`frontmatter-valid` in staged mode.** Subtle: the validator reads files from disk
   (`python3 methodology/frontmatter-validate.py <paths>`), but in staged mode the rule
   restricts to staged files. If the user has version-A staged and version-B in the
   working tree, the validator validates version-B — not what's about to be committed.

**Action.** No code fix needed for iter B; document the working-tree-vs-staged-content
caveat in the `frontmatter-valid` rule comment, and (separately) consider adding the two
scenarios to a future regression suite. Could be addressed in iter B's PR or deferred.

**Why SUGGESTION.** Forward-looking polish; doesn't block.

---

### 📝 NIT-1 — Retroactive ssd-init 1.6.0 changelog backfill (accept)

**Where:** [ssd-init/SKILL.md changelog](../../../../../../ssd-init/SKILL.md)

Coder added a previously-missing v1.6.0 entry while updating ssd-init for v1.8.0. Same
pattern as iter A of ssd-commit-split, which added the missing `frontmatter-valid` row to
ssd/SKILL.md's Methodology Enforcement table. Coder explicitly surfaces this in their item
5 for reviewer judgment.

**Reviewer judgment:** accept. The 1.6.0 work was real (added the four
parallel-features `ssd.*` keys to the project.yml template) but undocumented in the
changelog at the time of v1.16.0 ship. Backfilling now is a docs-fix adjacent to the
v1.8.0 work and the alternative (a separate PR) is overkill for a 6-line addition.

**Action.** None. Acknowledging the pattern.

---

## Coder's items addressed

| # | Question | Answer |
|---|---|---|
| 1 | `--staged` mode adoption per rule | ✓ Walked through: wip-commits SKIPs explicitly (new), feature-flag-present/adr-delta/no-leaky-state SKIP with `diff_scope_label()`, tests-pass mode-agnostic, frontmatter-valid validates files on disk (see SUGGESTION-1 for the working-tree-vs-staged-content caveat). |
| 2 | Hook script error UX | ✓ Exit-2 with multi-line stderr including uninstall command. UX matches architect risk-table expectation. |
| 3 | Coexistence pattern correctness | ✓ `|| exit $?` propagates correctly. `$(git rev-parse --show-toplevel)` works from any directory inside the repo. Pattern is sound. |
| 4 | Step 5.5 ordering vs Step 6 | See **MINOR-1** above. The Step 5.5 → Step 6 ordering creates the gitignore_mode-detection bug. Suggested fix: read `.gitignore` directly at Step 5.5 start. |
| 5 | Retroactive 1.6.0 ssd-init changelog | See **NIT-1** — accepted as adjacent docs-fix. |
| 6 | gate-rules.sh smoke-test coverage | See **SUGGESTION-1** — adr-delta + frontmatter-valid staged-mode scenarios untested. Acceptable; document caveats. |

---

## Substantive checks performed

| Check | Result |
|---|---|
| `--staged` flag implementation | ✓ Clean. New `MODE` variable, default `branch`, alternative `staged`. `diff_files()` branches on MODE. Backward-compatible. |
| `diff_scope_label()` helper | ✓ Returns the right string for each mode. Used consistently in SKIP detail messages across 3 rules. |
| `wip-commits` staged-mode SKIP | ✓ Behavior correct (skip when no commits exist yet). Wording polish noted as MINOR-2. |
| Hook script wrapper | ✓ Locates gate-rules.sh via `git rev-parse --show-toplevel`. Exits 2 with clear error if missing. Forwards exit code from gate-rules.sh. Header documents install, doctrine, exit codes. Made executable (`-rwxr-xr-x`). |
| Hook script executable bit persistence | ✓ File mode 0755 should be preserved when committed via git. Verified locally via `ls -la`. |
| `methodology/hooks/README.md` quality | ✓ Comprehensive — install, verify, uninstall, coexistence pattern, CI integration backstop, doctrine reminders, contract for future hooks. Strong adoption document. |
| ssd-init Step 5.5 prose | ✓ Profile-aware (expert offer; standard/novice silent). "Print don't execute" the install command — preserves user agency at the hook trust boundary. See **MINOR-1** for the ordering gap. |
| README dogfood paragraph | ✓ Concise. References ADR-0008 and the `.ssd/features/` path. Reflects the user's manual backfill commit. |
| CHANGELOG v1.19.0 entry | ✓ Comprehensive. Acknowledges the manual `b6fc739` backfill. Epic close table is clear. Matches v1.18.0 format. |
| Epic close at v1.19.0 (not v1.20.0) | ✓ Architect-spec-conformant. User-driven backfill in `b6fc739` satisfied iter C's original scope; folding the README polish into iter B closes the epic cleanly. |
| Scope discipline | ✓ Nothing from a hypothetical iter D leaked in. The `--staged` flag landed here because iter B's hook depended on it — architecturally sound, not scope creep. |
| Tone consistency | ✓ Matches existing voice. The hook script header is opinionated and direct (doctrine reminders). The README is practical with concrete commands. |

---

## Self-Verification (per code-reviewer/SKILL.md)

1. **Read actual files cited?** Yes — read all modified files end-to-end and the two new files.
2. **MAJOR/BLOCKER claims traced?** N/A — zero MAJOR/BLOCKER findings.
3. **Citations correct?** Line numbers from working-tree files at review time.
4. **Stated assumptions?** Yes — MINOR-1 assumes a fresh-init flow where `project.yml`
   doesn't yet exist when Step 5.5 fires. This is the normal init case, not an edge case.
   SUGGESTION-1 assumes a developer might have version-A staged and version-B in working
   tree (rare but real).
5. **Sub-agents?** None.
6. **Downgraded speculative claims?** Considered MAJOR for MINOR-1 (Step 5.5 ordering),
   but downgraded because the failure mode is "wrong prompt shown" (user can decline), not
   destructive. If the prompt auto-executed the install (which it explicitly doesn't —
   architect spec is clear), then it would be MAJOR.
7. **Phase 3.5 (Fix-Introduces-Edge-Cases)?** Applied — the `--staged` flag is a new
   defensive branch on `diff_files()` and the rules. Inventoried:
   - `MODE` variable is read by `diff_files()` and `diff_scope_label()` — both handle
     both modes correctly.
   - `wip-commits` got explicit staged-mode handling — addressed.
   - `frontmatter-valid` reads files from disk regardless of mode — works but has the
     working-tree-vs-staged-content caveat noted in SUGGESTION-1.
   - `tests-pass` and `feature-flag-present` don't differ behaviorally between modes —
     correct.
8. **Remediation mode?** No (round 1).

---

## Return-to-coder instructions

Gate passes. Coder MAY address MINOR-1 (recommended — small prose fix that prevents an
LLM-execution ambiguity) and MINOR-2 (one-line wording polish) in this round, or defer.

SUGGESTION-1 (smoke test coverage) and NIT-1 (retroactive backfill) are optional.

**Recommended:** address MINOR-1 + MINOR-2 inline now (both are <10 lines of prose
change), defer the rest, then stage / commit / push / open PR.

---

# Round 2 Update — 2026-06-10 (inline)

**Verdict: 🟢 GATE PASSES.** MINOR-1 + MINOR-2 closed. SUGGESTION-1 and NIT-1 deferred.

### ✅ MINOR-1 — Step 5.5 ordering / mode detection

Closed. New "Step 5.5 mode-detection" paragraph added at the top of the step. Explicitly
instructs the LLM-executing orchestrator to read `.gitignore` (not `project.yml`) at Step
5.5 entry, because `project.yml` is written in Step 6. The selective-pattern marker line
(`!.ssd/features/**/01-architect.md`) is unique to the v1.18.0+ pattern and provides a
reliable filesystem-grounded signal. The trailing "skip if blanket" sentence simplified to
just acknowledge the pre-flight check.

### ✅ MINOR-2 — `wip-commits` staged-mode wording

Closed. Replaced "rule applies at PR gate time" with "no commits to grep yet" — direct,
accurate, no implication that the rule is PR-specific. Comment expanded to clarify the
rule runs in branch mode after the commit lands. Verified with re-run of
`gate-rules.sh --staged` (output is now `staged mode (no commits to grep yet)`).

### 🟡 SUGGESTION-1 — adr-delta + frontmatter-valid staged-mode test scenarios (deferred)

Acceptable to defer. Both scenarios involve subtle behaviors (threshold calc on staged
diff for adr-delta; working-tree-content-vs-staged-content for frontmatter-valid) that
deserve their own test fixtures. Captured implicitly via the architect-spec
quality-gate row; explicit regression suite is a future iteration of the testing harness
(would extend `scripts/parity-test.sh` from v1.13.0).

### 📝 NIT-1 — Retroactive 1.6.0 changelog entry (accepted, no change)

Stays in this PR. The 6-line backfill is adjacent to v1.8.0's changelog work; a separate
PR for it would be overkill.

## Post-round-2 gate-rules.sh

```
PASS wip-commits :: no WIP/checkpoint commits between main and HEAD
SKIP tests-pass :: no test_command in .ssd/project.yml
SKIP feature-flag-present :: no feature_flag_marker
SKIP adr-delta :: no diff (vs main)
PASS frontmatter-valid :: 18 artifact(s) validated against schemas
SKIP no-leaky-state :: no diff (vs main)
exit: 0
```

```
# --staged mode:
SKIP wip-commits :: staged mode (no commits to grep yet)
SKIP tests-pass :: no test_command in .ssd/project.yml
SKIP feature-flag-present :: no feature_flag_marker
SKIP adr-delta :: no diff (staged files)
PASS frontmatter-valid :: 18 artifact(s) validated against schemas
SKIP no-leaky-state :: no diff (staged files)
exit: 0
```

## Self-verification (round 2)

1. MINOR-1 closure verified against the diff? Yes — read the new Step 5.5 mode-detection
   paragraph and the trimmed closing sentence. The contract now grounds the
   blanket-vs-selective decision in `.gitignore` state (filesystem) rather than
   `project.yml` (which may not exist).
2. MINOR-2 closure verified? Yes — new SKIP message direct and accurate. Re-ran
   `gate-rules.sh --staged` and saw the updated output.
3. New regressions from round-2 edits? None. Step 5.5 pre-flight is purely additive prose;
   wip-commits message is a string-only change.

**Gate decision: PASS.** Iter B ready to ship as v1.19.0. Epic complete after merge.
