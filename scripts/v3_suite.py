#!/usr/bin/env python3
"""Deterministic SSD 3.0 checks.

Live model calls, native Claude plugin validation, and in-session instruction
loading are not this script. Those stay NOT_RUN. A check that did not run is
printed as NOT_RUN and is not counted as a pass.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from methodology.ssdlib import (  # noqa: E402
    authz,
    evidence,
    executor,
    findings,
    lifecycle,
    modelsel,
    paths,
    portable,
    resume,
    schemas,
    skillmeta,
    state,
)
from methodology.ssdlib import doctor as doctor_mod  # noqa: E402

PASS = 0
FAIL = 0
NOT_RUN = 0
ROWS: list[dict] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    status = "PASS" if ok else "FAIL"
    if ok:
        PASS += 1
    else:
        FAIL += 1
    ROWS.append({"name": name, "status": status, "detail": detail})
    print(f"{status} {name}" + (f" :: {detail}" if detail and not ok else ""))


def note(name: str, detail: str) -> None:
    global NOT_RUN
    NOT_RUN += 1
    ROWS.append({"name": name, "status": "NOT_RUN", "detail": detail})
    print(f"NOT_RUN {name} :: {detail}")


def git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, text=True)


def init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True, capture_output=True)
    git(path, "config", "user.email", "v3@test.local")
    git(path, "config", "user.name", "v3")
    git(path, "config", "commit.gpgsign", "false")
    (path / "README.md").write_text("sample\n", encoding="utf-8")
    git(path, "add", "README.md")
    git(path, "commit", "-qm", "init")


def skill_text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_metadata() -> None:
    results, errors = skillmeta.check_tree(ROOT)
    check("skill-frontmatter-tree", errors == 0, "; ".join(r["detail"] for r in results if r["status"] != "PASS"))
    for rel, phrases in {
        "ssd-init/SKILL.md": ["Idempotent", "Never replace", "test_command", "CLAUDE.md", "selective"],
        "systems-designer/SKILL.md": ["block condition"],
        "code-reviewer/SKILL.md": ["BLOCKER", "gate_pass"],
        "software-standards/SKILL.md": ["Hard Truth"],
        "feynman/SKILL.md": ["explicitly invokes", "--force"],
        "ssd/SKILL.md": ["Rule zero", "--force", "propose"],
    }.items():
        text = skill_text(rel)
        missing = [p for p in phrases if p not in text]
        check(f"invariant-text {rel}", not missing, ",".join(missing))
        links_ok = True
        detail = ""
        import re
        for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text):
            target = target.split()[0]
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            path = (ROOT / rel).parent / target.split("#", 1)[0]
            if not path.exists():
                links_ok = False
                detail = target
                break
        check(f"links {rel}", links_ok, detail)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        cases = {
            "missing-frontmatter": ("# Title\n**Version:** 1.0.0\n", "FAIL"),
            "bad-yaml": ("---\nname: [unterminated\n---\n**Version:** 1.0.0\n", "FAIL"),
            "duplicate-key": ("---\nname: duplicate-key\nname: duplicate-key\ndescription: x\n---\n**Version:** 1.0.0\n", "FAIL"),
            "long-desc": (
                "---\nname: long-desc\ndescription: " + ("x" * 1025) + "\n---\n**Version:** 1.0.0\n",
                "FAIL",
            ),
            "version-drift": (
                "---\nname: version-drift\ndescription: ok\nmetadata:\n  version: \"9.9.9\"\n---\n**Version:** 1.0.0\n",
                "FAIL",
            ),
            "name-mismatch": (
                "---\nname: other\ndescription: ok\n---\n**Version:** 1.0.0\n",
                "FAIL",
            ),
        }
        for dirname, (body, expect) in cases.items():
            skill = root / dirname
            skill.mkdir()
            (skill / "SKILL.md").write_text(body, encoding="utf-8")
            got = skillmeta.check_file(skill / "SKILL.md")["status"]
            check(f"lint-negative {dirname}", got == expect, got)
        old = skillmeta.yaml
        skillmeta.yaml = None
        try:
            got = skillmeta.check_file(root / "name-mismatch" / "SKILL.md")
            check("lint-missing-parser", got["status"] == "ERROR", got["status"])
        finally:
            skillmeta.yaml = old


def test_paths_and_state() -> None:
    described = paths.describe(ROOT)
    check("library-root", Path(described["library_root"]) == ROOT, described["library_root"])
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp) / "my project"
        init_repo(project)
        legacy = paths.legacy_validator_path(project)
        resolved = paths.resolve_validator(project, ROOT)
        check("legacy-validator-misses-external-project", legacy is None)
        check(
            "library-validator-fallback",
            resolved == (ROOT / "methodology" / "frontmatter-validate.py").resolve(),
            str(resolved),
        )
        check("missing-ssd-proposes-init", state.classify(project)["status"] == "missing")
        (project / ".ssd").mkdir()
        (project / ".ssd" / "project.yml").write_text("", encoding="utf-8")
        check("empty-yaml-is-corrupt", state.classify(project)["status"] == "corrupt")
        (project / ".ssd" / "project.yml").write_text("[]\n", encoding="utf-8")
        check("non-mapping-is-corrupt", state.classify(project)["status"] == "corrupt")
        (project / ".ssd" / "project.yml").write_text("project:\n  name: t\n", encoding="utf-8")
        check("mapping-is-valid", state.classify(project)["status"] == "valid")
        shutil.rmtree(project / ".ssd")
        (project / ".ssd").symlink_to(project / "no-such-store")
        check("dangling-store-is-unreadable", state.classify(project)["status"] == "unreadable")
        main = Path(tmp) / "main-repo"
        init_repo(main)
        wt = Path(tmp) / "linked-tree"
        subprocess.run(["git", "-C", str(main), "worktree", "add", "-q", str(wt), "-b", "wt"], check=True, capture_output=True)
        check("linked-worktree", paths.worktree_is_linked(wt))
        check("worktree-toplevel", paths.worktree_root(wt) == wt.resolve())


def test_schemas() -> None:
    problems = schemas.in_sync(ROOT / "methodology" / "schemas", ROOT / "methodology" / "schemas" / "json")
    check("schemas-in-sync", not problems, "; ".join(problems))
    proc = subprocess.run(
        [sys.executable, str(ROOT / "methodology" / "frontmatter-validate.py")],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    fails = [line for line in proc.stdout.splitlines() if line.startswith("FAIL ")]
    check("historical-frontmatter", proc.returncode == 0 and not fails, fails[:3].__repr__())
    skeptic = (ROOT / "methodology" / "schemas" / "codebase-skeptic.yml").is_file()
    refactor = (ROOT / "methodology" / "schemas" / "refactor.yml").is_file()
    check("skeptic-schema-exists", skeptic)
    check("refactor-plan-stays-unmatched", not refactor)
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "01-architect.md"
        bad.write_text("---\nskill: architect\nversion: 1\n---\n", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(ROOT / "methodology" / "frontmatter-validate.py"), str(bad)],
            capture_output=True,
            text=True,
        )
        check("incomplete-new-artifact-fails", proc.returncode != 0 and "FAIL " in proc.stdout)


def test_doctor_and_setup() -> None:
    before = subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain"], text=True)
    report = doctor_mod.doctor(ROOT)
    after = subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain"], text=True)
    check("doctor-no-writes", report["writes"] == 0 and before == after)
    check("doctor-no-network", report["network"] == "not-attempted")
    names = {row["name"] for row in report["capabilities"]}
    check("doctor-capability-rows", len(names) >= 11, str(len(names)))
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp) / "app"
        project.mkdir()
        (project / "Makefile").write_text("test:\n\ttouch RAN\n", encoding="utf-8")
        found = lifecycle.discover_test_commands(project)
        check("discover-does-not-execute", found and found[0]["executed"] is False and not (project / "RAN").exists())
        snap = {p.name for p in project.iterdir()}
        plan = lifecycle.plan(project, library=ROOT)
        check("setup-plan-writes-nothing", plan["writes"] == 0 and {p.name for p in project.iterdir()} == snap)
        text = "Keep this.\n"
        (project / "AGENTS.md").write_text(text, encoding="utf-8")
        merged = lifecycle.merge_managed(project / "AGENTS.md", "project-instructions", "SSD block")
        check("managed-block-keeps-user-text", merged.startswith("Keep this."))
        stripped = lifecycle.strip_managed(merged)
        check("strip-removes-only-managed-block", stripped.strip() == "Keep this.")
        (project / ".ssd").mkdir()
        (project / ".ssd" / "notes.txt").write_text("history\n", encoding="utf-8")
        (project / ".git" / "hooks").mkdir(parents=True)
        foreign = project / ".git" / "hooks" / "pre-commit"
        foreign.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        removed = lifecycle.remove(project, library=ROOT)
        check("remove-keeps-history-and-foreign-hook", (project / ".ssd" / "notes.txt").is_file() and foreign.is_file() and removed["status"] == "PASS")
        (project / ".ssd" / "format").write_text("4\n", encoding="utf-8")
        raised = False
        try:
            lifecycle.assert_can_write(project, "2.14.0")
        except RuntimeError:
            raised = True
        check("older-library-refuses-newer-format", raised)
        lifecycle.assert_can_write(project, "9.0.0")
        (project / ".ssd" / "format").unlink()
        lifecycle.assert_can_write(project, "2.14.0")
        check("absent-format-marker-unchanged", True)


def test_portable_and_plugin() -> None:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    plugin = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    market = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8"))
    check("plugin-version-matches-library", plugin.get("version") == version and market["plugins"][0]["version"] == version, plugin.get("version"))
    skills = plugin.get("skills") or []
    check("plugin-lists-methodology", "./methodology" in skills)
    check("plugin-has-no-bin", "bin" not in json.dumps(plugin))
    check("plugin-skills-exist", all((ROOT / p.lstrip("./")).is_dir() for p in skills))
    agents = ["ssd-architect.md", "ssd-coder.md", "ssd-reviewer.md"]
    check("three-role-files", all((ROOT / "agents" / name).is_file() for name in agents))
    reviewer = (ROOT / "agents" / "ssd-reviewer.md").read_text(encoding="utf-8")
    check("reviewer-tools-are-read-only", "Bash" not in reviewer.split("---", 2)[1])
    hooks = json.loads((ROOT / "hooks" / "hooks.json").read_text(encoding="utf-8"))
    check("hooks-wrapped", isinstance(hooks.get("hooks"), dict) and "PreToolUse" in hooks["hooks"])
    agents_md = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    check("agents-md-under-200", len(agents_md.splitlines()) < 200, str(len(agents_md.splitlines())))
    check("claude-imports-agents", (ROOT / "CLAUDE.md").read_text(encoding="utf-8").strip() == "@AGENTS.md")
    note("in-session-instruction-loading", "claude is not installed; file import was not executed in a session")
    note("native-plugin-validate", "claude plugin validate was not run")
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / "portable"
        result = portable.export(ROOT, dest)
        check("portable-closure", not result["problems"], "; ".join(result["problems"][:5]))
        manifest = json.loads((dest / "portable-manifest.json").read_text(encoding="utf-8"))
        check("portable-unattended-off", manifest.get("unattended_run") is False and manifest.get("enforcement") == "none")
        bundled = (dest / "feynman" / "SKILL.md").read_text(encoding="utf-8")
        front = bundled.split("---", 2)[1]
        check("portable-strips-host-field", "disable-model-invocation" not in front)
        check("portable-keeps-explicit-invocation", "explicitly invokes" in bundled)


def test_authz_and_hook() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp) / "proj"
        control = Path(tmp) / "control"
        project.mkdir()
        control.mkdir()
        env_worker = os.environ.get("SSD_WORKER")
        env_control = os.environ.get("SSD_CONTROL_DIR")
        os.environ["SSD_CONTROL_DIR"] = str(control)
        os.environ.pop("SSD_WORKER", None)
        try:
            (project / ".ssd" / "control").mkdir(parents=True)
            (project / ".ssd" / "control" / "grants.yml").write_text(
                "grants:\n  - {action: ship, snapshot: abc, uses_remaining: 5, repo: forged}\n",
                encoding="utf-8",
            )
            denied = authz.check(project, action="ship", snapshot="abc")
            check("in-repo-grant-ignored", denied["allowed"] is False)
            os.environ["SSD_WORKER"] = "1"
            worker_blocked = False
            try:
                authz.grant(project, action="ship", snapshot="abc")
            except PermissionError:
                worker_blocked = True
            check("worker-cannot-grant", worker_blocked)
            os.environ.pop("SSD_WORKER", None)
            authz.grant(project, action="ship", snapshot="abc", uses=1)
            allowed = authz.check(project, action="ship", snapshot="abc", consume=True)
            again = authz.check(project, action="ship", snapshot="abc", consume=True)
            other = authz.check(project, action="ship", snapshot="def")
            check("grant-consumed-once", allowed["allowed"] is True and again["allowed"] is False)
            check("grant-bound-to-snapshot", other["allowed"] is False)
            closed = authz.guarded(project, "git push origin main", guard_present=False)
            check("missing-guard-fails-closed", closed["decision"] == "deny" and closed["executed"] is False)
            denied_cmd = authz.classify_command("git push origin main")
            allowed_cmd = authz.classify_command("git status")
            check("command-pattern-is-supplemental", denied_cmd["decision"] == "deny" and allowed_cmd["decision"] == "allow")
        finally:
            if env_worker is None:
                os.environ.pop("SSD_WORKER", None)
            else:
                os.environ["SSD_WORKER"] = env_worker
            if env_control is None:
                os.environ.pop("SSD_CONTROL_DIR", None)
            else:
                os.environ["SSD_CONTROL_DIR"] = env_control
    hook = ROOT / "methodology" / "hooks" / "ssd_hook.py"

    def run_hook(payload: str) -> dict:
        proc = subprocess.run([sys.executable, str(hook)], input=payload, capture_output=True, text=True)
        check_rc = proc.returncode == 0
        if not check_rc:
            return {"_rc": proc.returncode, "_err": proc.stderr}
        return json.loads(proc.stdout)

    empty = run_hook("")
    check("hook-empty-is-not-approval", "permissionDecision" not in json.dumps(empty))
    malformed = run_hook("{")
    check("hook-malformed-is-not-approval", "permissionDecision" not in json.dumps(malformed))
    denied = run_hook(json.dumps({
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "git push origin main"},
    }))
    decision = (denied.get("hookSpecificOutput") or {}).get("permissionDecision")
    check("hook-denies-default-branch-push", decision == "deny", json.dumps(denied)[:200])
    post = run_hook(json.dumps({"hook_event_name": "PostToolUse", "tool_name": "Bash"}))
    check("hook-post-tool-is-feedback", "already ran" in post.get("systemMessage", ""))
    stop = run_hook(json.dumps({"hook_event_name": "Stop", "stop_hook_active": True}))
    check("hook-stop-does-not-loop", "not looping" in stop.get("systemMessage", ""))


def test_executor() -> None:
    ok, detail = executor.mechanism_available()
    if not ok:
        note("executor-jail", detail)
        return
    with tempfile.TemporaryDirectory() as tmp:
        snap = Path(tmp) / "snap"
        out = Path(tmp) / "out"
        snap.mkdir()
        (snap / "ok.txt").write_text("data\n", encoding="utf-8")
        secret = Path(tmp) / "secret.txt"
        secret.write_text("top-secret\n", encoding="utf-8")
        (snap / "leak").symlink_to(secret)
        os.environ["SECRET_TOKEN"] = "hunter2"
        try:
            escaped = executor.run(snap, ["cat", "/src/leak"], out, timeout=20)
            host_read = executor.run(snap, ["cat", str(secret)], out, timeout=20)
            printed = executor.run(snap, ["sh", "-c", "printf %s \"${SECRET_TOKEN:-EMPTY}\""], out, timeout=20)
            wrote = executor.run(snap, ["sh", "-c", "echo hi > /out/hello.txt"], out, timeout=20)
            mutated = executor.run(snap, ["sh", "-c", "echo pwned > /src/pwned"], out, timeout=20)
            net = executor.run(
                snap,
                ["python3", "-c", "import socket; socket.create_connection(('1.1.1.1', 443), 2)"],
                out,
                timeout=20,
            )
        finally:
            os.environ.pop("SECRET_TOKEN", None)
        check("jail-symlink-does-not-resolve", escaped["status"] == "FAIL", escaped.get("stderr", "")[:180])
        check("jail-absolute-host-path-fails", host_read["status"] == "FAIL", str(host_read.get("exit_code")))
        check("jail-strips-secret-env", printed["status"] == "PASS" and printed["stdout"].strip() == "EMPTY", printed["stdout"])
        hello = out / "hello.txt"
        check("jail-output-dir", wrote["status"] == "PASS" and hello.is_file() and "hi" in hello.read_text(encoding="utf-8"))
        check("jail-snapshot-not-mutated", mutated["snapshot_mutated"] is False and not (snap / "pwned").exists())
        check("jail-network-blocked", net["status"] == "FAIL", str(net.get("exit_code")))


def test_findings_and_models() -> None:
    snapshot = "snap-1"
    report = {
        "gate_pass": True,
        "reviewed_snapshot": snapshot,
        "findings": [
            {"id": "crit-1", "severity": "BLOCKER", "verification_status": "confirmed", "location": "a.py:1", "evidence": "boom"},
        ],
    }
    missing_runner = findings.certify(report, snapshot=snapshot, runner=None)
    check("missing-runner-is-not-run", missing_runner["status"] == "NOT_RUN")
    check("model-gate-pass-ignored", missing_runner["authoritative_gate_pass"] is False)
    stale = findings.certify(report, snapshot="other", runner={"status": "PASS", "snapshot": "other"})
    check("stale-review-fails", stale["status"] == "FAIL")
    clean = {
        "gate_pass": False,
        "reviewed_snapshot": snapshot,
        "findings": [],
    }
    certified = findings.certify(clean, snapshot=snapshot, runner={"status": "PASS", "snapshot": snapshot})
    check("runner-pass-and-no-blockers", certified["status"] == "PASS")
    graded = findings.grade_review(
        {"findings": [{"id": "crit-1", "severity": "BLOCKER"}]},
        {"crit-1": {"severity": "critical", "present": True}, "false-1": {"severity": "major", "present": False}},
    )
    check("planted-critical-detected", graded["critical_missed"] == [] and graded["false_positives"] == [])
    missed = findings.grade_review({"findings": []}, {"crit-1": {"severity": "critical", "present": True}})
    check("missed-critical-stays-visible", missed["critical_missed"] == ["crit-1"])
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp)
        (project / ".ssd").mkdir()
        (project / ".ssd" / "project.yml").write_text("ssd:\n  gitignore_mode: selective\n", encoding="utf-8")
        inherited = modelsel.resolve(project, supported_models={"local-model"})
        check("omitted-model-is-inherit", inherited["behavior_change"] is False and inherited["roles"]["reviewer"]["effective_identity"] == "unknown")
        (project / ".ssd" / "project.yml").write_text(
            "ssd:\n  models:\n    reviewer: not-a-real-model\n",
            encoding="utf-8",
        )
        rejected = modelsel.resolve(project, supported_models={"local-model"})
        check("unsupported-model-not-substituted", rejected["roles"]["reviewer"]["model_status"] == "unsupported" and rejected["roles"]["reviewer"]["effective_model"] == "inherit")
        (project / ".ssd" / "project.yml").write_text(
            "ssd:\n  models:\n    reviewer: local-model\n",
            encoding="utf-8",
        )
        selected = modelsel.resolve(project, supported_models={"local-model"})
        check("explicit-supported-model", selected["roles"]["reviewer"]["effective_model"] == "local-model")


def test_evidence_and_resume() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp) / "proj"
        init_repo(project)
        none = evidence.check(project)
        check("no-evidence-is-not-run", none["status"] == "NOT_RUN")
        evidence.record(project, results=[{"status": "PASS", "rule": "tests-pass"}], command="true")
        fresh = evidence.check(project)
        check("evidence-matches-snapshot", fresh["status"] == "PASS")
        (project / "README.md").write_text("changed\n", encoding="utf-8")
        stale = evidence.check(project)
        check("dirty-snapshot-invalidates-evidence", stale["status"] == "FAIL")
        summary = evidence.summarize("SKIP tests-pass :: no command\n", snapshot={"head": "abc"})
        check("skip-summarizes-as-not-run", summary["status"] == "NOT_RUN")
        run = project / ".ssd" / "features" / "feat" / "auto-runs"
        run.mkdir(parents=True)
        (run / "20261005T000000Z-run.md").write_text(
            "---\nskill: ssd\nversion: 3.0.0\nproduced_at: 2026-10-05T00:00:00Z\nproduced_by: test\n"
            "project: t\nscope: feat\nconsumed_by: []\nrun:\n  stop_reason: null\n  input_fingerprint: fp1\n"
            "  transitions:\n    - {from: design, to: code}\n  budgets:\n    transitions: 4\n---\nbody\n",
            encoding="utf-8",
        )
        ready = resume.resume(project, "20261005T000000Z-run.md", snapshot="fp1", worker_alive="dead")
        check("resume-same-record", ready["state"] == "ok" and ready["consumed_transitions"] == 1 and ready["shipping"] == "not-authorized")
        alive = resume.resume(project, "20261005T000000Z-run.md", worker_alive="alive")
        check("resume-live-worker-stops", alive["reason"] == "FM-2")
        conflict = resume.resume(project, "20261005T000000Z-run.md", snapshot="other", worker_alive="dead")
        check("resume-fingerprint-conflict", conflict["reason"] == "STOP-4")
        text = (run / "20261005T000000Z-run.md").read_text(encoding="utf-8")
        (run / "20261005T000000Z-run.md").write_text(text.replace("stop_reason: null", "stop_reason: STOP-1"), encoding="utf-8")
        finished = resume.resume(project, "20261005T000000Z-run.md", worker_alive="dead")
        check("resume-does-not-reset-finished-run", finished["reason"] == "STOP-4" and finished["shipping"] == "not-restored")


def test_eval_driver() -> None:
    proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "eval_driver.py"), "validate"], cwd=ROOT, capture_output=True, text=True)
    check("eval-offline-validate", proc.returncode == 0, proc.stdout[-300:])
    arm_c = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "eval_driver.py"), "run", "--fixture", "ev03-bare-ssd", "--arm", "C"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    check("eval-arm-c", arm_c.returncode == 0 and "NOT_RUN" in arm_c.stdout, arm_c.stdout[-200:])
    planted = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "eval_driver.py"), "run", "--fixture", "planted-fail-candidate", "--arm", "B"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    check("eval-planted-candidate-fails", planted.returncode == 1, planted.stdout[-200:])
    bad = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "eval_driver.py"), "run", "--fixture", "planted-bad-grader", "--arm", "B"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    check("eval-planted-grader-fails", bad.returncode == 1)
    env = os.environ.copy()
    env.pop("SSD_EVAL_SPEND_CEILING", None)
    env.pop("SSD_EVAL_RUNTIME", None)
    live = subprocess.run([sys.executable, str(ROOT / "scripts" / "eval_driver.py"), "live"], cwd=ROOT, capture_output=True, text=True, env=env)
    check("eval-live-without-ceiling-is-not-run", live.returncode == 2 and "NOT_RUN" in live.stdout)
    manifest = None
    try:
        data = json.loads(arm_c.stdout)
        manifest = data.get("manifest")
    except json.JSONDecodeError:
        manifest = None
    if manifest and Path(manifest).is_file():
        repro = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "eval_driver.py"), "reproduce", "--manifest", manifest],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        check("eval-reproduce", repro.returncode == 0 and "recorded_revision" in repro.stdout)
    else:
        note("eval-reproduce", "arm C manifest was not written")
    note("eval-live-model-repetitions", "no model runtime and no spend ceiling; three live repetitions were not executed")
    note("five-user-pilot", "no five-user session was run; deferred to the owner")


def main() -> int:
    test_metadata()
    test_paths_and_state()
    test_schemas()
    test_doctor_and_setup()
    test_portable_and_plugin()
    test_authz_and_hook()
    test_executor()
    test_findings_and_models()
    test_evidence_and_resume()
    test_eval_driver()
    out = Path("/tmp/ssd-v3-suite.json")
    out.write_text(json.dumps({"pass": PASS, "fail": FAIL, "not_run": NOT_RUN, "rows": ROWS}, indent=2) + "\n", encoding="utf-8")
    print(f"SUMMARY pass={PASS} fail={FAIL} not_run={NOT_RUN}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
