---
skill: code-reviewer
version: 1.4.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: branch add-parallel-features-b vs main (uncommitted working-tree diff)
consumed_by: [coder]
finding_counts:
  blocker: 0
  major: 0
  minor: 3
  question: 0
  suggestion: 1
  nit: 0
gate_pass: true
remediation_mode: false
round: 1
closed_from_previous_round: []
round_2_inline: true
round_2_closed: [MINOR-1, MINOR-2, MINOR-3, SUGGESTION-1]
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

- **Diff vs main:** 5 files, ~430 lines added net. CHANGELOG +86, VERSION 1-line bump, ssd-init
  +17 (3 sections touched), ssd/rails.md +13 (1 new bullet + changelog), ssd/SKILL.md +325
  (mostly the new "Workstream Lifecycle Commands" section, plus banner bump, Invocation table
  update, Step 0 cross-ref, changelog entry).
- **Methodology gate:** PASS / SKIP / SKIP / SKIP / PASS — clean.
- **Frontmatter-valid:** 7/7 artifacts validate (iter A's tree plus iter B's `01-architect.md`,
  `coder-status.md`, and this review's parent dir).

## Verdict

🟢 **Gate passes.** Zero BLOCKER, zero MAJOR. Three MINORs surface real clarity / completeness
gaps in the new SKILL.md prose; none block the merge. One SUGGESTION.

The work is high quality. The validate-all-first restructure on `/ssd switch` (caught during
coding, documented in coder-status § "Spec changes during coding") is a real correctness
improvement over the iter A architect's loose ordering — exactly what the iter B architect EC-3
called for, made enforceable in prose. Convention 1 (numbered behavior steps with exact git
commands + numbered FMs + side-effect summary) is consistently applied across all three commands.
Scope discipline holds — nothing from iter C snuck in.

---

## Findings

### 🟡 MINOR-1 — `switch_note_default` profile-default phrasing is awkward

**Where:** [ssd/SKILL.md "Workstream Lifecycle Commands" → `/ssd switch` step 4, third bullet](../../../../../ssd/SKILL.md)

**Current text:** *"Default (`switch_note_default: prompt`, or unset on novice/standard profile
per § 'Profile-aware defaults'): orchestrator drafts the note, presents it to the user with a
three-option choice…"*

