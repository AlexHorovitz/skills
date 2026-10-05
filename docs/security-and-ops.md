# Security and operations

This note describes the boundary SSD 3.0 actually implements. It is not a certification that every host path is closed.

## What is trusted

Repository files, issue text, tool output, and model-written reports are data. A worker cannot authorize itself by writing `approved: true`, deleting `.ssd/current.yml`'s `auto_run` lock, or claiming the user consented.

Grants for `ship`, `deploy`, `publish`, `release`, `tag-default`, `rollout-advance`, and `flag-removal` are stored outside the project:

- `SSD_CONTROL_DIR`, or
- `~/.ssd-control/<sha256 of the project path, first 16 hex chars>`

`SSD_WORKER=1` cannot create a grant and cannot consume one. A grant names the action and the snapshot. A different snapshot does not match. One use is the default.

In-repo files such as `.ssd/control/grants.yml` are ignored.

If the checker itself is absent, the action is denied. Command regular expressions are a supplement, not the boundary.

## What a worker must not hold

The autonomous process should not have production deploy credentials, package-publish tokens, or permission to move the default branch. The hook adapter denies a short list of shell shapes (`git push` of `main` or `master`, tag pushes, `gh release`, `npm publish`, and the rest in `methodology/ssdlib/authz.py`). A hook that does not run does not create those permissions, and it also does not remove them: the control-directory check still has to pass.

A branch push that is not the default branch is still an external side effect. This adapter does not treat it as a deploy, and it does not grant it.

## Review and tests

`agents/ssd-reviewer.md` lists Read, Grep, and Glob. That file is a request to the host. The tested restriction is the executor:

`unshare --user --map-root-user --mount --net --fork`, then a `chroot` whose root contains a copy of the snapshot, a read-only bind of the host toolchain, and a tmpfs on `/tmp`.

The snapshot copy keeps symlinks as symlinks. A link to a host secret does not resolve inside the jail. The command's environment is empty except for `PATH`, `HOME`, `TMPDIR`, and `LANG`. Secret-shaped variables are not copied.

Output belongs in `/out`, which is copied to the caller’s output directory. The snapshot directory on the host is not the write target.

If `unshare` cannot do this, `methodology/ssdlib/executor.py` returns `NOT_RUN` and doctor marks shell isolation unsupported. Strong-assurance review is then off. Inline review must be labeled `inline`.

## Hooks

`hooks/hooks.json` points at `methodology/hooks/ssd_hook.py`.

- PreToolUse can deny a matched Bash command by printing a permission decision and exiting 0.
- Exit code 2 would also block PreToolUse on Claude Code. This adapter exits 0 and uses the JSON decision so a normal command is not blocked by accident.
- A command-hook timeout on PreToolUse does not block. That is why the control directory remains the authority.
- PostToolUse runs after the tool. Its message is feedback.
- An empty or malformed payload writes a message and grants nothing.

No project test suite runs from the hook.

## Human ship

`/ssd ship` stays the human's command. The worker path does not gain a temporary exception for it. There is no `--force`.

## Profiles

| Profile | What was tested here | What is not claimed |
| --- | --- | --- |
| Linux 6.12, Python 3.12, unshare user/mount/net | Jail, authz, resume, hooks-as-a-process | Claude Code delivering the hook |
| Portable bundle | Metadata and relative links | Any host runtime |
| Plugin manifest | JSON shape and version sync with `VERSION` | `claude plugin validate` |

Unattended `run` is certified only for the first row's tested adapter. Other routes stay at effective mode `propose`.
