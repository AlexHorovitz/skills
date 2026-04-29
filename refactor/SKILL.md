# Refactoring Skill

<!-- License: See /LICENSE -->

**Version:** 1.2.1

## Purpose
Continuously scan codebases for refactoring opportunities—improving code quality, reducing technical debt, and enhancing maintainability without changing external behavior. Be opportunistic but disciplined: refactor with purpose, not for sport.

## When to Use
- After features ship and dust settles
- When code review reveals systemic issues
- Before adding features to messy areas
- During dedicated tech debt sprints
- When test coverage makes refactoring safe

## Interface

| | |
|---|---|
| **Input** | `.ssd/milestones/<milestone>/skeptic-before.md` (primary, when invoked by `/ssd milestone`) or `.ssd/features/<slug>/04-code-review.md`. If neither exists, perform a codebase scan. |
| **Output** | `.ssd/milestones/<milestone>/refactor-plan.md` (with frontmatter) + refactored code submitted as separate PRs from feature work |
| **Consumed by** | `code-reviewer` (each refactoring PR goes through the same gate as feature work, with `remediation_mode: true`); `/ssd verify` (re-runs skeptic on identical scope) |
| **SSD Phase** | `/ssd milestone` |

**Each refactor item in the output plan MUST cite a specific finding ID from the input.** No cite →
not in scope. This enforces the loop-closure contract: every refactor traces to a reviewed finding.

**Required output frontmatter:**
```yaml
---
skill: refactor
version: 1.2.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <milestone>
consumed_by: [code-reviewer, ssd]
input_artifact: .ssd/milestones/<milestone>/skeptic-before.md
items:
  - id: R1
    cites: [S-F3, S-U1]        # finding IDs from input
    pattern: extract-service
    files: [apps/goals/services/goal_scoring.py]
    budget_hours: 4
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
---
```

---

> **Language note:** Examples and tooling references in this skill are Python-centric for illustration. When refactoring code in other languages, adapt the patterns and tools to the project's actual stack. The *principles* (extract method, guard clauses, parameter objects) and the *workflow* (tests first, small steps, behavior preservation) are universal — the syntax and tool names are not.

---

## Refactoring Philosophy

### The Boy Scout Rule
> Leave the code better than you found it.

But also:
> Don't rewrite the campsite while others are trying to use it.

### When to Refactor

**Good times to refactor:**
- You're already changing the code for a feature
- Tests exist and are passing
- You understand the code deeply
- The improvement has clear benefits
- The team agrees on the direction

**Bad times to refactor:**
- Right before a major release
- When you don't understand the code
- When tests are missing or failing
- For purely aesthetic reasons
- When it blocks others' work

### The Refactoring Contract

1. **Behavior must not change.** If users notice anything different, it's not a refactor—it's a bug.
2. **Tests must pass.** Before and after. No exceptions.
3. **Small steps.** Each commit should be independently safe to deploy.
4. **Revert-ready.** If anything goes wrong, roll back immediately.

---

## Reference Files

This skill is organized into focused files. Load the relevant file based on the task:

| File | Contents | Load when |
|---|---|---|
| `patterns.md` | Scanning techniques (complexity, duplication, dependencies, coverage, churn) + 6 refactoring patterns with before/after examples | Identifying refactoring candidates or applying a specific pattern |

**On first invocation**: Start with the philosophy, workflow, and prioritization below. Load `patterns.md` when you need scanning commands or pattern examples.

---

## Refactoring Workflow

### Step 1: Ensure Test Coverage

Before touching anything:

```bash
# Check coverage for the area you're refactoring
pytest --cov=apps/subscriptions --cov-report=html
# Open htmlcov/index.html and verify critical paths are covered
```

**If coverage is insufficient, write tests first.** Characterization tests that capture current behavior, even if that behavior is buggy.

### Step 2: Make a Refactoring Plan

```markdown
## Refactoring: Extract SubscriptionService

### Current State
Subscription logic is scattered across views, models, and management commands.

### Target State  
All subscription business logic in SubscriptionService class.

### Steps
1. [ ] Create SubscriptionService with empty methods
2. [ ] Move create logic from view to service
3. [ ] Move cancel logic from view to service
4. [ ] Move renew logic from management command to service
5. [ ] Update views to use service
6. [ ] Update management command to use service
7. [ ] Remove duplicate code from models
8. [ ] Add comprehensive service tests

### Risks
- View tests may break (need to update mocks)
- Management command behavior might differ slightly

### Rollback
Each step is a separate PR. Revert individual PRs if issues arise.
```

### Step 3: Small, Safe Steps

Each commit should:
- Pass all tests
- Be deployable independently
- Be revertable without affecting other changes

```bash
# Good commit sequence
git commit -m "Add empty SubscriptionService class"
git commit -m "Extract create_subscription to service"
git commit -m "Update CreateSubscriptionView to use service"
git commit -m "Remove create logic from view"
```

### Step 4: Verify Behavior Unchanged

After refactoring:
- All existing tests pass
- Manual smoke test of affected features
- Compare logs/metrics before and after (same patterns?)

### Step 4.5: Budget Check (at each step boundary)

At each step boundary, compare elapsed effort to the `budget_hours` declared in the plan. If elapsed
is > 150% of planned, emit a **scope reconsider** prompt and choose one:

- **Cut scope.** Ship what's done; defer the rest to a follow-up plan item.
- **Escalate.** Something is harder than expected — tell a human before sinking more time.
- **Defer.** Abandon this refactor item; move the citation back to the skeptic report as "deferred."

