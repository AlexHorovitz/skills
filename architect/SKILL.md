# Architect Skill

<!-- License: See /LICENSE -->

**Version:** 1.1.0

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
| **Input** | Feature brief → read from `ssd/features/<slug>/00-brief.md` (if present), otherwise the user's description |
| **Output** | `ssd/features/<slug>/01-architect.md` (with YAML frontmatter per `ssd/SKILL.md` §"Structured Output Requirements") + ADRs in `docs/decisions/` |
| **Consumed by** | `coder` (reads `01-architect.md` for implementation), `systems-designer` (reads `01-architect.md` for production readiness review) |
| **SSD Phase** | `/ssd start`, `/ssd feature` |

**Required output sections** (each section of the artifact maps to a Quality Gate item; an empty or
stub-only section fails the gate):

1. Current Scale Baseline (see Universal Principle 2)
2. Component Diagram
3. Data Model
4. API / Interface Contract
5. Integration Contract (see Universal Principle 6) — only when queues/events/retries are in scope
6. Decision Log (ADR references)
7. Risk Assessment
8. Feature Flag Plan — flag name, default state, rollout stages

**Required output frontmatter:**
```yaml
---
skill: architect
version: 1.1.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <feature-slug>
consumed_by: [coder, systems-designer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: true|not_applicable
  adrs: [ADR-NNNN, ...]
  risk_assessment: true
  feature_flag: <flag-name>|not_applicable
  scale_baseline: true
quality_gate_pass: true
---
```

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

### 6. Integration Has a First-Class Contract

If the design involves queues, events, webhooks, retries, or cross-service calls, produce the
integration contract as part of the spec — never as an afterthought. Address these concerns in the
design, not at review:

- **Idempotency.** Which operations can be safely retried? What is the idempotency key? What layer
  enforces uniqueness (app, DB constraint, message broker)?
- **Ordering.** Does the code assume messages arrive in order? What happens when they don't?
- **Schema evolution.** How are payloads versioned? What happens to in-flight messages during a rolling
  deploy?
- **Dead-letter handling.** Where do permanently-failed messages go? Who reads the DLQ? What's the SLA?
- **Synchronous vs async boundary.** If chosen synchronous, what's the acceptable tail latency and the
  timeout/retry policy? If async, what's the eventual-consistency window that callers must tolerate?

Produce these as a dedicated "Integration Contract" section in the output artifact.

### Current Scale Baseline (required deliverable)

Principle 2 ("Design for the next 10x") is meaningless without a 1x anchor. Every architect output must
declare the current-scale baseline in one short section:

- Current users / MAU / tenants
- Peak QPS (or requests/minute) on hot paths
- Database size and daily growth
- Deploy frequency
- Target 10x numbers derived from each of the above

The 10x target is mechanical from the baseline — no judgment, no rhetoric.

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

### Decisions that are ALWAYS ADRs

These eight decisions produce an ADR every time. If any one of them is implicit in your design, write
the ADR anyway — the absence of an ADR here is a design smell.

1. **Database choice** (including "which Postgres version / which managed service")
2. **Auth strategy** (session vs JWT, IdP choice, RBAC/ABAC, multi-tenant isolation)
3. **Sync vs async boundary** (queues, events, background jobs)
4. **Monolith vs services** (and if services: per-service vs shared data store)
5. **Deployment target** (platform, region, container runtime)
6. **Schema migration strategy** (two-phase, blue/green, migration framework)
7. **Third-party vs build** (every SaaS dependency with lock-in implications)
8. **Licensing** (open-source dependencies with copyleft, commercial dependencies with per-seat cost)

Everything else: write an ADR if a future engineer might ask "why did they do it this way?" If the
answer to that question is "read the code," you owe the ADR.

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

Each gate item maps to a required section in the output artifact. An empty or stub-only section
auto-fails the gate — `quality_gate_pass: false` in frontmatter and the skill cannot hand off.

| Gate item | Required section in `01-architect.md` |
|---|---|
| Platform guide applied | Component Diagram reflects the loaded platform guide |
| Major decisions are ADRs | Decision Log references ≥1 ADR per always-ADR topic in scope |
| Data model reviewed | Data Model (fields, FKs, indexes, soft-delete) |
| API/interface contract defined | API / Interface Contract |
| Auth/authorization specified | ADR + API Contract (auth headers, scopes) |
| Async/background work identified | Integration Contract (if queues/events are used) |
| Feature flag strategy defined | Feature Flag Plan (name, default, rollout stages) |
| CI/CD and deployment path sketched | Referenced in Risk Assessment and/or ADR |
| Top 3 risks identified with mitigations | Risk Assessment |
| Current Scale Baseline + 10x target | Current Scale Baseline |
| Walking Skeleton deployable today | Deployment path ADR + Risk Assessment note |

---

## Self-Verification (before emitting output)

Before writing the final artifact, answer these questions. If any answer is "no" or "I'm not sure,"
pause and address it.

1. For every deliverable listed in my Quality Gate, is a concrete section produced with real content,
   or am I just asserting it's done?
2. Did I adapt guidance to the project's actual stack, or copy-paste examples from the platform guide's
   defaults?
3. Did I read the relevant platform guide (and framework guide, if web) rather than pattern-matching?
4. For each always-ADR topic that applies in scope, does an ADR file exist in `docs/decisions/`?
5. Did I declare the Current Scale Baseline with actual numbers, or placeholder text?

---

## Changelog

- **1.1.0** (2026-04-18) — Declared prescribed output path and YAML frontmatter (A1); Quality Gate now
  maps each item to a required artifact section with auto-fail on empty (A2); added Universal Principle
  6 "Integration Has a First-Class Contract" (A3); enumerated the eight always-ADR decisions (A4); added
  Current Scale Baseline as a required deliverable (A5); added Self-Verification gate (O6).
- **1.0.0** — Initial release.

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
