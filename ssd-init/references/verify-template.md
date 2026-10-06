# Optional project verify skill

Offer this file. Do not install it over an existing `verify` skill.

A host instruction to verify, an opt-in git hook, an agent execution guard, and report-only CI are four different things. This template is the instruction. It does not run on every commit by itself, and it does not cover documentation-only or test-only commits unless the project's own recipe says so.

```markdown
---
name: verify
description: Run this project's confirmed test command and report the exit status. Use when the user asks to verify the current change.
---

# Verify

Read `.ssd/gate.yml` key `test_command`. If it is missing or commented, say `NOT_RUN` and name the key. Do not guess `test`, `tests`, or `testCommand`.

Run that command in the selected worktree. Record the exit status. A failure stays a failure. Do not edit tests or acceptance criteria to obtain a pass.

This skill does not ship and does not grant a gate pass.
```
