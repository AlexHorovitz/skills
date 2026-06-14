# InsanelyGreat's SSD — Claude Code Skills

[![CI](https://github.com/AlexHorovitz/skills/actions/workflows/quality.yml/badge.svg)](https://github.com/AlexHorovitz/skills/actions/workflows/quality.yml)
[![Methodology: InsanelyGreat SSD](https://img.shields.io/badge/Methodology-InsanelyGreat%20SSD-0a84ff?style=flat-square)](https://insanelygreat.com/ssd.html)
[![Manifesto: Agile²](https://img.shields.io/badge/Manifesto-Agile%C2%B2-1d1d1f?style=flat-square)](https://insanelygreat.com/agile2.html)
[![Free for personal use](https://img.shields.io/badge/License-Free%20for%20personal%20use-30d158?style=flat-square)](LICENSE)

**Library version:** see [`VERSION`](VERSION) · changelog in [`CHANGELOG.md`](CHANGELOG.md)

A free-for-personal-use skill set for [Claude Code](https://claude.ai/code) that implements **Shippable States Development (SSD)** — a pragmatic engineering discipline for solo developers and small teams, originated by [Alex Horovitz](https://insanelygreat.com/about.html) and published at [insanelygreat.com](https://insanelygreat.com). Platform-adaptive: web, iOS, Android, macOS, and headless.

**Core invariant:** If you can't ship it right now, you don't have a product — you have a construction site.

**Dogfood.** As of v1.19.0 (per [ADR-0008](docs/decisions/ADR-0008-ssd-commit-split.md)) this repo tracks its own SSD artifacts under [`.ssd/features/`](.ssd/features/) — briefs, architect specs, coder-status reports, and code-reviews for every epic shipped in v1.5.0+. Read the history of how the methodology was built using the methodology itself. The epics so far:

- [`ssd-skill-upgrades`](.ssd/features/ssd-skill-upgrades/01-architect.md) — 9-iteration epic implementing v1.5–v1.14 (5 ADRs: iterations, `current.yml` split, rails, profiles, gate execution).
- [`parallel-features`](.ssd/features/parallel-features/01-architect.md) — concurrent feature workstreams (3 iterations, v1.15–v1.17; [ADR-0007](docs/decisions/ADR-0007-parallel-features.md)).
- [`ssd-commit-split`](.ssd/features/ssd-commit-split/01-architect.md) — the selective-commit convention that makes this very list visible (2 iterations, v1.18–v1.19; [ADR-0008](docs/decisions/ADR-0008-ssd-commit-split.md)).
- [`ssd-profile-audit`](.ssd/features/ssd-profile-audit/01-architect.md) — made the sub-skills profile-aware on *substance* not tone (v1.20; [ADR-0010](docs/decisions/ADR-0010-profile-aware-subskills.md)). *Later removed wholesale by SSD 2.0 — see below; the dogfood record keeps the reversal honest.*
- [`ssd-upgrade`](.ssd/features/ssd-upgrade/01-architect.md) — `/ssd upgrade`: detect SSD convention drift and migrate a project forward idempotently (4 iterations, v1.21–v1.24; [ADR-0013](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)).
- [`ssd-skill-chapter-split`](.ssd/features/ssd-skill-chapter-split/00-brief.md) — split the `ssd/SKILL.md` monolith into a thin spine + on-demand chapters (v1.25; the [ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) 2.0 prerequisite P1).
- [`ssd-2.0-cuts`](.ssd/features/ssd-2.0-cuts/01-architect.md) — **SSD 2.0**, the subtractive milestone ([ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md), greenlit via [`ssd-2.0-greenlight`](.ssd/features/ssd-2.0-greenlight/00-brief.md)). Three iterations: (A) remove the `developer_profile`/`teaching_mode` concept library-wide — BREAKING, v2.0.0; (B) collapse to **one surface, progressively disclosed** — v2.1.0; (C) the `/ssd upgrade` deprecation path via the `obsoleted_in` manifest field — v2.2.0.

## Methodology

This repository is the official Claude Code skill implementation of **Shippable States Development**. The canonical methodology pages are:

- 📘 [Shippable States Development (SSD)](https://insanelygreat.com/ssd.html) — the methodology in full
- 📗 [The InsanelyGreat Guide](https://insanelygreat.com/guide.html) — practical implementation
- 📙 [Agile²](https://insanelygreat.com/agile2.html) — companion manifesto on process-as-tool
- 📕 [Solo Developer's Engineering Manifesto](https://insanelygreat.com/solo-developer-manifesto.html)
- 📒 [The Ratchet Principle: Code Quality Without a QA Team](https://insanelygreat.com/ratchet-principle.html)

If this skill set has helped you ship better software, a star on this repo and a link back to [insanelygreat.com](https://insanelygreat.com) keeps the methodology discoverable.

Verify your installed version matches the guide at [insanelygreat.com/guide.html](https://insanelygreat.com/guide.html):

```bash
cat ~/.claude/skills/VERSION
```

---

## What Is SSD?

InsanelyGreat's SSD keeps software in a deployable, production-ready state at all times. It synthesizes continuous deployment, trunk-based development, and feature flags into a workflow a single developer can actually maintain — amplified by Claude Code at every step.

Five principles:
1. **Constant Production Parity** — Deploy "Hello World" on Day 1. Deployment is never "the hard part."
2. **The Shippable State Invariant** — Every session ends with passing tests and nothing broken.
3. **Feature Flags Over Feature Branches** — All work on main, behind flags, off by default.
4. **The Ratchet Principle** — Forward progress only. No WIP commits, no "fix tomorrow."
5. **Scope Flexibility Is a Feature** — Cutting scope is engineering judgment, not failure.

---

## Where to Start

**Step 1: `/ssd-init` once per project.** First-run housekeeping — creates the `.ssd/` working
directory (gitignored), writes `.ssd/project.yml` with your stack/framework/platform, creates
`docs/decisions/` + `docs/runbooks/` + `docs/architecture/`, and runs SSD prerequisite checks
(CI/CD, test harness, feature-flag system, deployed hello-world). Idempotent — safe to re-run.
`/ssd` phases refuse to proceed until init has run.

**Step 2: `/ssd` every session.** Since v2.1, SSD has **one surface, progressively disclosed**
([ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) Pillar 3). The everyday path is the bare
command — it reads your project state and proposes the next action, naming the explicit step it takes
so you never have to memorize the verb set.

```
/ssd-init   ← first time only (prerequisite to all /ssd phases)
/ssd        ← auto-detect state and propose the next action (the path you use)
/ssd start  ← bootstrap a new project (Walking Skeleton) when there's no state to detect yet
```

The full verb set (`feature`, `design`, `gate`, `milestone`, `verify`, `ship`, `audit`, `upgrade`)
stays a first-class escape hatch — every phase is still directly invokable. The command path is a
**thin alias** that lowers into the conversational path, not a co-equal surface. See
[The Meta-Skill](#ssd--the-meta-skill) below for the full set.

### Skill Taxonomy

| Type | Skills | When you invoke directly |
|---|---|---|
| Bootstrap | `ssd-init` | Once, at project start (or when `.ssd/` has drifted) |
| Orchestrator | `.ssd` | Always — start here after init |
| Domain | `architect`, `coder`, `systems-designer`, `refactor` | When working outside the SSD workflow |
| Review | `code-reviewer`, `codebase-skeptic`, `software-standards` | On-demand or via SSD |
| Reference | `methodology` | When you want to understand SSD doctrine |

---

## Skills

### `/ssd-init` — Project Bootstrap

Run once per project (idempotent; safe to re-run). Creates `.ssd/` (gitignored working directory),
`.ssd/project.yml` (detected stack/framework/platform), `.ssd/current.yml` (active workstreams),
`docs/decisions/` / `docs/runbooks/` / `docs/architecture/` (committed decision records), and reports
SSD prerequisite status (CI/CD, tests, flags, deploy).

### `/ssd` — The Meta-Skill

The orchestrator. Sequences the right sub-skills for each development phase. Requires `ssd-init` to
have run. The bare `/ssd` auto-detects state and proposes the next action; the explicit verbs below
are the escape hatch when you want to force a specific phase.

```
/ssd            — Auto-detect state and propose the next action (the everyday path)
/ssd start      — New project or major feature: Walking Skeleton setup
/ssd feature    — Active development: design → build → review → deploy loop
/ssd design     — Bundled architect + systems-designer pass (single invocation)
/ssd milestone  — Post-sprint consolidation: deep audit + targeted refactor
/ssd verify     — Remediation verification (mandatory after milestone refactors)
/ssd gate       — Shippable state check only (code-reviewer + methodology rules)
/ssd ship       — Deploy readiness check only (systems-designer checklist)
/ssd audit      — Adversarial comparative review (nuclear option)
/ssd upgrade    — (v1.21+) report/migrate SSD convention drift (--apply · --adopt)
```

**Parallel workstreams** (v1.16+, [ADR-0007](docs/decisions/ADR-0007-parallel-features.md)) — manage
more than one feature at once:

```
/ssd feature new <slug>   — scaffold a new workstream: branch + (optional) worktree + brief + state entry
/ssd switch <slug>        — pause the current workstream (capture a handoff note), resume the target
/ssd worktree <slug> …    — explicit git-worktree lifecycle (add | remove) for a workstream
```

### Sub-Skills

| Skill | Role |
|---|---|
| `/ssd-init` | First-run housekeeping: creates `.ssd/` tree, writes `project.yml`, runs prerequisite checks (prerequisite to all `/ssd` phases) |
| `/architect` | Design: models, services, API contracts. Platform-adaptive (web, iOS, Android, macOS, headless) |
| `/systems-designer` | Production readiness: reliability, observability, deployment safety |
| `/coder` | Implementation from spec (Python, TypeScript, Swift, Ruby, Java, C#, PHP, Go, Rust, C/C++, Obj-C) |
| `/code-reviewer` | PR gate: BLOCKER/MAJOR findings block merge |
| `/codebase-skeptic` | Deep architectural critique through 10 expert lenses |
| `/software-standards` | Adversarial comparative audit |
| `/refactor` | Post-ship targeted improvement |
| `/methodology` | SSD methodology reference + `/methodology score` self-adherence metric |

---

## Installation

Clone the repo into your Claude Code skills directory:

```bash
git clone https://github.com/AlexHorovitz/skills ~/.claude/skills
```

Then, from your project root, run the bootstrap once:

```
/ssd-init
```

After that, invoke any SSD phase:

```
/ssd feature
/ssd milestone
/ssd gate
```

Or call a sub-skill directly when working outside the SSD workflow:

```
/coder
/code-reviewer
/codebase-skeptic
```

---

## Hard Rules

1. **No merge without a clean `/ssd gate`** — No BLOCKER or MAJOR findings. No exceptions.
2. **No incomplete work on main without a feature flag** — WIP commits on main are banned.
3. **Tests must pass before and after every change** — "I'll fix the tests tomorrow" is not a shippable state.
4. **Refactor only after shipping** — Separate PRs, never mixed with feature work.
5. **Deploy beats perfection** — Reduce scope rather than delay a deploy.
6. **Production parity from day one** — If you haven't deployed to production yet, that is your next task.

---

## Contributing

Contributions are welcome. All content in this repo is Markdown — there is no code to compile or test suite to run. The bar for a good contribution is whether Claude follows the guidance accurately and produces better outcomes than it would without it.

### What to contribute

- **Fixes** — Incorrect advice, outdated API references, broken examples, typos
- **Additions** — Missing patterns, platforms, or frameworks that belong in an existing guide
- **New platform guides** — A new `architect/` subdirectory for a platform not yet covered (e.g., `watchOS`, `tvOS`, `embedded`, `visionOS`)
- **New framework guides** — A new `architect/web/frameworks/` file for a web framework not yet covered (e.g., `sveltekit`, `remix`, `nestjs`). Copy `architect/web/frameworks/TEMPLATE.md` and fill in each section to ensure structural parity with existing guides
- **New skills** — A complete `SKILL.md` for a workflow not yet covered

### What not to contribute

- Promotional content, vendor recommendations without technical rationale
- Vague or aspirational guidance ("always write clean code") without actionable specifics
- Anything that contradicts the SSD core invariant (shippable state at all times)

### How to submit

1. Fork the repo
2. Make your changes on a branch
3. Open a pull request with a clear description of what changed and why

### Writing style

These files are read by Claude, not rendered as a website. Write for clarity and precision over prose elegance.

- **Be specific.** "Use PostgreSQL" is better than "use a relational database."
- **Give the rule, then the rationale.** State the decision first, explain why second.
- **Include the counter-case.** Every "always do X" is more useful when paired with "except when Y."
- **Concrete examples over abstractions.** A short code block or table beats three paragraphs.
- **Match the existing tone.** Direct, opinionated, no hedging.

### File structure conventions

Each skill or guide follows this pattern:

```
skill-name/
└── SKILL.md          — the skill itself (invoked by /skill-name in Claude Code)

architect/
└── platform/
    └── GUIDE.md      — platform-specific reference, loaded by the architect skill
```

`SKILL.md` and `GUIDE.md` files begin with a one-line license reference: `<!-- License: See /LICENSE -->`. The full license terms live in the `LICENSE` file at the repository root.

---

## Skill Hygiene Contract

Every skill in this directory MUST conform to these conventions. Skills that violate them are flagged
by the skill linter (when present) and block `/ssd start` in strict mode.

**File structure:**
- `SKILL.md` begins with `# Skill Name` as the first line. The license pointer (`<!-- License: See /LICENSE -->`)
  and `**Version:** X.Y.Z` follow the title, not precede it. License is a single-line pointer — not
  an inlined 13-line preamble.
- Skills whose `SKILL.md` exceeds **400 lines** MUST split into `SKILL.md` (philosophy + workflow +
  pointers) plus one or more `references/*.md` (or topically-named sibling files) with detailed
  patterns, checklists, and examples.
- Every `SKILL.md` ends with a `## Changelog` section. Each version bump adds a dated entry describing
  what changed and why.

**Interface discipline:**
- Every skill's `## Interface` table declares explicit input/output *paths* (e.g.,
  `.ssd/features/<slug>/01-architect.md`) — not just downstream skill names.
- Every primary output artifact has YAML frontmatter conforming to the shared schema documented in
  `ssd/chapters/state.md` § "Structured Output Requirements."
- Every skill's Purpose contains a "When NOT to use" clause disambiguating it from any overlapping
  skill (see `ssd/chapters/skills.md` § "Resolving Skill Overlap").

**Header / license ordering:**
- Title-first: `# Skill Name` is line 1.
- Metadata block follows: license pointer, version.
- Content follows metadata.

**Future work:**
- **Contract tests** (`skills/tests/`): fixtures that assert each skill produces output conforming to
  its declared frontmatter schema and required sections. Tests contract, not quality. Not yet
  implemented — intended layer for preventing silent skill regressions.
- **Cross-skill schema contracts**: shared JSON Schema files that both producer and consumer skills
  reference. E.g., `code-reviewer.output.frontmatter ⊇ {finding_counts, gate_pass}`.

---

## License

© 2026 Alex Horovitz. Shareware license — free for personal and internal organizational use. See [LICENSE](LICENSE) for details.

If SSD saved you a death march or helped your team ship with less stress, consider a small donation:
[venmo.com/alex-horovitz](https://venmo.com/alex-horovitz?txn=pay&amount=20&note=SSD-Claude-Skill%20Donation) · $20 suggested · entirely optional
