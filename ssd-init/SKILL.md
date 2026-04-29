# SSD Init Skill

<!-- License: See /LICENSE -->

**Version:** 1.2.0

## Purpose

First-run housekeeping for a project adopting Shippable States Development. Sets up the `.ssd/` working directory, gitignore discipline, project-shape detection, and prerequisite checks so that subsequent `/ssd start` and `/ssd feature` invocations have a consistent, known-good foundation.

Run **once** at the beginning of a project's SSD adoption. Idempotent: safe to re-run against an already-initialized project; it will detect existing state and surface anything out of conformance rather than overwriting.

## When to Use

- First time invoking any `/ssd` command on a project
- When onboarding an existing codebase to SSD methodology
- When `.ssd/` directory has drifted from the expected structure
- When `/ssd` commands are failing with "no project configuration" errors

**When NOT to use:**
- Mid-feature — `ssd-init` is a prerequisite, not a workflow step. Use `/ssd feature` once init is complete.
- For proposal review (`proposal-reviewer`) or capitalization assessment (`software-capitalization`) — those skills are outside the SSD workflow and do not require init.

## Interface

| | |
|---|---|
| **Input** | Current working directory (assumed project root, or walked upward to find one); optional user clarifications for platform / distribution channel |
| **Output** | `.ssd/` directory with subtree; `.gitignore` entry; `.ssd/project.yml`; `.ssd/init-log.md` |
| **Consumed by** | `.ssd` (all phases), `architect`, `systems-designer`, `coder`, review skills — all read from and write to `.ssd/` |
| **SSD Phase** | Prerequisite to all phases. Typically called before `/ssd start`. |

---

## The `.ssd/` Convention

**Core rule (user-set):** All documentation and artifacts that Claude produces in service of an SSD project live under `.ssd/` at the project root. The directory is `.gitignore`d by default so that working plans, transient reviews, and intermediate artifacts do not pollute the repo's committed history.

```
<project-root>/
└── .ssd/                                # gitignored
    ├── README.md                       # explains this dir + conventions
    ├── project.yml                     # detected + declared project metadata
    ├── current.yml                     # active workstreams (see /ssd Session Continuity)
    ├── init-log.md                     # record of what ssd-init did and when
    ├── features/                       # per-feature artifact bundles (from /ssd feature)
    │   └── <feature-slug>/             # e.g., goal-approval-flow
    │       ├── 00-brief.md             # user's original brief
    │       ├── 01-architect.md         # architect spec
    │       ├── 02-systems-designer.md  # production readiness checklist
    │       ├── 03-coder-status.md      # coder output + test results
    │       ├── 04-code-review.md       # code-reviewer output
    │       └── 05-deploy.md            # deployment log
    ├── milestones/                     # per-milestone artifact bundles (from /ssd milestone)
    │   └── YYYY-MM-DD-<topic>/         # e.g., 2026-04-18-q2-consolidation
    │       ├── sha-before
    │       ├── metrics-before.yml
    │       ├── skeptic-before.md
    │       ├── refactor-plan.md
    │       ├── refactor-prs.md
    │       ├── skeptic-after.md
    │       └── verification.md
    ├── audits/                         # software-standards comparative audits
    │   └── YYYY-MM-DD-<scope>/
    │       └── standards-report.md
    └── archive/                        # completed workstreams (moved from features/ or milestones/)
        ├── features/<feature-slug>/
        └── milestones/<topic>/
```

**Feature-centric / milestone-centric layout.** Artifacts for a given feature or milestone are co-located, with a numbered file prefix (01-architect, 02-systems-designer, 03-coder-status, 04-code-review, 05-deploy) reflecting SSD's phase order. This matches what every sub-skill's Interface table declares.

