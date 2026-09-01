<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

### `/ssd start` — Walking Skeleton

For new projects or major features requiring end-to-end scaffolding.

**Step 1: Foundation**
Invoke `architect` to design:
- Project structure and app boundaries
- Core data models
- CI/CD pipeline design
- Feature flag system

Then invoke `systems-designer` to produce:
- Day-1 deployment checklist
- Monitoring and observability plan
- Initial failure mode analysis

**Exit gate**: Deploy "Hello World" to the project's distribution channel (production URL, TestFlight, Play Internal Testing, notarized build, or container registry). If deployment takes more than one working day, stop and fix the deployment pipeline first.

**Step 2: First End-to-End Slice**
Invoke `architect` to design the thinnest single user flow (e.g., "user can log in"). Then follow the Feature Loop below for that slice.

**Step 3: Expand**
Every subsequent feature uses `/ssd feature`.

---

### `/ssd feature` — Feature Loop

The standard daily development cycle. Repeat per feature.

1. **Design** — invoke `architect`
   - Data model changes
   - Service layer design
   - API contract
   - Produces a spec for the coder

2. **Production check** — invoke `systems-designer`
   - Identify failure modes for this feature
   - Confirm observability hooks are planned
   - Verify deployment safety (migration strategy, feature flag plan)
   - Produces: production readiness checklist specific to this feature

3. **Build** — invoke `coder` (auto-detects language; loads language-specific reference)
   - Implement from the architect spec
   - All new code goes behind a feature flag unless it's infrastructure
   - Mark uncertainties with `# REVIEW:` comments

4. **Review gate** — invoke `code-reviewer`
   - BLOCKER or MAJOR findings → return to Build, do not proceed
   - Clean review → proceed to deploy

5. **Deploy**
   - CI/CD to staging, then production
   - Feature flag: off (internal only) until verified
   - Monitor for 30 minutes post-deploy

6. **Enable flag**
   - Internal users → beta → 100%
   - Remove flag and dead code once 100% stable

**Shippable state invariant**: At the end of each work session, verify the invariant defined in `methodology/core.md` § "The Shippable State Invariant." The canonical checklist lives there — do not maintain a separate copy here.

#### Artifact-store commit on phase advance (ADR-0018, opt-in)

When `.ssd` is a store symlink and `project.yml.ssd.store_auto_commit` is true, the orchestrator
commits the store on **every** phase transition above:

```bash
bash methodology/store.sh commit --auto -m "<phase>: <slug>[#<iter>]"
```

Three properties, each deliberate:

- **Local only.** `store.sh commit` has no network path at all. Committing is bookkeeping; **pushing is
  an outward action** and stays explicit (`/ssd store push`), consistent with this library's refusal to
  auto-tag or auto-push.
- **Silent no-op** when the store has no changes, so a phase that wrote nothing produces no commit.
- **Never fails a phase.** A store-commit failure warns and continues — the `.ssd/` write already
  succeeded and remains the authoritative state, exactly as a failed `issue-sync` mirror does.

With no store link, or `auto_commit` false, this is a no-op.

#### `/ssd store` — manage the private artifact store

| Command | Effect |
|---|---|
| `/ssd store status` | link, target, store repo, uncommitted count, and any `project.yml` drift |
| `/ssd store init <root>` | prepare the private repo (idempotent) |
| `/ssd store link <root>` | **dry-run**: lists every file that would move out of the project |
| `/ssd store link <root> --confirm` | acts — moves the artifacts and creates the symlink |
| `/ssd store commit [-m msg]` | commit the store (local) |
| `/ssd store push` | push the store (outward; explicit) |

`link` *moves* artifacts out of the project — the second destructive operation in the library — so it
is dry-run by default and always prints the complete file list first.

#### GitHub issue sync on phase advance (ADR-0014, opt-in)

When `.ssd/project.yml` has `integrations.github.issue_tracking: on`, the orchestrator mirrors the
advancing workstream's state to GitHub issues on **every** phase transition above. The mirror is
**one-way** (local `.ssd/` drives GitHub) and **best-effort** — it never blocks a phase.

On each advance, the orchestrator:

1. Runs `bash methodology/issue-sync.sh preflight`. **Exit 3** (no `gh`, unauthenticated, or no repo)
   → warn once and continue the phase; local state is authoritative and unaffected.
2. For each ADR in the workstream's `adrs_authored`, runs `issue-sync.sh ensure-epic <ADR-NNNN>
   "<title>"` and caches the returned number in `current.yml.active[].epic`.
3. Runs `issue-sync.sh ensure-feature <slug> <phase> <epic#>` and caches `current.yml.active[].issue`.
   For an **iterated** workstream the orchestrator passes the iteration-qualified slug
   (`<slug>#<iter>`, e.g. `github-issue-tracking#b`) so a new iteration gets its **own** feature issue
   rather than re-opening the closed prior-iteration one (ADR-0014 iter-B D3).
4. Runs `issue-sync.sh set-phase <issue#> <phase>` to swap the `ssd:phase/*` label and refresh the
   issue body block.

**Closing on `done` (iter B, ADR-0014 Q2).** When a workstream advances to `done`:

