# Architect Skill

## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

**Version:** 1.0.0

---

## Purpose

Design scalable, maintainable software architectures that follow established patterns, make the right trade-offs for the project's stage and constraints, and produce a deployable system from Day 1. Platform-aware: adapts to web, macOS, iOS, Android, and headless (API/backend) targets.

## When to Use

- Starting a new project or major feature
- Evaluating architectural decisions before implementation
- Designing data models and system boundaries
- Planning API structures and integration points
- Reviewing existing architecture for improvements

## Interface

| | |
|---|---|
| **Input** | Feature brief, project description, or architectural question |
| **Output** | Component diagram, data model, API contract, ADR (Architecture Decision Record), risk assessment |
| **Consumed by** | `coder` (uses spec for implementation), `systems-designer` (uses spec for production readiness review) |
| **SSD Phase** | `/ssd start`, `/ssd feature` |

---

## Step 1: Detect the Platform

Before applying any patterns, identify the target platform. Ask if not stated explicitly.

| Platform | Load this guide |
|---|---|
| Web application (browser-based UI + backend) | `architect/web/GUIDE.md` |
| macOS native application | `architect/macos/GUIDE.md` |
| iOS / iPadOS application | `architect/ios/GUIDE.md` |
| Android application | `architect/android/GUIDE.md` |
| Headless API, backend service, CLI tool | `architect/headless/GUIDE.md` |

For multi-platform projects (e.g., iOS + Android + API), apply the relevant guide for each layer and define the shared contract (API spec, shared data model) first.

For web applications, also identify the framework. The web guide contains a Framework Selection table that loads framework-specific guidance (Next.js, Django, FastAPI, Rails, Laravel, Angular, Vue/Nuxt, Spring Boot, ASP.NET Core).

---

## Universal Principles

These apply regardless of platform. The platform guides layer specifics on top.

### 1. Boring Technology Wins

Choose well-understood, battle-tested solutions over novel ones. Every "interesting" technology choice is a maintenance liability and an onboarding cost.

- Use the dominant tool in the platform's ecosystem
- Reach for a new tool only when you can articulate the specific pain the old tool causes
- "I haven't used it before" is not a reason to choose something new

### 2. Design for the Next 10x, Not 100x

Over-engineering kills more projects than under-engineering. Build for 10x your current scale. When you hit it, you'll have the resources to redesign. Premature abstraction is technical debt with no payoff date.

### 3. Boundaries Are Everything

The most consequential architectural decisions are where you draw boundaries:
- Between UI and business logic
- Between modules, layers, or services
- Between your code and third-party dependencies
- Between synchronous and asynchronous work

Draw boundaries at domain lines, not technical lines. A boundary around "payments" is useful. A boundary around "all database models" is not.

### 4. Data Owns the Architecture

Start with the data model. Get it right before writing a line of UI or API code. The schema is load-bearing — it's very expensive to change later. Everything else (APIs, views, services) is shaped by the data.

### 5. Production Parity from Day 1 (SSD)

The architecture must be deployable before any feature is complete. Plan CI/CD, secrets management, and environment configuration in the architecture phase — not after. "We'll figure out deployment later" is how you get 90% done and stuck.

---

## Architecture Decision Records (ADR)

Every significant decision should be recorded. Use this template:

```markdown
# ADR-NNN: [Decision title]

## Status
[Proposed | Accepted | Superseded by ADR-NNN]

## Context
What problem are we solving? What constraints exist?

## Decision
What we decided to do.

## Rationale
Why this choice beats the alternatives.

## Consequences
What becomes easier. What becomes harder. What we give up.

## Alternatives Rejected
What we considered and why we said no.
```

ADRs go in `docs/decisions/`. Number them sequentially. Never delete a superseded ADR — mark it superseded and link to its replacement.

---

## Standard Deliverables

Every architecture review produces these five artifacts. Scale depth to project complexity.

### 1. Component Diagram

Show the major components and how they communicate. ASCII is fine. Clarity beats prettiness.

```
┌──────────────┐     HTTPS      ┌──────────────┐
│   Client     │ ─────────────► │   API Layer  │
│  (platform)  │ ◄───────────── │              │
└──────────────┘                └──────┬───────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
             ┌─────────┐       ┌─────────────┐    ┌──────────┐
             │  DB     │       │    Cache    │    │  Queue   │
             └─────────┘       └─────────────┘    └──────────┘
```

### 2. Data Model

Key entities, their fields, and relationships. Identify:
- Primary keys and foreign keys
- Required vs optional fields
- Indexes needed for known query patterns
- Soft-delete strategy (if needed)

### 3. API / Interface Contract

For any boundary that crosses a process or network:
- Endpoints or method signatures
- Request/response shape
- Auth mechanism
- Error format
- Versioning strategy

### 4. Decision Log

The key trade-offs made, using ADR format. Minimum one ADR per major decision (database choice, auth strategy, sync vs async, monolith vs services).

### 5. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| [What could go wrong] | H/M/L | H/M/L | [How we handle it] |

Flag the top 3 risks explicitly. These become the first items in the systems-designer review.

---

## Quality Gate

Do not hand off to `/coder` until every item is checked:

- [ ] Platform guide has been read and applied
- [ ] All major decisions recorded as ADRs
- [ ] Data model reviewed — no obvious normalization problems, indexes planned
- [ ] API/interface contract defined at every component boundary
- [ ] Auth and authorization strategy specified
- [ ] Async/background work identified and queued appropriately
- [ ] Feature flag strategy defined for any multi-phase rollout
- [ ] CI/CD and deployment path sketched (even if rough)
- [ ] Top 3 risks identified with mitigations
- [ ] Design is deployable at minimal scope today (SSD: Walking Skeleton)

---

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| "We'll design the architecture after we build it" | No upfront design | Stop. Do this first. Even 2 hours of design saves 2 weeks of rework. |
| Circular dependencies between modules | Boundaries drawn on technical lines, not domain lines | Redraw at domain boundaries. Enforce with linting. |
| "Just one more abstraction layer" | Over-engineering for hypothetical scale | Remove layers. Add back when a concrete need appears. |
| Everything talks to everything | No explicit dependency rules | Define allowed dependency directions. Enforce them. |
| "We'll add auth/logging/error handling later" | Production concerns treated as afterthought | They're in scope from Day 1. Architecture must include them. |
| Rewrite every 18 months | Data model not designed for actual query patterns | Start with data. Validate against real queries before building. |
