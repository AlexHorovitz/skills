# Owner actions

The implementation request authorized a branch and a pull request. It did not authorize any of the following.

- Tag `3.0.0` or push the tag.
- Publish a GitHub release.
- Submit `.claude-plugin/marketplace.json` to a marketplace.
- Run `claude plugin validate` on a machine where Claude Code is installed, then decide whether the README may call the plugin path tested.
- Set `SSD_EVAL_RUNTIME` and `SSD_EVAL_SPEND_CEILING` and run live evaluations. The driver returns `NOT_RUN` until both are set, and this tree still has no model driver behind that flag.
- Run the five-user protocol in `usability.md`.
- Enable a required status check. `.github/workflows/quality.yml` stays informational.
- Retire clone installation. ADR-0024 defers that.

Rollback for a project that applied `format-marker`: restore the `.bak` files `migrate.sh` writes, or check out the previous library. A v2.14 binary does not read `.ssd/format`.