**Problem.** "Default (`switch_note_default: prompt`, or unset on novice/standard…)" is hard to
parse on first read. The reader can't tell if the parenthetical is naming the value, the
trigger, or both. The intended semantics are:
- Explicit `switch_note_default: prompt` in project.yml → prompt behavior.
- `switch_note_default` unset AND profile is novice/standard → prompt behavior (per the
  Profile-aware defaults table's `switch_note_default` column).
- Explicit `switch_note_default: auto` OR unset+expert → auto behavior (the other bullet).

The current phrasing collapses both triggers into one parenthetical and reads as a value-or-state
ambiguity.

**Suggested fix.** Restructure as: *"Default behavior — used when either (a) `project.yml.ssd.switch_note_default: prompt` is set, or (b) `switch_note_default` is unset and `developer_profile` is novice or standard (per § 'Profile-aware defaults' table). The orchestrator drafts…"*

Three lines, no semantic change.

**Why MINOR.** Prose clarity matters more here than usual because the LLM-executing orchestrator
reads this text and dispatches behavior based on it. An ambiguous bullet might dispatch the
wrong default for an unset+expert user. The two-clause restructure is mechanical.

---

### 🟡 MINOR-2 — `/ssd feature new` doesn't specify partial-failure recovery

**Where:** [ssd/SKILL.md "Workstream Lifecycle Commands" → `/ssd feature new`, behavior steps 6–10](../../../../../ssd/SKILL.md)

**Problem.** The behavior is documented as 11 sequential steps. Steps 6 through 10 are all
mutations:
- 6: `git checkout -b <branch> <base-ref>` (or `git branch` if `--worktree`)
- 7: `git worktree add <path> <branch>` (if `--worktree`)
- 8: Write `00-brief.md` or `iterations/<iter>/brief.md`
- 9: Append to `current.yml.active[]`
- 10: Initialize `current.notes.yml.features.<slug>`

If any of steps 7-10 fails after step 6 succeeds, the orchestrator has created a git branch (and
possibly a worktree dir and a brief file) without a corresponding `current.yml` entry. The
workstream exists in git but not in SSD state.

The self-verification block at the end of the section addresses *file-level atomicity*
("current.yml and current.notes.yml writes are atomic via temp-file-rename or in-memory-prepare-then-write")
but does NOT address *multi-step rollback* across git/filesystem/yaml writes.

**Failure modes that survive the existing validations:**
- Step 7 `git worktree add` fails after step 6 succeeds — e.g., disk full, permission denied on
  parent dir. Step 7's FM-4 catches the path-collision case via pre-check, but not these
  resource failures.
- Step 8 brief write fails — e.g., disk full, parent dir permissions.
- Step 9 `current.yml` append fails — e.g., disk full, file lock, etc.
- Step 10 `current.notes.yml` init fails — same.

After any of these failures, the orchestrator should either (a) roll back the prior mutating
steps or (b) explicitly tell the user what state remains and how to clean up.

**Suggested fix.** Add a step 11.5 / appendix at the end of `/ssd feature new`'s behavior list:

> **Partial-failure recovery.** If any of steps 6–10 fails after a prior step's mutation
> succeeded, the orchestrator (a) does NOT continue with subsequent steps, (b) prints what state
> exists vs. what's missing, and (c) suggests the recovery action: `git branch -D <branch>` to
> undo step 6, `git worktree remove <path>` to undo step 7, `rm <brief-path>` to undo step 8.
> The orchestrator does not auto-rollback because a partial failure may indicate a deeper issue
> (disk full, permissions) that a rollback could compound.

**Why MINOR.** Real correctness gap but low-probability failure modes. The recovery is simple
and the user is informed. Worth documenting; not worth blocking iter B for it.

---

### 🟡 MINOR-3 — `/ssd switch` step 3 doesn't detect worktree-branch drift

**Where:** [ssd/SKILL.md "Workstream Lifecycle Commands" → `/ssd switch` step 3, second sub-bullet](../../../../../ssd/SKILL.md)

**Problem.** When the target has `target.worktree: <path>`, step 3 verifies only that the
`<path>` exists on disk (and refuses with FM-10 if not). It does NOT verify that the recorded
`target.branch` matches what's actually checked out in the worktree.

**The failure case.** User manually ran `git -C <worktree-path> checkout other-branch` at some
point. Now `current.yml.active[<target>].branch` says `add-feature-b` but the worktree's HEAD
points at `other-branch`. The `/ssd switch` succeeds (step 5 just prints the `cd <path>`), the
user `cd`s into the worktree, and continues working — on the wrong branch, with the orchestrator
unaware of the drift.

**Suggested fix.** Add a sub-bullet to step 3, worktree path:

> Verify `git -C <path> symbolic-ref --short HEAD` matches `target.branch`. If they differ,
> refuse with FM-14: *"workstream <slug>'s recorded branch (`<recorded>`) doesn't match the
> worktree's actual HEAD (`<actual>`); the worktree was manually checked out to a different
> branch. Run `/ssd workstream set-branch <slug> <actual>` (deferred to iter D) to update the
> record, or `git -C <path> checkout <recorded>` to restore the worktree."*

**Alternate fix (smaller).** Auto-update `target.branch` to the worktree's actual HEAD with a
warning. Less safe — silently rewrites state without user confirmation.

**Why MINOR.** Drift is an edge case requiring explicit user action (manual `git checkout` in
the worktree) and the user is likely aware they did it. But silently allowing the drift means
the next `/ssd gate` runs against the wrong branch. Worth catching at switch time.

---

### 💡 SUGGESTION-1 — Three-option handoff prompt should specify the prompt mechanism

**Where:** [ssd/SKILL.md `/ssd switch` step 4, third bullet](../../../../../ssd/SKILL.md)

**Current text:** *"…orchestrator drafts the note, presents it to the user with a three-option
choice: **save** (accept draft as-is), **edit** (user provides replacement text), **skip**
(don't write). Write per the chosen option."*

The mechanism — how exactly the orchestrator "presents" the choice — isn't specified. In
practice the LLM-executing orchestrator could use `AskUserQuestion` (structured), inline prose
prompt, or just narrate and wait. Different mechanisms produce different UX.

**Suggestion.** Either (a) specify "use `AskUserQuestion` with a single-question / three-option
schema (or the conversational-surface equivalent in interactive mode)," or (b) leave the
mechanism open but make the requirement explicit: "the chosen mechanism MUST yield a binding
selection back to the orchestrator before step 5 proceeds — narration-without-blocking is not
sufficient."

This is forward-looking polish. Iter A's own dogfooded `/ssd switch` (when implemented in
production) will surface the best mechanism via use; documenting now would lock in.

---

## Substantive checks performed

| Check | Result |
|---|---|
| `/ssd feature new` Convention 1 structure | ✓ Signature line + Purpose + 11 numbered steps with exact git invocations + 6 FMs + side-effects summary. |
| `/ssd switch` validate-all-first ordering | ✓ Steps 1–3 are pure validation; mutations start at step 4. Coder-status notes the restructure as not-strictly-spec-drift; the iter B architect's EC-3 called for it but didn't enforce step ordering — the SKILL.md prose now does. Excellent move. |
| `/ssd worktree` add/remove parity | ✓ Both have parallel structure. `remove` correctly handles the missing-on-disk case via `git worktree prune` per iter B EC-5. |
| Self-verification block | ✓ Four-point checklist, actionable. Calls out atomic writes and dirty-check-before-mutation for `/ssd switch`. |
| FM numbering coherence | ✓ FM-1 through FM-13 across the three commands; no duplicates, no gaps once you account for FM-10 being `/ssd switch`-specific while `/ssd worktree remove` handles the missing-dir case as auto-recovery (not an FM). Documented clearly. |
| ssd-init/SKILL.md change | ✓ Step 6 project.yml write now includes 4 new keys with defaults. New paragraph after the write explains the parallel-features defaults and links to ADR-0007. Doesn't break existing init flow (keys are optional with documented defaults — orchestrator falls back if missing, per iter A's documentation). |
| ssd/rails.md non-rail bullet | ✓ New "What This Is NOT" bullet clarifies the workstream-container vs. workstream-step distinction. Doctrine-consistent with rails.md's existing voice. v1.1.0 changelog entry matches v1.0.0's tone. |
| CHANGELOG accuracy | ✓ Sections cover new commands, touched skills, edge cases resolved, schema (none), deferred-to-C, deferred-to-D. Match what's actually in the diff. |
| Scope discipline (nothing iter-C leaked) | ✓ No `OVERLAP-N` references, no `touches:` consumption logic (only mention is "the field is recorded; consumption is deferred"), no gate-rules.sh changes. |
| Tone consistency | ✓ The new prose matches the existing SKILL.md voice — terse, technical, no marketing-speak. Matches the existing `/ssd feature` and `/ssd gate` sections. |
| Cross-references | ✓ § "Iterations Inside a Feature", § "The SSD Artifact Tree" worktree note (with git 2.31+ caveat), § "Profile-aware defaults", ADR-0007. All exist and resolve. |

