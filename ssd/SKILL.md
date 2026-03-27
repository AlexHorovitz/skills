## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

**Version:** 1.0.0

# SSD Meta-Skill

## Purpose
Orchestrate the full skill chain for Shippable States Development. Every work session ends in a deployable, production-ready state. If you can't ship it right now, you don't have a product — you have a construction site.

## When to Use
Invoke this skill when starting a session and you want to follow the SSD workflow. It selects and sequences sub-skills based on the phase argument you provide.

## Interface

| | |
|---|---|
| **Input** | Phase argument (`start`, `feature`, `milestone`, `audit`, `gate`, `ship`) + project context |
| **Output** | Orchestrated session: invokes the appropriate sub-skills in sequence and enforces the shippable state invariant |
| **Consumed by** | None — top-level orchestrator |
| **SSD Phase** | All phases |

---

## Invocation

```
/ssd start      — New project or major feature: Walking Skeleton setup
/ssd feature    — Active development: design → build → review → deploy loop
/ssd milestone  — Post-sprint consolidation: deep audit + targeted refactor
/ssd audit      — Adversarial comparative review (nuclear option)
/ssd gate       — Shippable state check only (code-reviewer)
/ssd ship       — Deploy readiness check only (systems-designer checklist)
```

If no argument is given, ask the user which phase they are in.

---

## Phase Playbooks

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

**Shippable state invariant**: At the end of each work session:
- [ ] All tests pass
- [ ] Code committed and pushed
- [ ] CI/CD pipeline green
- [ ] Feature flags set correctly
- [ ] No BLOCKER/MAJOR findings in code-reviewer report

---

### `/ssd milestone` — Milestone Audit

Run every 4–8 weeks or after 10+ features land. Always runs *after* shipping, never instead of it.

1. **Deep audit** — invoke `codebase-skeptic`
   - Full architectural critique across ten expert voices
   - Output: prioritized findings list

2. **Refactor planning** — invoke `refactor`
   - Start with high complexity + high churn areas
   - Write tests first if coverage is insufficient
   - Small, independently deployable commits only
   - Each refactor is a separate PR from feature work

3. **Validate** — invoke `code-reviewer` on each refactoring PR
   - Same gate as feature work: no BLOCKER/MAJOR

4. **Deploy** and confirm production health post-refactor

**Constraint**: Scope cuts and refactors are not failure — they are engineering judgment. Reducing scope to maintain shippable state is correct behavior.

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

---

### `/ssd ship` — Deploy Readiness Check

Invoke `systems-designer` deploy checklist for the feature about to ship.

Confirms (adapt to platform):

**Web / Headless:**
- [ ] Migrations are safe (no table locks, reversible)
- [ ] Feature flag configured
- [ ] Rollback procedure documented
- [ ] Monitoring dashboards open
- [ ] On-call team briefed

**Mobile (iOS / Android):**
- [ ] Build archived and uploaded to TestFlight / Play Internal Testing
- [ ] Crash reporting verified on latest build
- [ ] Feature flags configured via remote config
- [ ] Rollback plan: previous build available in distribution channel
- [ ] Release notes drafted

**macOS Desktop:**
- [ ] Notarization passing
- [ ] Distribution mechanism verified (TestFlight for Mac / signed DMG)
- [ ] Crash reporting verified
- [ ] Feature flags configured

---

## Hard Rules (Invariants)

These are not suggestions. Violating them breaks SSD.

1. **No merge without a clean `/ssd gate`** — no BLOCKER or MAJOR findings
2. **No incomplete work on main without a feature flag** — WIP commits are banned
3. **Tests must pass before and after every change** — "I'll fix the tests tomorrow" is not a shippable state
4. **Refactor only after shipping** — separate PRs, never mixed with feature work
5. **Deploy beats perfection** — reduce scope rather than delay a deploy
6. **Production parity from day one** — if you haven't deployed to your distribution channel yet (production server, TestFlight, Play Internal Testing, notarized build), that is your next task

---

## Sub-Skill Reference

| Sub-Skill | Role in SSD | Phase |
|---|---|---|
| `architect` | Design: models, services, API boundaries | start, feature |
| `systems-designer` | Production readiness: reliability, observability, deployment safety | start, feature, ship |
| `coder` | Implementation from spec (language-adaptive) | feature |
| `code-reviewer` | PR gate: BLOCKER/MAJOR findings block merge | feature, milestone, gate |
| `codebase-skeptic` | Deep architectural critique (10 expert voices) | milestone |
| `software-standards` | Adversarial comparative audit | audit |
| `refactor` | Post-ship targeted improvement | milestone |

`proposal-reviewer` and `software-capitalization` are standalone domain tools and do not participate in the SSD workflow.

---

## Review Tier Selection

Three skills do "review" work. Never chain all three — pick the right tier:

- **`code-reviewer`** — every PR, always, no exceptions
- **`codebase-skeptic`** — milestone reviews and pre-release audits
- **`software-standards`** — comparative/adversarial evaluation only

