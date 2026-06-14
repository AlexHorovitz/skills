<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

## Sub-Skill Reference

| Sub-Skill | Role in SSD | Phase |
|---|---|---|
| `ssd-init` | First-run housekeeping: `.ssd/` tree, gitignore, `project.yml`, prerequisite checks | **prerequisite to all phases** |
| `architect` | Design: models, services, API boundaries | start, feature |
| `systems-designer` | Production readiness: reliability, observability, deployment safety | start, feature, ship |
| `coder` | Implementation from spec (language-adaptive) | feature |
| `code-reviewer` | PR gate: BLOCKER/MAJOR findings block merge | feature, milestone, gate |
| `codebase-skeptic` | Deep architectural critique (10 expert voices) | milestone |
| `software-standards` | Adversarial comparative audit | audit |
| `refactor` | Post-ship targeted improvement | milestone |
| `methodology` | SSD doctrine reference + `/methodology score` self-adherence metric | reference / any phase |

`proposal-reviewer` and `software-capitalization` are standalone domain tools and do not participate in the SSD workflow.

---

## Review Tier Selection

Three skills do "review" work. Never chain all three — pick the right tier:

- **`code-reviewer`** — every PR, always, no exceptions
- **`codebase-skeptic`** — milestone reviews and pre-release audits
- **`software-standards`** — comparative/adversarial evaluation only

---

## Resolving Skill Overlap

When two skills could both handle the same request, the orchestrator picks the more specific one —
unless the skill's "When NOT to use" clause disqualifies it. There are **8 known overlap pairs**.
The first three are *substitution* pairs (one skill replaces the other for a request); the rest
are *coordination* pairs (both skills run, but in a fixed order/role, or are selected by project
state, never competing). Skill A / Skill B below name the two skills; the rule says how they relate.

| Skill A | Skill B | Priority / coordination rule |
|---|---|---|
| `coder` | `python-django-coder` (when present) | If language = Python AND framework = Django, use `python-django-coder`. Otherwise use `coder`. |
| `code-reviewer` | `codebase-skeptic` | `code-reviewer` for PR-level review (≤500 changed lines). `codebase-skeptic` for milestone/architectural review. Never chain both on the same scope. |
| `codebase-skeptic` | `software-standards` | `codebase-skeptic` for continuous stewardship of an owned codebase. `software-standards` for vendor selection / legacy onboarding / pre-acquisition evaluation. Mutually exclusive. |
| `refactor` | `code-reviewer` | Coordination, not substitution. During `/ssd milestone` step 3, `refactor` *produces* the plan and `code-reviewer` *validates* each refactor PR (`remediation_mode: true` triggers Phase 1.5). `refactor` never reviews; `code-reviewer` never plans. A refactor item that no PR closes is surfaced by the milestone playbook ("no cite → not in scope"), not by either skill. |
| `architect` | `systems-designer` | Coordination. In `/ssd design`, `architect` runs first (models, APIs, ADRs); `systems-designer` runs second and is **purely additive** (failure modes, observability, deploy safety). Never substitute one for the other. `systems-designer` is N/A for markdown / docs-only projects, where `architect` runs alone. |
| `methodology` | (all skills) | Reference-tier. `methodology` supplies doctrine + the `/methodology score` self-adherence metric; it is rarely invoked directly in a feature loop. When another skill's behavior is in question, prefer that skill; consult `methodology` only for doctrine adjudication. |
| `codebase-skeptic` | `refactor` | Producer → consumer. In `/ssd milestone` / `/ssd verify`, `codebase-skeptic` *produces* findings (`skeptic-before.md` / `skeptic-after.md`) and `refactor` *consumes* them into a plan. Never the reverse — don't ask `refactor` to audit or `codebase-skeptic` to plan fixes. |
| `ssd-init` | `/ssd upgrade` | State-disjoint coordination ([ADR-0013](../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)). `ssd-init` when `.ssd/project.yml` is **absent** (first run / create). `/ssd upgrade` when it's **present and behind** (migrate to the latest conventions). Both call `methodology/migrate.sh`; neither duplicates migration logic. Never run `ssd-init` to "catch up" an initialized project — that's `/ssd upgrade`. |

Each *substitution*-pair skill MUST have a "When NOT to use" section naming the other skill(s) and the priority
rule. The orchestrator reads these to decide which skill to invoke when the user's request is
ambiguous. A new skill added alongside an existing one must declare a priority rule at creation — a
skill without a declared priority cannot be promoted past draft.

---

