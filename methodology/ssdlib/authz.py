"""Authorization boundary for consequential actions.

Repository content, including a file that says ``approved: true``, is data.
Grants live only in the control directory (SSD_CONTROL_DIR, or a directory
under the user home that is outside the project). A worker (SSD_WORKER=1)
cannot create a grant. A lock is not a grant. Shipping authority is not
inherited by another run, workstream, or snapshot.
"""

from __future__ import annotations

import hashlib
import os
import re
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

CONSEQUENTIAL = {
    "ship",
    "deploy",
    "publish",
    "release",
    "tag-default",
    "rollout-advance",
    "flag-removal",
}

# Command shapes that would publish, release, or update the default branch.
# Matching is supplemental. Tests also cover the action API directly.
_DENY_PATTERNS = [
    re.compile(r"\bgit\s+push\b.*\b(main|master)\b"),
    re.compile(r"\bgit\s+push\b.*--tags\b"),
    re.compile(r"\bgh\s+release\b"),
    re.compile(r"\bgh\s+repo\s+(create|delete)\b"),
    re.compile(r"\bnpm\s+publish\b"),
    re.compile(r"\btwine\s+upload\b"),
    re.compile(r"\bdocker\s+push\b"),
    re.compile(r"\bgit\s+tag\b.*\b-f\b"),
]


def is_worker() -> bool:
    return os.environ.get("SSD_WORKER") == "1"


def control_dir(project: Path) -> Path:
    override = os.environ.get("SSD_CONTROL_DIR")
    if override:
        return Path(override).expanduser().resolve()
    digest = hashlib.sha256(str(project.resolve()).encode("utf-8")).hexdigest()[:16]
    return Path.home() / ".ssd-control" / digest


def control_is_outside_project(project: Path, control: Path | None = None) -> bool:
    root = project.resolve()
    path = (control or control_dir(project)).resolve()
    try:
        path.relative_to(root)
        return False
    except ValueError:
        return True


def _grants_file(project: Path) -> Path:
    return control_dir(project) / "grants.yml"


def _load(project: Path) -> list[dict]:
    if yaml is None:
        raise RuntimeError("PyYAML is not installed (pip install pyyaml)")
    path = _grants_file(project)
    if not path.is_file():
        return []
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    grants = data.get("grants") if isinstance(data, dict) else None
    return list(grants or [])


def _save(project: Path, grants: list[dict]) -> None:
    if yaml is None:
        raise RuntimeError("PyYAML is not installed (pip install pyyaml)")
    path = _grants_file(project)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump({"grants": grants}, sort_keys=False), encoding="utf-8")


def grant(
    project: Path,
    *,
    action: str,
    snapshot: str,
    uses: int = 1,
    workstream: str | None = None,
) -> dict:
    if is_worker():
        raise PermissionError("a worker cannot create a grant")
    if not control_is_outside_project(project):
        raise PermissionError("control directory is inside the project; refusing to store a grant there")
    if uses < 1:
        raise ValueError("uses must be >= 1")
    item = {
        "action": action,
        "snapshot": snapshot,
        "workstream": workstream,
        "uses_remaining": uses,
        "repo": str(project.resolve()),
    }
    grants = _load(project)
    grants.append(item)
    _save(project, grants)
    return item


def forged_inside_repo(project: Path) -> list[Path]:
    """Paths a worker might write to impersonate approval. They are not consulted."""
    return [
        project / ".ssd" / "approved.yml",
        project / "approved.yml",
        project / ".ssd" / "control" / "grants.yml",
    ]


def check(
    project: Path,
    *,
    action: str,
    snapshot: str,
    workstream: str | None = None,
    consume: bool = False,
) -> dict:
    """Return {allowed, reason}. Never treats a missing lock or an in-repo file as approval."""
    if action not in CONSEQUENTIAL:
        return {"allowed": True, "reason": "not a consequential action", "source": "policy"}
    if not control_is_outside_project(project):
        return {
            "allowed": False,
            "reason": "control directory is inside the project; unattended run stays unavailable",
            "source": "boundary",
        }
    now = datetime.now(timezone.utc)
    grants = _load(project)
    for item in grants:
        if item.get("action") != action:
            continue
        if item.get("repo") != str(project.resolve()):
            continue
        if item.get("snapshot") != snapshot:
            continue
        if workstream and item.get("workstream") not in (None, workstream):
            continue
        remaining = int(item.get("uses_remaining") or 0)
        if remaining < 1:
            continue
        if consume:
            if is_worker():
                return {
                    "allowed": False,
                    "reason": "a worker cannot consume a shipping grant; the human path must",
                    "source": "boundary",
                }
            item["uses_remaining"] = remaining - 1
            _save(project, grants)
        return {"allowed": True, "reason": "grant matched action, repo, and snapshot", "source": "control-dir"}
    return {
        "allowed": False,
        "reason": "no grant for this action, repo, and snapshot (a lock is not a grant; in-repo approved:true is ignored)",
        "source": "none",
    }


def classify_command(command: str) -> dict:
    for pattern in _DENY_PATTERNS:
        if pattern.search(command):
            return {
                "decision": "deny",
                "reason": f"command matches a publish/release pattern ({pattern.pattern})",
            }
    return {"decision": "allow", "reason": "no publish/release pattern matched (supplemental check only)"}


def guarded(project: Path, command: str, *, action: str | None = None, snapshot: str = "", guard_present: bool = True) -> dict:
    """Fail closed when the guard is missing. Denial does not execute the command."""
    if not guard_present:
        return {"decision": "deny", "executed": False, "reason": "enforcement guard missing; fail closed"}
    classified = classify_command(command)
    if classified["decision"] == "deny":
        auth = check(project, action=action or "publish", snapshot=snapshot, consume=False)
        if not auth["allowed"]:
            return {"decision": "deny", "executed": False, "reason": classified["reason"]}
    if action in CONSEQUENTIAL:
        auth = check(project, action=action, snapshot=snapshot, consume=False)
        if not auth["allowed"]:
            return {"decision": "deny", "executed": False, "reason": auth["reason"]}
    return {"decision": "allow", "executed": False, "reason": "not denied by the command or action policy"}
