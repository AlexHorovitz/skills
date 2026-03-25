# Insanely Great SSD — Claude Code Skills

A free, open skill set for [Claude Code](https://claude.ai/code) that implements **Shippable States Software Development** — a pragmatic engineering discipline for solo developers and small teams.

**Core invariant:** If you can't ship it right now, you don't have a product — you have a construction site.

Learn more: [insanelygreat.dev](https://insanelygreat.com) (or open `index.html` locally)

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
| `/architect` | Design: models, services, API contracts |
| `/systems-designer` | Production readiness: reliability, observability, deployment safety |
| `/coder` | Implementation from spec (Python, Django, Swift, Go, Rust, C/C++, Obj-C) |
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

## License

© 2026 Alex Horovitz. Shareware license — free for personal and internal organizational use. See [LICENSE](LICENSE) for details.

If SSD saved you a death march or helped your team ship with less stress, consider a small donation:
[venmo.com/alex-horovitz](https://venmo.com/alex-horovitz?txn=pay&amount=20&note=SSD-Claude-Skill%20Donation) · $20 suggested · entirely optional
