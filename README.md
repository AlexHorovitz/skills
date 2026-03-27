# Insanely Great SSD — Claude Code Skills

A free, open skill set for [Claude Code](https://claude.ai/code) that implements **Shippable States Software Development** — a pragmatic engineering discipline for solo developers and small teams. Platform-adaptive: web, iOS, Android, macOS, and headless.

**Core invariant:** If you can't ship it right now, you don't have a product — you have a construction site.

Learn more: [insanelygreat.com](https://insanelygreat.com)

---

## What Is SSD?

Insanely Great SSD keeps software in a deployable, production-ready state at all times. It synthesizes continuous deployment, trunk-based development, and feature flags into a workflow a single developer can actually maintain — amplified by Claude Code at every step.

Five principles:
1. **Constant Production Parity** — Deploy "Hello World" on Day 1. Deployment is never "the hard part."
2. **The Shippable State Invariant** — Every session ends with passing tests and nothing broken.
3. **Feature Flags Over Feature Branches** — All work on main, behind flags, off by default.
4. **The Ratchet Principle** — Forward progress only. No WIP commits, no "fix tomorrow."
5. **Scope Flexibility Is a Feature** — Cutting scope is engineering judgment, not failure.

---

## Skills

### `/ssd` — The Meta-Skill

The orchestrator. Sequences the right sub-skills for each development phase.

```
/ssd start      — New project or major feature: Walking Skeleton setup
/ssd feature    — Active development: design → build → review → deploy loop
/ssd milestone  — Post-sprint consolidation: deep audit + targeted refactor
/ssd gate       — Shippable state check only (code-reviewer)
/ssd ship       — Deploy readiness check only (systems-designer checklist)
/ssd audit      — Adversarial comparative review (nuclear option)
```

### Sub-Skills

| Skill | Role |
|---|---|
| `/architect` | Design: models, services, API contracts. Platform-adaptive (web, iOS, Android, macOS, headless) |
| `/systems-designer` | Production readiness: reliability, observability, deployment safety |
| `/coder` | Implementation from spec (Python, TypeScript, Swift, Ruby, Java, C#, PHP, Go, Rust, C/C++, Obj-C) |
| `/code-reviewer` | PR gate: BLOCKER/MAJOR findings block merge |
| `/codebase-skeptic` | Deep architectural critique through 10 expert lenses |
| `/software-standards` | Adversarial comparative audit |
| `/refactor` | Post-ship targeted improvement |
| `/methodology` | SSD methodology reference |

---

## Installation

Clone the repo into your Claude Code skills directory:

```bash
git clone https://github.com/AlexHorovitz/skills ~/.claude/skills
```

Then invoke any skill from Claude Code:

```
/ssd feature
/coder
/code-reviewer
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
- **New framework guides** — A new `architect/web/frameworks/` file for a web framework not yet covered (e.g., `sveltekit`, `remix`, `nestjs`)
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

`SKILL.md` files begin with the license block (see any existing file). `GUIDE.md` files do not need the license block — they are reference material, not standalone skills.

---

## License

© 2026 Alex Horovitz. Shareware license — free for personal and internal organizational use. See [LICENSE](LICENSE) for details.

If SSD saved you a death march or helped your team ship with less stress, consider a small donation:
[venmo.com/alex-horovitz](https://venmo.com/alex-horovitz?txn=pay&amount=20&note=SSD-Claude-Skill%20Donation) · $20 suggested · entirely optional
