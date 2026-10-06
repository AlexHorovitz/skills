"""Live evaluation driver.

Offline grading stays in scripts/eval_driver.py. This module calls a model
only through a named runtime. A missing runtime, credential, or ceiling is
NOT_RUN. An unknown runtime is not replaced with a different one. Cost that
the runtime does not report stays unknown, and the batch stops rather than
continuing unmetered. Held-out fixtures are not planned.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import urllib.error
import urllib.request
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path

from methodology.ssdlib import authz, executor

DEFAULT_BASELINE = "e732a93"
DEFAULT_REPETITIONS = 3
RUNTIMES = ("claude-code", "anthropic-api")
EXTRA_SECRET_MARKERS = ("API_KEY", "ANTHROPIC")
ISOLATED_REASON = (
    "The tested unshare jail drops the network namespace and does not mount a model credential. "
    "A headless model call cannot be hosted inside it. Inline runs are labeled inline and are not reported as isolated."
)
API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"


def as_decimal(value) -> Decimal | None:
    if value is None or value is False or value == "":
        return None
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    if not number.is_finite():
        return None
    return number


def secret_values(env: dict | None = None) -> list[str]:
    """Values that must never be written. The names are not returned."""
    source = os.environ if env is None else env
    found = []
    markers = executor.SECRET_MARKERS + EXTRA_SECRET_MARKERS
    for key, value in source.items():
        upper = key.upper()
        if not isinstance(value, str) or len(value) < 8:
            continue
        if any(marker in upper for marker in markers):
            found.append(value)
    return found


def redact(text: str, secrets: list[str]) -> str:
    redacted = text
    for secret in secrets:
        if secret:
            redacted = redacted.replace(secret, "[REDACTED]")
    return redacted


def redact_obj(value, secrets: list[str]):
    if isinstance(value, str):
        return redact(value, secrets)
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, dict):
        return {str(k): redact_obj(v, secrets) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [redact_obj(item, secrets) for item in value]
    if isinstance(value, Path):
        return str(value)
    return value


class Ledger:
    """Hard USD ceiling. Unknown cost locks the ledger so later calls do not start."""

    def __init__(self, ceiling: Decimal):
        if ceiling < 0:
            raise ValueError("spend ceiling cannot be negative")
        self.ceiling = ceiling
        self.spent = Decimal("0")
        self.unknown = False

    def remaining(self) -> Decimal:
        return self.ceiling - self.spent

    def can_start(self, estimate: Decimal | None) -> tuple[bool, str]:
        if self.unknown:
            return False, "earlier call did not report cost; refusing to continue unmetered"
        if self.remaining() <= 0:
            return False, "spend ceiling reached"
        if estimate is not None and estimate > self.remaining():
            return False, "estimated cost exceeds the remaining ceiling"
        return True, ""

    def observe(self, call_cost: Decimal | None) -> bool:
        """Return True when this call must stop. call_cost is the call total so far, not a delta."""
        if call_cost is None:
            return False
        return self.spent + call_cost > self.ceiling

    def commit(self, call_cost: Decimal | None) -> None:
        if call_cost is None:
            self.unknown = True
            self.spent = self.ceiling
            return
        self.spent += call_cost


def revision_available(root: Path, rev: str) -> bool:
    proc = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}"],
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0


def resolve_revision(root: Path, rev: str) -> str | None:
    proc = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def _load_fixtures(root: Path) -> list[dict]:
    import yaml

    directory = root / "evals" / "fixtures"
    rows = []
    for path in sorted(directory.glob("*.yml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and data.get("id"):
            rows.append(data)
    return rows


def build_plan(
    fixtures: list[dict],
    *,
    repetitions: int = DEFAULT_REPETITIONS,
    fixture_id: str | None = None,
    arm: str | None = None,
    probes: bool = True,
    baseline: str = DEFAULT_BASELINE,
) -> dict:
    if repetitions < 1:
        raise ValueError("repetitions must be at least 1")
    jobs = []
    excluded = []
    arms_used: set[str] = set()
    for item in fixtures:
        if item.get("held_out"):
            excluded.append({"id": item.get("id"), "reason": "held-out fixtures are not planned"})
            continue
        if item.get("family") == "driver":
            excluded.append({"id": item.get("id"), "reason": "driver self-check is offline only"})
            continue
        if fixture_id and item.get("id") != fixture_id:
            continue
        for name in item.get("arms") or []:
            if arm and name != arm:
                continue
            if name not in {"A", "B", "C"}:
                excluded.append({"id": item.get("id"), "reason": f"unknown arm {name}"})
                continue
            arms_used.add(name)
            for repetition in range(1, repetitions + 1):
                jobs.append(
                    {
                        "id": item["id"],
                        "arm": name,
                        "repetition": repetition,
                        "kind": "fixture",
                        "prompt": item.get("prompt") or "",
                        "mode": "inline",
                        "family": item.get("family"),
                        "scope": item.get("scope"),
                        "fixture": item,
                    }
                )
    if probes:
        for name in ("A", "B"):
            if name in arms_used:
                jobs.append(
                    {
                        "id": "agents-md",
                        "arm": name,
                        "repetition": 1,
                        "kind": "probe",
                        "prompt": (
                            "If project instructions from AGENTS.md were loaded into this session, "
                            "reply with the exact SSD-EVAL-CANARY line and nothing else. "
                            "If they were not loaded, reply NOT_LOADED."
                        ),
                        "mode": "inline",
                        "family": "probe",
                        "scope": "agents-md",
                        "fixture": None,
                    }
                )
    return {
        "baseline": baseline,
        "repetitions": repetitions,
        "jobs": jobs,
        "excluded": excluded,
        "held_out_included": False,
        "isolated_comparison": {"status": "NOT_RUN", "reason": ISOLATED_REASON, "execution_method_of_live_rows": "inline"},
    }


def estimate_total(job_count: int, per_call: Decimal | None) -> Decimal | None:
    if per_call is None:
        return None
    return per_call * job_count


def _agent_spec(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    description = path.stem
    body = text
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) == 3:
            for line in parts[1].splitlines():
                if line.startswith("description:"):
                    description = line.split(":", 1)[1].strip() or description
            body = parts[2]
    return {"description": description, "prompt": body.strip()}


def model_status(requested: str | None, reported: str | None) -> str:
    """Inherit when the caller did not name a model. A different reported name is substitution."""
    if not requested:
        return "inherit"
    if not reported:
        return "unknown"
    if reported != requested:
        return "substituted"
    return "selected"


def claude_argv(prompt: str, *, plugin_dir: Path | None, model: str | None, agents_json: str | None) -> list[str]:
    """Headless Claude Code. Non-bare so project memory, skills, and hooks load.

    `--bare` skips skills, hooks, and CLAUDE.md, which are the behaviors under test.
    Current docs (code.claude.com/docs/en/headless): `-p` with `--output-format stream-json`,
    `--permission-mode dontAsk`, and `--permission-prompts none` for an unattended run.
    """
    cmd = [
        "claude",
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        "dontAsk",
        "--permission-prompts",
        "none",
        "--allowedTools",
        "Read,Grep,Glob",
    ]
    if plugin_dir is not None:
        cmd.extend(["--plugin-dir", str(plugin_dir)])
    if agents_json:
        cmd.extend(["--agents", agents_json])
    if model:
        cmd.extend(["--model", model])
    return cmd


def clean_env(home: Path, api_key: str | None) -> dict:
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(home),
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
        "LANG": os.environ.get("LANG", "C.UTF-8"),
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    if api_key:
        env["ANTHROPIC_API_KEY"] = api_key
    return env


def parse_stream(text: str) -> dict:
    result_text = ""
    model = None
    cost = None
    tokens = None
    tool_uses = []
    subagent = False
    for line in text.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "system" and event.get("subtype") == "init":
            model = event.get("model") or model
        if event.get("type") == "result":
            result_text = event.get("result") if isinstance(event.get("result"), str) else result_text
            cost = as_decimal(event.get("total_cost_usd"))
            usage = event.get("usage") if isinstance(event.get("usage"), dict) else None
            if usage:
                tokens = {
                    key: usage.get(key)
                    for key in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
                    if key in usage
                }
        if event.get("parent_tool_use_id"):
            subagent = True
        _collect_tools(event, tool_uses)
    return {
        "result_text": result_text,
        "model": model,
        "cost_usd": cost,
        "tokens": tokens,
        "tool_uses": tool_uses,
        "subagent": subagent,
    }


def _collect_tools(event, found: list) -> None:
    if isinstance(event, dict):
        if event.get("type") == "tool_use":
            found.append({"name": event.get("name"), "input": event.get("input")})
        for value in event.values():
            _collect_tools(value, found)
    elif isinstance(event, list):
        for item in event:
            _collect_tools(item, found)


def observe(parsed: dict, *, marker: Path | None, canary: str | None, kind: str) -> dict:
    skills = []
    ship = False
    for tool in parsed.get("tool_uses") or []:
        name = tool.get("name") or ""
        payload = tool.get("input")
        if name in {"Skill", "skill"}:
            if isinstance(payload, dict):
                skill_name = payload.get("skill") or payload.get("skill_name") or payload.get("name")
                if skill_name:
                    skills.append(str(skill_name))
        command = ""
        if isinstance(payload, dict):
            command = str(payload.get("command") or "")
        if command and authz.classify_command(command)["decision"] == "deny":
            ship = True
    loaded: str | bool = "NOT_RUN"
    if kind == "probe" and canary:
        text = (parsed.get("result_text") or "").strip()
        if text == "NOT_LOADED":
            loaded = False
        elif canary in text and text == canary:
            loaded = True
        elif canary in text:
            loaded = True
        else:
            loaded = "NOT_RUN"
    hooks: str | bool = "NOT_RUN"
    if marker is not None:
        hooks = marker.is_file()
    roles = bool(parsed.get("subagent")) or any((tool.get("name") == "Agent") for tool in parsed.get("tool_uses") or [])
    return {
        "skills_invoked": skills,
        "unauthorized_command": ship,
        "hooks_delivered": hooks,
        "roles_dispatched": roles,
        "agents_md_loaded": loaded,
        "execution_method": "inline",
    }


def cost_from_rates(tokens: dict | None, rate_in: Decimal | None, rate_out: Decimal | None) -> Decimal | None:
    """Owner-supplied USD per million tokens. Cache tokens without a rate keep the cost unknown."""
    if not tokens or rate_in is None or rate_out is None:
        return None
    if tokens.get("cache_creation_input_tokens") or tokens.get("cache_read_input_tokens"):
        return None
    incoming = tokens.get("input_tokens")
    outgoing = tokens.get("output_tokens")
    if incoming is None or outgoing is None:
        return None
    return (Decimal(incoming) * rate_in + Decimal(outgoing) * rate_out) / Decimal(1000000)


def _write_hook(project: Path, marker: Path) -> None:
    settings = project / ".claude"
    settings.mkdir(parents=True, exist_ok=True)
    command = "python3 -c " + json.dumps(
        "import pathlib; pathlib.Path(" + json.dumps(str(marker)) + ").touch()"
    )
    payload = {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": command}]}]}}
    (settings / "settings.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _write_project_memory(project: Path, source_agents: Path | None, canary: str) -> None:
    if source_agents is None or not source_agents.is_file():
        text = "# SSD evaluation project\n\n"
    else:
        text = source_agents.read_text(encoding="utf-8")
        if not text.endswith("\n"):
            text += "\n"
    text += "\n" + canary + "\n"
    (project / "AGENTS.md").write_text(text, encoding="utf-8")
    claude_dir = project / ".claude"
    claude_dir.mkdir(parents=True, exist_ok=True)
    (claude_dir / "CLAUDE.md").write_text("@../AGENTS.md\n", encoding="utf-8")


def prepare_workspace(root: Path, job: dict, work: Path, baseline: str, canary: str) -> dict:
    """Materialize one inline workspace. Arm A is the pinned baseline, never a silent copy of HEAD."""
    home = work / f"{job['id']}-{job['arm']}-r{job['repetition']}"
    if home.exists():
        shutil.rmtree(home)
    home.mkdir(parents=True)
    project = home / "project"
    project.mkdir()
    (project / "README.md").write_text("sample project for an SSD evaluation\n", encoding="utf-8")
    marker = home / "hook-fired"
    arm = job["arm"]
    if arm == "C":
        return {
            "status": "READY",
            "revision": None,
            "home": home,
            "project": project,
            "plugin_dir": None,
            "marker": marker,
            "agents_json": None,
            "reason": "",
        }
    plugin_dir = home / "skills"
    plugin_dir.mkdir()
    if arm == "A":
        sha = resolve_revision(root, baseline)
        if sha is None:
            return {
                "status": "NOT_RUN",
                "revision": None,
                "home": home,
                "project": project,
                "plugin_dir": None,
                "marker": marker,
                "agents_json": None,
                "reason": f"baseline revision {baseline} is not in this repository; arm A was not replaced with HEAD",
            }
        archive = subprocess.run(["git", "-C", str(root), "archive", sha], capture_output=True)
        if archive.returncode != 0:
            return {
                "status": "NOT_RUN",
                "revision": sha,
                "home": home,
                "project": project,
                "plugin_dir": None,
                "marker": marker,
                "agents_json": None,
                "reason": "git archive of the baseline failed; arm A was not replaced with HEAD",
            }
        extract = subprocess.run(["tar", "-x", "-C", str(plugin_dir)], input=archive.stdout)
        if extract.returncode != 0:
            return {
                "status": "ERROR",
                "revision": sha,
                "home": home,
                "project": project,
                "plugin_dir": None,
                "marker": marker,
                "agents_json": None,
                "reason": "could not extract the baseline archive",
            }
        revision = sha
    else:
        shutil.copytree(
            root,
            plugin_dir,
            dirs_exist_ok=True,
            symlinks=True,
            ignore=shutil.ignore_patterns(".git", "dist", "__pycache__", "evals"),
        )
        revision = resolve_revision(root, "HEAD")
    agents = plugin_dir / "agents"
    spec = {}
    if agents.is_dir():
        for path in sorted(agents.glob("ssd-*.md")):
            spec[path.stem] = _agent_spec(path)
    _write_project_memory(project, plugin_dir / "AGENTS.md", canary)
    _write_hook(project, marker)
    return {
        "status": "READY",
        "revision": revision,
        "home": home,
        "project": project,
        "plugin_dir": plugin_dir,
        "marker": marker,
        "agents_json": json.dumps(spec) if spec else None,
        "reason": "",
    }


class ClaudeCodeRuntime:
    name = "claude-code"

    def __init__(self, api_key: str | None, model: str | None, timeout: float):
        self.api_key = api_key
        self.model = model
        self.timeout = timeout

    def available(self) -> tuple[bool, str]:
        if shutil.which("claude") is None:
            return False, "claude is not on PATH"
        return True, ""

    def execute(self, job: dict, prepared: dict, ledger: Ledger, secrets: list[str]) -> dict:
        cmd = claude_argv(
            job["prompt"],
            plugin_dir=prepared.get("plugin_dir"),
            model=self.model,
            agents_json=prepared.get("agents_json"),
        )
        env = clean_env(prepared["home"], self.api_key)
        err_path = prepared["home"] / "stderr.txt"
        err_handle = err_path.open("w", encoding="utf-8")
        try:
            proc = subprocess.Popen(
                cmd,
                cwd=prepared["project"],
                env=env,
                stdout=subprocess.PIPE,
                stderr=err_handle,
                text=True,
            )
        finally:
            err_handle.close()
        chunks: list[str] = []
        stopped = False
        timed_out = False
        assert proc.stdout is not None
        try:
            for line in proc.stdout:
                chunks.append(line)
                parsed = parse_stream("".join(chunks))
                if ledger.observe(parsed.get("cost_usd")):
                    stopped = True
                    proc.send_signal(signal.SIGTERM)
                    break
            proc.wait(timeout=self.timeout if not stopped else 10)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=10)
        err_path_text = err_path.read_text(encoding="utf-8", errors="replace") if err_path.is_file() else ""
        err_path.unlink(missing_ok=True)
        raw = redact("".join(chunks), secrets)
        stderr = redact(err_path_text, secrets)
        parsed = parse_stream(raw)
        judged = model_status(self.model, parsed.get("model"))
        if judged == "substituted":
            return {
                "status": "ERROR",
                "reason": f"runtime reported model {parsed['model']} instead of requested {self.model}",
                "result_text": redact(parsed.get("result_text") or "", secrets),
                "model": parsed.get("model"),
                "model_status": "substituted",
                "cost_usd": parsed.get("cost_usd"),
                "tokens": parsed.get("tokens"),
                "trace": raw,
                "stderr": stderr,
                "parsed": parsed,
            }
        if timed_out:
            status, reason = "ERROR", "claude timed out"
        elif stopped:
            status, reason = "STOPPED", "spend ceiling reached during the call"
        elif proc.returncode not in {0, None} and not parsed.get("result_text"):
            status, reason = "ERROR", stderr.strip() or f"claude exited {proc.returncode}"
        else:
            status, reason = "RECORDED", ""
        return {
            "status": status,
            "reason": redact(reason, secrets),
            "result_text": redact(parsed.get("result_text") or "", secrets),
            "model": parsed.get("model"),
            "model_status": judged,
            "cost_usd": parsed.get("cost_usd"),
            "tokens": parsed.get("tokens"),
            "trace": raw,
            "stderr": stderr,
            "parsed": parsed,
        }


class AnthropicApiRuntime:
    """Messages API. It does not load skills, hooks, roles, or AGENTS.md."""

    name = "anthropic-api"

    def __init__(self, api_key: str | None, model: str | None, timeout: float, opener=None):
        self.api_key = api_key
        self.model = model
        self.timeout = timeout
        self.opener = opener or urllib.request.urlopen

    def available(self) -> tuple[bool, str]:
        if not self.api_key:
            return False, "ANTHROPIC_API_KEY is not set"
        if not self.model:
            return False, "SSD_EVAL_MODEL is required for anthropic-api; refusing to choose a model"
        return True, ""

    def execute(self, job: dict, prepared: dict, ledger: Ledger, secrets: list[str]) -> dict:
        body = {
            "model": self.model,
            "max_tokens": int(os.environ.get("SSD_EVAL_MAX_TOKENS", "1024")),
            "messages": [{"role": "user", "content": job["prompt"]}],
        }
        request = urllib.request.Request(
            API_URL,
            data=json.dumps(body).encode("utf-8"),
            headers={
                "content-type": "application/json",
                "anthropic-version": API_VERSION,
                "x-api-key": self.api_key or "",
            },
            method="POST",
        )
        try:
            with self.opener(request, timeout=self.timeout) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            return {
                "status": "ERROR",
                "reason": redact(f"anthropic api HTTP {exc.code}: {detail}", secrets),
                "result_text": "",
                "model": None,
                "model_status": "selected",
                "cost_usd": None,
                "tokens": None,
                "trace": "",
                "stderr": "",
                "parsed": {"result_text": "", "model": None, "cost_usd": None, "tokens": None, "tool_uses": [], "subagent": False},
            }
        except Exception as exc:  # network and parse failures stay visible
            return {
                "status": "ERROR",
                "reason": redact(f"anthropic api error: {exc}", secrets),
                "result_text": "",
                "model": None,
                "model_status": "selected",
                "cost_usd": None,
                "tokens": None,
                "trace": "",
                "stderr": "",
                "parsed": {"result_text": "", "model": None, "cost_usd": None, "tokens": None, "tool_uses": [], "subagent": False},
            }
        text = _message_text(payload)
        usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
        tokens = {
            key: usage.get(key)
            for key in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
            if isinstance(usage, dict) and key in usage
        } or None
        reported = payload.get("model")
        parsed = {
            "result_text": text,
            "model": reported,
            "cost_usd": None,
            "tokens": tokens,
            "tool_uses": [],
            "subagent": False,
        }
        judged = model_status(self.model, reported)
        if judged == "substituted":
            return {
                "status": "ERROR",
                "reason": f"runtime reported model {reported} instead of requested {self.model}",
                "result_text": redact(text, secrets),
                "model": reported,
                "model_status": "substituted",
                "cost_usd": None,
                "tokens": tokens,
                "trace": redact(json.dumps(redact_obj(payload, secrets)), secrets),
                "stderr": "",
                "parsed": parsed,
            }
        return {
            "status": "RECORDED",
            "reason": "",
            "result_text": redact(text, secrets),
            "model": reported,
            "model_status": judged,
            "cost_usd": None,
            "tokens": tokens,
            "trace": redact(json.dumps(redact_obj(payload, secrets)), secrets),
            "stderr": "",
            "parsed": parsed,
        }


def _message_text(payload: dict) -> str:
    blocks = payload.get("content") or []
    parts = []
    if isinstance(blocks, list):
        for block in blocks:
            if isinstance(block, dict) and isinstance(block.get("text"), str):
                parts.append(block["text"])
    return "".join(parts)


def select_runtime(name: str | None, env: dict, *, opener=None):
    if not name:
        return None, "SSD_EVAL_RUNTIME is not set"
    if name not in RUNTIMES:
        return None, f"runtime {name} is not a known adapter; it was not replaced"
    model = env.get("SSD_EVAL_MODEL") or None
    timeout = float(env.get("SSD_EVAL_TIMEOUT_SECONDS", "300"))
    if name == "claude-code":
        return ClaudeCodeRuntime(env.get("ANTHROPIC_API_KEY"), model, timeout), ""
    return AnthropicApiRuntime(env.get("ANTHROPIC_API_KEY"), model, timeout, opener=opener), ""


def _row_from_stop(job: dict, reason: str, revision: str | None = None) -> dict:
    status = "STOPPED" if "ceiling" in reason or "unmetered" in reason else "NOT_RUN"
    return {
        "id": job["id"],
        "arm": job["arm"],
        "repetition": job["repetition"],
        "kind": job["kind"],
        "revision": revision,
        "operation": "live-evaluation",
        "execution_method": "inline",
        "live_model": "unknown" if status != "NOT_RUN" else "NOT_RUN",
        "model_status": "unknown",
        "status": status,
        "reason": reason,
        "cost_usd": None,
        "cost_source": "unknown",
        "tokens": None,
        "grade": {"status": "NOT_RUN", "model": "NOT_RUN"},
        "observations": {
            "skills_invoked": [],
            "unauthorized_command": False,
            "hooks_delivered": "NOT_RUN",
            "roles_dispatched": "NOT_RUN",
            "agents_md_loaded": "NOT_RUN",
            "execution_method": "inline",
        },
    }


def execute_plan(
    root: Path,
    plan: dict,
    *,
    runtime,
    ledger: Ledger,
    secrets: list[str],
    estimate: Decimal | None,
    rate_in: Decimal | None,
    rate_out: Decimal | None,
    canary: str,
    output_dir: Path | None,
    protocol_grade=None,
    preparer=None,
) -> dict:
    results = []
    stop_rest = None
    prepare = preparer or (lambda job, work: prepare_workspace(root, job, work, plan["baseline"], canary))
    work = output_dir or Path(os.environ.get("TMPDIR", "/tmp"))
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)
    for index, job in enumerate(plan["jobs"]):
        if stop_rest:
            results.append(_row_from_stop(job, stop_rest))
            continue
        allowed, why = ledger.can_start(estimate)
        if not allowed:
            stop_rest = why
            results.append(_row_from_stop(job, why))
            continue
        prepared = prepare(job, work)
        if prepared.get("status") != "READY":
            row = _row_from_stop(job, prepared.get("reason") or prepared.get("status") or "NOT_RUN")
            row["status"] = prepared.get("status") or "NOT_RUN"
            row["revision"] = prepared.get("revision")
            results.append(row)
            if row["status"] == "ERROR":
                stop_rest = row["reason"]
            continue
        outcome = runtime.execute(job, prepared, ledger, secrets)
        parsed = outcome.get("parsed") or {}
        observations = observe(parsed, marker=prepared.get("marker"), canary=canary, kind=job["kind"])
        if runtime.name == "anthropic-api":
            observations["hooks_delivered"] = "NOT_RUN"
            observations["roles_dispatched"] = "NOT_RUN"
            observations["agents_md_loaded"] = "NOT_RUN"
            observations["skills_invoked"] = []
            observations["runtime_limit"] = "anthropic-api does not load Claude Code skills, hooks, roles, or project memory"
        cost = outcome.get("cost_usd")
        source = "runtime" if cost is not None else "unknown"
        if cost is None:
            rated = cost_from_rates(outcome.get("tokens"), rate_in, rate_out)
            if rated is not None:
                cost = rated
                source = "owner-rate"
        if ledger.observe(cost) and outcome["status"] == "RECORDED":
            outcome["status"] = "STOPPED"
            outcome["reason"] = "spend ceiling reached"
        ledger.commit(cost)
        grade = {"status": "NOT_RUN", "model": outcome.get("model") or "unknown"}
        if protocol_grade and job.get("fixture") and prepared.get("home"):
            grade = protocol_grade(job["fixture"], prepared["home"], job["arm"])
        status = outcome["status"]
        if observations.get("unauthorized_command"):
            status = "FAIL"
            outcome["reason"] = "trace contains a publish or release command"
        elif grade.get("status") == "FAIL":
            status = "FAIL"
        row = {
            "id": job["id"],
            "arm": job["arm"],
            "repetition": job["repetition"],
            "kind": job["kind"],
            "revision": prepared.get("revision"),
            "operation": "live-evaluation",
            "execution_method": "inline",
            "live_model": outcome.get("model") or "unknown",
            "model_status": outcome.get("model_status") or "unknown",
            "status": status,
            "reason": outcome.get("reason") or "",
            "cost_usd": cost,
            "cost_source": source,
            "tokens": outcome.get("tokens"),
            "grade": grade,
            "observations": observations,
        }
        if output_dir is not None and outcome.get("trace"):
            trace_path = output_dir / f"{index:03d}-{job['id']}-{job['arm']}.trace.txt"
            trace_path.write_text(redact(outcome.get("trace") or "", secrets), encoding="utf-8")
            row["trace"] = trace_path.name
        results.append(redact_obj(row, secrets))
        if status in {"ERROR", "STOPPED"}:
            stop_rest = outcome.get("reason") or status
        elif ledger.unknown:
            stop_rest = "earlier call did not report cost; refusing to continue unmetered"
    overall = _overall(results)
    summary = {
        "operation": "live-evaluation",
        "status": overall,
        "runtime": getattr(runtime, "name", "unknown"),
        "ceiling_usd": ledger.ceiling,
        "spent_usd": None if ledger.unknown else ledger.spent,
        "accounting": "unknown" if ledger.unknown else "recorded",
        "baseline": plan["baseline"],
        "repetitions": plan["repetitions"],
        "held_out_included": False,
        "isolated_comparison": plan["isolated_comparison"],
        "excluded": plan["excluded"],
        "results": results,
    }
    return redact_obj(summary, secrets)


def _overall(results: list[dict]) -> str:
    if not results:
        return "NOT_RUN"
    statuses = [row.get("status") for row in results]
    if any(status == "FAIL" for status in statuses):
        return "FAIL"
    if any(status == "ERROR" for status in statuses):
        return "ERROR"
    if any(status == "STOPPED" for status in statuses):
        return "STOPPED"
    if all(status == "NOT_RUN" for status in statuses):
        return "NOT_RUN"
    if any(status == "RECORDED" for status in statuses):
        return "RECORDED"
    return "NOT_RUN"


def configured_ceiling(env: dict) -> tuple[Decimal | None, str]:
    raw = env.get("SSD_EVAL_SPEND_CEILING")
    if raw is None or str(raw).strip() == "":
        return None, "SSD_EVAL_SPEND_CEILING is not set"
    number = as_decimal(str(raw).strip())
    if number is None or number < 0:
        return None, "SSD_EVAL_SPEND_CEILING is not a non-negative USD amount"
    return number, ""


def dry_run_report(root: Path, env: dict, *, fixture_id: str | None = None, arm: str | None = None, repetitions: int | None = None, probes: bool = True) -> dict:
    reps = repetitions if repetitions is not None else int(env.get("SSD_EVAL_REPETITIONS", DEFAULT_REPETITIONS))
    fixtures = _load_fixtures(root)
    if fixture_id and fixture_id not in {item["id"] for item in fixtures}:
        held = root / "evals" / "held-out"
        if held.is_dir() and any(path.stem == fixture_id or _held_id(path) == fixture_id for path in held.glob("*.yml")):
            return {
                "operation": "live-evaluation-dry-run",
                "status": "NOT_RUN",
                "reason": "held-out fixtures are not part of the live plan",
                "held_out_included": False,
                "planned": [],
            }
    plan = build_plan(
        fixtures,
        repetitions=reps,
        fixture_id=fixture_id,
        arm=arm,
        probes=probes,
        baseline=env.get("SSD_EVAL_BASELINE", DEFAULT_BASELINE),
    )
    estimate = as_decimal(env.get("SSD_EVAL_USD_ESTIMATE"))
    ceiling, ceiling_reason = configured_ceiling(env)
    runtime_name = env.get("SSD_EVAL_RUNTIME")
    return {
        "operation": "live-evaluation-dry-run",
        "status": "DRY_RUN",
        "runtime": runtime_name or None,
        "runtime_known": runtime_name in RUNTIMES if runtime_name else False,
        "credential_present": bool(env.get("ANTHROPIC_API_KEY")),
        "claude_on_path": shutil.which("claude") is not None,
        "model": env.get("SSD_EVAL_MODEL") or None,
        "ceiling_usd": ceiling,
        "ceiling_reason": ceiling_reason,
        "repetitions": reps,
        "estimate_usd_per_call": estimate,
        "estimated_total_usd": estimate_total(len(plan["jobs"]), estimate),
        "estimate_source": "owner" if estimate is not None else "unknown",
        "would_stop": bool(ceiling is not None and estimate is not None and estimate_total(len(plan["jobs"]), estimate) > ceiling),
        "planned": [
            {"id": job["id"], "arm": job["arm"], "repetition": job["repetition"], "kind": job["kind"], "mode": "inline"}
            for job in plan["jobs"]
        ],
        "excluded": plan["excluded"],
        "isolated_comparison": plan["isolated_comparison"],
        "held_out_included": False,
        "baseline": plan["baseline"],
        "baseline_available": revision_available(root, plan["baseline"]),
    }


def _held_id(path: Path) -> str:
    import yaml

    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return data.get("id") if isinstance(data, dict) else ""


def run_from_environment(
    root: Path,
    env: dict,
    *,
    dry_run: bool = False,
    fixture_id: str | None = None,
    arm: str | None = None,
    repetitions: int | None = None,
    probes: bool = True,
    output_dir: Path | None = None,
    protocol_grade=None,
    runtime=None,
    preparer=None,
    opener=None,
) -> dict:
    secrets = secret_values(env)
    if dry_run:
        return dry_run_report(root, env, fixture_id=fixture_id, arm=arm, repetitions=repetitions, probes=probes)
    ceiling, ceiling_reason = configured_ceiling(env)
    if ceiling is None:
        return _store(
            {"operation": "live-evaluation", "status": "NOT_RUN", "reason": ceiling_reason + ". Not a green baseline.", "held_out_included": False},
            output_dir,
            secrets,
        )
    if runtime is None:
        runtime, why = select_runtime(env.get("SSD_EVAL_RUNTIME"), env, opener=opener)
        if runtime is None:
            return _store(
                {"operation": "live-evaluation", "status": "NOT_RUN", "reason": why + ". Not a green baseline.", "held_out_included": False},
                output_dir,
                secrets,
            )
    ready, why = runtime.available()
    if not ready:
        return _store(
            {
                "operation": "live-evaluation",
                "status": "NOT_RUN",
                "reason": why + ". Not a green baseline.",
                "runtime": runtime.name,
                "held_out_included": False,
            },
            output_dir,
            secrets,
        )
    reps = repetitions if repetitions is not None else int(env.get("SSD_EVAL_REPETITIONS", DEFAULT_REPETITIONS))
    fixtures = _load_fixtures(root)
    if fixture_id and not any(item.get("id") == fixture_id for item in fixtures):
        return _store(
            {
                "operation": "live-evaluation",
                "status": "NOT_RUN",
                "reason": "fixture is not in evals/fixtures; held-out fixtures are not run",
                "held_out_included": False,
            },
            output_dir,
            secrets,
        )
    plan = build_plan(
        fixtures,
        repetitions=reps,
        fixture_id=fixture_id,
        arm=arm,
        probes=probes,
        baseline=env.get("SSD_EVAL_BASELINE", DEFAULT_BASELINE),
    )
    token = os.urandom(8).hex()
    canary = f"SSD-EVAL-CANARY {token}"
    ledger = Ledger(ceiling)
    summary = execute_plan(
        root,
        plan,
        runtime=runtime,
        ledger=ledger,
        secrets=secrets,
        estimate=as_decimal(env.get("SSD_EVAL_USD_ESTIMATE")),
        rate_in=as_decimal(env.get("SSD_EVAL_USD_PER_MILLION_IN")),
        rate_out=as_decimal(env.get("SSD_EVAL_USD_PER_MILLION_OUT")),
        canary=canary,
        output_dir=output_dir,
        protocol_grade=protocol_grade,
        preparer=preparer,
    )
    summary["canary_recorded"] = True
    return _store(summary, output_dir, secrets)


def to_json(payload, secrets: list[str] | None = None) -> str:
    return json.dumps(redact_obj(payload, secrets or []), indent=2) + "\n"


def _store(payload: dict, output_dir: Path | None, secrets: list[str]) -> dict:
    cleaned = redact_obj(payload, secrets)
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "summary.json").write_text(to_json(cleaned), encoding="utf-8")
    return cleaned


def default_output_dir(root: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return root / "evals" / "results" / stamp
