"""Read-only classification of project SSD state.

missing  — no .ssd/ or no project.yml. The next action is a setup proposal.
valid    — project.yml (and current.yml, if present) parse as mappings.
corrupt  — a state file exists but is not usable YAML or not a mapping.
unreadable — the file cannot be read.

A corrupt file is never reported as a healthy empty project.
"""

from __future__ import annotations

from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - surfaced by the caller
    yaml = None


def classify(project: Path) -> dict:
    ssd = project / ".ssd"
    if not ssd.exists() and not ssd.is_symlink():
        return {
            "status": "missing",
            "detail": "no .ssd/ directory",
            "next": "/ssd-init",
        }
    if ssd.is_symlink() and not ssd.exists():
        return {
            "status": "unreadable",
            "detail": f".ssd symlink is dangling ({ssd})",
            "next": "repair the store link; do not treat this as a new project",
        }
    project_yml = ssd / "project.yml"
    if not project_yml.exists():
        return {
            "status": "missing",
            "detail": ".ssd/ exists but project.yml does not",
            "next": "/ssd-init",
        }
    if yaml is None:
        return {
            "status": "unreadable",
            "detail": "PyYAML is not installed; state was not parsed",
            "next": "install PyYAML (pip install pyyaml) and re-run doctor",
        }
    for name in ("project.yml", "current.yml"):
        path = ssd / name
        if not path.exists():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            return {
                "status": "unreadable",
                "detail": f"cannot read {name}: {exc}",
                "next": "fix permissions; do not re-initialize over this state",
            }
        try:
            data = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            return {
                "status": "corrupt",
                "detail": f"{name} is not valid YAML: {exc}",
                "next": "fix the file; do not treat it as an empty project",
            }
        if data is None:
            return {
                "status": "corrupt",
                "detail": f"{name} is empty",
                "next": "fix the file; an empty state file is not a healthy project",
            }
        if not isinstance(data, dict):
            return {
                "status": "corrupt",
                "detail": f"{name} is {type(data).__name__}, not a mapping",
                "next": "fix the file; do not guess a workstream",
            }
    return {
        "status": "valid",
        "detail": "project.yml parses as a mapping",
        "next": "/ssd",
    }
