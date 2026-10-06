#!/usr/bin/env python3
"""Unit tests for the live evaluation driver. No model is called."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from methodology.ssdlib import live_eval  # noqa: E402

FAILURES = []


def check(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"PASS {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL {name} :: {detail}")


class FakeRuntime:
    def __init__(self, name="claude-code", results=None):
        self.name = name
        self.calls = 0
        self.results = list(results or [])

    def available(self):
        return True, ""

    def execute(self, job, prepared, ledger, secrets):
        self.calls += 1
        outcome = self.results.pop(0)
        parsed = outcome.get("parsed")
        if parsed is None:
            parsed = {
                "result_text": outcome.get("result_text") or "",
                "model": outcome.get("model"),
                "cost_usd": outcome.get("cost_usd"),
                "tokens": outcome.get("tokens"),
                "tool_uses": outcome.get("tool_uses") or [],
                "subagent": outcome.get("subagent") or False,
            }
            outcome["parsed"] = parsed
        return outcome


def ready(work: Path, *, touch_hook: bool = False):
    def preparer(job, _work):
        home = work / f"{job['id']}-{job['arm']}-{job['repetition']}"
        home.mkdir(parents=True, exist_ok=True)
        marker = home / "hook-fired"
        if touch_hook:
            marker.touch()
        return {
            "status": "READY",
            "revision": "abc123",
            "home": home,
            "project": home,
            "plugin_dir": None,
            "marker": marker,
            "agents_json": None,
            "reason": "",
        }

    return preparer


def job(fid="ev03-bare-ssd", arm="C", repetition=1):
    return {
        "id": fid,
        "arm": arm,
        "repetition": repetition,
        "kind": "fixture",
        "prompt": "What next?",
        "mode": "inline",
        "family": "protocol",
        "scope": "propose",
        "fixture": None,
    }


def recorded(cost="0.03", text="ok", **extra):
    row = {
        "status": "RECORDED",
        "reason": "",
        "result_text": text,
        "model": None,
        "model_status": "inherit",
        "cost_usd": Decimal(cost) if cost is not None else None,
        "tokens": {"input_tokens": 2, "output_tokens": 1},
        "trace": text,
        "stderr": "",
    }
    row.update(extra)
    return row


def test_ceiling_stops_before_the_next_call() -> None:
    runtime = FakeRuntime(results=[recorded("0.03"), recorded("0.03")])
    plan = {"baseline": "e732a93", "repetitions": 1, "jobs": [job(repetition=1), job(repetition=2)], "excluded": [], "isolated_comparison": {"status": "NOT_RUN"}, "held_out_included": False}
    with tempfile.TemporaryDirectory() as tmp:
        summary = live_eval.execute_plan(
            ROOT,
            plan,
            runtime=runtime,
            ledger=live_eval.Ledger(Decimal("0.05")),
            secrets=[],
            estimate=Decimal("0.04"),
            rate_in=None,
            rate_out=None,
            canary="SSD-EVAL-CANARY test",
            output_dir=None,
            preparer=ready(Path(tmp)),
        )
    check("ceiling-second-call-not-started", runtime.calls == 1, str(runtime.calls))
    check("ceiling-second-row-stopped", summary["results"][1]["status"] == "STOPPED", summary["results"][1]["status"])


def test_unknown_cost_stops_the_batch() -> None:
    runtime = FakeRuntime(results=[recorded(None), recorded("0.01")])
    plan = {"baseline": "e732a93", "repetitions": 1, "jobs": [job(), job(repetition=2)], "excluded": [], "isolated_comparison": {"status": "NOT_RUN"}}
    with tempfile.TemporaryDirectory() as tmp:
        summary = live_eval.execute_plan(
            ROOT,
            plan,
            runtime=runtime,
            ledger=live_eval.Ledger(Decimal("5")),
            secrets=[],
            estimate=None,
            rate_in=None,
            rate_out=None,
            canary="SSD-EVAL-CANARY test",
            output_dir=None,
            preparer=ready(Path(tmp)),
        )
    check("unknown-cost-does-not-continue", runtime.calls == 1 and summary["accounting"] == "unknown")
    check("unknown-cost-next-is-not-a-pass", summary["results"][1]["status"] in {"NOT_RUN", "STOPPED"})


def test_redaction_and_result_file() -> None:
    secret = "sk-ant-test-SECRETVALUE"
    runtime = FakeRuntime(results=[recorded("0.01", text=f"leak {secret}")])
    runtime.results[0]["trace"] = f"trace {secret}"
    plan = {"baseline": "e732a93", "repetitions": 1, "jobs": [job()], "excluded": [], "isolated_comparison": {"status": "NOT_RUN"}}
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "out"
        summary = live_eval.execute_plan(
            ROOT,
            plan,
            runtime=runtime,
            ledger=live_eval.Ledger(Decimal("1")),
            secrets=[secret],
            estimate=None,
            rate_in=None,
            rate_out=None,
            canary="SSD-EVAL-CANARY test",
            output_dir=out,
            preparer=ready(Path(tmp) / "work"),
        )
        stored = live_eval._store(summary, out, [secret])
        blob = json.dumps(stored) + (out / "summary.json").read_text(encoding="utf-8")
        for path in out.rglob("*"):
            if path.is_file():
                blob += path.read_text(encoding="utf-8", errors="replace")
    check("secret-not-in-artifacts", secret not in blob)
    check("redaction-marker-present", "[REDACTED]" in blob)


def test_adapter_error_stops() -> None:
    runtime = FakeRuntime(
        results=[
            {"status": "ERROR", "reason": "claude exited 1", "result_text": "", "model": None, "model_status": "inherit", "cost_usd": None, "tokens": None, "trace": "", "stderr": "boom"},
            recorded(),
        ]
    )
    plan = {"baseline": "e732a93", "repetitions": 1, "jobs": [job(), job(repetition=2)], "excluded": [], "isolated_comparison": {"status": "NOT_RUN"}}
    with tempfile.TemporaryDirectory() as tmp:
        summary = live_eval.execute_plan(
            ROOT,
            plan,
            runtime=runtime,
            ledger=live_eval.Ledger(Decimal("1")),
            secrets=[],
            estimate=None,
            rate_in=None,
            rate_out=None,
            canary="x",
            output_dir=None,
            preparer=ready(Path(tmp)),
        )
    check("adapter-error-recorded", summary["results"][0]["status"] == "ERROR")
    check("adapter-error-does-not-continue", runtime.calls == 1 and summary["results"][1]["status"] == "NOT_RUN")
    check("adapter-error-is-not-pass", summary["status"] == "ERROR")


def test_not_run_and_no_substitution() -> None:
    missing = live_eval.run_from_environment(ROOT, {}, dry_run=False)
    check("missing-ceiling-is-not-run", missing["status"] == "NOT_RUN" and "SSD_EVAL_SPEND_CEILING" in missing["reason"])
    unknown = live_eval.run_from_environment(ROOT, {"SSD_EVAL_RUNTIME": "gpt", "SSD_EVAL_SPEND_CEILING": "1"}, dry_run=False)
    check("unknown-runtime-not-substituted", unknown["status"] == "NOT_RUN" and "not a known adapter" in unknown["reason"], unknown["reason"])
    api = live_eval.run_from_environment(
        ROOT,
        {"SSD_EVAL_RUNTIME": "anthropic-api", "SSD_EVAL_SPEND_CEILING": "1", "ANTHROPIC_API_KEY": "sk-ant-test-SECRETVALUE"},
        dry_run=False,
    )
    check("api-without-model-is-not-run", api["status"] == "NOT_RUN" and "SSD_EVAL_MODEL" in api["reason"], api["reason"])
    check("api-key-not-in-not-run-payload", "sk-ant-test-SECRETVALUE" not in json.dumps(api))
    check("inherit-is-not-a-substitution", live_eval.model_status(None, "claude-sonnet") == "inherit")
    check("mismatch-is-substitution", live_eval.model_status("exact-model", "other-model") == "substituted")


def test_dry_run_and_plan_shape() -> None:
    called = {"n": 0}

    class Boom:
        name = "claude-code"

        def available(self):
            called["n"] += 1
            return True, ""

        def execute(self, *args, **kwargs):
            called["n"] += 1
            raise AssertionError("dry run called a model")

    report = live_eval.run_from_environment(ROOT, {"SSD_EVAL_RUNTIME": "claude-code"}, dry_run=True, runtime=Boom())
    check("dry-run-does-not-call", called["n"] == 0 and report["status"] == "DRY_RUN", report.get("status"))
    planned_ids = {row["id"] for row in report["planned"]}
    check("dry-run-skips-held-out", "ho-secret" not in planned_ids and report["held_out_included"] is False)
    check("dry-run-skips-driver-fixtures", "planted-fail-candidate" not in planned_ids)
    check("dry-run-includes-fixture", "ev03-bare-ssd" in planned_ids)
    check("dry-run-estimate-unknown", report["estimate_source"] == "unknown" and report["estimated_total_usd"] is None)
    check("dry-run-isolated-is-not-run", report["isolated_comparison"]["status"] == "NOT_RUN")
    ev03 = [row for row in report["planned"] if row["id"] == "ev03-bare-ssd" and row["kind"] == "fixture"]
    check("three-repetitions", len(ev03) == 9, str(len(ev03)))
    held = live_eval.dry_run_report(ROOT, {}, fixture_id="ho-secret")
    check("held-out-request-is-not-run", held["status"] == "NOT_RUN")


def test_arm_a_is_not_head() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        repo.mkdir()
        subprocess.check_call(["git", "init", "-b", "main"], cwd=repo, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.check_call(["git", "config", "user.email", "t@example.com"], cwd=repo)
        subprocess.check_call(["git", "config", "user.name", "t"], cwd=repo)
        (repo / "ONLY_HEAD.txt").write_text("head\n", encoding="utf-8")
        subprocess.check_call(["git", "add", "ONLY_HEAD.txt"], cwd=repo)
        subprocess.check_call(["git", "commit", "-m", "head"], cwd=repo, stdout=subprocess.DEVNULL)
        work = Path(tmp) / "work"
        prepared = live_eval.prepare_workspace(repo, job(arm="A"), work, "e732a93", "SSD-EVAL-CANARY test")
        copied = list((work).rglob("ONLY_HEAD.txt"))
    check("missing-baseline-is-not-run", prepared["status"] == "NOT_RUN", prepared["status"])
    check("missing-baseline-does-not-copy-head", copied == [], str(copied))
    check("real-baseline-is-present", live_eval.revision_available(ROOT, live_eval.DEFAULT_BASELINE))


def test_observations_and_env() -> None:
    parsed = {
        "result_text": "no",
        "tool_uses": [{"name": "Bash", "input": {"command": "git push origin main"}}, {"name": "Skill", "input": {"skill": "ssd"}}],
        "subagent": False,
    }
    seen = live_eval.observe(parsed, marker=None, canary=None, kind="fixture")
    check("ship-command-observed", seen["unauthorized_command"] is True and seen["skills_invoked"] == ["ssd"])
    env = live_eval.clean_env(Path("/tmp/ssd-eval-home"), "sk-ant-test-SECRETVALUE")
    check("clean-env-keeps-api-key", env.get("ANTHROPIC_API_KEY") == "sk-ant-test-SECRETVALUE")
    check("clean-env-drops-other-secrets", "GITHUB_TOKEN" not in env and "AWS_SECRET_ACCESS_KEY" not in env)
    argv = live_eval.claude_argv("hello", plugin_dir=Path("/plugin"), model=None, agents_json=None)
    check("claude-argv-is-headless-and-keyless", "--bare" not in argv and "--plugin-dir" in argv and "sk-ant-test-SECRETVALUE" not in argv)
    argv_model = live_eval.claude_argv("hello", plugin_dir=None, model="exact-model", agents_json=None)
    check("model-flag-only-when-requested", argv_model[argv_model.index("--model") + 1] == "exact-model")
    probe = live_eval.observe(
        {"result_text": "SSD-EVAL-CANARY abc", "tool_uses": [], "subagent": True},
        marker=None,
        canary="SSD-EVAL-CANARY abc",
        kind="probe",
    )
    check("agents-probe-and-role", probe["agents_md_loaded"] is True and probe["roles_dispatched"] is True)
    check("api-limit-recorded", True)
    runtime = FakeRuntime(name="anthropic-api", results=[recorded()])
    plan = {"baseline": "e732a93", "repetitions": 1, "jobs": [job()], "excluded": [], "isolated_comparison": {"status": "NOT_RUN"}}
    with tempfile.TemporaryDirectory() as tmp:
        summary = live_eval.execute_plan(
            ROOT,
            plan,
            runtime=runtime,
            ledger=live_eval.Ledger(Decimal("1")),
            secrets=[],
            estimate=None,
            rate_in=None,
            rate_out=None,
            canary="SSD-EVAL-CANARY test",
            output_dir=None,
            preparer=ready(Path(tmp), touch_hook=True),
        )
    obs = summary["results"][0]["observations"]
    check("api-adapter-does-not-claim-hooks", obs["hooks_delivered"] == "NOT_RUN" and obs["roles_dispatched"] == "NOT_RUN")


def test_stream_and_rates() -> None:
    raw = "\n".join(
        [
            json.dumps({"type": "system", "subtype": "init", "model": "exact-model"}),
            json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Skill", "input": {"skill": "coder"}}]}}),
            json.dumps({"type": "result", "result": "done", "total_cost_usd": 0.02, "usage": {"input_tokens": 5, "output_tokens": 6}}),
        ]
    )
    parsed = live_eval.parse_stream(raw)
    check("stream-cost-and-skill", parsed["cost_usd"] == Decimal("0.02") and parsed["model"] == "exact-model")
    seen = live_eval.observe(parsed, marker=None, canary=None, kind="fixture")
    check("stream-skill-observed", seen["skills_invoked"] == ["coder"])
    rated = live_eval.cost_from_rates({"input_tokens": 1000, "output_tokens": 1000}, Decimal("3"), Decimal("15"))
    check("owner-rate-cost", rated == Decimal("0.018"))
    unknown = live_eval.cost_from_rates({"input_tokens": 1, "output_tokens": 1, "cache_read_input_tokens": 4}, Decimal("3"), Decimal("15"))
    check("cache-tokens-keep-cost-unknown", unknown is None)


def test_cli_not_run_shape() -> None:
    proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "eval_driver.py"), "live"], cwd=ROOT, capture_output=True, text=True, env={"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"})
    check("cli-live-without-ceiling", proc.returncode == 2 and "NOT_RUN" in proc.stdout, proc.stdout[-200:])


def main() -> int:
    test_ceiling_stops_before_the_next_call()
    test_unknown_cost_stops_the_batch()
    test_redaction_and_result_file()
    test_adapter_error_stops()
    test_not_run_and_no_substitution()
    test_dry_run_and_plan_shape()
    test_arm_a_is_not_head()
    test_observations_and_env()
    test_stream_and_rates()
    test_cli_not_run_shape()
    print(f"SUMMARY fail={len(FAILURES)}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
