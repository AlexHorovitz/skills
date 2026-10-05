# ADR-0023: Authorization lives outside the repository

## Status

Accepted — 2026-10-05 — SSD 3.0.0.

Extends the stop registry. Does not renumber STOP-1..STOP-7 or FM-1..FM-6 from [ADR-0020](ADR-0020-autonomy-ladder.md).

## Context

An autorun lock coordinates work. It does not approve shipping. A file inside the repository that says `approved: true` is data the worker can write. Hook exit codes are not a session authorization contract: a missing, malformed, or timed-out command hook can leave the host's normal permission flow in place.

STOP-4, as written for the autonomy ladder, is the hand-back when continuing would mean guessing. A conflicting replay of a transition is that situation.

## Decision

1. Consequential actions are `ship`, `deploy`, `publish`, `release`, `tag-default`, `rollout-advance`, and `flag-removal`. Grants live in `SSD_CONTROL_DIR` or `~/.ssd-control/<sha256(project)[:16]>`, which must be outside the project. `SSD_WORKER=1` cannot create or consume a grant.
2. `methodology/ssdlib/authz.py` does not read `.ssd/control/grants.yml` or any other in-repo approval file. Command patterns (`git push` of `main`/`master`, `git push --tags`, `gh release`, `npm publish`, and the others in that module) are supplemental. If the guard is missing, the check fails closed.
3. The same fingerprint on the same autorun edge returns `state=ok reason=replay` and does not append. The same fingerprint on a different edge returns `state=stop reason=STOP-4`. A transition without `--fingerprint` keeps the v2.14 counting behavior, including review loops. `--child-transitions` counts against the same budget.
4. `/ssd resume` continues the same record. It does not reset consumed transitions, does not restore a shipping grant, and does not invent a finish when `stop_reason` is null.
5. The reviewer role file lists read and search tools only. Tests run through `methodology/ssdlib/executor.py` (`unshare` user, mount, and net namespaces, then `chroot`). If that mechanism is unavailable, strong-assurance review is unsupported and the effective mode for an unattended run stays `propose`.
6. `hooks/hooks.json` calls `methodology/hooks/ssd_hook.py`. The hook is not the authority. An empty or malformed payload does not grant permission. Post-tool output is feedback.

## Consequences

This boundary is the Python control directory plus the unshare jail. It is not a claim that an unrestricted host shell is sandboxed. Paths the host exposes outside this adapter are unverified, and unattended `run` is not certified on those paths.

No new `--force` flag exists.
