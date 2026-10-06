# SSD repository instructions

This file is for people and agents working **in this repository** (the SSD skill pack). The block installed in a user's project is [ssd-init/references/project-instructions.md](ssd-init/references/project-instructions.md). Do not paste role bodies here, and do not replace that file with this one.

## Rail

brief → design → code → review → gate → ship.

The human supplies the objective, constraints, and acceptance criteria. Do not change them so a check will pass.

Bare `/ssd` reads state and proposes the next action. The default autonomy mode is `propose`. `advance` and `run` keep their existing meanings. There is no `--force` ship.

Autonomous execution cannot ship, deploy, publish, remove a release control, or grant itself that authority. A missing autorun lock is not approval. When isolation or a trusted approval is missing, the effective mode is `propose`. Do not rewrite the user's configuration to hide that.

Order is announce → log → act.

## Checks

Executable referees, from the repository root:

```bash
bash methodology/gate-rules.sh --base main
bash scripts/parity-test.sh
python3 scripts/v3_suite.py
python3 scripts/skill-frontmatter-check.py
```

`PASS`, `FAIL`, `ERROR`, and `NOT_RUN` are different. A missing tool is not a pass. Schema validity is not a gate result.

Resolve roots with `python3 methodology/ssd_cli.py paths`. Do not search a user project for a copy of these scripts that is not there.

## State

A missing `.ssd/` means propose `/ssd-init`. A state file that does not parse is corrupt, not an empty project. Migrations are additive. Do not reinterpret old records.

Feynman, software-standards, and codebase-skeptic start only when a person invokes them.

## This checkout

Library version is the `VERSION` file. Skill banners are per skill. Plugin version in `.claude-plugin/plugin.json` tracks `VERSION`.

Project memory for a checkout of this repository is `.claude/CLAUDE.md`, which imports this file. Claude Code does not load a `CLAUDE.md` at the plugin root. Plugin users get the rail from the skills, especially `ssd/SKILL.md`. This file stays the contributor guide.

CI in `.github/workflows/quality.yml` is informational. Do not add a required status check.

Optional workflows, secondary verification, specialist fan-out, cloud routines, MCP, and Spec Kit are not part of the core product until an ADR says they shipped. Clone installation stays supported.
