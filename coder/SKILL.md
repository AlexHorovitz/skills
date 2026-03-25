## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Coder Skill

## Purpose

Translate designs, specifications, and requirements into clean, working code that follows team conventions and is ready for review. Language-agnostic by default; loads language-specific guidance automatically based on context.

## When to Use

- Implementing new features from specs or user stories
- Writing new modules, classes, or functions
- Converting pseudocode or designs into working code
- Building out endpoints, data models, services, or business logic

## Dependencies

- Requires: Design spec from `architect` skill (when available)
- Produces: Implementation code for `code-reviewer` skill

---

## Language Selection

When invoked, **detect the project language** from context (file extensions, imports, project files). Then load the corresponding language reference:

| Language | Reference File |
|---|---|
| Python / Django | `languages/python.md` |
| Swift | `languages/swift.md` |
| Rust | `languages/rust.md` |
| C | `languages/c.md` |
| C++ | `languages/cpp.md` |
| Go | `languages/golang.md` |
| Objective-C | `languages/objc.md` |

If the language is not in this list, apply the universal principles below and use community-standard conventions for that language.

If multiple languages are in use (e.g. Swift + C bridge, Go + C extension), load all relevant files and note where cross-language boundaries require extra care.

---

## Universal Principles

These apply regardless of language. Language files add specifics on top of them.

### 1. Readability Over Cleverness

Write code a tired developer at 2am can understand. No clever one-liners that require mental compilation.

- Name things for what they **do**, not what they **are**
- Prefer explicit steps over dense expressions
- Optimize for the reader, not the writer

### 2. Explicit Over Implicit

- Spell out intent: avoid abbreviations, single-letter variables (except trivial loop counters)
- Prefer clear names over comments that explain bad names
- Surface constraints and assumptions in the code itself, not just docs

### 3. Small Functions, Single Responsibility

- If a function does two things, write two functions
- If a docstring contains "and", consider a split
- Functions should fit on one screen without scrolling

### 4. Fail Loudly at Boundaries, Silently Never

- Validate at system boundaries: user input, external APIs, file I/O
- Use specific, descriptive error types — never swallow exceptions
- Log at decision points and errors; never use print/printf in production code

### 5. Leave the Codebase Better Than You Found It

- Consistent style with the surrounding file
- No commented-out code in final commits
- No hardcoded secrets, credentials, or environment-specific paths

---

## Universal Implementation Workflow

### Step 1: Understand the Requirement

Before writing a single line, answer:
- What is the input?
- What is the output?
- What are the error cases?
- What are the edge cases?
- What are the performance constraints?

### Step 2: Write the Interface First

Define the function/method signature and its contract (types, return values, exceptions/errors). Stub the body.

### Step 3: Implement the Happy Path

Get the primary flow working correctly before handling edge cases.

### Step 4: Add Error Handling

Handle each error case explicitly. Match the error handling idioms of the target language (see language file).

### Step 5: Add Logging

Log at entry/exit of significant operations and at every error path. Use structured logging where the language supports it.

### Step 6: Mark Uncertainties

Flag anything you're unsure about for the reviewer:

```
# REVIEW: Is this the correct behavior for nil/null input?
# REVIEW: Should we retry on network timeout here?
# TODO: Add rate limiting once volume is known
```

---

## Universal Quality Checklist

Before submitting for review:

- [ ] Function names describe what the function **does**
- [ ] No commented-out code
- [ ] No print/printf/NSLog debug output
- [ ] No hardcoded secrets, API keys, or credentials
- [ ] Errors are handled explicitly — no silent swallowing
- [ ] REVIEW/TODO comments explain uncertainties
- [ ] Tests exist for happy path and primary error cases
- [ ] New code is consistent in style with the surrounding file

See the language-specific file for additional checklist items.

---

## SSD Integration

This skill operates within the SSD workflow:

```
architect → systems-designer → [coder] → code-reviewer → deploy
```

**Feature flag requirement**: All incomplete or experimental work must be deployed behind a feature flag. Never commit work-in-progress directly to a live code path on main.

**Review gate**: Output from this skill goes to `code-reviewer`. BLOCKER or MAJOR findings return here before merge.
