# Changelog

All notable changes to the InsanelyGreat's SSD skills library are documented here.

Format: `[version] — date — description`

---

## [1.9.0] — 2026-04-29

### Iteration 5 of the SSD skill-upgrades epic — bundled design pass (P1.4)

`architect` and `systems-designer` always run sequentially with the same inputs in the standard
`/ssd feature` flow. v1.9.0 lets them run as one logical step.

**New phase**: `/ssd design <slug>` (or `/ssd design <slug>#<iter>` for multi-iteration features):
1. Invokes `architect`; produces `01-architect.md`.
2. Reads the architect output, invokes `systems-designer`; produces `02-systems-designer.md`.
3. Surfaces gaps systems-designer rejected back to the user as one actionable block.

**Individual invocations remain valid.** `architect` and `systems-designer` are independently
invocable for ad-hoc design work, milestone redesigns, and external consumers (`codebase-skeptic`
reading just the architect spec). `/ssd design` is a convenience — it does not gate or change either
skill's contract.

**Skip `/ssd design` when systems-designer is N/A** (markdown-only repos, ADR-only PRs, skills
libraries). Invoke `architect` directly.

**Touched skills:**
- `ssd` — v1.6.0 → v1.7.0
- `architect` — v1.1.1 → v1.2.0 (changelog note only)
- `systems-designer` — v1.2.1 → v1.3.0 (changelog note only)

**Iteration sequence:** 5 of 9 done. Next: P1.3 (no-arg `/ssd` auto-detect).

---

## [1.8.0] — 2026-04-29

### Iteration 4 of the SSD skill-upgrades epic — deferred-findings ledger (P1.5)

Carry-over of non-blocking findings between iterations of a multi-iteration feature was previously
encoded as prose bullets in `current.yml` (`carried_to_pr_3c: [...]`). Iteration 4 makes it a
structured ledger with auto-load and auto-verify behavior.

**New artifact:** `.ssd/features/<slug>/iterations/<iter>/deferred.yml` (v1 schema):

```yaml
schema_version: 1
findings:
  - id: <severity>-<n>
    summary: <one-line>
    source: <relative-path-to-source-review>
    raised_in_iteration: <iter-id>
    target_iteration: <iter-id>|null
    status: open|closed|rolled-forward
    closed_in: <code-review-path>|null
```

**Auto-load on coder entry**: when entering coder phase for `<iter>`, the orchestrator pulls
entries with `target_iteration: <iter>` and `status: open` into the coder's input context as a
"Deferred from prior iterations" block. Coder either closes them in the diff or rolls them forward
with rationale.

**Auto-verify on review**: every multi-iteration review reads `deferred.yml` and checks each
entry's status against the diff. New frontmatter block `deferred_handled` with `closed`,
`rolled_forward`, and `silent_findings` (the last MUST be empty — silent findings are themselves a
MAJOR).

**Coder-status frontmatter additions**: `deferred.loaded` (count), `deferred.closed` (IDs),
`deferred.rolled_forward` (IDs).

**Single-cycle features** (no `iterations/` subdirectory) skip the ledger entirely — the schema
stays lean for the common case.

**Touched skills:**
- `coder` — v1.1.1 → v1.2.0
- `code-reviewer` — v1.3.0 → v1.4.0

**Iteration sequence:** 4 of 9 done. Next: P1.4 (bundled design pass).

---

## [1.7.0] — 2026-04-29

### Iteration 3 of the SSD skill-upgrades epic — multi-round gates (P1.2)

A `code-review` round that emits BLOCKER/MAJOR sends the workstream back to coder. The follow-up
review used to be tracked via filename suffixes (`04-code-review-round-2.md` was a manual
convention). It is now a structured concept the orchestrator auto-manages.

**Frontmatter additions to `code-reviewer` output:**
- `round: <int>` — 1 for first review, N for re-reviews. Auto-numbered by inspecting existing
  `code-review*` artifacts in the directory.
- `closed_from_previous_round: [<finding-id>, ...]` — list of finding IDs the reviewer verified
  closed since round N-1. Round 1 reviews use `[]`. Verification is per-claim against the code,
  not a copy from coder-status.

**Output paths by round + context:**
- Single-cycle feature, round 1: `.ssd/features/<slug>/04-code-review.md` (existing convention,
  unchanged).