Feature flags mitigate technical risk. They do not mitigate scope risk. Don't keep grinding.

### Step 5: Loop Closure

Before marking a refactor plan item done:

1. **Re-run the originating finding's check.** If the finding came from codebase-skeptic's Evans voice
   ("KR logic spread across 4 services"), re-run that lens on the refactored code. If it came from
   code-reviewer's Red Flags ("lazy import inside method"), grep for the pattern.
2. **Record closure in the refactor-prs.md artifact.** One of: ✅ closed / 🔄 partial / ❌ abandoned.
3. **If partial or abandoned:** explicitly name the residue. "Extracted 3 of 4 services; the fourth
   needs a model change and is deferred to plan item R7."

Skipping this step turns refactors into proof-by-assertion. The milestone's `/ssd verify` phase will
re-run skeptic on the full scope; if this item didn't close, `/ssd verify` will catch it — but finding
out there is worse than finding out here.

### Step 6: Systems-Designer Coordination

If any item in the plan touches failure modes, observability, transaction boundaries, async/sync
flipping, queue semantics, or deploy ordering, set `touches_failure_modes / touches_observability /
touches_deploy_path: true` in the item's frontmatter and re-run `systems-designer` on the affected
area. A refactor that silently changes production-readiness profile is the kind of drift SSD exists to
prevent.

---

## Prioritization Framework

Not all refactoring is equal. Prioritize by impact:

### High Priority (Do Soon)
| Condition | Why |
|-----------|-----|
| High complexity + High churn | Frequently changed, hard to change safely |
| Security-related code | Risk of introducing vulnerabilities |
| Missing critical tests | Can't safely change anything |
| Blocking new features | Opportunity cost of not fixing |

### Medium Priority (Plan for It)
| Condition | Why |
|-----------|-----|
| Moderate complexity, stable code | Painful but not urgent |
| Inconsistent patterns | Cognitive load for team |
| Outdated dependencies | Security/compatibility risk growing |

### Low Priority (Opportunistic)
| Condition | Why |
|-----------|-----|
| Working code with tests | If it ain't broke... |
| Style-only improvements | Low value, low risk |
| Rarely touched code | Effort exceeds benefit |

### The Refactoring Backlog

Maintain a living document:

```markdown
# Refactoring Backlog

## High Priority
- [ ] #123 Extract PaymentService (complexity: 25, churn: high)
- [ ] #124 Add tests for authentication flow (coverage: 20%)

## Medium Priority  
- [ ] #125 Consolidate user notification methods (3 duplicates)
- [ ] #126 Replace raw SQL queries in reports module

## Low Priority / Opportunistic
- [ ] #127 Rename confusing variable names in legacy module
- [ ] #128 Convert old-style string formatting to f-strings

## Completed
- [x] #120 Extract SubscriptionService (2024-01-15)
- [x] #121 Remove deprecated API endpoints (2024-01-10)
```

---

## Metrics to Track

### Code Health Metrics

Track these monthly:

| Metric | Tool | Target |
|--------|------|--------|
| Cyclomatic complexity (avg) | radon | < 5 |
| Test coverage | pytest-cov | > 80% |
| Duplication | pylint | < 5% |
| Dependency depth | pydeps | < 4 levels |
| Tech debt ratio | SonarQube | < 5% |

### Refactoring Impact

After major refactors, measure:

- **Time to implement features** in refactored area (should decrease)
- **Bug rate** in refactored area (should decrease)  
- **Code review time** (should decrease)
- **Onboarding feedback** ("is this area confusing?")

---

## Common Refactoring Mistakes

| Mistake | Consequence | Prevention |
|---------|-------------|------------|
| Refactoring without tests | Bugs introduced silently | Tests first, always |
| Big bang rewrites | Never ships, loses context | Small incremental steps |
| Refactoring during feature work | Confusing PRs, mixed concerns | Separate PRs |
| Refactoring stable code | Wasted effort, risk for no gain | Focus on high-churn areas |
| Changing behavior "while we're here" | Hidden bugs | Strict behavior preservation |
| Not communicating | Merge conflicts, duplicated work | Announce refactoring plans |

---

## Quality Checklist

Before completing a refactoring:

- [ ] All tests pass (no new test failures)
- [ ] Test coverage maintained or improved
- [ ] No behavior changes (verified by tests + manual check)
- [ ] Code complexity reduced (measured)
- [ ] Changes are in small, reviewable commits
- [ ] Each commit is independently deployable
- [ ] PR description explains the "why" not just the "what"
- [ ] Rollback plan documented
- [ ] Each item cites the originating finding ID
- [ ] Closure recorded (✅ / 🔄 / ❌) per item in `refactor-prs.md`
- [ ] If any item touched failure modes / observability / deploy, `systems-designer` was re-run on the
      affected area

---

## Changelog

- **1.2.1** (2026-04-28) — Working-tree path references updated from `ssd/` to `.ssd/` per repo-wide convention change. See repo CHANGELOG [1.4.0]. No behavior change.

- **1.2.0** (2026-04-18) — Declared output artifact path and YAML frontmatter with per-item finding
  citations (R1); added Step 4.5 budget check with halt-and-rollback options (R2); added Step 5 Loop
  Closure with per-item re-check and closure status (R4); added Step 6 Systems-Designer Coordination
  trigger (R3); expanded Quality Checklist with citation + closure + systems-designer handoff items.
  R5 (language-specific pattern files) deferred; patterns.md remains Python-centric with a language
  note.
- **1.1.0** — Split out `patterns.md` from `SKILL.md`.
- **1.0.0** — Initial release.
