# Code Reviewer Skill

<!-- License: See /LICENSE -->

**Version:** 1.4.0

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
| **Input** | Code diff, PR, or specific files under review. For remediation branches: also read `.ssd/milestones/<milestone>/skeptic-before.md` (if present) for prior-review context. |
| **Output** | Findings report with YAML frontmatter and severity-classified findings (BLOCKER / MAJOR / MINOR / QUESTION / SUGGESTION / NIT). Path varies by context: `.ssd/features/<slug>/04-code-review.md` (single-cycle feature, round 1) → `04-code-review-round-N.md` (round 2+); `.ssd/features/<slug>/iterations/<iter>/code-review/round-N.md` (multi-iteration feature, see ssd/SKILL.md § "Iterations Inside a Feature"); `.ssd/milestones/<milestone>/review-<pr>.md` (milestone). |
| **Consumed by** | `ssd` gate (reads `gate_pass` from frontmatter; BLOCKER or MAJOR findings block merge) |
| **SSD Phase** | `/ssd feature`, `/ssd milestone`, `/ssd gate` |

**Required output frontmatter** — every primary output opens with:

```yaml
---
skill: code-reviewer
version: 1.3.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <branch|commit-range|files>
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 0
  suggestion: 0
  nit: 0
gate_pass: true            # computed: blocker == 0 AND major == 0
remediation_mode: false    # true when reviewing a fix-oriented branch
round: 1                   # round number; 1 for first review, N for re-reviews
closed_from_previous_round: []   # finding IDs closed since round N-1
---
```

The `round` and `closed_from_previous_round` fields are written by every review; round 1 reviews
set `round: 1` and `closed_from_previous_round: []`. Round 2+ reviews fill `closed_from_previous_round`
with the IDs of findings claimed closed since the prior round.

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

### Phase 1.5: Prior-Review Follow-up (for remediation branches)

If the PR claims to remediate a prior review (via commit message, branch name, linked ACTION_PLAN, or
explicit PR description), do this before any other review work. Set `remediation_mode: true` in
frontmatter.

1. **Locate the prior review.** If the PR description links to it, follow the link. Otherwise look for
   `.ssd/milestones/<milestone>/skeptic-before.md` or `.ssd/features/<slug>/04-code-review.md`. If you
   cannot find it, ask. Do not review the branch without the prior review in hand — you will miss
   "unaddressed" findings.

2. **Enumerate the prior findings.** Create a table: finding ID | claim | PR status
   (addressed / partially addressed / deferred / silent).

3. **For each finding marked "silent":** check the branch diff to confirm the code wasn't changed. If a
   finding is silent, flag it as a MAJOR finding on the PR — either the finding was wrongly dismissed,
   or the dismissal reasoning was not written down.

4. **For each finding marked "partially addressed":** verify the deferred portion has a follow-up ticket
   or PR. If not, flag as MINOR.

5. **For findings marked "addressed":** apply the Edge Case Inventory (see `examples.md` §8) and the
   Fix-Introduces-Edge-Cases phase (3.5) to the fix code.

Never approve a remediation branch without completing this phase. "The commit message said it's fixed"
is not the same as "I verified it's fixed."

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

### Phase 3.5: Fix-Introduces-Edge-Cases (for bug-fix or defensive-code PRs)

When a PR adds defensive code (null guards, exception handlers, cache layers, fallback paths, retry
loops), the new code is a new surface area. Review it as new code, not as "the fix."

For each added defensive branch, enumerate the states it can enter:

1. **Null return from a helper:** Does the caller handle `None`? (e.g., `.first()`, `dict.get()`,
   `Model.objects.filter(...).first()`)
2. **Filter mismatched with constraint:** If catching `IntegrityError`, does the post-catch fetch filter
   match the constraint that raised the error? (A constraint on `status IN (A, B, C)` with a fetch
   excluding `status IN (D, E)` can return None.)
3. **Cache invalidation race:** Does the new cache have a test that exercises concurrent write+read? If
   not, the cache is stale-by-design in some window.
4. **Retry idempotency:** Does the new retry loop wrap a side-effecting operation? If yes, is the
   operation idempotent, or is the loop itself wrapped in a transaction?
5. **Exception narrowing edge:** If the catch was narrowed from `except Exception` to specific types,
   enumerate what other exceptions the try block can raise. Do any of them deserve different handling?
6. **Signal handler ordering:** If the fix adds a signal, document the ordering assumption (pre-save vs
   post-save, sender filter, race with other signals).
7. **New configuration knob:** If the fix adds a setting / env var, what's the default behavior if it's
   missing? Does the default break existing users?

Each bullet that applies gets its own finding if the code doesn't address it. A PR that "fixes a race
condition by adding an IntegrityError handler" that silently drops records under a secondary race is not
fixed — it is bug-shaped-differently.

