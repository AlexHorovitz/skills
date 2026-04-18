<!-- License: See /LICENSE -->


# Codebase Review Report Template

> **Usage notes for the agent:**
> - Include ONLY sections for voices that were activated. Delete the rest.
> - Each voice section should contain 1–4 specific findings. Quality over quantity.
> - Findings without specifics (file names, function names, patterns) are not findings — they are noise.
> - The Synthesis section is required regardless of how many voices fired.
> - Adjust length proportionally to the scope of what was reviewed. A 200-line module review should
>   not look like a 200,000-line platform review.

---

# Codebase Review: `[Project Name or Description]`

**Reviewed:** `[Date]`
**Scope:** `[What was examined — full repo, module, service, architecture description, excerpts]`
**Domain:** `[What the system does, in plain language]`
**Stack:** `[Primary language(s), frameworks, runtime environment]`
**Voices Activated:** `[Comma-separated list of activated voices]`

---

## Overall Posture

```
[One of:]
  ✅ Sound — defensible architecture, addressable issues
  ⚠  Drifting — coherent intent undermined by accumulating decisions
  🔴 At Risk — structural problems that compound; requires deliberate intervention
  💀 In Crisis — foundational issues; forward progress accrues debt faster than value
```

**In one sentence:** `[The single most important thing to know about this codebase right now.]`

---

<!-- ============================================================
     VOICE SECTIONS — DELETE SECTIONS FOR VOICES NOT ACTIVATED
     ============================================================ -->

## Fowler — Architecture & Evolutionary Design

> *Refactoring, software smells, distribution decisions, change-enabling structure*

### Findings

**[Severity: ⚠/🔴/💀] [Finding title]**
`[File/module/service reference if available]`
[2–4 sentences: what is observed, why it is a problem, what the cost is over time.]

**[Severity] [Finding title]**
[Finding detail.]

### Fowler's Recommendation
[What Fowler would say to do. Specific and actionable. May reference a refactoring pattern by name.]

---

## Uncle Bob — Code Structure & SOLID

> *Clean code, dependency direction, modularity, naming, separation of concerns*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Uncle Bob's Recommendation
[Specific recommendation. May reference which SOLID principle is violated and how to correct the dependency direction.]

---

## Beck — Tests & Feedback Loops

> *Test quality, TDD signals, YAGNI, incremental design, feedback cycle length*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Beck's Recommendation
[Specific recommendation. Address test quality, coverage gaps, or over-engineering as applicable.]

---

## Feathers — Safety of Change

> *Testability, seams, characterization, legacy rescue, blast radius*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Feathers's Recommendation
[Specific recommendation. Name the seam to cut, the characterization test to write first, or the safest approach to the change at hand.]

---

## Evans — Domain Model & Bounded Contexts

> *Ubiquitous language, model integrity, bounded contexts, aggregate design*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Evans's Recommendation
[Specific recommendation. May reference context map, anti-corruption layer, or ubiquitous language repair.]

---

## Hohpe — Integration & Messaging

> *Messaging patterns, idempotency, schema contracts, coupling via integration*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Hohpe's Recommendation
[Specific recommendation. Name the messaging pattern to apply, the idempotency key to add, or the coupling to break.]

---

## Humble — Delivery Pipeline & Deployment

> *Pipeline completeness, manual steps, rollback, environment parity, deploy safety*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Humble's Recommendation
[Specific recommendation. Describe the pipeline improvement, the manual step to automate, or the rollback mechanism to build.]

---

## Kleppmann — Data Systems & Consistency

> *Consistency models, concurrency, replication, schema evolution, clock assumptions*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Kleppmann's Recommendation
[Specific recommendation. Name the isolation level, the idempotency mechanism, or the consistency tradeoff to make explicit.]

---

## Jobs — Product Judgment & Coherence

> *Simplicity, API design, feature coherence, configuration surface, user model*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Jobs's Recommendation
[Specific recommendation. What to remove, what to simplify, what opinionated default to adopt.]

---

## Wozniak — Engineering Economy & Elegance

> *Unnecessary complexity, algorithmic waste, abstraction tax, genuine ingenuity*

### Findings

**[Severity] [Finding title]**
`[Reference]`
[Finding detail.]

**[Severity] [Finding title]**
[Finding detail.]

### Wozniak's Recommendation
[Specific recommendation. Name the layer to remove, the algorithm to replace, or the elegant solution that is already present and worth preserving.]

---

<!-- ============================================================
     END VOICE SECTIONS
     ============================================================ -->

---

## Synthesis

### Remediation Drift (only when reviewing a fix-oriented branch)

For each original finding, mark ✅ / 🔄 / ❌. Then list any *new* issues introduced by the fixes
themselves.

| Original finding | Status | Notes |
|---|---|---|
| [finding] | ✅ fixed | [commit ref] |
| [finding] | 🔄 deferred | [why] |
| [finding] | ❌ unaddressed | [what was expected] |

**New issues introduced by fixes:**
- [fix location → new issue]

*Omit this subsection when not reviewing a remediation branch.*

---

### Dominant Failure Mode
[The single unifying problem, stated plainly. If there isn't one dominant failure mode, say so and
name the top two or three themes instead.]

### Highest-Leverage Intervention
[If you could only fix one thing, what is it? Be specific. Name the module, the pattern, the missing
test, the wrong dependency direction. This is the answer a senior engineer needs before they can
prioritize the remediation work.]

### Where the Voices Disagree
[Optional — include if two voices genuinely point in different directions. Example: "Beck would add
tests before touching anything; Feathers would agree, but notes there is no seam to test against
without first doing a small refactor — which creates a circular dependency in the remediation plan.
The resolution is to use Feathers's sprout technique to create a seam first, then add the
characterization test, then refactor safely."]

*If all activated voices agree on the core problem, omit this section.*

### Prioritized Remediation Order

| Priority | Action | Voice(s) | Effort | Risk if Deferred |
|---|---|---|---|---|
| 1 | [Action] | [Voice] | S/M/L | Low/Med/High/Critical |
| 2 | [Action] | [Voice] | S/M/L | Low/Med/High/Critical |
| 3 | [Action] | [Voice] | S/M/L | Low/Med/High/Critical |
| ... | | | | |

*Effort: S = hours, M = days, L = weeks or more*

---

## Caveats & Scope Limitations

[Anything important that was not visible in the review. E.g., "The deployment pipeline was not
visible in this review — Humble's section reflects what could be inferred from CI configuration
files only." Or "Database schema was not included; Kleppmann's findings are based on ORM usage
patterns in application code only."]

*If review had full visibility and no significant gaps, write: "None. Review had sufficient visibility
to support all findings above."*

---

*Review conducted using the Codebase Skeptic framework. Findings represent the application of
established software engineering authority to observed evidence, not personal preference.*
