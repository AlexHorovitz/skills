# Coder Skill

<!-- License: See /LICENSE -->

**Version:** 1.1.1

## Purpose

Translate designs, specifications, and requirements into clean, working code that follows team conventions and is ready for review. Language-agnostic by default; loads language-specific guidance automatically based on context.

## When to Use

- Implementing new features from specs or user stories
- Writing new modules, classes, or functions
- Converting pseudocode or designs into working code
- Building out endpoints, data models, services, or business logic

## Interface

| | |
|---|---|
| **Input** | `.ssd/features/<slug>/01-architect.md` (primary spec) + language context (auto-detected from repo). Feature flag name read from the architect spec's Feature Flag Plan section. |
| **Output** | `.ssd/features/<slug>/03-coder-status.md` (with frontmatter) + implementation commits with feature flags for incomplete work and `# REVIEW:` markers |
| **Consumed by** | `code-reviewer` (reads `03-coder-status.md` + the diff for detailed review) |
| **SSD Phase** | `/ssd feature` |

**Required output frontmatter (`03-coder-status.md`):**
```yaml
---
skill: coder
version: 1.1.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <feature-slug>
consumed_by: [code-reviewer]
files_touched: [<path>, ...]
tests_added: [<path>, ...]
review_markers: <count>      # number of # REVIEW: comments
test_results:
  command: "<actual-test-command>"
  exit_code: 0
  stdout_tail: "<last 20 lines>"
lint_results:
  command: "<actual-lint-command>"
  exit_code: 0
type_check_results:
  command: "<actual-typecheck-command>"
  exit_code: 0
feature_flag:
  name: <flag-name-from-architect-spec>
  default: off
spec_drift: false            # true if implementation diverged from architect spec
---
```

If `feature_flag.name` is missing from the architect spec AND the change is not pure infrastructure,
surface this as a blocker to the user and halt — SSD requires all new code behind a flag.

---

## Language Selection

When invoked, **detect the project language** from context (file extensions, imports, project files). Then load the corresponding language reference:

| Language | Reference File |
|---|---|
| Python | `languages/python.md` |
| TypeScript | `languages/typescript.md` |
| Swift | `languages/swift.md` |
| Ruby | `languages/ruby.md` |
| Java | `languages/java.md` |
| C# / .NET | `languages/csharp.md` |
| PHP | `languages/php.md` |
| Rust | `languages/rust.md` |
| Go | `languages/golang.md` |
| C | `languages/c.md` |
| C++ | `languages/cpp.md` |
| Objective-C | `languages/objc.md` |

If the language is not in this list, apply the universal principles below and use community-standard conventions for that language.

If multiple languages are in use (e.g. Swift + C bridge, Go + C extension), load all relevant files and note where cross-language boundaries require extra care.

If the project uses a web framework (Django, FastAPI, Next.js, Rails, Laravel, Angular, Vue/Nuxt, Spring Boot, ASP.NET Core), also load the corresponding framework architecture guide from `architect/web/frameworks/`. Language guides cover syntax and idioms; framework guides cover project structure and architectural patterns.

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

### Step 6.5: Check for Spec Drift

Did your implementation differ materially from the architect spec? (Different data shape, different
API signature, different boundary, different dependency.) If yes:

- Amend the relevant ADR in `docs/decisions/`, OR
- File an ADR supersession (new ADR marked as superseding the drifted one)

Record `spec_drift: true` in the coder-status frontmatter and explain the drift in the artifact body.
A spec-vs-impl mismatch that isn't recorded will be discovered later as a review finding or an
incident — catch it now.

### Step 7: Run Tests, Lint, Type Check

Do not mark the coder phase done until:

```bash
<test-command>     # e.g., `uv run pytest` / `npm test` / `go test ./...`
<lint-command>     # e.g., `ruff check` / `eslint .` / `golangci-lint run`
<typecheck-command>  # e.g., `mypy .` / `tsc --noEmit` / `go vet ./...`
```

All three must exit 0. Record exit codes + last 20 lines of output in the coder-status frontmatter. If
any step fails, fix or file a REVIEW marker — do not hand off a red build.

---

## Cross-Language Boundaries

Projects spanning multiple languages (Swift + C bridge, Python + Rust extension, TypeScript + WASM,
etc.) require extra care at the boundary:

- Load all relevant language reference files, not just the "primary" one.
- Match the ownership/lifetime rules at the boundary (who allocates, who frees; reference counting vs.
  copy semantics).
- Run each language's Quality Checklist independently — a bridge passes only when both sides pass.
- Document the bridge contract (function signatures, ABI, marshaling) in the architect spec's
  Integration Contract section.

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

---

## Self-Verification (before emitting `03-coder-status.md`)

1. Did I actually run the test / lint / type-check commands, or am I claiming they pass from memory?
2. Does every `# REVIEW:` marker in my diff appear in the `review_markers` count?
3. Did I read `01-architect.md` and compare my implementation to the spec for drift (Step 6.5)?
4. Is the feature flag name from the spec actually wired in the code AND the config?
5. If this is a multi-language change, did I run each language's Quality Checklist independently?

---

## Changelog

- **1.1.1** (2026-04-28) — Working-tree path references updated from `ssd/` to `.ssd/` per repo-wide convention change. See repo CHANGELOG [1.4.0]. No behavior change.

- **1.1.0** (2026-04-18) — Declared output artifact path `03-coder-status.md` and YAML frontmatter with
  test/lint/typecheck results (C1, C2); added Step 6.5 spec-drift check with ADR amendment prompt
  (C3); made the feature flag read from the architect spec and halt if absent (C4); added
  Cross-Language Boundaries section (C5); added Self-Verification gate (O6).
- **1.0.0** — Initial release.