---

## Coder's items addressed

| # | Question | Answer |
|---|---|---|
| 1 | `/ssd switch` step 5 cd path as LAST line | ✓ Verified — prose explicitly says "as the LAST line of output." |
| 2 | `/ssd feature new` step 7 worktree path cross-ref | ✓ Verified — step 7 references § "The SSD Artifact Tree" worktree note which documents the git 2.31+ + realpath fallback. |
| 3 | Profile-aware promote prompt | ✓ Spec mentions `--promote` for expert profile to skip the flat→multi-iter promotion prompt. Pattern-consistent with novice/standard/expert profile-aware defaults elsewhere. |
| 4 | FM number consistency | ✓ FM-1..FM-13 used; no gaps once you understand that FM-10 is `/ssd switch`-specific. See substantive checks table. |
| 5 | ssd-init writes keys only on fresh init | ✓ Acceptable — orchestrator falls back to defaults if keys are missing (iter A's schema docs say "missing keys behave exactly as if the default were declared"). Existing projects don't need to re-run init. The fallback path is explicit in iter A's SKILL.md schema section. |

---

## Self-Verification (per code-reviewer/SKILL.md)

1. **Did I read the actual files I'm citing?** Yes — ran `git diff main` to capture the full
   diff, read the new SKILL.md section end-to-end, read the ssd-init + rails.md edits.
2. **Did I verify each MAJOR/BLOCKER claim?** N/A — zero MAJOR/BLOCKER findings. The MINORs
   are documented prose gaps verified by reading the prose itself.
3. **Citations correct?** Line numbers from working-tree files at review time; user shouldn't
   edit between gate and commit.
4. **Stated assumptions?** Yes — MINOR-3 assumes "user might manually checkout in a worktree";
   this is a real edge case (e.g., user uses lazygit to fix a typo on the wrong branch).
5. **Sub-agents?** None used.
6. **Downgraded speculative claims?** MINOR-2 was tempting to call MAJOR (real correctness gap)
   but downgraded because (a) the failure modes are low-probability resource exhaustion,
   (b) the user is informed (not silent), (c) the recovery is straightforward. MINOR-3 was
   tempting to upgrade to MAJOR but the trigger (manual `git checkout` inside a worktree) is
   user-initiated drift, not an orchestrator bug.
7. **Phase 3.5 (Fix-Introduces-Edge-Cases)?** Applied to `/ssd switch`'s new validate-all-first
   ordering. The new structure (step 3 = pure validation, steps 4-6 = mutations) introduces a
   new edge case where the orchestrator could pass all validations, then have step 5
   (`git checkout`) fail anyway due to (e.g.) a race with another process modifying the working
   tree. The self-verification block addresses this generically ("write to a temp file +
   rename"). Not flagged as a new finding because the alternative (mutate-first-then-rollback)
   is strictly worse.
8. **Remediation mode?** No (round 1).

---

## Return-to-coder instructions

Gate passes. Coder MAY address MINORs 1–3 in this round (recommended for clarity) or defer to a
follow-up. SUGGESTION-1 is optional.

If addressing all three MINORs in this round:
- MINOR-1: ~3 lines of prose restructure in `/ssd switch` step 4.
- MINOR-2: ~5 lines added at end of `/ssd feature new` behavior list.
- MINOR-3: ~5 lines added to `/ssd switch` step 3 second sub-bullet + new FM-14.

Total: ~15 lines added, no structural change. Easy to bundle into the same commit before push.

If deferring: log the three as `questions_for_next_session` in `.ssd/current.notes.yml` so they
surface during iter C's planning.

**Recommended:** address all three now. They're all clarity / completeness improvements on prose
the LLM-executing orchestrator depends on; a clearer doc here saves debugging time later.

---

# Round 2 Update — 2026-05-24 (inline)

**Round 2 verdict: 🟢 GATE PASSES.** All three MINORs + the one SUGGESTION closed in the same
round. Coder bundled the four prose edits into the iter B work — total +20 lines added across
two locations in `ssd/SKILL.md`. Verified against the diff:

### ✅ MINOR-1 — `switch_note_default` profile-default phrasing

Verified. New text restructures the bullet into a two-clause precondition: *"used when either
(a) `project.yml.ssd.switch_note_default: prompt` is set explicitly, or (b) `switch_note_default`
is unset AND `developer_profile` is `novice` or `standard`."* Reads cleanly; the LLM dispatches
the right behavior unambiguously.

### ✅ MINOR-2 — Partial-failure recovery for `/ssd feature new`

Verified. New "Partial-failure recovery" appendix after the side-effects list. Specifies: no
auto-continue past failure, explicit summary of state vs. missing, named recovery commands
(`git branch -D`, `git worktree remove`, `rm <brief>`), explicit "no auto-rollback" with
rationale (deeper resource issues that rollback would mask).

### ✅ MINOR-3 — Worktree-branch drift detection

Verified. New sub-bullet under step 3 worktree-non-null branch: runs
`git -C <path> symbolic-ref --short HEAD` and checks it equals `target.branch`. Mismatch
triggers new FM-14 with explicit recovery instructions (`git -C <path> checkout <recorded>` or
the deferred-iter-D `/ssd workstream set-branch`). The "no auto-update" stance is documented —
silent state rewrite on drift would hide the user's manual change.

### ✅ SUGGESTION-1 — Prompt mechanism specified

Verified. Closed in conjunction with MINOR-1's restructure. The new text explicitly says
*"…blocks waiting for a binding user choice (use `AskUserQuestion` with three options, or the
conversational-surface equivalent — narrate-without-blocking is insufficient)…"*

## Post-round-2 gate-rules.sh

```
PASS wip-commits :: no WIP/checkpoint commits between main and HEAD
SKIP tests-pass :: no test_command in .ssd/project.yml
SKIP feature-flag-present :: no feature_flag_marker in .ssd/project.yml
SKIP adr-delta :: no diff vs main (commits pending)
PASS frontmatter-valid :: 7 artifact(s) validated against schemas
exit: 0
```

## Self-verification (round 2)

1. Each closure verified against the diff? Yes — read the four edited regions; the prose
   matches each finding's suggested fix.
2. New regressions from round-2 edits? None — all edits are localized; no other parts of the
   section touched. FM-14 added cleanly to the FM list.
3. `closed_from_previous_round` accurate? Yes — `round_2_closed: [MINOR-1, MINOR-2, MINOR-3,
   SUGGESTION-1]` matches the verified closures.

**Gate decision: PASS.** Iter B is ready to ship as v1.16.0.
