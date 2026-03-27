<!-- License: See /LICENSE -->

# [Framework Name] — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses [Framework Name].

Covers [Framework Name] [version]+. [Note any legacy versions to avoid.]

---

## When to Choose [Framework Name]

**Choose it when:** [2-3 scenarios where this framework is the right fit]

**Do not choose it when:** [2-3 scenarios where another framework would be better]

---

## Project Structure

```
my-app/
├── [canonical directory structure for this framework]
```

[Explain any non-obvious conventions or decisions.]

---

## Routing

[How routes are defined, organized, and matched in this framework. Include code examples.]

---

## Data Layer

[ORM/database patterns, model definitions, query patterns, migrations. Include code examples.]

---

## Middleware

[How middleware/interceptors work, common middleware patterns, ordering.]

---

## Authentication

[Canonical auth patterns for this framework: session-based, JWT, OAuth, etc.]

---

## Template / View Patterns

[Component patterns, template engines, serialization — whatever the framework uses for rendering output. Adapt the section title to the framework's terminology.]

---

## API Patterns

[REST/GraphQL patterns, request/response handling, validation, error formatting.]

---

## Testing Strategy

[Testing framework, test organization, what to test at each layer, example test patterns.]

---

## Deployment (Walking Skeleton)

[Minimal steps to get a "Hello World" deployed to production on Day 1. This is critical for SSD — the Walking Skeleton must be deployable immediately.]

---

## [Framework]-Specific Quality Checklist

- [ ] [Framework-specific quality checks]
- [ ] [Performance gotchas unique to this framework]
- [ ] [Security considerations specific to this framework]
- [ ] [Common misconfigurations]

---

## Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| [Common failure] | [Root cause] | [Resolution] |