- Single-cycle feature, round 2+: `.ssd/features/<slug>/04-code-review-round-N.md`.
- Multi-iteration feature: `.ssd/features/<slug>/iterations/<iter>/code-review/round-N.md`.
- Inline round-2 in the existing `04-code-review.md` remains valid for small remediations
  (1–3 closures) — pattern used by iteration 1 of this epic.

**`current.yml.active[].gate_rounds`** (field added in iter 1, populated from this iter): the
orchestrator increments it when a new round is written. Useful budget signal — `gate_rounds: 3`
suggests a contested design, scope cut, or rework.

**Touched skills:**
- `code-reviewer` — v1.2.1 → v1.3.0
- `ssd` — v1.5.0 → v1.6.0

**Iteration sequence:** 3 of 9 done. Next: P1.5 (deferred ledger), parallel-safe with this iter on
the iter-2 substrate.

---

## [1.6.0] — 2026-04-29

### Iteration 2 of the SSD skill-upgrades epic — first-class iterations (P1.1, ADR-0001)

A "feature" in SSD is no longer assumed to be a single design → build → review → deploy cycle.
Multi-iteration features (e.g., athena's `talentos-reimagined-phase3-ui` shipping as 3a / 3b / 3c)
now have a first-class home rather than the filename hack (`-3b`, `-round-2`) that observed usage
had been driving toward.

**Schema additions** (additive; back-compat with single-cycle features is total):
- `<slug>#<iter-id>` syntax accepted on every `/ssd` phase command.
- Opt-in `.ssd/features/<slug>/iterations/<iter-id>/` subtree per feature; epic-level docs
  (`00-brief.md`, `01-architect.md`, `02-systems-designer.md`) stay at the feature root and are
  shared across iterations.
- Per-iteration files: `brief.md`, `coder-status.md`, `code-review/round-N.md` (P1.2 in iter 3),
  `deferred.yml` (P1.5 in iter 4), `deploy.md`.
- `iteration` field in `current.yml` v2 (added in iter 1) is now actively populated.

**Resolution rules** documented in `ssd/SKILL.md` § "Iterations Inside a Feature":
1. Slug with `#`: operate on the iteration subtree; first reference promotes a flat-layout feature
   non-destructively (epic artifacts stay at the root).
2. Slug without `#` on a multi-iteration feature: orchestrator surfaces active iterations and asks.
3. Slug without `#` on a flat-layout feature: single-cycle path, unchanged.

**Touched skills:**
- `ssd` — v1.4.0 → v1.5.0
- `ssd-init` — v1.3.0 → v1.4.0 (documents that `iterations/` subdirs are created by the
  orchestrator on demand, not by init)

**New artifact:** `docs/decisions/ADR-0001-iterations-as-schema-substrate.md`.

**Iteration sequence:** 2 of 9 done. Next: P1.2 (multi-round gates), which builds on this
substrate.

---

## [1.5.0] — 2026-04-28

### Iteration 1 of the SSD skill-upgrades epic

First substantive iteration of the multi-iteration plan documented at
[.ssd/features/ssd-skill-upgrades/01-architect.md](.ssd/features/ssd-skill-upgrades/01-architect.md). Bundled
two engine-level upgrades that have no inter-dependency (P1.6 + P1.7).

**Executable gate rules (P1.6, ADR-0005):**
- New file `methodology/gate-rules.sh` — bash routine implementing four mechanical checks
  (`wip-commits`, `tests-pass`, `feature-flag-present`, `adr-delta`) with `PASS|FAIL|SKIP`
  structured stdout and `--json` mode for CI consumption.
- `ssd/SKILL.md` § "Methodology Enforcement" now invokes the script synchronously and refuses to
  pass the gate on any FAIL with the doctrine cite named.
- `methodology/SKILL.md` (v1.3.0) gains a "Gate Rules — Executable" section describing the script,
  the rule table, and direct-invocation usage for CI.
- Rationale: gate rules that aren't executable are decoration. ADR-0005 documents why bash is the
  right tool versus orchestrator-internal LLM checks (composability, reproducibility, testability,
  speed, fail-loud).

**`current.yml` v2 split + notes sidecar (P1.7, ADR-0002):**
- `.ssd/current.yml` is now schema-validated machine state; carries `schema_version: 2`.
- `.ssd/current.notes.yml` is the new free-form sidecar for handoff notes, scope changes, and
  questions for the next session.
- `ssd-init/SKILL.md` (v1.3.0) Step 7 split into "create both files fresh" and "v1 detected →
  prompted migration with `.bak`" paths. Migration is opt-in. Legacy v1 files continue to parse.
- v2 schema includes nullable `iteration`, `gate_rounds`, `rail_deviations` fields. Populated by
  later iterations (P1.1, P1.2, P2.A); present from v1.5.0 so the schema ships forward-compatible.

**Touched skills:**
- `ssd` — v1.3.0 → v1.4.0
- `methodology` — v1.2.1 → v1.3.0 → **v1.3.1** (round-2 fixes from iteration-1 code review)
- `ssd-init` — v1.2.0 → v1.3.0

**Round-2 fixes** (closed during iteration 1's code-review gate, before merge):
- MAJOR-1: `feature-flag-present` greps the added diff lines (`^+[^+]`) instead of file contents.
  A pre-existing flag marker elsewhere in a file no longer gives unflagged additions a free pass.
- MAJOR-2: both `feature-flag-present` and `adr-delta` build a quoted bash array of changed files
  instead of unquoted command substitution, closing a silent-SKIP on filenames with spaces or
  shell metacharacters.
- MINOR-1: `yaml_get` skips comment lines so `# test_command: pytest` is documentation, not a value.
- MINOR-2: `--base` argument parser rejects missing values and adjacent flags.
- Both MAJORs verified with synthetic git fixtures: file with pre-existing flag + unflagged
  addition → correct FAIL; spaced directory + ADR-less architectural change → correct FAIL.

**New artifacts:**
- `methodology/gate-rules.sh`
- `docs/decisions/ADR-0002-current-yml-split.md`
- `docs/decisions/ADR-0005-gate-execution-model.md`

**Iteration sequence:** This is iteration 1 of 9. Next: P1.1 (first-class iterations substrate). The
remaining iterations will land independently per the epic plan.

---

## [1.4.0] — 2026-04-28

### Working-tree convention: `ssd/` → `.ssd/`

The SSD working directory at the project root is renamed from visible `ssd/` to hidden `.ssd/`. All
path references in skill specs, gitignore guidance, and orchestrator logic are updated in lockstep.

**Why.** Two reasons: (1) in the SSD skills repo itself, a visible `ssd/` directory at the project
root collides with the orchestrator skill source directory, making `/ssd-init` impossible to run
cleanly inside this repo; (2) the working tree is transient state — review reports, design specs,
session-continuity pointers — not source code humans need to browse alongside the rest of the repo.
Hiding it keeps file-tree noise down while remaining fully accessible via `cd .ssd/`, IDE go-to-file,
and `ls -a`.

**Touched skills (path references updated; behavior unchanged):**
- `ssd` (orchestrator) → v1.3.0
- `ssd-init` → v1.2.0
- `architect`, `code-reviewer`, `codebase-skeptic`, `coder`, `methodology`, `refactor`,
  `software-standards`, `systems-designer` — Interface tables and inline path references updated;
  per-skill changelog entries added.

**Touched docs:**
- `README.md` — `Where to Start` and skill table use `.ssd/`.
- `CHANGELOG.md` — this entry; historical entries restored to their original `ssd/` wording (the
  convention they actually shipped under).
- `real-world-artifacts/ssd-upgrades-plan.md` — working-tree references updated; references to the
  orchestrator skill source (`~/.claude/skills/ssd/SKILL.md`) preserved.

`/ssd-init` invocations on existing projects with an `ssd/` working tree should: (a) stop, (b) `mv
ssd .ssd`, (c) re-run `/ssd-init` (idempotent — will detect existing state).

---

## [1.3.0] — 2026-04-18

### Post-v1.2-remediation skill improvements

Executed from `ai_working_directory/claude_skills_improvements/` plan (00-README + 01–04). The
remediation branch for work shipped successfully but fresh critic runs exposed gaps in the skills
themselves — missing operational failure-mode lenses, no loop closure, no structured hand-offs between
skills. This release addresses those gaps.

**New skill — ssd-init (v1.1.0):**
- First-run housekeeping for SSD projects. Creates `ssd/` (gitignored), `ssd/project.yml`,
  `ssd/current.yml`, `docs/decisions/`, `docs/runbooks/`, `docs/architecture/`, and runs SSD
  prerequisite checks (CI/CD, tests, flags, deployed hello-world). Idempotent — safe to re-run.
  Prerequisite to all `/ssd` phases. (Working tree later renamed to `.ssd/` in v1.4.0.)
- v1.1.0 aligns its artifact tree with the feature-centric / milestone-centric layout that every
  other sub-skill now declares: `ssd/features/<slug>/01-architect.md … 05-deploy.md` for features,
  `ssd/milestones/<YYYY-MM-DD-topic>/skeptic-before.md … verification.md` for milestones,
  `ssd/audits/<YYYY-MM-DD-scope>/` for audits. Replaces v1.0.0's per-skill subdirectory layout to
  eliminate the path mismatch that would have broken the chain.

**Orchestrator (ssd v1.2.0):**
- Declared the SSD artifact tree at `ssd/` (gitignored) + `docs/decisions/` (committed) (O1)
- Required YAML frontmatter on every primary output, with finding_counts / gate_pass / deliverables
  fields (O2)
- Added `/ssd verify` phase and mandatory before/after snapshot convention for milestones (O4, O5)
- Session continuity via `ssd/current.yml` (active workstreams, budget, last_touched) (O8)
- Methodology-backed gate enforcement table (O9)
- Skill-overlap priority table (coder vs python-django-coder, code-reviewer vs codebase-skeptic,
  codebase-skeptic vs software-standards) (O11)

**Review skills:**
- **codebase-skeptic (v1.2.0)**: mandatory Phase 2.5 Operational Failure Modes Sweep (C1);
  Forward-Looking Pass in Phase 4 (C4); Remediation Branch mode + self-verification in Operational
  Notes (C2, O6); reciprocal `/code-reviewer` hook table (C7); Incident-Story attestation for Beck,
  Domain-Modeling Stance for Evans, Deployment-Gate Hardening for Humble (C3, C5, C6).
- **code-reviewer (v1.2.0)**: Phase 1.5 Prior-Review Follow-up for remediation branches (R6); Phase 3.5
  Fix-Introduces-Edge-Cases (R2); 12 new Red Flags including LLM prompt injection, IntegrityError
  fetch mismatch, cache-without-race-test, release theatre (R3); Verify-Before-Escalating rule for
  sub-agent parallelization (R4); Severity Discipline (O7); Self-Verification (O6); LLM-specific
  examples, Edge Case Inventory template, Private-state mutation anti-pattern added to examples.md
  (R1, R5, R7).

**Build / design skills:**
- **architect (v1.1.0)**: output path + Quality Gate section mapping (A1, A2); Universal Principle 6
  "Integration Has a First-Class Contract" (A3); eight always-ADR decisions enumerated (A4); Current
  Scale Baseline required deliverable (A5).
- **systems-designer (v1.2.0)**: Phase 0 input validation against architect spec (S1); three-tier
  output with machine-check / human-review / block conditions (S2); new Concerns for AI/LLM
  Integration (S3), Compliance & Data Lifecycle (S4), Cost Observability (S5), Chaos / Failure
  Injection (S6).
- **coder (v1.1.0)**: output artifact `03-coder-status.md` with test/lint/typecheck results (C1, C2);
  Step 6.5 spec-drift check with ADR amendment prompt (C3); feature flag read from architect spec,
  halt if absent (C4); Cross-Language Boundaries section (C5).
- **refactor (v1.2.0)**: per-item finding citation requirement (R1); Step 4.5 Budget Check with
  halt-and-rollback options (R2); Step 5 Loop Closure with per-item re-check (R4); Step 6
  Systems-Designer Coordination trigger (R3).

**Audit / reference skills:**
- **software-standards (v1.1.0)**: two-mode support Comparative / Adversarial Single (ST1); 2–3
  evidence citations required per /10 score (ST2); explicit "When NOT to Use" delineation vs.
  codebase-skeptic (ST3); output path + frontmatter (ST4).
- **methodology (v1.2.0)**: clarified it provides machine-checkable rule source for `/ssd gate` (M1);
  added `/methodology score` self-adherence metric invocation (M2); audience-split expectation for
  adoption.md (M3); date-stamped comparisons with 12-month refresh prompt (M4).

**Cross-cutting:**
- Added "Skill Hygiene Contract" section to README.md (O10): file structure, interface discipline,
  header/license ordering, and future contract-test layer.
- Title-first header ordering enforced across all SKILL.md files (X6).
- License pointer already single-line since v1.2.0; Skill Hygiene Contract now requires it (X1).
- Per-skill `## Changelog` section required + added to all touched skills (X3).

---

## [1.2.0] — 2026-03-27

### Codebase review remediation

Eating own dogfood in real time. Executed findings from `codebase-skeptic` review (`documentation/skills/codebase-review-2026-03-27.md`). Voices activated: Fowler, Uncle Bob, Evans, Jobs, Wozniak.

- **ssd/SKILL.md** (v1.1.0) — replaced duplicated doctrine (shippable state invariant checklist, hard rules) with references to `methodology/core.md`; replaced inline ship checklist with directive to invoke `systems-designer`
- **code-reviewer/** (v1.1.0) — decomposed into orchestrator + `examples.md` sub-file; extracted all code examples (correctness, security, performance, maintainability, testing) and comment-writing examples into reference file; added language-adaptation note
- **refactor/** (v1.1.0) — decomposed into orchestrator + `patterns.md` sub-file; extracted scanning techniques and 6 refactoring patterns into reference file; added language-adaptation note
- **systems-designer/SKILL.md** (v1.1.0) — added language-adaptation note acknowledging Python-centric examples
- **methodology/SKILL.md** (v1.1.0) — version bumped to reflect prior decomposition (was still at 1.0.0)
- **All 37 files** — replaced 12-line per-file license blocks with one-line reference (`<!-- License: See /LICENSE -->`); ~500 tokens recovered per session
- **README** — updated contributing guide to reflect new license convention and framework template
- **architect/web/frameworks/TEMPLATE.md** — new file; structural template for framework guide contributions ensuring section parity across all guides
- **5 skills** — bumped version markers from 1.0.0 to 1.1.0 (ssd, code-reviewer, refactor, systems-designer, methodology)
- **.gitignore** — created; excludes `.DS_Store`

---

## [1.1.1] — 2026-03-27

- **README, CHANGELOG** — corrected brand name from "Insanely Great SSD" to "InsanelyGreat's SSD"

---

## [1.1.0] — 2026-03-27

### Structural improvements (this session)

- **LICENSE** — corrected to match shareware terms stated in all SKILL.md files (was accidentally set to The Unlicense)
- **README** — updated description to "free-for-personal-use"; added "Where to Start" section with canonical entry point (`/ssd`); added Skill Taxonomy table classifying skills as orchestrator / domain / review / reference
- **ssd/SKILL.md** — removed dead reference to local development file (`~/Development/Claude-Skills/ssd-meta-skill-proposal.md`)
- **methodology/** — decomposed 794-line monolith into focused sub-files:
  - `core.md` — Iron Law, Five Principles, Decision Framework, Metrics, Engineering Mindset (stable doctrine)
  - `patterns.md` — Five implementation patterns + Advanced topics (how-to layer)
  - `adoption.md` — Getting started, objections, org adoption, comparisons, resources (human onboarding material)
  - `SKILL.md` — slim orchestrator (~50 lines) that loads the right sub-file based on context
- **All SKILL.md files** — added standardized `## Interface` table (Input / Output / Consumed by / SSD Phase) to all 9 skills
- **All SKILL.md files** — added `**Version:** 1.0.0` marker to each skill header
- **CHANGELOG.md** — created this file

---

## [1.0.0] — 2026-03-25 / 2026-03-26

### Initial release

- `4b97b09` (2026-03-25) — Initial SSD skills: ssd, architect, coder, code-reviewer, systems-designer, refactor, methodology, software-standards, codebase-skeptic
- `f144156` (2026-03-25) — Updated license agreements across all files
- `8d9356b` (2026-03-26) — Made mobile, web, and desktop first-class citizens in SSD methodology; expanded platform coverage
- `abd9841` (2026-03-26) — Added 9 web framework guides (Next.js, Django, FastAPI, Rails, Laravel, Angular, Vue/Nuxt, Spring Boot, ASP.NET Core) and 5 language guides (C, C++, Go, PHP, Obj-C)

---

## Versioning Policy

Each SKILL.md carries its own version marker (`**Version:** x.y.z`). The library version in this changelog tracks the overall collection.

- **Patch** (x.y.**Z**): Corrections, typo fixes, updated code examples
- **Minor** (x.**Y**.z): New guides, new skills, new platform coverage, structural improvements that don't change skill behavior
- **Major** (**X**.y.z): Breaking changes to skill interface contracts or SSD doctrine
