"""Read-only doctor and capability report.

Doctor never installs packages, edits permissions, repairs state, or opens
a network connection.
"""

from __future__ import annotations

import importlib.util
import shutil
from datetime import datetime, timezone
from pathlib import Path

from methodology.ssdlib import authz, executor, paths, state
from methodology.ssdlib.skillmeta import iter_skill_files


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def installation_kind(library: Path) -> str:
    plugin = library / ".claude-plugin" / "plugin.json"
    git = library / ".git"
    if plugin.is_file() and git.exists():
        return "clone+plugin"
    if plugin.is_file():
        return "plugin"
    if git.exists():
        return "clone"
    return "unknown"


def duplicate_skills(library: Path) -> list[str]:
    names: dict[str, list[str]] = {}
    for skill in iter_skill_files(library):
        names.setdefault(skill.parent.name, []).append(str(skill))
    return [name for name, paths_ in names.items() if len(paths_) > 1]


def dependencies() -> list[dict]:
    rows = []
    for tool in ("git", "bash", "python3"):
        found = shutil.which(tool)
        rows.append({
            "name": tool,
            "status": "supported" if found else "unsupported",
            "evidence": found or "not on PATH",
        })
    yaml_ok = importlib.util.find_spec("yaml") is not None
    rows.append({
        "name": "pyyaml",
        "status": "supported" if yaml_ok else "unsupported",
        "evidence": "import yaml" if yaml_ok else "pip install pyyaml",
    })
    return rows


def capabilities(project: Path | None, library: Path) -> list[dict]:
    when = _now()
    jail_ok, jail_detail = executor.mechanism_available()
    claude = shutil.which("claude")
    skill_count = len(iter_skill_files(library))
    hooks_present = (library / "hooks" / "hooks.json").is_file()
    claude_note = "claude CLI is on PATH" if claude else "claude CLI is absent"
    rows = [
        ("skill_discovery", "supported", f"{skill_count} SKILL.md directories are on disk; host loading was not executed"),
        ("agent_delegation", "unknown", f"role files are on disk; a host did not dispatch them here; {claude_note}"),
        ("structured_output", "supported", "frontmatter-validate.py validates artifacts independently of the model"),
        (
            "event_adapters",
            "unknown",
            ("hooks/hooks.json is on disk" if hooks_present else "hooks/hooks.json is missing")
            + f"; Claude Code did not deliver an event here; {claude_note}",
        ),
        ("shell_isolation", "supported" if jail_ok else "unsupported", jail_detail),
        ("filesystem_restrictions", "supported" if jail_ok else "unsupported", "chroot jail copies the snapshot; host paths are not mounted" if jail_ok else jail_detail),
        ("network_restrictions", "supported" if jail_ok else "unsupported", "executor drops the network namespace" if jail_ok else jail_detail),
        (
            "trusted_human_approval",
            "supported" if project and authz.control_is_outside_project(project) else "unsupported",
            "grants live outside the project; in-repo approval files are ignored",
        ),
        ("workflow_engine", "unsupported", "coded workflows are not enabled; the local autorun path is the executor"),
        ("evaluation_tooling", "supported", "scripts/eval_driver.py runs offline and can call a named live runtime; a missing runtime, credential, or ceiling is NOT_RUN"),
        ("usage_reporting", "unknown", "token counts stay unknown until a live runtime reports them; elapsed time is recorded when a run journal has timestamps"),
    ]
    return [
        {
            "name": name,
            "status": status,
            "host_version": "claude-cli-absent" if not claude else "present",
            "installation": installation_kind(library),
            "configuration_source": "repository",
            "evidence": evidence,
            "verified_at": when,
        }
        for name, status, evidence in rows
    ]


def doctor(cwd: Path | None = None) -> dict:
    described = paths.describe(cwd)
    library = Path(described["library_root"])
    version = (library / "VERSION").read_text(encoding="utf-8").strip()
    project = Path(described["project_root"]) if described["project_root"] else None
    state_info = state.classify(project) if project else {"status": "missing", "detail": "no project", "next": "/ssd-init"}
    deps = dependencies()
    missing = [row["name"] for row in deps if row["status"] != "supported"]
    remedies = []
    if state_info["status"] == "missing":
        remedies.append("Run /ssd-init and approve the presented change set. Doctor will not create it.")
    elif state_info["status"] in {"corrupt", "unreadable"}:
        remedies.append(state_info["next"])
    if "pyyaml" in missing:
        remedies.append("Install PyYAML: pip install pyyaml. Doctor will not install it.")
    if not shutil.which("claude"):
        remedies.append("Native Claude Code checks are NOT_RUN here. Install the host before claiming plugin or hook delivery.")
    caps = capabilities(project, library)
    unsupported = [row["name"] for row in caps if row["status"] == "unsupported"]
    if "shell_isolation" in unsupported:
        remedies.append("Strong-assurance review is off until the unshare jail works. Do not call inline review isolated.")
    return {
        "version": version,
        "installation": installation_kind(library),
        "duplicate_skills": duplicate_skills(library),
        "roots": described,
        "state": state_info,
        "dependencies": deps,
        "capabilities": caps,
        "remedies": remedies,
        "writes": 0,
        "network": "not-attempted",
    }


def render(report: dict) -> str:
    lines = [
        f"SSD doctor  version {report['version']}  installation {report['installation']}",
        f"library:  {report['roots']['library_root']}",
        f"project:  {report['roots']['project_root']}",
        f"worktree: {report['roots']['worktree_root']}  linked={report['roots']['worktree_linked']}",
        f"storage:  {report['roots']['storage_kind']}  {report['roots']['storage_root']}",
        f"state:    {report['state']['status']}  {report['state']['detail']}",
        "dependencies:",
    ]
    for row in report["dependencies"]:
        lines.append(f"  {row['status']:12} {row['name']}  {row['evidence']}")
    lines.append("capabilities:")
    for row in report["capabilities"]:
        lines.append(f"  {row['status']:12} {row['name']}  {row['evidence']}")
    if report["duplicate_skills"]:
        lines.append("duplicate skills: " + ", ".join(report["duplicate_skills"]))
    else:
        lines.append("duplicate skills: none")
    lines.append("remedies:")
    if report["remedies"]:
        lines.extend(f"  - {item}" for item in report["remedies"])
    else:
        lines.append("  - none")
    lines.append("doctor performed no writes and no network calls")
    return "\n".join(lines) + "\n"
