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

`bash methodology/gate-rules.sh --base main` was run on commit `a9d6baa` (the release commit, before this evidence update). Exit 0.

## Gate

```
PASS wip-commits
PASS tests-pass :: bash scripts/parity-test.sh exit 0
SKIP feature-flag-present :: no feature_flag_marker
PASS adr-delta :: 4 ADR file(s)
PASS frontmatter-valid :: 5 artifact(s) validated; 1 unvalidated (the baseline verification note)
PASS no-leaky-state
SKIP store-link-sane :: no store link
PASS skill-version-sync :: 9 examples match; 2 exempt
PASS migration-manifest-current :: 16 entries, none newer than 3.0.0
PASS rails-walked :: ssd-v3 carries gate_pass: true
PASS deviations-recorded :: production_runtime=false
SKIP feynman-clean :: no report in scope
SKIP issue-sync-current :: issue tracking off
PASS skill-metadata :: 11 skills
GATE 10 pass · 4 skip · 0 fail
```

The full text is the command above. A skip is a check that did not run.
