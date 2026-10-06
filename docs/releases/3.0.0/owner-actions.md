# Owner actions

The implementation request authorized a branch and a pull request. It did not authorize any of the following.

- Tag `3.0.0` or push the tag.
- Publish a GitHub release.
- Submit `.claude-plugin/marketplace.json` to a marketplace.
- `claude plugin validate .` already ran on the owner's Mac. The result was "Validation passed with warnings", and both warnings are addressed in this tree (`docs/releases/3.0.0/plugin-validate.md`). A second run after this commit, and a clean-host plugin install, are still yours if you want them. This environment has no `claude` binary.
- Run live evaluations when you are ready to spend. The driver is in the tree. Set a runtime, a credential, and `SSD_EVAL_SPEND_CEILING`, then follow `docs/releases/3.0.0/live-evals.md`. Start with `python3 scripts/eval_driver.py live --dry-run` and a one-fixture ceiling. This environment had no credential, so the live rows are still `NOT_RUN`.
- Run the five-user protocol in `usability.md`.
- Enable a required status check. `.github/workflows/quality.yml` stays informational.
- Retire clone installation. ADR-0024 defers that.

Rollback for a project that applied `format-marker`: restore the `.bak` files `migrate.sh` writes, or check out the previous library. A v2.14 binary does not read `.ssd/format`.
