---
skill: brief
version: 1.25.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-skill-chapter-split
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-skill-chapter-split (2.0 prerequisite P1, path A)

Splits the 1,465-line `ssd/SKILL.md` monolith into a thin spine + on-demand chapter files. This is
**path A** from the 2.0 planning discussion: ship the structural split **now, on the 1.x line, as a
behavior-preserving refactor** (separate PR per Hard Rule 4), relieving the context-ceiling forcing
function ([issue #15](https://github.com/AlexHorovitz/skills/issues/15), [ADR-0012](../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md))
**without** committing to the contested 2.0 deletions. 2.0 then becomes pure subtraction on an
already-chaptered file (mirrors how `/ssd upgrade` shipped ahead of the cuts).

## Approach — stub-and-chapter (zero cross-ref breakage)

The spine keeps **every section heading** as a 2-line stub that redirects to its chapter; the section
*body* moves to `ssd/chapters/<name>.md`. Because every `§ "Section"` heading still exists in the
spine, all live cross-references (sibling-skill `SKILL.md` files, ADRs, README that cite
`ssd/SKILL.md § "…"`) keep resolving — no churn. `.ssd/` artifacts and CHANGELOG entries are dated
historical records and are **not** rewritten.

## In scope

- **Kept inline** (front page): Purpose / When / Prerequisite / Interface / Invocation / the no-arg
  **Auto-Detect** behavior (the progressive-disclosure core) / The Rails pointer / Hard Rules.
- **Moved to chapters** (`ssd/chapters/`): phase playbooks, `/ssd upgrade`, workstream-lifecycle
  commands, developer-profile+teaching, artifact tree, state schema (structured output + iterations +
  session continuity), methodology enforcement, sub-skill reference/overlap.
- **Changelog** (181 in-file lines) → pointer to the repo `CHANGELOG.md` (already mirrored there).
- `VERSION`/banner → 1.25.0; CHANGELOG entry.

## Explicitly NOT in scope (deferred to 2.0)

- **No deletions.** The Developer-Profile+Teaching chapter and bridge-flags are **relocated, not
  removed** — flagged in `chapters/profile.md` as the ADR-0012 Pillar-1 deletion candidate so 2.0 is a
  one-file `rm` + spine-stub removal. Removing the profile *concept* is the contested 2.0 cut, gated on
  accepting ADR-0012.
- No README command-list refresh (separate doc-currency task).

## Acceptance

- Behavior-preserving: every section heading still present in the spine (as a stub); no body text lost
  (each moved section appears in exactly one chapter); contested sections relocated verbatim.
- `scripts/parity-test.sh` green; `gate-rules.sh --base main` exit 0 (`skill-version-sync` still PASS).
- Spine substantially smaller (target < ~250 lines from 1,465); chapters load on demand.
- `/ssd gate` clean (no BLOCKER/MAJOR).
