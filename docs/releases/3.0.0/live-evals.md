# Live evaluations

The driver is `scripts/eval_driver.py`. It does not call a model until you set a runtime and a spend ceiling. A missing piece is `NOT_RUN`. That is not a pass. This checkout did not run a live model: no credential was available.

Held-out prompts in `evals/held-out/` are not planned and are not modified. Driver self-check fixtures (`family: driver`) stay offline. Arm A is git revision `e732a93` (override with `SSD_EVAL_BASELINE`). If that revision is not in the clone, arm A is `NOT_RUN` and is not replaced with `HEAD`.

## Install

Install Claude Code so `claude` is on `PATH`. The headless adapter uses `claude -p` with `--output-format stream-json`, `--permission-mode dontAsk`, and `--permission-prompts none` (Claude Code v2.1.259 or later for that last flag). It does **not** pass `--bare`, because bare mode skips skills, hooks, and `CLAUDE.md`, which are part of what the run records.

A second adapter, `anthropic-api`, calls the Messages API with `ANTHROPIC_API_KEY`. It cannot load skills, hooks, role files, or `AGENTS.md`. Those observations stay `NOT_RUN` on that runtime. The API requires `SSD_EVAL_MODEL`. The driver does not pick a model for you.

Non-bare `claude -p` can use an existing Claude Code login. Set `ANTHROPIC_API_KEY` in the environment when you want the API key instead. The driver reads that variable and does not write it. It does not copy other secrets (`GITHUB_TOKEN`, cloud keys, and the rest of the secret markers) into the child environment.

## Dry run

From the repository root. This prints the plan and does not call a model. It works before the runtime is installed.

```bash
python3 scripts/eval_driver.py live --dry-run
```

`estimate_source` is `unknown` until you set an owner estimate. The estimate is not a measurement.

```bash
export SSD_EVAL_USD_ESTIMATE=0.02
python3 scripts/eval_driver.py live --dry-run
```

The plan is three repetitions (`SSD_EVAL_REPETITIONS`, default 3) of each fixture arm, plus one `agents-md` probe for arms A and B. Isolated rows are `NOT_RUN`: the unshare jail drops the network, so a model call is not hosted inside it. Inline rows are labeled `inline`.

## Small ceiling first

```bash
export SSD_EVAL_RUNTIME=claude-code
export SSD_EVAL_SPEND_CEILING=0.25
# optional; omit to let the CLI inherit a model. A reported name that differs is an error.
# export SSD_EVAL_MODEL=your-exact-model-name
python3 scripts/eval_driver.py live --dry-run
python3 scripts/eval_driver.py live --fixture ev03-bare-ssd --arm C --repetitions 1 --no-probes
```

If that summary looks right, raise the ceiling and run the full plan:

```bash
export SSD_EVAL_SPEND_CEILING=5
python3 scripts/eval_driver.py live
```

Messages API, still with a ceiling, and with rates only if you want the driver to turn reported tokens into a USD figure. Cache tokens without their own rate leave the cost `unknown`.

```bash
export SSD_EVAL_RUNTIME=anthropic-api
export SSD_EVAL_MODEL=your-exact-model-name
export ANTHROPIC_API_KEY=your-key
export SSD_EVAL_SPEND_CEILING=0.25
export SSD_EVAL_USD_PER_MILLION_IN=3
export SSD_EVAL_USD_PER_MILLION_OUT=15
python3 scripts/eval_driver.py live --fixture ev03-bare-ssd --arm C --repetitions 1 --no-probes
```

Unset `ANTHROPIC_API_KEY` when you are done. Do not put it in a file in this repository.

## What the ceiling does

Before each call, a remaining balance of zero, or an owner estimate larger than the remaining balance, stops the batch. During a Claude Code stream, a reported `total_cost_usd` above the ceiling sends SIGTERM and records `STOPPED`. If a finished call does not report cost and you did not set both per-million rates, the cost stays `unknown` and later calls do not start. Unknown is not treated as zero.

Exit codes: `0` when the batch is `RECORDED` or the command was a dry run, `2` for `NOT_RUN` or `STOPPED`, `1` for `FAIL` or `ERROR`. `RECORDED` means the call was stored. It is not a claim that a behavior passed.

## Where results land

`evals/results/<UTC>/summary.json` plus one redacted trace per call. The directory is gitignored. Copy a summary into the release notes only after you have read it. The T02 rows in `evidence.md` stay `NOT_RUN` until that real summary exists.

`summary.json` uses the same fields as an offline manifest where they apply: `id`, `arm`, `revision`, `operation`, `grade`, and `live_model`. `live_model` is `unknown` when the runtime does not name a model. `execution_method` is `inline` or the isolated row's `NOT_RUN`.

Timeout for one call is `SSD_EVAL_TIMEOUT_SECONDS` (default 300).
