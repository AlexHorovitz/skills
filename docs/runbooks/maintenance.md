# Maintenance

Owner: Alex Horovitz. The 3.0.0 change does not assign a second maintainer.

| Area | What to do |
| --- | --- |
| Compatibility | Re-run `bash scripts/parity-test.sh` and `python3 scripts/v3_suite.py` when a referee or schema changes. |
| Schemas | Edit `methodology/schemas/*.yml` only, then regenerate JSON with `methodology/ssdlib/schemas.py`. |
| Evaluations | Live runs need `SSD_EVAL_RUNTIME`, a credential, and `SSD_EVAL_SPEND_CEILING`. Without them the driver returns `NOT_RUN`. Commands and the ceiling rules are in `docs/releases/3.0.0/live-evals.md`. Do not schedule unbounded nightly spend. |
| Security | Reports against the control directory, the jail, or a hook bypass go to the owner. Do not publish raw traces. |
| Docs | Release notes live in `CHANGELOG.md` and `docs/releases/`. |

Informational CI (`.github/workflows/quality.yml`) must not be turned into a required status check from this repository's workflow file alone. A required check is an owner decision on the forge.

Rollback of a project upgrade is `methodology/ssdlib/lifecycle.py` restore from the backup `migrate.sh` writes, then running the previous library. See [ADR-0024](../decisions/ADR-0024-v3-scope.md) for the format marker's limit.
