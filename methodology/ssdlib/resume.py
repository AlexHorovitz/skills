"""Resume an existing auto-run without resetting what it already consumed.

This does not start a new record, does not restore a shipping grant, and does
not clear a lock it does not own. An abrupt death leaves stop_reason null;
that is reported as indeterminate rather than finished.
"""

from __future__ import annotations

import os
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None


def _load(path: Path) -> dict:
    if yaml is None:
        raise RuntimeError("PyYAML is not installed (pip install pyyaml)")
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        raise ValueError("run record has no frontmatter")
    end = text.find("\n---", 3)
    data = yaml.safe_load(text[3:end])
    if not isinstance(data, dict):
        raise ValueError("run record frontmatter is not a mapping")
    return data


def find_record(project: Path, run_id: str) -> Path | None:
    root = project / ".ssd" / "features"
    if not root.is_dir():
        return None
    matches = [path for path in root.rglob("*-run.md") if run_id in path.name or path.name == run_id]
    if len(matches) == 1:
        return matches[0]
    return None


def resume(project: Path, run_id: str, *, snapshot: str | None = None, worker_alive: str = "unknown") -> dict:
    path = find_record(project, run_id)
    if path is None:
        return {"state": "stop", "reason": "STOP-4", "detail": f"run {run_id} was not found; not guessing"}
    try:
        meta = _load(path)
    except (OSError, ValueError, RuntimeError) as exc:
        return {"state": "stop", "reason": "STOP-6", "detail": f"run record unreadable: {exc}"}
    run = meta.get("run") or {}
    transitions = run.get("transitions") or []
    stop = run.get("stop_reason")
    if stop:
        return {
            "state": "stop",
            "reason": "STOP-4",
            "detail": f"run already finished with {stop}; resume will not open a new budget",
            "consumed_transitions": len(transitions),
            "shipping": "not-restored",
        }
    if worker_alive == "alive":
        return {
            "state": "stop",
            "reason": "FM-2",
            "detail": "a worker may still be alive; not starting a second effect",
            "consumed_transitions": len(transitions),
        }
    recorded_snapshot = run.get("input_fingerprint")
    if snapshot and recorded_snapshot and snapshot != recorded_snapshot:
        return {
            "state": "stop",
            "reason": "STOP-4",
            "detail": "input fingerprint changed; reconcile before continuing",
            "consumed_transitions": len(transitions),
            "shipping": "not-restored",
        }
    liveness = "indeterminate" if worker_alive == "unknown" else worker_alive
    budgets = run.get("budgets") or {}
    return {
        "state": "ok",
        "reason": "resume-ready",
        "detail": "same record, same consumption, shipping authority not restored",
        "record": str(path.relative_to(project)),
        "consumed_transitions": len(transitions),
        "budget_transitions": budgets.get("transitions"),
        "liveness": liveness,
        "stop_reason": None,
        "shipping": "not-authorized",
        "next": "continue the recorded phase only after a person confirms the tree",
    }


def worker_flag() -> str:
    return os.environ.get("SSD_WORKER_ALIVE", "unknown")