5. Runs `issue-sync.sh close-feature <issue#>`. With `auto_close: false` (default) this returns
   **exit 10 = needs-confirm**: surface the intent and prompt once ("Close feature issue #F?"); on
   yes, re-run with `--confirm`. With `auto_close: true` it closes immediately (still announced).
6. Then closes the epic **only if both guards pass** (the [D1 split](../../docs/decisions/ADR-0014-github-issue-state-tracking.md)):
   - **Orchestrator guard (local):** inspect `.ssd/current.yml` (incl. archived entries' planned-
     iteration markers, e.g. `iter_b_tracked_on`). If any further iteration for this epic is planned
     or active, **do not** propose `close-epic`. This is why epic #27 stayed open when iter A's #28
     closed.
   - **Script guard (GitHub):** `issue-sync.sh close-epic <epic#>` refuses (exit 0, `state=skipped`,
     `reason=open-children`) while any `ssd:feature` child is still open, and otherwise returns
     exit 10 / closes under the same `auto_close`/`--confirm` gate as the feature.

Each action is **surfaced in the proposal before it runs** (rule-zero: no silent outward action).
Per [ADR-0014](../../docs/decisions/ADR-0014-github-issue-state-tracking.md) Q2, create/update are
automatic under the toggle (additive, low-stakes); **closing** is gated behind
`integrations.github.auto_close` (default = prompt once). The `issue-sync-current` gate rule
(informational, SKIP-by-default) flags any mirror drift at `/ssd gate` time. With the toggle absent
or `off`, this whole block is a no-op — zero network calls, behavior identical to a project that never
heard of issue tracking.

---

### `/ssd design` — Bundled Design Pass

`architect` and `systems-designer` always run in sequence with the same inputs in the standard
`/ssd feature` flow. v1.7.0 lets them run as one logical step.

```
/ssd design <slug>
/ssd design <slug>#<iter>
```

The orchestrator:

1. Invokes `architect` first; produces `.ssd/features/<slug>/01-architect.md` (or
   `iterations/<iter>/01-architect.md` for multi-iteration features).
2. Reads the architect output and invokes `systems-designer` with it as input; produces
   `02-systems-designer.md` alongside.
3. Surfaces any architect-spec gaps that systems-designer rejected back to the user as a single
   actionable block (rather than two separate handoffs).

**This does not replace** the individual invocations. `architect` and `systems-designer` remain
independently invocable for ad-hoc design work, milestone redesigns, and external consumers
(e.g., `codebase-skeptic` reading just the architect spec). `/ssd design` is a convenience —
it does not gate or change either skill's contract.

**Skip `/ssd design` when systems-designer is N/A** (e.g., a markdown-only documentation project,
a skills library, an ADR-only PR). The user can invoke `architect` directly.

---

### `/ssd milestone` — Milestone Audit

Run every 4–8 weeks or after 10+ features land. Always runs *after* shipping, never instead of it.

**Step 0: Snapshot.** Before any analysis:
- Record git SHA → `.ssd/milestones/<milestone>/sha-before`
- Save current coverage / metrics → `.ssd/milestones/<milestone>/metrics-before.yml`

