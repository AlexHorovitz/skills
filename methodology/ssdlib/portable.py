"""Dependency-complete portable export.

The bundle is generated. Host-only frontmatter fields are stripped and the
body states that unattended execution is not enabled. Relative links must
resolve inside the bundle. This module does not claim a host ran the bundle.
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

HOST_FIELDS = {
    "disable-model-invocation",
    "user-invocable",
    "allowed-tools",
    "context",
    "hooks",
    "model",
    "effort",
    "argument-hint",
    "when_to_use",
    "paths",
}

LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
DYNAMIC_RE = re.compile(r"^!\`.*\`\s*$", re.MULTILINE)

BANNER = (
    "> Portable bundle. These instructions do not enforce permissions, "
    "isolation, or unattended run. Invoke audits and setup explicitly. "
    "Do not start an unattended run from this bundle.\n"
)


def _strip_frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return BANNER + "\n" + text
    end = text.find("\n---\n", 4)
    if end == -1:
        return text
    raw = text[4:end]
    # Drop host-only top-level keys. Nested metadata stays.
    kept = []
    skip = False
    key = None
    for line in raw.splitlines():
        if line and not line.startswith(" ") and not line.startswith("-") and ":" in line:
            key = line.split(":", 1)[0].strip()
            skip = key in HOST_FIELDS
        if skip:
            continue
        kept.append(line)
    body = text[end + 5 :]
    body = DYNAMIC_RE.sub("(command injection removed: run the documented command yourself and paste nothing automatically)", body)
    front = "---\n" + "\n".join(kept).rstrip() + "\n---\n\n"
    return front + BANNER + "\n" + body


def export(library: Path, dest: Path) -> dict:
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    copied = []
    for skill in sorted(p for p in library.glob("*/SKILL.md")):
        if skill.parent.name in {"dist", "evals"}:
            continue
        target_root = dest / skill.parent.name
        shutil.copytree(
            skill.parent,
            target_root,
            symlinks=True,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
        skill_md = target_root / "SKILL.md"
        skill_md.write_text(_strip_frontmatter(skill_md.read_text(encoding="utf-8")), encoding="utf-8")
        copied.append(skill.parent.name)
    # Skill directories are already copied. Copy siblings they link to, and
    # skip anything the skill copy already placed (methodology is itself a skill).
    for rel in ("methodology", "scripts", "docs/decisions", "ssd/rails.md", "ssd/chapters", "CHANGELOG.md", "AGENTS.md", "LICENSE"):
        src = library / rel
        if not src.exists():
            continue
        target = dest / rel
        if target.exists():
            continue
        if src.is_dir():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(src, target, symlinks=True, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
    for name in ("LICENSE", "VERSION"):
        shutil.copy2(library / name, dest / name)
    manifest = {
        "format": "ssd-portable-1",
        "enforcement": "none",
        "unattended_run": False,
        "label": "format-validated-only",
        "skills": copied,
        "host_runtime_tested": None,
    }
    (dest / "portable-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    readme = dest / "PORTABLE.md"
    readme.write_text(
        "# SSD portable bundle\n\n"
        "Format-validated only. No host runtime was exercised to produce this bundle.\n\n"
        "Unattended `run` is not enabled. Setup (`ssd-init`), Feynman, software-standards, "
        "and codebase-skeptic start only when a person invokes them.\n\n"
        "Library scripts and schemas are included beside the skills so `../methodology/` "
        "links from a skill directory still resolve.\n",
        encoding="utf-8",
    )
    problems = closure_problems(dest)
    return {"dest": str(dest), "skills": copied, "problems": problems, "manifest": manifest}


def closure_problems(bundle: Path) -> list[str]:
    problems = []
    manifest = bundle / "portable-manifest.json"
    if not manifest.is_file():
        problems.append("missing portable-manifest.json")
    for required in ("LICENSE", "VERSION", "methodology/gate-rules.sh", "methodology/schemas"):
        if not (bundle / required).exists():
            problems.append(f"missing {required}")
    for skill in bundle.glob("*/SKILL.md"):
        text = skill.read_text(encoding="utf-8")
        if "disable-model-invocation" in text.split("---", 2)[1] if text.startswith("---") else "":
            problems.append(f"{skill.parent.name}: host invocation field still present")
        for match in LINK_RE.finditer(text):
            target = match.group(1).split()[0]
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if target.startswith("#"):
                continue
            path = (skill.parent / target.split("#", 1)[0]).resolve()
            try:
                path.relative_to(bundle.resolve())
            except ValueError:
                problems.append(f"{skill.parent.name}: link escapes the bundle ({target})")
                continue
            if not path.exists():
                problems.append(f"{skill.parent.name}: broken link {target}")
    return problems
