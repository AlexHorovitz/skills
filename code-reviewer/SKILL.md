<!-- License: See /LICENSE -->

**Version:** 1.1.0

# Code Reviewer Skill

## Purpose
Conduct rigorous, adversarial code reviews that catch bugs, security vulnerabilities, performance issues, and maintainability problems before they reach production. Be ruthless but constructive—the goal is better code, not crushed developers.

## When to Use
- Reviewing pull requests before merge
- Auditing existing code for quality issues
- Post-incident code analysis
- Pre-release security and quality reviews

## Interface

| | |
|---|---|
| **Input** | Code diff, PR, or specific files under review |
| **Output** | Findings report with severity-classified findings (BLOCKER / MAJOR / MINOR / QUESTION / SUGGESTION / NIT) |
| **Consumed by** | `ssd` (BLOCKER or MAJOR findings block merge; clean report allows proceed) |
| **SSD Phase** | `/ssd feature`, `/ssd milestone`, `/ssd gate` |

---

> **Language note:** Examples in this skill are written in Python/Django for illustration. When reviewing code in other languages or frameworks, adapt the patterns to the project's actual stack. The *concepts* (N+1 queries, IDOR, race conditions, guard clauses) are universal — the syntax is not.

---

## Review Philosophy

### Ruthless ≠ Mean

**Ruthless means:**
- Finding every issue, not just the obvious ones
- Questioning assumptions and edge cases
- Refusing to approve code that isn't ready
- Holding the same standard for everyone, including yourself

**Ruthless does NOT mean:**
- Personal attacks or condescension
- Blocking code for stylistic preferences
- Demanding perfection when "good enough" suffices
- Nitpicking without providing value

### The Reviewer's Mindset

1. **Assume bugs exist.** Your job is to find them.
2. **Think like an attacker.** How could this be exploited?
3. **Think like a user.** What happens when they do unexpected things?
4. **Think like the on-call engineer.** Can I debug this at 3am?
5. **Think like the next developer.** Will they understand this in 6 months?

---

## The Review Process

### Phase 1: Understand Context (Before Reading Code)

Before looking at the implementation:

1. **Read the PR description.** What problem is being solved?
2. **Check the ticket/issue.** What are the requirements?
3. **Look at the test plan.** How is this being verified?
4. **Note the scope.** Is this a bug fix, feature, or refactor?

**If context is missing, request it.** Don't review code you don't understand.

### Phase 2: High-Level Review (Architecture & Design)

Read through the changes once, asking:

- Does this approach make sense for the problem?
- Are there simpler alternatives?
- Does this fit the existing architecture?
- Are the abstractions appropriate (not over/under-engineered)?

**Stop here if design is fundamentally wrong.** Don't polish a turd.

### Phase 3: Detailed Review (Line by Line)

Now examine the code systematically:

```
For each file:
  1. Correctness: Does it do what it claims?
  2. Security: Can it be exploited?
  3. Performance: Will it scale?
  4. Maintainability: Can others understand it?
  5. Testing: Is it adequately covered?
```

### Phase 4: Integration Review (The Bigger Picture)

After understanding the changes:

- How does this interact with existing code?
- What breaks if this fails?
- Are there migration or deployment concerns?
- What's the rollback strategy?

---

## Reference Files

This skill is organized into focused files. Load the relevant file based on the review context:

| File | Contents | Load when |
|---|---|---|
| `examples.md` | Annotated code examples: correctness bugs, security vulnerabilities, performance issues, maintainability smells, testing gaps, comment writing | Performing detailed line-by-line review (Phase 3) |

**On first invocation**: Start with the process and checklist below. Load `examples.md` when you need illustrative patterns during detailed review.

---

## Severity Levels

Use consistent prefixes:

| Prefix | Meaning | Blocks Merge? |
|--------|---------|---------------|
| `🔴 BLOCKER:` | Critical bug, security issue, data loss risk | Yes |
| `🟠 MAJOR:` | Significant issue that should be fixed | Yes |
| `🟡 MINOR:` | Small improvement, not urgent | No |
| `💭 QUESTION:` | Seeking clarification | Depends |
| `💡 SUGGESTION:` | Optional improvement idea | No |
| `📝 NIT:` | Style/formatting, truly optional | No |

---

## Review Checklist

### For Every PR

**Correctness**
- [ ] Logic handles all expected inputs correctly
- [ ] Edge cases are handled (null, empty, boundary values)
- [ ] Error cases are handled appropriately
- [ ] State changes are atomic where needed

**Security**
- [ ] No SQL injection vulnerabilities
- [ ] Authorization checks on all data access
- [ ] No sensitive data in logs or error messages
- [ ] Input validation on all user inputs
- [ ] No hardcoded secrets or credentials

**Performance**
- [ ] No N+1 queries
- [ ] Queries are indexed appropriately
- [ ] No unbounded operations
- [ ] Expensive operations are async or cached

**Maintainability**
- [ ] Code is readable without comments explaining what
- [ ] Functions have single responsibility
- [ ] No magic numbers or strings
- [ ] Error messages are actionable
- [ ] Consistent with existing codebase style

**Testing**
- [ ] Happy path tested
- [ ] Error cases tested
- [ ] Edge cases tested
- [ ] Tests are not brittle (test behavior, not implementation)

---

## Red Flags That Demand Extra Scrutiny

When you see these, slow down and review extra carefully:

| Red Flag | Why It's Risky |
|----------|----------------|
| `eval()`, `exec()` | Code injection |
| Raw SQL queries | SQL injection |
| `request.data` used directly | Mass assignment |
| `except:` or `except Exception:` | Swallowed errors |
| `# TODO`, `# FIXME`, `# HACK` | Technical debt |
| Commented-out code | Dead code |
| Files > 500 lines | Likely doing too much |
| Functions > 50 lines | Likely doing too much |
| Deeply nested conditionals | Hard to reason about |
| No tests for new code | Untested = broken |
| `time.sleep()` in non-test code | Probably wrong approach |
| Disabled linting rules | Hiding problems |

---

## When to Block vs. Approve

### Block (Request Changes)

- Security vulnerabilities
- Data loss or corruption risks
- Incorrect business logic
- Missing critical error handling
- Performance issues that will cause outages
- Missing tests for complex logic

### Approve with Comments

- Minor style improvements
- Optional refactoring suggestions
- Documentation improvements
- Nice-to-have optimizations

### Approve Immediately

- Typo fixes
- Documentation-only changes
- Test-only improvements
- Reverting problematic changes

---

## Common Review Mistakes to Avoid

| Mistake | Why It's Bad | Instead |
|---------|--------------|---------|
| Rubber-stamping | Misses bugs | Take time, be thorough |
| Blocking on style | Wastes time | Use automated linting |
| Reviewing too much at once | Review quality drops | Request smaller PRs |
| Not running the code | Misses runtime issues | Pull branch, test locally |
| Only reading the diff | Misses context | Look at full files |
| Approving to be nice | Ships bugs | Be honest, be kind |