**Heuristic:** If the PR's test suite only exercises the *primary* race / error / edge condition (the
one named in the commit message), it's undertested. The test must also exercise the edge cases the fix
itself introduces. See `examples.md` §8 for the Edge Case Inventory template.

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
| Lazy import inside a method (`def foo(): from x import y`) | Circular-dep symptom; the module graph wants to be different from what's declared |
| `.first()` / `dict.get()` / `next(iter(...), None)` with no None check on the result | Silent data loss / NoneType crash deferred to a later line |
| New cache layer without a race test | Invalidation windows uncaught; stale data serves as authoritative |
| Test mutates a `_private` attribute of the code under test | Test couples to internal representation; refactor tax |
| CI safety check with `continue-on-error: true` or `|| true` | Release theatre — the check reports but cannot stop |
| `IntegrityError` caught with a post-catch fetch that filters on status | Fetch filter must match the constraint set exactly, or records silently drop |
| User-controlled string inside an LLM prompt f-string | Prompt injection |
| `json.loads(llm_response)` with no schema check | Crashes when the model drifts; consumes bad data when it doesn't |
| Retry loop wrapping a non-idempotent operation | Duplicate writes on transient failure |
| `on_delete=CASCADE` to a FK whose target can be administratively deleted | Data loss by cleanup job |
| `conn_max_age > 0` with no connection-pool observability | Silent exhaustion under deploy + traffic |
| `transaction.atomic()` wrapping external API calls | Transaction held open during network I/O; blocks other writers |

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

---

## Parallelizing the Review via Sub-Agents

When a review is large enough to benefit from parallelization (multiple sub-agents reviewing different
file sets), the parent reviewer carries three obligations:

1. **Verify all BLOCKER and MAJOR claims before publishing them.** Sub-agents have partial context and
   often flag patterns as bugs when they are deliberate design choices. A false BLOCKER is worse than no
   BLOCKER — it erodes trust in the skill and wastes remediation cycles.

2. **Downgrade severity when the agent's rationale is "could be a bug" rather than "is a bug."** "May
   leak data in a multi-tenant context" is MAJOR in a multi-tenant product, and not a finding at all in
   a single-tenant one. The parent must check which applies.

3. **Deduplicate findings.** Two sub-agents working on overlapping file sets will report the same issue
   with different framing. Report once, cite both.

**Verification process for BLOCKER claims from sub-agents:**
- Read the file at the line cited.
- Trace the code path to confirm the claimed execution can happen.
- Run the relevant test if one exists; if not, note its absence.
- If the claim survives, publish. If it doesn't, downgrade or drop.

Never republish a sub-agent's BLOCKER without this three-step verification. "Agent said so" is not
evidence; it is hearsay.

---

## Severity Discipline

The difference between MAJOR and QUESTION is whether the reviewer has traced the path to a real bug vs.
noticed a pattern that could be a bug.

**Downgrade a MAJOR to QUESTION when:**
- The claim assumes a scenario ("if two threads...") without evidence the scenario can occur in this
  system
- The claim depends on context ("if this is multi-tenant...") that hasn't been verified
- The claim is "pattern X is sometimes wrong" without verifying it's wrong here

**Upgrade a QUESTION to MAJOR when:**
- The author of the PR answers the question in a way that confirms the bug
- A trace through the code confirms the claim

False MAJORs are worse than missed MINORs. A MAJOR that turns out to be wrong erodes trust in the
reviewer; a MINOR that goes uncaught gets caught on the next review.

---

## Self-Verification (before emitting output)

Before writing the final output artifact, answer these questions. If any answer is "no" or "I'm not
sure," pause and address it.

1. Did I read the actual files I'm citing, or am I pattern-matching from memory? (If memory: go read the
   files now.)
2. Did I verify each BLOCKER/MAJOR claim by tracing the execution path?
3. For each citation (file:line), does the line still exist at that number?
4. Are there claims that depend on assumptions I haven't stated?
5. If I parallelized via sub-agents, did I verify every sub-agent's BLOCKER/MAJOR claim before promoting
   it?
6. Did I downgrade any speculative claims ("could be a bug under X conditions") to QUESTION unless X is
   proven to apply?
7. Did I apply Phase 3.5 (Fix-Introduces-Edge-Cases) to every defensive code branch in the diff?
8. If `remediation_mode: true`, did I complete Phase 1.5 and enumerate prior findings by status?

---

## Deferred-Findings Verification

For multi-iteration features, every code review reads
`.ssd/features/<slug>/iterations/<iter>/deferred.yml` (if present) and verifies the status of each
entry in the diff under review.

For each entry with `target_iteration: <this-iter>` and `status: open`:

1. **Coder claims `closed`**: verify the fix in the diff. If verified, leave the entry as
   `status: closed, closed_in: <this-review-path>`. If unverified, raise a MAJOR finding (the fix
   is missing or incomplete).
