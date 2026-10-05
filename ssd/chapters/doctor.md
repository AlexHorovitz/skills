<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand. License: see /LICENSE. -->

## `/ssd doctor`

Read-only. Run:

```bash
python3 methodology/ssd_cli.py doctor
```

Resolve `methodology/ssd_cli.py` from the SSD library root, not by searching the project.

Doctor reports the installation source and version, duplicate skills, library and project and worktree and storage roots, state health (`missing`, `valid`, `corrupt`, `unreadable`), required dependencies, and the capability report (`supported`, `unsupported`, or `unknown`). Each capability names its evidence and when it was last checked.

It does not install dependencies, edit permissions, repair state, or open a network connection. Remedies are sentences the user can act on. A requested `run` mode that the capability report cannot support is reported as effective mode `propose`. The configuration file is left as the user wrote it.

## Daily summary

An ordinary `/ssd` reply names the workstream, the iteration, the requested and effective mode, what changed, which evidence is current, what is blocked, and the next command. It asks for a decision only when the user has to make one. It does not depend on color. It says **ready for human review** or **gate passed for this revision**. It says **shipped** only after a separate, authorized ship actually happened.

```text
Workstream: auth-flow | Iteration: 02
Mode: propose | Review: isolated agent
State: review complete; gate not yet run for the current revision
Attention: 1 major finding remains unresolved
Next: /ssd gate
Shipping: not authorized
```

That shape is the target. Expand logs only when the user asks.
