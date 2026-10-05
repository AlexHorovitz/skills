# ADR-0021: Portable skill frontmatter, and deliberate invocation

## Status

Accepted — 2026-10-05 — SSD 3.0.0.

Amends the title-first hygiene note in `README.md`. Does not change [ADR-0009](ADR-0009-skill-version-sync.md): the `**Version:**` banner remains the authored skill version. `metadata.version`, when present, mirrors that banner. Neither is the library `VERSION` file, except that `ssd/SKILL.md` still tracks the library version at the edit that last changed that file.

## Context

The Agent Skills specification (checked 2026-10-05) requires a file to start with `---` and to carry `name` and `description`. `name` matches the parent directory. `description` is at most 1,024 characters. The host listing budget is a different number and is not the portable limit.

This repository's hygiene text said each `SKILL.md` begins with a Markdown title. That made portable discovery depend on a host-specific fallback. Setup and the broad audits (`ssd-init`, `feynman`, `software-standards`, `codebase-skeptic`) were also ordinary skills a host could auto-invoke.

## Decision

1. Every library `SKILL.md` starts with YAML frontmatter. `name` matches the directory. `description` is nonempty and at most 1,024 characters.
2. The title, license pointer, and `**Version:**` banner follow the frontmatter. The banner stays the authored skill version ([ADR-0009](ADR-0009-skill-version-sync.md)).
3. `ssd-init`, `feynman`, `software-standards`, and `codebase-skeptic` set `disable-model-invocation: true` in the Claude Code adapter. Their bodies repeat the same restriction for hosts that ignore the field. A person invokes them by name. Automation may propose a Feynman audit and must not start one.
4. `methodology/gate-rules.sh` rule `skill-metadata` runs `scripts/skill-frontmatter-check.py` only in this library (the project contains both `methodology/migrations.yml` and the checker). Anywhere else the rule SKIPs. If the checker cannot import its parser it exits 2 and the rule FAILs. A missing parser is not a pass.
5. Entrypoints stay at or below 400 physical lines. Archives under `references/archive-v2.14.md` are historical text, not the current contract.

## Consequences

Hosts that do not read frontmatter still see the body, including the deliberate-invocation sentences. Missing frontmatter is not claimed to make a skill universally uninvocable.

`disable-model-invocation` is stripped from the portable export. The body sentences remain. Native `claude plugin validate` was not run in the 3.0.0 implementation environment.
