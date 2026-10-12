# Evaluations

Offline validation and live model execution are different operations.

`python3 scripts/eval_driver.py validate` checks fixture shape. It does not call a model and it does not measure routing.

`python3 scripts/eval_driver.py run --fixture ID --arm A|B|C` copies the checkout into a fresh home (arm C copies nothing) and runs the deterministic protocol grader. Arm C failing because `/ssd` is absent would be a manufactured delta; the grader does not do that.

`python3 scripts/eval_driver.py live` returns `NOT_RUN` unless `SSD_EVAL_RUNTIME` and `SSD_EVAL_SPEND_CEILING` are both set, and unless the named runtime can actually start. The adapters are `claude-code` (`claude -p`) and `anthropic-api`. An unknown runtime is not replaced. `python3 scripts/eval_driver.py live --dry-run` prints the plan and does not call a model. The owner runbook is `docs/releases/3.0.0/live-evals.md`. A missing credential or a missing binary is `NOT_RUN`, not a green baseline.

`evals/held-out/` is reserved. Those prompts are not in `evals/fixtures/` and are not used to tune descriptions.

The unchanged product's parity run is recorded in `.ssd/milestones/2026-10-05-v3-baseline/verification.md` at revision `e732a93`. Live arms of that baseline were not executed: no model runtime was available, and spending was not authorized. A missing runtime is `NOT_RUN`. It is not a retrospective pass.

Trusted assertions live in this directory and in `scripts/v3_suite.py`. Workers are not given this directory as their output path.
