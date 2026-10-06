# 3.0.0 evidence

Host: Linux, Python 3.12, PyYAML installed, bash, git, shellcheck 0.9.0. `claude` is not on PATH. `unshare` user/mount/net works.

| Command | Working directory | Exit | Result |
| --- | --- | --- | --- |
| `bash scripts/parity-test.sh` | repository root | 0 | 384/384 |
| `python3 scripts/v3_suite.py` | repository root | 0 | 101 pass, 0 fail, 3 NOT_RUN |
| `python3 scripts/live_eval_test.py` | repository root | 0 | fake runtime; ceiling, redaction, NOT_RUN, recording, adapter errors |
| `shellcheck -S warning methodology/*.sh scripts/*.sh` | repository root | 0 | clean |
| `python3 methodology/frontmatter-validate.py` | repository root | 0 | no FAIL lines (historical artifacts plus the new workstream) |
| `python3 scripts/skill-frontmatter-check.py` | repository root | 0 | library skills |

`claude plugin validate .` was run by the owner on a Mac with Claude Code installed. The result was "Validation passed with warnings". Both warnings are addressed in this tree. The record is `plugin-validate.md`. This host still has no `claude` binary, so the suite asserts that record and the tree fixes; it does not execute `claude`.

The live evaluation driver is in `scripts/eval_driver.py` and `methodology/ssdlib/live_eval.py`. This host has no `claude` binary and no model credential, so the driver was not pointed at a model. Live repetitions stay `NOT_RUN`. The owner commands are in `live-evals.md`.

The remaining `NOT_RUN` rows in the v3 suite are: in-session instruction loading, live model repetitions, and the five-user pilot.

Jail checks inside the suite passed on this host: symlink escape, absolute host path, secret environment, designated output, snapshot immutability, and blocked network. That certifies `methodology/ssdlib/executor.py` on this profile. It does not certify an unrestricted host shell.

`bash methodology/gate-rules.sh --base main` was run on this branch after the plugin-validate follow-up (the warning-fix commit, before this evidence paragraph was edited). Exit 0. An earlier run on `a9d6baa` had the same 10 pass / 4 skip / 0 fail shape.

## Gate

```
PASS wip-commits :: no WIP/checkpoint commits between main and HEAD
PASS tests-pass :: `bash scripts/parity-test.sh` exit 0
SKIP feature-flag-present :: no feature_flag_marker in .ssd/project.yml or .ssd/gate.yml
PASS adr-delta :: 4 ADR file(s) changed in docs/decisions/ for 3054 architectural lines
PASS frontmatter-valid :: 5 artifact(s) validated against schemas; 1 unvalidated (no matching schema)
PASS no-leaky-state :: no gitignored-by-policy files in diff
SKIP store-link-sane :: no store link (.ssd is a project-local directory)
PASS skill-version-sync :: 9 skill example(s) match banner; 2 exempt (no example block)
PASS migration-manifest-current :: manifest valid (16 entries; ids unique, ascending, ≤ VERSION 3.0.0)
PASS rails-walked :: 1 feature dir(s) in this release each carry a code review with gate_pass: true
PASS deviations-recorded :: 1 feature dir(s): every in-scope rail step either walked or recorded (production_runtime=false)
SKIP feynman-clean :: no feynman report in scope (vs main)
SKIP issue-sync-current :: issue_tracking not on (mirror dormant)
PASS skill-metadata :: 11 skill(s) have valid frontmatter
GATE 10 pass · 4 skip · 0 fail — a skip is a check that did not run
```

A skip is a check that did not run. It is not a pass.
