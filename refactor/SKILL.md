<!-- License: See /LICENSE -->

**Version:** 1.1.0

# Refactoring Skill

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
| **Input** | `codebase-skeptic` or `code-reviewer` findings (when available); otherwise, codebase scan |
| **Output** | Prioritized refactor plan + refactored code submitted as separate PRs from feature work |
| **Consumed by** | `code-reviewer` (each refactoring PR goes through the same gate as feature work) |
| **SSD Phase** | `/ssd milestone` |

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