"""Optional per-role model and effort selection.

Omitted fields mean inherit. Nothing here names a commercial model as a
requirement. Unsupported values are rejected before a run; they are not
silently replaced with a more expensive model.
"""

from __future__ import annotations

from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

ROLES = ("architect", "coder", "reviewer")


def _ssd_block(project: Path) -> dict:
    if yaml is None:
        raise RuntimeError("PyYAML is not installed (pip install pyyaml)")
    path = project / ".ssd" / "project.yml"
    if not path.is_file():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError("project.yml is not a mapping")
    block = data.get("ssd") or {}
    return block if isinstance(block, dict) else {}


def resolve(project: Path, *, supported_models: set[str] | None = None) -> dict:
    """Return requested and effective selections.

    ``supported_models`` is the host allow-list. ``None`` means the host did
    not report one: any explicit non-inherit value is unsupported, and the
    effective value stays inherit. An empty allow-list is the same.
    """
    block = _ssd_block(project)
    models = block.get("models") or {}
    effort = block.get("effort") or {}
    if models and not isinstance(models, dict):
        raise ValueError("ssd.models must be a mapping")
    if effort and not isinstance(effort, dict):
        raise ValueError("ssd.effort must be a mapping")
    supported = supported_models
    out = {"roles": {}, "behavior_change": False}
    for role in ROLES:
        requested_model = models.get(role, "inherit") if models else "inherit"
        requested_effort = effort.get(role, "inherit") if effort else "inherit"
        if not isinstance(requested_model, str) or not isinstance(requested_effort, str):
            raise ValueError(f"{role} selection must be a string")
        model_status = "inherit"
        effective_model = "inherit"
        if requested_model != "inherit":
            if supported is None or requested_model not in supported:
                model_status = "unsupported"
                effective_model = "inherit"
            else:
                model_status = "selected"
                effective_model = requested_model
                out["behavior_change"] = True
        effort_status = "inherit"
        effective_effort = "inherit"
        if requested_effort != "inherit":
            # Effort is host-defined. Without a host report it is unsupported.
            if supported is None:
                effort_status = "unsupported"
                effective_effort = "inherit"
            else:
                effort_status = "selected"
                effective_effort = requested_effort
                out["behavior_change"] = True
        out["roles"][role] = {
            "requested_model": requested_model,
            "effective_model": effective_model,
            "model_status": model_status,
            "requested_effort": requested_effort,
            "effective_effort": effective_effort,
            "effort_status": effort_status,
            "effective_identity": "unknown" if effective_model == "inherit" else effective_model,
        }
    if not models and not effort:
        out["behavior_change"] = False
    return out
