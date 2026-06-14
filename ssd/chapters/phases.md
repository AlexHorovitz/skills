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

1. **Deep audit** — invoke `codebase-skeptic`
   - Full architectural critique across ten expert voices
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

