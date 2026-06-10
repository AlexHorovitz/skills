---
skill: code-reviewer
version: 1.4.0
produced_at: 2026-05-21T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: branch add-parallel-features vs origin/main (uncommitted working-tree diff + 1 new untracked file)
consumed_by: [coder]
finding_counts:
  blocker: 0
  major: 1
  minor: 3
  question: 1
  suggestion: 2
  nit: 1
gate_pass: false
remediation_mode: false
round: 2
closed_from_previous_round: [MAJOR-1, MINOR-1, MINOR-2, MINOR-3, SUGGESTION-1, NIT-1]
round_2_finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 0
  suggestion: 0
  nit: 0
round_2_gate_pass: true
deferred_with_assent: [SUGGESTION-2, QUESTION-1]
---

# Iteration A — Code Review (Round 1)

## Scope verified

- **Diff vs origin/main (tracked):** `CHANGELOG.md` (+71 lines), `VERSION` (1 line), `ssd/SKILL.md` (+57 lines). Net additive.
- **Untracked (will be in committed PR):** `docs/decisions/ADR-0007-parallel-features.md` (189 lines, NEW).
- **Working-tree-only, gitignored (reviewed for honesty, not shipped):** `.ssd/features/parallel-features/{00-brief,01-architect,03-coder-status}.md`, `.ssd/current.yml`, `.ssd/current.notes.yml`, `.ssd/project.yml`.
- **Methodology gate:** PASS / SKIP / SKIP / SKIP / PASS — clean. `adr-delta` SKIPs because diff is uncommitted; will PASS post-commit because ADR-0007 lands with this PR.
- **Frontmatter validator (`frontmatter-validate.py`):** 5/5 PASS on iteration A artifacts.

This is round 1, first review. No prior findings to verify.

## Verdict

🟠 **Gate fails on one MAJOR.** ADR-0007's number conflicts with an unmerged sibling branch
(`add-adr-0006`) — the coder explicitly flagged the renumbering risk in coder-status and the
fix needs to be made *before* commit, not deferred. Three MINORs surface real-but-non-blocking
gaps in the documentation (lazy-backfill correctness guard, branch-uniqueness invariant, profile
default mapping). Everything else is clean.

Quality of work itself is high. ADR-0007 is substantive (not strawman alternatives, honest
"What we give up" section); SKILL.md edits are surgical and forward-link to the right ADR
sections; CHANGELOG accurately reports the spec drift; scope discipline holds (nothing from
iteration B or C leaked in). The MAJOR is process-coordination, not a defect in the work.

---

## Findings

### 🟠 MAJOR-1 — ADR-0007 numbering conflicts with unmerged sibling ADR

**Where:** [docs/decisions/ADR-0007-parallel-features.md](../../../docs/decisions/ADR-0007-parallel-features.md:1) (entire file)

**Evidence (verified):**
- `git ls-tree origin/main docs/decisions/` returns ADR-0001 through ADR-0005 only.
- `git log origin/main --oneline -- docs/decisions/` shows no ADR-0006 commit on the target branch.
- The repo's local `add-adr-0006` branch contains a retroactive ADR-0006 (commit `869b001 docs: retroactive ADR-0006 for frontmatter validator (v1.14.0)`). That branch is **unmerged** at the time of this review.
- This PR (`add-parallel-features`) is currently the only thing introducing a numbered ADR file *after* origin/main's ADR-0005.

