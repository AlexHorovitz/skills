#!/usr/bin/env python3
"""Neutral evaluation driver.

Offline validation and live model execution are different operations.
A missing runtime, credential, or spend ceiling prints NOT_RUN and exits 2.
It never records a green baseline and never substitutes a different runtime.
Graders and ground truth live under evals/, which workers are not given as a
writable output directory.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "evals" / "fixtures"
HELD_OUT = ROOT / "evals" / "held-out"


def _load(path: Path) -> dict:
    import yaml

    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or "id" not in data:
        raise ValueError(f"{path} is not a fixture")
    return data


def fixtures() -> list[dict]:
    return [_load(path) for path in sorted(FIXTURES.glob("*.yml"))]


def validate_offline() -> dict:
    import yaml  # noqa: F401 — fail visibly if missing

    rows = []
    errors = 0
    for item in fixtures():
        problems = []
        if "prompt" not in item:
            problems.append("missing prompt")
        if "arms" not in item:
            problems.append("missing arms")
        if item.get("held_out"):
            problems.append("held-out fixture is in the tuning set")
        status = "FAIL" if problems else "PASS"
        if problems:
            errors += 1
        rows.append({"id": item["id"], "status": status, "problems": problems})
    held = sorted(p.name for p in HELD_OUT.glob("*.yml")) if HELD_OUT.is_dir() else []
    return {"operation": "offline-validation", "results": rows, "errors": errors, "held_out": held}


def _isolate(arm: str, library: Path) -> Path:
    home = Path(tempfile.mkdtemp(prefix=f"ssd-eval-{arm}-"))
    repo = home / "repo"
    repo.mkdir()
    (repo / "README.md").write_text("sample project\n", encoding="utf-8")
    if arm == "C":
        # No skills, hooks, instructions, or state hints.
        return home
    dest = home / "skills"
    if arm == "A":
        # Unchanged product is the pinned revision's tree. This driver copies
        # the checkout it was launched from and records that revision; it does
        # not rewrite prompts.
        shutil.copytree(library, dest, symlinks=True, ignore=shutil.ignore_patterns(".git", "dist", "__pycache__"))
    elif arm == "B":
        shutil.copytree(library, dest, symlinks=True, ignore=shutil.ignore_patterns(".git", "dist", "__pycache__"))
    else:
        raise ValueError(f"unknown arm {arm}")
    return home


def _grade(fixture: dict, home: Path, arm: str) -> dict:
    """Deterministic protocol grader. Does not call a model."""
    skills = home / "skills"
    has_skills = skills.is_dir() and any(skills.glob("*/SKILL.md"))
    expect = (fixture.get("expect") or {}).get("protocol") or {}
    problems = []
    if arm == "C":
        if has_skills:
            problems.append("no-SSD arm contains skills")
        # Absence of an SSD command is not a failure.
        return {"status": "PASS" if not problems else "FAIL", "problems": problems, "model": "NOT_RUN"}
    if not has_skills:
        problems.append(f"arm {arm} lost the skill tree")
    if fixture.get("planted_grade") == "fail":
        problems.append("planted failing candidate")
    if fixture.get("planted_grader") == "bad-input":
        problems.append("grader rejected the input")
    return {"status": "PASS" if not problems else "FAIL", "problems": problems, "model": "NOT_RUN"}


def run_offline(fixture_id: str, arm: str) -> dict:
    fixture = next(item for item in fixtures() if item["id"] == fixture_id)
    if arm not in fixture.get("arms", []):
        return {
            "id": fixture_id,
            "arm": arm,
            "status": "NOT_RUN",
            "reason": "fixture does not apply to this arm",
            "operation": "offline-execution",
        }
    revision = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    home = _isolate(arm, ROOT)
    try:
        graded = _grade(fixture, home, arm)
        manifest = {
            "id": fixture_id,
            "arm": arm,
            "revision": revision,
            "home": str(home),
            "operation": "offline-execution",
            "live_model": "NOT_RUN",
            "grade": graded,
        }
        (home / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        manifest["manifest"] = str(home / "manifest.json")
        return manifest
    except Exception:
        shutil.rmtree(home, ignore_errors=True)
        raise


def run_live(args=None, env: dict | None = None) -> dict:
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from methodology.ssdlib import live_eval

    source = os.environ if env is None else env
    dry_run = bool(getattr(args, "dry_run", False))
    fixture_id = getattr(args, "fixture", None)
    arm = getattr(args, "arm", None)
    repetitions = getattr(args, "repetitions", None)
    probes = not bool(getattr(args, "no_probes", False))
    output = None
    if not dry_run and source.get("SSD_EVAL_RUNTIME") and source.get("SSD_EVAL_SPEND_CEILING"):
        chosen = getattr(args, "output", None)
        output = Path(chosen) if chosen else live_eval.default_output_dir(ROOT)
    return live_eval.run_from_environment(
        ROOT,
        source,
        dry_run=dry_run,
        fixture_id=fixture_id,
        arm=arm,
        repetitions=repetitions,
        probes=probes,
        output_dir=output,
        protocol_grade=_grade,
    )


def reproduce(manifest_path: Path) -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    current = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    return {
        "id": data.get("id"),
        "arm": data.get("arm"),
        "recorded_revision": data.get("revision"),
        "current_revision": current,
        "same_revision": data.get("revision") == current,
        "recorded_grade": data.get("grade"),
        "operation": "reproduce",
    }


def _dump(payload: dict) -> str:
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from methodology.ssdlib.live_eval import secret_values, to_json

    return to_json(payload, secret_values())


def _live_exit(payload: dict) -> int:
    status = payload.get("status")
    if status in {"FAIL", "ERROR"}:
        return 1
    if status in {"NOT_RUN", "STOPPED"}:
        return 2
    if status == "RECORDED":
        return 0
    return 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="eval-driver")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate")
    run_p = sub.add_parser("run")
    run_p.add_argument("--fixture", required=True)
    run_p.add_argument("--arm", required=True, choices=("A", "B", "C"))
    run_p.add_argument("--live", action="store_true")
    run_p.add_argument("--dry-run", action="store_true")
    run_p.add_argument("--repetitions", type=int)
    run_p.add_argument("--no-probes", action="store_true")
    run_p.add_argument("--output")
    rep = sub.add_parser("reproduce")
    rep.add_argument("--manifest", required=True)
    live_p = sub.add_parser("live")
    live_p.add_argument("--dry-run", action="store_true")
    live_p.add_argument("--fixture")
    live_p.add_argument("--arm", choices=("A", "B", "C"))
    live_p.add_argument("--repetitions", type=int)
    live_p.add_argument("--no-probes", action="store_true")
    live_p.add_argument("--output")
    args = parser.parse_args(argv)
    try:
        if args.cmd == "validate":
            payload = validate_offline()
            print(json.dumps(payload, indent=2))
            return 1 if payload["errors"] else 0
        if args.cmd == "run":
            if args.live:
                payload = run_live(args)
                print(_dump(payload))
                return _live_exit(payload)
            payload = run_offline(args.fixture, args.arm)
            print(json.dumps(payload, indent=2))
            grade = payload.get("grade") or {}
            if payload.get("status") == "NOT_RUN":
                return 2
            return 0 if grade.get("status") == "PASS" else 1
        if args.cmd == "live":
            payload = run_live(args)
            print(_dump(payload))
            if args.dry_run:
                return 0 if payload.get("status") in {"DRY_RUN", "NOT_RUN"} else 1
            return _live_exit(payload)
        if args.cmd == "reproduce":
            print(json.dumps(reproduce(Path(args.manifest)), indent=2))
            return 0
    except Exception as exc:  # visible failure, not a pass
        print(json.dumps({"status": "ERROR", "reason": str(exc)}))
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
