"""Bind gate evidence to the snapshot that was checked.

A later edit, including a dirty tree, invalidates the record. Missing tools
are NOT_RUN or ERROR, never PASS.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


def _git(cwd: Path, *args: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "-C", str(cwd), *args],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return None


def _tree_status(dirty: str) -> str:
    """Ignore the evidence directory this module writes. Recording a result must not stale itself."""
    kept = []
    for line in dirty.splitlines():
        path = line[3:] if len(line) > 3 else line
        if path.startswith(".ssd/gate-evidence"):
            continue
        kept.append(line)
    return "\n".join(kept)


def working_snapshot(project: Path) -> dict:
    head = _git(project, "rev-parse", "HEAD")
    dirty = _tree_status(_git(project, "status", "--porcelain", "-uall") or "")
    digest = hashlib.sha256(dirty.encode("utf-8")).hexdigest()
    return {"head": head, "dirty_sha256": digest, "dirty": bool(dirty)}


def record(project: Path, *, results: list[dict], command: str) -> dict:
    snap = working_snapshot(project)
    payload = {
        "snapshot": snap,
        "command": command,
        "results": results,
    }
    directory = project / ".ssd" / "gate-evidence"
    directory.mkdir(parents=True, exist_ok=True)
    ident = snap["head"] or "no-head"
    path = directory / f"{ident[:12]}-{snap['dirty_sha256'][:12]}.json"
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    (directory / "latest").write_text(str(path.name), encoding="utf-8")
    return {"path": str(path), "payload": payload}


def load_latest(project: Path) -> dict | None:
    pointer = project / ".ssd" / "gate-evidence" / "latest"
    if not pointer.is_file():
        return None
    path = pointer.parent / pointer.read_text(encoding="utf-8").strip()
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def check(project: Path) -> dict:
    saved = load_latest(project)
    if saved is None:
        return {"status": "NOT_RUN", "reason": "no gate evidence recorded for this project"}
    current = working_snapshot(project)
    saved_snap = saved.get("snapshot") or {}
    if saved_snap.get("head") != current["head"] or saved_snap.get("dirty_sha256") != current["dirty_sha256"]:
        return {
            "status": "FAIL",
            "reason": "saved evidence does not match the current HEAD or dirty snapshot",
            "saved": saved_snap,
            "current": current,
        }
    statuses = [row.get("status") for row in saved.get("results") or []]
    if any(status in {"FAIL", "ERROR"} for status in statuses):
        return {"status": "FAIL", "reason": "recorded results include FAIL or ERROR", "results": statuses}
    if any(status == "NOT_RUN" for status in statuses) or not statuses:
        return {"status": "NOT_RUN", "reason": "a recorded check did not run", "results": statuses}
    if all(status == "PASS" for status in statuses):
        return {"status": "PASS", "reason": "evidence matches this snapshot", "results": statuses}
    return {"status": "ERROR", "reason": f"unrecognized statuses {statuses}"}


def summarize(lines: str, *, snapshot: dict) -> dict:
    """Translate gate-rules.sh lines into PASS/FAIL/ERROR/NOT_RUN without rewriting the script."""
    results = []
    for line in lines.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] not in {"PASS", "FAIL", "SKIP"}:
            continue
        status = {"PASS": "PASS", "FAIL": "FAIL", "SKIP": "NOT_RUN"}[parts[0]]
        rule = parts[1] if len(parts) > 1 else "unknown"
        results.append({"rule": rule, "status": status, "raw": line})
    if not results:
        overall = "ERROR"
    elif any(row["status"] == "FAIL" for row in results):
        overall = "FAIL"
    elif any(row["status"] == "NOT_RUN" for row in results):
        overall = "NOT_RUN"
    else:
        overall = "PASS"
    return {"status": overall, "overall": overall, "snapshot": snapshot, "results": results}