**Step 0.5: Epistemic audit — propose `/feynman`** (ADR-0016). Offer it; do not run it unasked. Say
what it does in one line ("grades what this project believes about itself against evidence") and why
here ("a milestone acts on the *account* of the codebase — Step 1 audits the code, this audits the
account"). Then:
- **Accepted** → output `.ssd/milestones/<milestone>/feynman.md`. Its 🔴 contradicted claims become
  declared scope for Step 1, so the skeptic reviews the structures the false beliefs were resting on.
- **Declined** → record the decision in the milestone record. A skipped audit is a choice, not an
  absence, and the next reader should be able to tell which it was.

Never auto-run this step. An audit on every cycle becomes the ritual its own Phase 3 exists to catch —
which would make the skill fail its own inventory. Offer, record, move on.

1. **Deep audit** — invoke `codebase-skeptic`
   - Full architectural critique across fifteen expert voices, of which 2–15 activate per codebase
   - Output: `.ssd/milestones/<milestone>/skeptic-before.md` (with frontmatter per O2)

2. **Refactor planning** — invoke `refactor`
   - Input: `skeptic-before.md`
   - Each refactor item cites a specific finding ID from skeptic-before.md. No cite → not in scope.
   - Output: `.ssd/milestones/<milestone>/refactor-plan.md`
   - Start with high complexity + high churn areas
   - Write tests first if coverage is insufficient
   - Small, independently deployable commits only
   - Each refactor is a separate PR from feature work

3. **Validate** — invoke `code-reviewer` on each refactoring PR
   - `remediation_mode: true` in frontmatter
   - Same gate as feature work: no BLOCKER/MAJOR
   - Record PR list → `.ssd/milestones/<milestone>/refactor-prs.md`

4. **Deploy** and confirm production health post-refactor

5. **Verify (mandatory)** — invoke `/ssd verify` (see below). The milestone is complete only when
   verification passes.

**Constraint**: Scope cuts and refactors are not failure — they are engineering judgment. Reducing scope to maintain shippable state is correct behavior.

---

### `/ssd verify` — Remediation Verification

Mandatory after milestone refactors. Before the next feature cycle begins, run verification:

1. **Re-invoke `codebase-skeptic`** with scope = same as `skeptic-before.md`. Its output goes to
   `.ssd/milestones/<milestone>/skeptic-after.md` (with frontmatter).

2. **Diff the frontmatter** against `skeptic-before.md`. For each original finding, mark its status:
   - ✅ closed / 🔄 partial / ❌ unaddressed / 🆕 new-regression
   New findings that weren't in the "before" run are surfaced separately.

3. **Re-invoke `code-reviewer`** on the refactor diff with explicit `remediation_mode: true` (triggers
   Phase 1.5 + Phase 3.5).

3.5. **If `/feynman` ran at Step 0.5 of the milestone, propose re-running it.** Verification's own
   claim — "all original findings are ✅ closed" — is exactly the kind of assertion the epistemic
   audit exists to test, and a milestone that closes findings on paper is the failure mode it was
   built for. Compare `claim_counts` against the earlier report: contradicted going up during a
   remediation is a louder signal than any single unclosed finding.

4. **Verification passes if:**
   - All original BLOCKER / 🔴 / 💀 findings are ✅ closed
   - No 🆕 new-regression is BLOCKER severity
   - Code review on the remediation diff has no BLOCKERs

   Output: `.ssd/milestones/<milestone>/verification.md`.

If verification fails, the milestone is NOT complete. Return to refactor.

Verification is not optional. A refactor that claims to close findings without verification is
indistinguishable from wishful thinking.

---

### `/ssd audit` — Nuclear Audit

For adversarial evaluation: comparing approaches, legacy onboarding, vendor selection, or when you need an uncomfortable honest assessment.

Invoke `software-standards`.

**Also propose `/feynman`** when the uncomfortable question is internal rather than comparative.
`software-standards` answers "how do we compare to the field?"; `feynman` answers "is our own account
of ourselves true?" A vendor selection wants the former; "why does this keep slipping?" wants the
latter. Both may run — they are coordination, not substitution.

Output: comparative scored report with Hard Truth section.
Use findings to inform architect redesign or refactor priorities.

Do not invoke this routinely. It is for adversarial contexts, not everyday review.

---

### `/ssd gate` — Shippable State Check

Invoke `code-reviewer` on the current code or PR.

Pass criteria: no BLOCKER or MAJOR findings.
Fail: return to coder before proceeding.

**Multi-round behavior** (since v1.6.0): if `code-reviewer` emits BLOCKER or MAJOR, the gate fails
and the workstream returns to coder. After fixes, re-running `/ssd gate` produces a round-2
review:
- The orchestrator auto-numbers the round by inspecting existing `code-review*` artifacts in the
  relevant directory.
- Output path: `04-code-review-round-2.md` (single-cycle features) or
  `iterations/<iter>/code-review/round-2.md` (multi-iteration features).
- Frontmatter `round: 2` and `closed_from_previous_round: [BLOCKER-1, MAJOR-2, …]` (every closure
  verified against the code, not copied from coder-status).
- `current.yml.active[].gate_rounds` increments. A workstream with `gate_rounds: 3` has been
  through three reviews — useful budget signal.

For small remediations (1–3 finding closures), an inline round-2 update at the bottom of the
existing `04-code-review.md` is permitted in lieu of a separate file. See `code-reviewer/SKILL.md`
§ "Multi-Round Gates."

---

### `/ssd ship` — Deploy Readiness Check

Invoke `systems-designer` deploy checklist for the feature about to ship.

**At the gate boundary,** `feynman-clean` (ADR-0016) FAILs if a `feynman.md` in this change set
reports `contradicted` or `theater` claims — the project's own account of itself failed against
evidence, and shipping on it means shipping on a belief already falsified. Surface the rule's detail
verbatim, and never pass silently. **There is no `--force` to reach for** — the flag ADR-0012
Pillar 5 describes is not built (Feynman audit 2026-09-01, C4), so overriding this rule means merging
a red gate on purpose and recording the reason by hand in the deploy log. The rule SKIPs
when no audit is in scope: **not running `/feynman` is not a violation**, so a SKIP or PASS here means
"no failing audit in this change set", not "the beliefs are calibrated." Say that when you report it.

Invoke `systems-designer` to produce the platform-appropriate deploy checklist. The checklist is defined and maintained by that skill — do not duplicate it here. The systems-designer skill covers web, mobile (iOS/Android), and macOS desktop deployment readiness.

**Tag the release (after PR merge).** Once the release PR merges to `main`, tag the merge commit
so the release history stays navigable (the missing-tags drift the post-v1.19 milestone fixed):

```bash
git tag -a v<version> <merge-sha> -m "v<version> — <one-line summary>"
git push origin v<version>
```

This should be done by hand or via a release script; the orchestrator does **not** auto-tag,
because tagging pushes to the remote and outward-facing actions stay under explicit human
control. This step closes the post-merge half of the `core.md` §4 ratchet ("tag every release").
(Refactor R7, post-v1.19 milestone.)

---