2. **Coder claims `rolled-forward`**: confirm the coder-status body explains why and that
   `target_iteration` was bumped to a sensible future iter. If silent, raise a MINOR — rolling
   forward without rationale is the same kind of leak ADR-0002 closed for `current.yml`.
3. **Coder is silent on the entry**: raise a MAJOR — a deferred item that's neither closed nor
   rolled forward in its target iteration is the lost-finding failure mode.

For each entry with `target_iteration` not equal to `<this-iter>`: not in scope for this review.
Note in the review body that they exist (one line) so the reader knows they're tracked but
deferred.

**Frontmatter additions on review output:**

```yaml
deferred_handled:
  closed: [MINOR-N1]                # IDs closed in this round (verified against the diff)
  rolled_forward: [NIT-2]           # IDs the coder rolled forward (with reviewer assent)
  silent_findings: []               # IDs the coder neither closed nor rolled — should be empty
```

A non-empty `silent_findings` list is itself a MAJOR finding pattern.

**Single-cycle features** (no `iterations/` subdir, no `deferred.yml`) skip this entire phase. The
field stays absent from the frontmatter rather than appearing as `[]` everywhere — keep the
schema lean for the common case.

---

## Multi-Round Gates

A code-review pass that emits BLOCKER or MAJOR findings does not close — `code-reviewer` is
re-invoked on the diff that closes those findings, producing a round-2 review. This used to be
encoded as filename suffixes (`04-code-review-round-2.md` was a manual convention). As of v1.3.0
it is a structured concept the orchestrator manages.

**Round numbering:**
- The first review on a feature or iteration is `round: 1` (frontmatter), output path
  `04-code-review.md` (single-cycle) or `iterations/<iter>/code-review/round-1.md` (multi-iter).
- A re-review after fixes is `round: 2` (then 3, 4, …). Output path `04-code-review-round-2.md`
  (single-cycle) or `iterations/<iter>/code-review/round-2.md` (multi-iter).
- The orchestrator auto-numbers: it inspects existing `code-review*` artifacts in the relevant
  directory and writes the next available round.

**`closed_from_previous_round` discipline:** every round-2+ review's frontmatter must list the
finding IDs (`MAJOR-1`, `MINOR-3`, etc.) the reviewer believes were closed since the prior round.
The reviewer verifies each claim by reading the cited code path; never copy the list from the
coder-status without independent verification.

**`gate_rounds` in `current.yml`:** the orchestrator increments `current.yml.active[].gate_rounds`
when a new round is written. A workstream with `gate_rounds: 3` has been through three reviews;
useful for budget tracking ("this iteration has consumed three review rounds — is the design
contested?").

**Inline round-2 in single-cycle reviews**: small remediations (1–3 finding closures) may inline
the round-2 update at the bottom of the existing `04-code-review.md` rather than producing a
separate file, with `round: 2` and `closed_from_previous_round: [...]` updated in frontmatter.
This is the pattern iteration 1 of the ssd-skill-upgrades epic used; it remains a valid option for
small fix-ups where producing a second file is overkill.

---

## Changelog

- **1.4.0** (2026-04-29) — Iteration 4 of the ssd-skill-upgrades epic (P1.5): deferred-findings
  verification. New "Deferred-Findings Verification" section: every multi-iteration review reads
  `iterations/<iter>/deferred.yml` and verifies each entry's status against the diff. New
  `deferred_handled` frontmatter block (`closed`, `rolled_forward`, `silent_findings`). Silent
  findings (deferred but neither closed nor rolled forward in target iteration) are themselves a
  MAJOR. Single-cycle features skip this section entirely.
- **1.3.0** (2026-04-29) — Iteration 3 of the ssd-skill-upgrades epic (P1.2): multi-round gates as
  a built-in concept. New frontmatter fields `round` (number) and `closed_from_previous_round`
  (list of finding IDs) on every review. Output path varies by round and context (single-cycle
  vs. multi-iteration feature). New "Multi-Round Gates" section documents auto-numbering, the
  `closed_from_previous_round` discipline, and the inline-round-2 option for small remediations.
  No behavior change for round-1 reviews (default values).
- **1.2.1** (2026-04-28) — Working-tree path references updated from `ssd/` to `.ssd/` per repo-wide convention change. See repo CHANGELOG [1.4.0]. No behavior change.

- **1.2.0** (2026-04-18) — Added Phase 1.5 Prior-Review Follow-up for remediation branches (R6); added
  Phase 3.5 Fix-Introduces-Edge-Cases (R2); expanded Red Flags table with 12 new patterns including LLM
  prompt-injection, IntegrityError fetch mismatch, lazy imports, cache-without-race-test, and release
  theatre (R3); added Verify-Before-Escalating rule for sub-agent parallelization (R4); added explicit
  Severity Discipline section (O7); added Self-Verification gate (O6); declared output artifact path
  and YAML frontmatter schema (O2/O3).
- **1.1.0** — Split out `examples.md` from `SKILL.md` for reference material.
- **1.0.0** — Initial release.
