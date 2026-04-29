# Changelog

All notable changes to the InsanelyGreat's SSD skills library are documented here.

Format: `[version] — date — description`

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
