# 3.0.0 evidence

Host: Linux, Python 3.12, PyYAML installed, bash, git, shellcheck 0.9.0. `claude` is not on PATH. `unshare` user/mount/net works.

| Command | Working directory | Exit | Result |
| --- | --- | --- | --- |
| `bash scripts/parity-test.sh` | repository root | 0 | 384/384 |
| `python3 scripts/v3_suite.py` | repository root | 0 | 98 pass, 0 fail, 4 NOT_RUN |
| `shellcheck -S warning methodology/*.sh scripts/*.sh` | repository root | 0 | clean |
| `python3 methodology/frontmatter-validate.py` | repository root | 0 | no FAIL lines (historical artifacts plus the new workstream) |
| `python3 scripts/skill-frontmatter-check.py` | repository root | 0 | library skills |

The four `NOT_RUN` rows in the v3 suite are: in-session instruction loading, `claude plugin validate`, live model repetitions, and the five-user pilot.

Jail checks inside the suite passed on this host: symlink escape, absolute host path, secret environment, designated output, snapshot immutability, and blocked network. That certifies `methodology/ssdlib/executor.py` on this profile. It does not certify an unrestricted host shell.

`bash methodology/gate-rules.sh --base main` is run on the release commit and its output is appended below when that command has been executed. Until that line exists, do not read this file as a gate pass.

## Gate

Pending the post-commit run.