**The problem.** Sequential ADR numbering is a doctrine invariant in this repo — every existing ADR is numbered without gaps (0001…0005), and the `architect/SKILL.md` template treats numbering as "Number them sequentially." If `add-parallel-features` merges before `add-adr-0006`, the main branch will have ADR-0001..0005 + ADR-0007 with a gap where ADR-0006 should be. A future reader (or the orchestrator's `adr-delta` rule) cannot tell whether ADR-0006 was deleted, superseded, or never existed.

**Fix options, in order of preference.** The coder must pick one before commit:

1. **Bundle ADR-0006 into this PR.** Cherry-pick or rebase the retroactive ADR-0006 commit from `add-adr-0006` into `add-parallel-features`. Drop the `add-adr-0006` branch. This PR then ships ADR-0006 and ADR-0007 together. Cleanest by far, since the ADR-0006 is a docs-only retroactive ADR for already-merged v1.14.0 work — no risk of conflict.
2. **Commit to a merge order.** Decide that `add-adr-0006` merges first (it's smaller and ready), then this PR. Record the dependency explicitly in this PR's description and in the current handoff notes so the order isn't lost.
3. **Renumber to ADR-0006 now.** If the user has decided `add-adr-0006` is being abandoned, rename `ADR-0007-parallel-features.md` → `ADR-0006-parallel-features.md`, update all internal references in this branch's diff (CHANGELOG, SKILL.md, ADR body, the coder-status, the architect spec, this review). Three files in the committed diff would need the rename string-replaced.

**Why MAJOR rather than MINOR.** This is fixable in <5 minutes pre-commit and ~30 minutes post-commit (history rewrite or follow-up renumbering PR). Punting it to merge-time is exactly the kind of "we'll remember" promise that this feature was built to avoid making.

**Recommended action.** Option 1. The retroactive ADR-0006 is small and docs-only; bundling it removes the coordination problem entirely. Reviewer is fine with options 2 or 3 if the user has a reason to keep the branches separate, but the choice must be made now, not after `git push`.

---

### 🟡 MINOR-1 — Lazy-backfill rule can attach the wrong branch to a workstream

**Where:** [ssd/SKILL.md:611-615](../../../ssd/SKILL.md#L611) (the new "lazy backfill" paragraph under § "Session Continuity")

**Current text:** *"When the orchestrator next touches an active entry whose `branch:` is absent and exactly one active workstream has no recorded branch, it lazily backfills `branch:` with the current checkout's branch."*

**The failure case.** Two active workstreams:
- Workstream A: `branch: add-feature-a` (recorded).
- Workstream B: `branch: <absent>` (pre-1.15.0, never recorded).

Current state has exactly one ambiguous workstream (B). User checks out an unrelated branch `experiment-xyz` (debugging, exploration, anything) and runs `/ssd` (no-arg). The "exactly one ambiguous" guard fires; B gets backfilled with `branch: experiment-xyz`, which has nothing to do with B's actual branch.

**Why it slips through.** The "exactly one" guard protects against multi-ambiguity (two workstreams both needing a branch — orchestrator declines to guess). It does **not** protect against the case where the *current branch* has no plausible relationship to the workstream being backfilled.

**Suggested guard.** Backfill only if the current branch *plausibly* corresponds to the ambiguous workstream — concretely, when the current branch matches `branch_pattern` substituted with the workstream's slug, OR when there's an explicit Step 0 pattern-match resolution that pointed at this workstream. Without that guard, the backfill silently corrupts state.

**Why MINOR not MAJOR.** Lazy backfill is a convenience for pre-1.15.0 entries. It runs at most once per workstream lifetime. Wrong backfill is correctable (edit `current.yml` manually). And `current.yml` is gitignored — no PR-level damage. But documenting the unconstrained behavior is asking for a user report in iteration B.

---

### 🟡 MINOR-2 — Branch-uniqueness invariant is in the architect spec but absent from SKILL.md

**Where:** [ssd/SKILL.md:64-79](../../../ssd/SKILL.md#L64) (new Step 0 algorithm)

**Evidence.** [01-architect.md § "Auto-Detection — branch-name → slug"](../../../.ssd/features/parallel-features/01-architect.md) states: *"Multiple matches (case 2 collision — two entries declare the same `branch:`): impossible by construction; `/ssd feature new` refuses duplicate branches… The orchestrator emits an internal error if it finds two — that's a bug, not a user state."*

The committed SKILL.md doesn't carry this invariant forward. Step 0 step 2 says *"If any `current.yml.active[].branch` equals the current branch, that workstream is the resolved target"* — `any` is ambiguous: first-match? prompt-on-collision? undefined?

**Suggested fix.** Add a sentence to Step 0 step 2: *"By construction, no two `active[]` entries should share a `branch:` value; iteration B's `/ssd feature new` enforces this on creation. If the orchestrator encounters duplicate branches (a state corruption), it emits an error rather than guessing."* Two lines, zero behavior change in iteration A.

**Why MINOR.** Documentation gap; the runtime impact is iteration-B's problem (no commands write the field yet). But Step 0 is read-only logic in iteration A and the order-of-resolution should be unambiguous in the canonical doc.

---

### 🟡 MINOR-3 — Profile → `switch_note_default` mapping is implicit, not documented

**Where:** [ssd/SKILL.md:321-327](../../../ssd/SKILL.md#L321) (existing "Profile-aware defaults" table)

**Evidence.** ADR-0007 § "Configuration additions" and the new CHANGELOG entry both state: *"Novice profile defaults to `prompt`; expert to `auto`."* The dogfood `.ssd/project.yml` declares `switch_note_default: auto` because this project is `developer_profile: expert`. The "Profile-aware defaults" table in SKILL.md does not list `switch_note_default` as a profile-driven knob.

**The risk.** A new user looking at the Profile table to understand what profile changes about defaults won't see `switch_note_default` mentioned. They'll be surprised when iteration B's `/ssd switch` behaves differently between novice and expert profiles.

**Suggested fix.** Add a row or footnote to the Profile-aware defaults table noting that `switch_note_default` (iteration B) defaults differ by profile. Cite ADR-0007. Two-line addition.

**Why MINOR.** The mapping is documented in the ADR and CHANGELOG; just not in the table that users actually navigate to first. Could legitimately be deferred to iteration B (when the command lands and the table needs to mention the command anyway). Coder explicitly asked about this — confirming: deferring to iter B is fine *if* iter B doesn't forget; if iter A is shipping the profile-aware default semantics now, the table update should land now.

---

### 💭 QUESTION-1 — Why is ADR-0007 still untracked in the working tree?

**Where:** `git status` shows `?? docs/decisions/ADR-0007-parallel-features.md`.

**The question.** This PR's gate-rules `adr-delta` rule SKIPs ("no diff vs origin/main") because the only tracked changes vs origin/main are the three M-flagged files. Once the user runs `git add docs/decisions/ADR-0007-parallel-features.md`, the file becomes part of the diff and `adr-delta` will see it. The coder-status notes this explicitly — *"adr-delta SKIPs because diff is uncommitted at the time of this artifact; after commit the rule will see ADR-0007-parallel-features.md and PASS."*

Is the convention in this repo to keep new ADRs untracked until the user explicitly stages them? Or did the coder skip the `git add` deliberately because they were told "do not commit"? Per the coder's instructions: *"Do not commit. Just write the files."* — the literal reading is that not staging is correct. But for the user reviewing the PR, this is an extra `git add` step they need to remember.

**Why QUESTION not finding.** Process clarification, not a code defect. If the convention is "leave untracked for user to stage," this is fine. If the convention is "stage but don't commit," the coder missed a `git add` step. Confirm and document the convention either way.

---

### 💡 SUGGESTION-1 — Document the git version requirement for `--path-format=absolute`

**Where:** [ssd/SKILL.md:466-472](../../../ssd/SKILL.md#L466) (new worktree note)

**Verified.** I ran `git rev-parse --path-format=absolute --git-common-dir` on this repo's main checkout — works, returns `/Users/ahorovit/Development/insanelygreat/skills/.git`. `dirname` of that gives the repo root. ✓

**The caveat.** `--path-format=absolute` was added in **git 2.31** (March 2021). Users on older git (LTS distro repos, ancient enterprise environments) will see `unknown option`. For a portable skills library, either:
- Mention "git 2.31+" in the worktree note.
- Provide a fallback (e.g., `realpath "$(git rev-parse --git-common-dir)"` works on 2.5+ but is shellier).

**Why SUGGESTION not MINOR.** Documentation only; iteration B is where the actual invocation goes into orchestrator code, and that's where the fallback (if any) should live. Iteration A is just *describing* the mechanism. Worth noting for forward-looking implementation.

---

### 💡 SUGGESTION-2 — 4-workstream ceiling is a guess; treat it as a hypothesis to validate

**Where:** [ADR-0007 § "Scale Note"](../../../docs/decisions/ADR-0007-parallel-features.md:184) and [01-architect.md § "Current Scale Baseline"](../../../.ssd/features/parallel-features/01-architect.md)

**Evidence.** ADR-0007: *"Designed for up to 4 concurrent active workstreams per project per user. Above 4 the orchestrator emits a non-blocking advisory."* The architect spec table claims today's load is "typically 1, occasionally 2."

**The suggestion.** The 4-workstream ceiling is a doctrine pick, not data. After 3–6 months of usage, revisit it: do users actually hit 4? Does the advisory fire? Is the cognitive overhead claim correct? Either confirm or revise based on observed behavior.

This isn't an iter-A bug — it's a note-to-future-self. Consider adding to a "deferred decisions" section in `.ssd/current.notes.yml` so it doesn't fall off the radar.

**Why SUGGESTION.** Pure forward-looking advice; doesn't block anything.

---

### 📝 NIT-1 — ADR-0007 line 8 attributes "v2" to ADR-0002, which split rather than introduced v2

**Where:** [docs/decisions/ADR-0007-parallel-features.md:8](../../../docs/decisions/ADR-0007-parallel-features.md#L8)

**Current text:** *"`.ssd/current.yml.active` has been a list since v2 (ADR-0002), and `/ssd` (no-arg) auto-detect since v1.8.0 (P1.3) has surfaced multiple active workstreams to the user."*

**Pedantic correction.** ADR-0002 was the *split* of `current.yml` into machine + notes (v1 → v2 at library v1.4.0). The `active` list as a concept predates ADR-0002. The library version that introduced "active as a list" was actually whenever `current.yml` was first machine-formatted — earlier than ADR-0002.

**Suggested fix.** *"`.ssd/current.yml.active` has been a list since v1.4.0 (ADR-0002 formalized the v2 schema and confirmed the list shape)."*

Or just drop the ADR-0002 cite if it's not load-bearing. Either way, fix-or-don't is fine — this is pure NIT.

---

## Coder's questions, addressed

| # | Question | Answer |
|---|---|---|
| 1 | ADR-0007 numbering vs add-adr-0006 | **MAJOR-1 above.** Fix before commit. Reviewer recommends bundling ADR-0006 into this PR (option 1). |
| 2 | SKILL.md version jump 1.10 → 1.15 | **Acceptable.** Aligning SKILL.md to library version is the historical pattern (look at the changelog: v1.4.0 / v1.5.0 / v1.6.0 / v1.7.0 / v1.8.0 / v1.9.0 / v1.10.0 — each entry is both a SKILL.md and library bump). The 1.10 → 1.15 jump is the natural correction after four library-version bumps (1.11–1.14) that didn't touch this file. Future convention: if the pattern is "SKILL.md tracks library version," then v1.11–v1.14 should have had `Version: 1.10.0` in the SKILL.md banner with no skill changelog entry, and v1.15.0 is the next SKILL.md entry. This is consistent. |
| 3 | Lazy-backfill scope | **MINOR-1 above.** Add a guard that the current branch plausibly maps to the ambiguous workstream. |
| 4 | Worktree resolution invocation | **Verified correct on git 2.31+ (SUGGESTION-1 about version reqs).** I tested in this checkout; the invocation produces the expected absolute path. For linked worktrees the same invocation returns the main repo's `.git/`, and `dirname` of that is the main repo root. Don't have a linked worktree to test on, but the documented git behavior is that `--git-common-dir` returns the main repo's `.git` from any worktree associated with that repo. |
| 5 | `switch_note_default: auto` for expert profile | **MINOR-3 above.** Add to the Profile-aware defaults table now (preferred) or in iteration B (acceptable if iter B is committed). |

---

## Substantive checks performed

| Check | Result |
|---|---|
| ADR-0007 quality | ✓ Context establishes problem with empirical evidence ("14 versions, zero parallel sessions"). Decision section concrete and atomic (schema + config + commands + 3-iter slicing). Alternatives Rejected are all substantive (no strawmen — each has a real reason it was considered). Consequences section is honest about what gets harder (cd boundary, branch ambiguity, touches drift). Tone matches ADR-0001..0005. |
| Backward compatibility | ✓ New fields are optional with documented defaults; absence is valid by design. No `schema_version: 3` bump. Existing v2 `current.yml` files parse and behave identically. Lazy-backfill is the only state-mutating behavior, and even that mutates only `current.yml` (gitignored, recoverable). |
| Step 0 auto-detect algorithm | ✓ Order (exact → pattern → fall-through) is correct. Detached HEAD is handled (skip Step 0). Branch-uniqueness invariant has a gap in the docs (see MINOR-2). |
| Worktree note correctness | ✓ Invocation is correct on git 2.31+ (verified on this checkout). SUGGESTION-1 covers the version note. |
| CHANGELOG entry accuracy | ✓ Shipped scope matches the entry. Spec drift documented in a dedicated subsection. Deferred-to-B / Deferred-to-C lists are accurate per architect spec. |
| Spec drift acceptable | ✓ The dropped `methodology/schema-validator.sh` doesn't exist; the closest analog (`frontmatter-validate.py`) validates artifact frontmatter, not `current.yml`. The coder's justification (fields are optional, orchestrator reads tolerantly, no downstream consumer in iter A) holds. The fact that iter A doesn't include a current.yml validator is acceptable. If iter B/C makes `current.yml` schema validation load-bearing, the validator becomes appropriate to add then. |
| Scope discipline | ✓ Nothing from iteration B or C leaked into the diff. Specifically: no new commands shipped, no overlap-detection logic added, no `code-reviewer/SKILL.md` changes, no `ssd-init/SKILL.md` changes, no `ssd/rails.md` changes. The dogfood `.ssd/project.yml` update and the current.yml `branch: add-parallel-features` entry are appropriate scope for iter A. |
| Tone consistency | ✓ ADR-0007 reads like ADR-0001..0005 in voice and structure. SKILL.md additions don't feel bolted on — Step 0 follows the existing "Decision tree" narrative; worktree note is one paragraph in keeping with the artifact-tree section's style. |

---

## Self-Verification (per code-reviewer/SKILL.md)

1. **Did I read the actual files I'm citing, or am I pattern-matching from memory?** Read all cited lines. Diff output captured directly.
2. **Did I verify each BLOCKER/MAJOR claim by tracing the execution path?** MAJOR-1 verified by `git ls-tree origin/main docs/decisions/` (5 files, no ADR-0006) and `git log origin/main --oneline -- docs/decisions/` (no ADR-0006 commit on main).
3. **For each citation (file:line), does the line still exist at that number?** Line numbers are from the working-tree files at the time of review; user shouldn't edit between gate and commit.
4. **Claims depend on stated assumptions?** Yes — MAJOR-1 assumes "ADRs in this repo are numbered sequentially without gaps." Verified by `ls docs/decisions/` showing ADR-0001..0005 unbroken. MINOR-1 assumes the user might check out an unrelated branch (an experiment, a hotfix) — that's a realistic scenario, not hypothetical.
5. **Sub-agents?** None used. All review done in-process.
6. **Downgraded speculative claims?** Yes — SUGGESTION-1 (git version) and SUGGESTION-2 (4-workstream ceiling) are forward-looking, not "this is broken now." QUESTION-1 is a process clarification, not a bug claim.
7. **Phase 3.5 (Fix-Introduces-Edge-Cases)?** N/A — this is design + documentation, not bug-fix or defensive-code work. The orchestrator behavior added (Step 0, lazy backfill) is functional new surface, but it's spec only in iter A — actual code lands iter B. MINOR-1 catches a state-correctness gap that would otherwise be Phase 3.5 territory.
8. **Remediation mode?** No (round 1).

---

## Return-to-coder instructions

Address MAJOR-1 (numbering decision) before re-gating. The three MINORs are gate-passing per SSD severity rules but should be addressed in the same round to keep the diff small:

- MINOR-1: Add a single guard sentence to the lazy-backfill paragraph.
- MINOR-2: Add the branch-uniqueness invariant to Step 0.
- MINOR-3: Add `switch_note_default` to the Profile-aware defaults table (or commit to iter B addressing it).

SUGGESTION-1, SUGGESTION-2, QUESTION-1, NIT-1 are optional — coder may close them in this round or defer.

Re-running `/ssd gate parallel-features` after MAJOR-1 is resolved produces a round-2 review. Per
`code-reviewer/SKILL.md` § "Multi-Round Gates," for a single-MAJOR remediation an inline round-2
update at the bottom of this file is acceptable in lieu of a separate `04-code-review-round-2.md`.

---

# Round 2 Update — 2026-05-21

**Round 2 verdict: 🟢 GATE PASSES.** All six round-1 findings claimed closed verified against
the diff. SUGGESTION-2 and QUESTION-1 deferred with reviewer assent (S-2 captured as a future
review item; Q-1 resolved by the coder staging the new ADRs explicitly per § Q-1 below).

## Closures verified

### ✅ MAJOR-1 — ADR-0006 bundled into this PR (option 1 from round 1)

Verified:
- `git log --oneline -2` shows `e0ff458 docs: retroactive ADR-0006 for frontmatter validator (v1.14.0)` as HEAD, cherry-picked from `869b001` on `add-adr-0006`.
- `ls docs/decisions/` now shows ADR-0001..ADR-0007 contiguous, no gaps.
- The CHANGELOG entry for v1.15.0 now declares the ADR-0006 inclusion explicitly, citing the round-1 finding as the motivation.
- Cherry-pick was clean (2 files: ADR-0006 NEW + `.gitignore` trailing-newline normalization). No merge conflicts.

Round-1 evidence stands invalidated by the merge — `git ls-tree HEAD docs/decisions/` would now show ADR-0006 present. Future merge to main carries both ADRs together. Numbering invariant restored.

### ✅ MINOR-1 — Lazy-backfill plausibility guard added

Verified at [ssd/SKILL.md § "current.yml v2 schema"](../../../ssd/SKILL.md): the paragraph now requires **both** guards (exactly-one-ambiguous AND current-branch-plausibly-corresponds via `branch_pattern` substitution) before backfill. The failure case from round 1 (unrelated branch + one ambiguous workstream) now correctly leaves `branch:` absent and falls through to a prompt on next disambiguation.

### ✅ MINOR-2 — Branch-uniqueness invariant added to Step 0

Verified at [ssd/SKILL.md § "/ssd (no-arg) — Auto-Detect"](../../../ssd/SKILL.md): Step 0 step 2 now carries the explicit invariant ("no two `active[]` entries should share a `branch:` value") and the corruption-handling rule (orchestrator emits an error rather than picking a first match). Iteration B's `/ssd feature new` is named as the runtime enforcer.

### ✅ MINOR-3 — `switch_note_default` added to Profile-aware defaults table

Verified at [ssd/SKILL.md § "Profile-aware defaults"](../../../ssd/SKILL.md): the table gains a new column with per-profile defaults (`novice: prompt`, `standard: prompt`, `expert: auto`) plus a follow-up paragraph citing ADR-0007 and explaining the per-project override knob. Novice and standard intentionally collapse to the same default (`prompt`) — that's a reasonable choice for newer / cautious users, matching the architect spec's "novice gets prompt, expert gets auto" but extending standard to also get prompt (safer default for the middle tier).

### ✅ SUGGESTION-1 — Git 2.31+ note added to worktree paragraph

Verified at [ssd/SKILL.md § "The SSD Artifact Tree"](../../../ssd/SKILL.md): the worktree note now states "Requires git 2.31+" and provides a documented fallback (`realpath "$(git rev-parse --git-common-dir)"`) for older git, with a forward-pointer to iteration B's helper.

### ✅ NIT-1 — ADR-0007 line 8 attribution fixed

Verified at [docs/decisions/ADR-0007-parallel-features.md:8](../../../docs/decisions/ADR-0007-parallel-features.md): now reads *"`.ssd/current.yml.active` has been a list since v1.4.0 (ADR-0002 formalized the v2 schema and confirmed the list shape)"* — accurately attributes the list shape to v1.4.0 while still citing ADR-0002 for the schema formalization. Pedantry resolved.

## Deferred with reviewer assent

### 🟡 SUGGESTION-2 — 4-workstream ceiling revisit (recorded for future review)

Captured in [.ssd/current.notes.yml](../../../.ssd/current.notes.yml) as `NOTES-PF-1` with explicit review window 2026-08-21 to 2026-11-21 (3–6 months from v1.15.0 ship). The questions_for_next_session entry survives in the notes file when this workstream archives, so the deferral is durable. Not a blocker; intentional defer.

### 💭 QUESTION-1 — ADR file staging convention

Resolved by action: per the user's "Q-1 add" decision, both new ADRs (ADR-0006 from cherry-pick, ADR-0007 written by coder) will be staged before the round-2 gate check. The cherry-pick already created a tracked commit containing ADR-0006; ADR-0007 will be `git add`-ed in this round. No SKILL.md convention needs to be written down for this — the orchestrator's "user commits when ready" pattern is fine.

## Post-round-2 gate-rules.sh

Actual output captured 2026-05-21 after cherry-pick + `git add` of ADR-0007:

```
PASS wip-commits :: no WIP/checkpoint commits between origin/main and HEAD
SKIP tests-pass :: no test_command in .ssd/project.yml
SKIP feature-flag-present :: no feature_flag_marker in .ssd/project.yml
SKIP adr-delta :: architectural diff 2 lines below threshold 200
PASS frontmatter-valid :: 6 artifact(s) validated against schemas
exit: 0
```

Note on `adr-delta` SKIP (not PASS as the round-2 prediction expected): the rule's
"architectural diff" excludes markdown/doc files. With ADR-0006 and ADR-0007 in `docs/` and the
SKILL.md / CHANGELOG.md edits also doc-flavored, the only "architectural" line change is the
`VERSION` bump (2 lines: 1 added, 1 deleted). Below the 200-line threshold, so the rule SKIPs
rather than enforcing. This is the correct behavior — adr-delta is designed to catch *uncited*
architectural changes; this PR has two ADRs explicitly documenting its changes, so the rule
has nothing to enforce. Effectively a no-op SKIP, not a coverage gap.

## Self-verification (round 2)

1. **Each round-1 finding-closure claim verified against the diff?** Yes — see § "Closures verified" above. No "coder said it's fixed" entries.
2. **No new findings from the round-2 changes?** Verified: the round-2 edits are documentation-only and targeted at specific round-1 findings. No new functional surface, no new edge cases, no new dependencies.
3. **`closed_from_previous_round` frontmatter list accurate?** Yes — six IDs (MAJOR-1, MINOR-1, MINOR-2, MINOR-3, SUGGESTION-1, NIT-1) match the closures verified above. SUGGESTION-2 and QUESTION-1 are in `deferred_with_assent`, not `closed_from_previous_round`, because they were resolved by deferral or action, not by code change.

**Gate decision: PASS.** Workstream advances to `phase: gate` (or directly to deploy/commit per `/ssd ship` semantics for a markdown library). Coder is unblocked to stage + commit.
