# Plugin validation

The owner ran this command on a Mac with Claude Code installed, from a checkout of this branch:

```bash
claude plugin validate .
```

Result: **Validation passed with warnings**.

This environment has no `claude` binary, so the suite did not execute the command again. The record below is the owner's run. It is not a second local run.

## Warnings the owner saw

1. Marketplace manifest `.claude-plugin/marketplace.json`: `description: No marketplace description provided.`
2. Plugin root: `CLAUDE.md at the plugin root is not loaded as project context. To ship context with your plugin, use a skill (skills/<name>/SKILL.md) instead.`

## How this tree addresses them

The current Claude Code marketplace document (`https://code.claude.com/docs/en/plugin-marketplaces`, checked 2026-10-05) shows a top-level string field `description` ("Brief marketplace description"). The walkthrough example is `"description": "Plugins for my team"` beside `name`, `owner`, and `plugins`. That field is now set on the marketplace object. The plugin entry keeps its own description.

The root `CLAUDE.md` was only `@AGENTS.md`. `AGENTS.md` is the contributor guide for working in this repository. It is not the instruction block `ssd-init` installs in a user's project. Plugin users already receive the rail and the ship wall from the skills listed in `.claude-plugin/plugin.json`, in particular `ssd/SKILL.md`. That guide was not copied into a new skill.

Claude Code loads project instructions from `./CLAUDE.md` or `./.claude/CLAUDE.md` (`https://code.claude.com/docs/en/memory`). `@` imports resolve relative to the file that contains them. Checkout memory is now `.claude/CLAUDE.md` and its only line is `@../AGENTS.md`. There is no `CLAUDE.md` at the plugin root. A clone of this repository still loads the contributor guide when the repository is the project. A user's project `CLAUDE.md` is untouched.

A clean-host plugin install and marketplace submission were not part of this run.
