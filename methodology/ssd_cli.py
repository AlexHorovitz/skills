#!/usr/bin/env python3
"""SSD v3 command line. Read-only unless a subcommand says it writes."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from methodology.ssdlib import authz, doctor, evidence, lifecycle, paths, portable, state  # noqa: E402
from methodology.ssdlib.resume import resume  # noqa: E402


def _project(arg: str | None) -> Path:
    if arg:
        return Path(arg).resolve()
    found = paths.project_root()
    if found is None:
        raise SystemExit("no project root; pass --project")
    return found


def cmd_paths(args: argparse.Namespace) -> int:
    print(json.dumps(paths.describe(Path(args.cwd).resolve() if args.cwd else None), indent=2))
    return 0


def cmd_state(args: argparse.Namespace) -> int:
    project = _project(args.project)
    print(json.dumps(state.classify(project), indent=2))
    return 0


def cmd_doctor(_args: argparse.Namespace) -> int:
    report = doctor.doctor()
    sys.stdout.write(doctor.render(report))
    return 0


def cmd_setup_plan(args: argparse.Namespace) -> int:
    project = _project(args.project)
    print(json.dumps(lifecycle.plan(project, library=paths.library_root()), indent=2))
    return 0


def cmd_resume(args: argparse.Namespace) -> int:
    project = _project(args.project)
    result = resume(project, args.run_id, snapshot=args.snapshot, worker_alive=args.worker_alive)
    print(f"state={result['state']} reason={result['reason']}")
    print(result["detail"], file=sys.stderr)
    return 0 if result["state"] == "ok" else 2


def cmd_authz_check(args: argparse.Namespace) -> int:
    project = _project(args.project)
    result = authz.check(project, action=args.action, snapshot=args.snapshot, consume=args.consume)
    print(json.dumps(result))
    return 0 if result["allowed"] else 2


def cmd_authz_grant(args: argparse.Namespace) -> int:
    project = _project(args.project)
    try:
        item = authz.grant(project, action=args.action, snapshot=args.snapshot, uses=args.uses)
    except PermissionError as exc:
        print(f"state=refused reason={exc}", file=sys.stderr)
        return 2
    print(json.dumps(item))
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    dest = Path(args.dest)
    result = portable.export(paths.library_root(), dest)
    print(json.dumps({"skills": result["skills"], "problems": result["problems"]}, indent=2))
    return 1 if result["problems"] else 0


def cmd_evidence_check(args: argparse.Namespace) -> int:
    project = _project(args.project)
    result = evidence.check(project)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PASS" else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ssd")
    sub = parser.add_subparsers(dest="cmd", required=True)

    paths_p = sub.add_parser("paths", help="print library, project, worktree, and storage roots")
    paths_p.add_argument("--cwd")
    paths_p.set_defaults(func=cmd_paths)

    state_p = sub.add_parser("state", help="classify .ssd state as missing, valid, corrupt, or unreadable")
    state_p.add_argument("--project")
    state_p.set_defaults(func=cmd_state)

    doctor_p = sub.add_parser("doctor", help="read-only installation and capability report")
    doctor_p.set_defaults(func=cmd_doctor)

    plan_p = sub.add_parser("setup-plan", help="show the setup change set; writes nothing")
    plan_p.add_argument("--project")
    plan_p.set_defaults(func=cmd_setup_plan)

    resume_p = sub.add_parser("resume", help="validate a run before continuing it")
    resume_p.add_argument("run_id")
    resume_p.add_argument("--project")
    resume_p.add_argument("--snapshot")
    resume_p.add_argument("--worker-alive", default="unknown", choices=("unknown", "alive", "dead"))
    resume_p.set_defaults(func=cmd_resume)

    check_p = sub.add_parser("authz-check", help="check a consequential action against the control directory")
    check_p.add_argument("--project", required=True)
    check_p.add_argument("--action", required=True)
    check_p.add_argument("--snapshot", required=True)
    check_p.add_argument("--consume", action="store_true")
    check_p.set_defaults(func=cmd_authz_check)

    grant_p = sub.add_parser("authz-grant", help="record a human grant outside the project")
    grant_p.add_argument("--project", required=True)
    grant_p.add_argument("--action", required=True)
    grant_p.add_argument("--snapshot", required=True)
    grant_p.add_argument("--uses", type=int, default=1)
    grant_p.set_defaults(func=cmd_authz_grant)

    export_p = sub.add_parser("export-portable", help="write a dependency-complete portable bundle")
    export_p.add_argument("--dest", required=True)
    export_p.set_defaults(func=cmd_export)

    ev_p = sub.add_parser("evidence-check", help="reject gate evidence that does not match the current snapshot")
    ev_p.add_argument("--project")
    ev_p.set_defaults(func=cmd_evidence_check)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