Examples (all relative to the user's project root):
- `.ssd/features/goal-approval-flow/01-architect.md`
- `.ssd/features/goal-approval-flow/03-coder-status.md`
- `.ssd/milestones/2026-04-18-q2-consolidation/skeptic-before.md`
- `.ssd/milestones/2026-04-18-q2-consolidation/refactor-plan.md`
- `.ssd/audits/2026-04-18-vendor-selection/standards-report.md`

**ADRs and runbooks** live under `docs/decisions/` and `docs/runbooks/` at the project root — these are committed, not gitignored, because they are durable decision records rather than working artifacts.

**Why `.ssd/` (hidden) rather than `ssd/` (visible):** the working tree is transient state, not source code humans need to browse alongside the rest of the repo. Hiding it keeps `ls` output and IDE file trees clean while remaining navigable via `cd .ssd/`, IDE go-to-file, and `ls -a`. Gitignore keeps it out of commits. If a specific artifact (e.g., an ADR) needs to be committed, move it to `docs/decisions/` explicitly — the SSD skills will not do that automatically. Additionally, in the SSD skills repo itself, a visible `ssd/` directory at the project root would collide with the orchestrator skill source directory.

**Un-ignoring specific artifacts:** if a team decides to commit a subset (e.g., ADRs, milestone summaries), add an exception to `.gitignore`:

```
.ssd/
!.ssd/milestones/*/summary.md
```

`ssd-init` does not add exceptions by default.

---

## Workflow

Execute these steps in order. Each step is idempotent; if the work is already done, report it and continue.

### Step 1 — Locate Project Root

Walk up from the current working directory looking for one of:
- `.git/` (strongest signal)
- `pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`, `Gemfile`, `*.xcodeproj`, `*.csproj`
- `CLAUDE.md` at a directory boundary

If found, that directory is the project root. If not found, ask the user to confirm the intended project root. Do not silently assume CWD.

### Step 2 — Verify Git State

Run `git rev-parse --show-toplevel` to confirm a git repo. Outcomes:

- **Git repo, clean tree, on main/master:** proceed.
- **Git repo, dirty tree or feature branch:** warn but proceed. `ssd-init` creates new files; it does not modify committed code.
- **Not a git repo:** ask the user: (a) `git init` now, (b) proceed without git (skip `.gitignore` step), or (c) abort. Default: ask; do not `git init` without consent.

Record the result in the init log.

### Step 3 — Create `.ssd/` Directory Tree

Create the top-level bundle subdirectories. Individual feature / milestone / audit subfolders are created on-demand by the orchestrator when each flow starts.

```bash
mkdir -p .ssd/features .ssd/milestones .ssd/audits \
         .ssd/archive/features .ssd/archive/milestones
```

Also ensure the committed decision-record locations exist (these live outside `.ssd/` because they are tracked):

```bash
mkdir -p docs/decisions docs/runbooks docs/architecture
```

If `.ssd/` already exists:
- Verify each expected top-level subdirectory is present; create missing ones.
- Do NOT delete or move existing contents.
- Note in the init log which subdirs already existed.
- Existing feature / milestone folders are left untouched.

### Step 4 — Write `.ssd/README.md`

Write a short README explaining the convention:

```markdown
# SSD Working Directory

This directory holds artifacts produced by the Shippable States Development
(SSD) skills — architect specs, production-readiness checklists, code review
output, milestone reviews, refactor plans, and audit reports.

Contents are gitignored by default. To commit a specific artifact, either:

1. Move it to a committed location (`docs/decisions/` for ADRs, `docs/runbooks/`
   for runbooks), or
2. Add an exception to `.gitignore` (e.g., `!.ssd/milestones/*/summary.md`).

**Structure:**
- `project.yml` — detected project metadata (language, framework, platform)
- `current.yml` — active workstreams (features, milestones) in progress
- `features/<slug>/` — per-feature artifacts from `/ssd feature` (numbered 00–05)
- `milestones/YYYY-MM-DD-<topic>/` — milestone audit artifacts (skeptic-before, refactor-plan, skeptic-after, verification, …)
- `audits/YYYY-MM-DD-<scope>/` — software-standards comparative / adversarial audits
- `archive/features/` and `archive/milestones/` — completed workstreams

ADRs, runbooks, and architecture overviews live in `docs/decisions/`, `docs/runbooks/`, and
`docs/architecture/` — these are committed, not gitignored.

**Do not delete this directory manually.** It is the shared state between SSD
skill invocations. If you need to reset, use `ssd-init --reset` (after confirming
nothing important is lost).
```

Only write if the file does not exist. If it exists, leave it.

### Step 5 — Update `.gitignore`

Ensure `.ssd/` is in the project's `.gitignore`. Three cases:

1. **`.gitignore` exists and already contains `.ssd/` or `.ssd`:** no change.
2. **`.gitignore` exists and does not contain `.ssd/`:** append:
   ```
   
   # SSD working directory (see .ssd/README.md)
   .ssd/
   ```
3. **`.gitignore` does not exist:** create it with the above content.

Check for common variations before writing: `.ssd/`, `.ssd`, `/.ssd/`, `/.ssd`. Any of these counts as already ignored.

If the project is not a git repo (Step 2 outcome: no git, user declined init), skip this step and note in the log.

### Step 6 — Detect Project Shape

Inspect the repo and fill in `.ssd/project.yml`. Do not overwrite if the file exists; instead, read it and surface any drift to the user.

Detection heuristics:

**Language(s):**
- Python: `pyproject.toml`, `setup.py`, `requirements*.txt`, `*.py` density
- TypeScript/JavaScript: `package.json`, `tsconfig.json`, `*.ts` / `*.tsx` density
- Go: `go.mod`
- Rust: `Cargo.toml`
- Swift: `Package.swift`, `*.xcodeproj`
- Ruby: `Gemfile`
- Java/Kotlin: `pom.xml`, `build.gradle*`
- C#: `*.csproj`, `*.sln`

**Framework (if language is detected):**
- Python: Django (`manage.py` + `settings.py`), FastAPI (`fastapi` in deps), Flask
- TypeScript: Next.js (`next.config.*`), Nuxt, Angular (`angular.json`), Remix
- Ruby: Rails (`config/application.rb`)
- C#: ASP.NET Core (`Program.cs` with `WebApplication`)
- Swift: iOS / macOS (from xcodeproj target inspection)

**Platform target:** Ask the user if not obvious from framework detection:
- `web` — browser UI + backend
- `headless` — API / backend service / CLI
- `ios` — iOS / iPadOS app
- `android` — Android app
- `macos` — macOS desktop
- `multi` — explicitly spans multiple platforms (list each)

**Distribution channel:** Ask the user:
- Web: production URL (or "TBD")
- iOS/macOS: TestFlight / App Store / Mac App Store / direct DMG
- Android: Play Internal Testing / Play Store
- Headless: container registry / package registry URL

**Write to `.ssd/project.yml`:**

```yaml
# .ssd/project.yml — detected + declared project metadata
# Updated by ssd-init on YYYY-MM-DD. Edit to correct.

project:
  name: <detected-or-asked>
  slug: <kebab-case-name>
  root: <absolute-path-at-init-time>

stack:
  language: <primary>            # python | typescript | go | ...
  languages:                     # all detected languages
    - <lang>
  framework: <detected-or-none>
  platform: <web|headless|ios|android|macos|multi>

distribution:
  channel: <url-or-tbd>
  cadence: <daily|weekly|biweekly|unknown>

ssd:
  version: 1.0.0                 # ssd-init version that wrote this
  initialized_at: <ISO-8601>
  artifact_root: .ssd/            # relative to project root

integrations:                    # optional; filled in as features are added
  - type: jira
    enabled: false
  - type: github
    enabled: true                # inferred from .git remote
```

### Step 7 — Initialize `.ssd/current.yml`

Create the workstream pointer file if missing:

```yaml
# .ssd/current.yml — active SSD workstreams
# Managed by the /ssd orchestrator. Do not edit manually unless you know
# what you're doing.

active: []
archived: []
```

If it exists, leave it. Existing entries are the orchestrator's business, not init's.

### Step 8 — Check for `CLAUDE.md`

If the project root has a `CLAUDE.md`, read it and record that it exists. Surface to the user if it does not mention the SSD convention — they may want to add a pointer.

If there is no `CLAUDE.md`, offer to create a minimal one:

```markdown
# <Project Name>

## SSD Convention

This project uses Shippable States Development. SSD working artifacts live in
`.ssd/` (gitignored). Primary SSD commands:

- `/ssd start` — Walking Skeleton for new features
- `/ssd feature` — daily feature loop (architect → systems-designer → coder → review)
- `/ssd gate` — shippable-state check
- `/ssd milestone` — post-sprint audit

See `.ssd/README.md` for the artifact tree.

## Stack

<auto-filled from ssd/project.yml>

## Test / Lint / Build

<detected commands — fill in manually>

## Deployment

<distribution channel — fill in manually>
```

Do not overwrite an existing `CLAUDE.md`. If the user wants to merge, that's a separate action.

### Step 9 — Prerequisite Checks

Report the status of SSD prerequisites. These are not blockers for `ssd-init` — they are blockers for `/ssd start` — but the user should see them immediately.

| Prerequisite | Check | Severity if missing |
|---|---|---|
| CI/CD pipeline | `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`, `Jenkinsfile`, `buildkite.yml`, etc. | BLOCKER for `/ssd start` |
| Test harness | `pytest`, `jest`, `go test`, `cargo test`, XCTest, etc. | BLOCKER for `/ssd start` |
| Linter / formatter | `ruff`, `eslint`, `black`, `gofmt`, SwiftLint, etc. | MAJOR |
| Pre-commit hooks | `.pre-commit-config.yaml` or equivalent | MINOR |
| Feature flag system | `feature_flags`/`unleash`/`launchdarkly`/`growthbook` in deps, or config file | BLOCKER for `/ssd feature` (new features should be flag-gated) |
| Deployed "Hello World" | Distribution channel has a working deploy | BLOCKER for SSD methodology compliance |
| Secrets management | `.env.example`, vault config, key-vault reference | MAJOR |
| README with setup steps | `README.md` at root with install/run instructions | MAJOR |

Report as a table in the init log. Do not attempt to fix — that's `/ssd start`'s job.

### Step 10 — Write `.ssd/init-log.md`

Record what was done and what was found. This is the primary output artifact of `ssd-init`.

```markdown
---
skill: ssd-init
version: 1.0.0
produced_at: <ISO-8601>
project: <name>
---

# SSD Init Log

## Project Root
`<absolute-path>`

## Git State
- Repo: <yes|no|initialized-just-now>
- Branch: <branch-name-or-na>
- Clean tree: <yes|no>

## Directory Setup
- `.ssd/` — <created|already-existed>
- `.ssd/features/` — <created|already-existed>
- `.ssd/milestones/` — <created|already-existed>
- `.ssd/audits/` — <created|already-existed>
- `.ssd/archive/features/` — <created|already-existed>
- `.ssd/archive/milestones/` — <created|already-existed>
- `docs/decisions/` — <created|already-existed>
- `docs/runbooks/` — <created|already-existed>
- `docs/architecture/` — <created|already-existed>
- `.ssd/README.md` — <created|already-existed>
- `.ssd/project.yml` — <created|already-existed>
- `.ssd/current.yml` — <created|already-existed>

## Gitignore
- `.gitignore` — <created|already-existed|not-applicable-no-git>
- `.ssd/` entry — <added|already-present|skipped-no-git>

## Project Shape (see .ssd/project.yml for machine-readable form)
- Language: <...>
- Framework: <...>
- Platform: <...>
- Distribution channel: <...>

## CLAUDE.md
- Status: <existed|created-minimal|user-declined>
- SSD convention mentioned: <yes|no>

## Prerequisite Checks
| Prerequisite | Status | Severity |
|---|---|---|
| CI/CD | <present|missing> | <...> |
| ... | ... | ... |

## Recommended Next Step
<One of:>
- `/ssd start` — this is a greenfield project; set up the Walking Skeleton.
- `/ssd feature` — this is an existing project with the prerequisites in place.
- Address prerequisites first — <list blockers>.
```

### Step 11 — Recommend Next Step

Based on the prerequisite check results and project state:

- **All prerequisites present, no existing features:** recommend `/ssd start` to set up the Walking Skeleton.
- **All prerequisites present, existing codebase:** recommend `/ssd feature <name>` for the next piece of work.
- **BLOCKER-severity prerequisites missing:** list them, explain each is a blocker, recommend addressing in order (CI/CD first, then tests, then flags).
- **MAJOR-severity prerequisites missing:** note them but allow `/ssd` to proceed. The first `/ssd start` or `/ssd feature` will need to handle them.

---

## Idempotency Rules

`ssd-init` is safe to run repeatedly. Its contract:

1. **Never overwrites existing files.** If `.ssd/project.yml` exists, it is read, not replaced. The user must delete or edit it manually to change detected values.
2. **Never deletes existing files or directories.** No `rm`, no `mv`, no destructive ops.
3. **Idempotent edits to `.gitignore`.** Check before appending; multiple runs produce identical output.
4. **Appends to `.ssd/init-log.md` on re-run.** Each run adds a new section with its timestamp; does not replace prior entries.

If the project state genuinely needs to be reset, the user invokes `ssd-init --reset` (interactive, requires explicit confirmation on each deletion).

---

## Failure Modes

| Symptom | Cause | Resolution |
|---|---|---|
| `ssd-init` can't locate project root | CWD is outside any detectable project | Ask user to `cd` into the project or specify root explicitly |
| `.gitignore` cannot be written | Filesystem permission error | Report to user; do not attempt workarounds |
| `.ssd/project.yml` exists but is malformed YAML | Manual edit broke it | Ask user to fix; do not attempt auto-repair |
| Multiple language stacks detected, no primary | Polyglot repo | Ask user to declare primary language for SSD purposes |
| Git repo but no remote | Local-only repo | Proceed; note in log. Distribution channel prompt will handle "TBD" |
| `CLAUDE.md` exists with conflicting conventions | Team already uses a different artifact convention | Surface to user; do not overwrite. They must reconcile manually. |

---

## Integration with `/ssd` Commands

`ssd-init` is the **prerequisite** for all `/ssd` commands. The `/ssd` orchestrator should check for `.ssd/project.yml` on invocation:

- **Missing:** prompt the user to run `ssd-init` first. Do not auto-run it (gives the user control).
- **Present:** read it for project metadata and proceed with the requested phase.

Sub-skills (`architect`, `systems-designer`, `coder`, `code-reviewer`, `codebase-skeptic`, `refactor`) should read `.ssd/project.yml` to adapt their output to the project's stack and platform. They should write their outputs to the paths prescribed in `03-ssd-orchestration-improvements.md` (within `.ssd/`).

---

## Quality Checklist

Before declaring `ssd-init` complete:

- [ ] Project root located and confirmed
- [ ] `.ssd/` directory exists with all required subdirectories
- [ ] `.ssd/README.md` present
- [ ] `.ssd/project.yml` present and accurately reflects detected shape
- [ ] `.ssd/current.yml` present (may be empty)
- [ ] `.gitignore` contains `.ssd/` (if git repo)
- [ ] `.ssd/init-log.md` written with complete status
- [ ] Prerequisite checks run and recorded
- [ ] Next-step recommendation delivered to user
- [ ] No existing file was overwritten
- [ ] If `CLAUDE.md` did not exist, either created or user explicitly declined

---

## Interactions with Other Skills

Each sub-skill's `## Interface` table declares the exact input and output paths it uses. Feature work is grouped under `.ssd/features/<slug>/` with numbered files; milestone work is grouped under `.ssd/milestones/<YYYY-MM-DD-topic>/` by artifact name; audits live under `.ssd/audits/<YYYY-MM-DD-scope>/`.

**Feature flow (`/ssd feature`):**
- `architect` → `.ssd/features/<slug>/01-architect.md`
- `systems-designer` → `.ssd/features/<slug>/02-systems-designer.md`
- `coder` → `.ssd/features/<slug>/03-coder-status.md`
- `code-reviewer` → `.ssd/features/<slug>/04-code-review.md`
- deploy log → `.ssd/features/<slug>/05-deploy.md`

**Milestone flow (`/ssd milestone` → `/ssd verify`):**
- `codebase-skeptic` → `.ssd/milestones/<topic>/skeptic-before.md` then `skeptic-after.md`
- `refactor` → `.ssd/milestones/<topic>/refactor-plan.md`
- Each refactor PR's `code-reviewer` output → `.ssd/milestones/<topic>/review-<pr>.md`; rollup in `refactor-prs.md`
- `/ssd verify` → `.ssd/milestones/<topic>/verification.md`

**Audit flow (`/ssd audit`):**
- `software-standards` → `.ssd/audits/<YYYY-MM-DD-scope>/standards-report.md`

**Reference:**
- `methodology` → reads `.ssd/project.yml` for adherence scoring; on demand writes `.ssd/methodology-score-YYYY-MM-DD.md`.

**Durable decision records (committed, not in `.ssd/`):**
- ADRs → `docs/decisions/`
- Runbooks → `docs/runbooks/`
- Architecture overviews → `docs/architecture/`

Running `ls .ssd/features/<slug>/` reveals the full phase chain for a feature in order (00 → 05). Running `ls .ssd/milestones/<topic>/` reveals the before → plan → reviews → after → verification chain for a milestone.

---

## Changelog

- **1.2.0** (2026-04-28) — Switched the SSD working tree from visible `ssd/` to hidden `.ssd/`.
  Reasons: (1) `ssd/` collides with the orchestrator skill source directory at the project root in
  the SSD skills repo itself, and (2) the working tree is transient state, not something humans need
  to browse alongside source files. Hidden directory keeps the file tree clean while remaining
  navigable via `cd .ssd/`, IDE go-to-file, and `ls -a`. All path references and `.gitignore` rules
  in this skill now use `.ssd/`. Sub-skills' Interface tables updated in lockstep.
- **1.1.0** (2026-04-18) — Aligned artifact tree with the rest of the SSD skill chain: top-level
  directories are now `ssd/features/`, `ssd/milestones/`, `ssd/audits/` (feature-centric and
  milestone-centric layout) instead of per-skill subdirectories. Each feature bundle uses numbered
  file prefixes (01-architect.md … 05-deploy.md) matching what every sub-skill's Interface table now
  declares. Added `docs/decisions/`, `docs/runbooks/`, `docs/architecture/` to the created-on-init
  list so ADRs and runbooks have a known committed home. Updated file header to use the repo's
  single-line license pointer convention and title-first ordering.
- **1.0.0** (2026-04-18) — Initial implementation of first-run housekeeping workflow. Creates `ssd/`
  directory tree, gitignores it, detects project shape, writes metadata, runs prerequisite checks.
  Based on conventions proposed in
  `ai_working_directory/claude_skills_improvements/03-ssd-orchestration-improvements.md` (O1, O3, O8).
  The earlier improvements proposal used `.ssd/` (hidden); this skill adopted the user's choice of
  `ssd/` (visible + gitignored). Reversed in v1.2.0.
