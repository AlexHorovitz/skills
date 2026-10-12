"""Portable skill-metadata checks.

Authored skill version is the ``**Version:**`` banner. ``metadata.version`` in
frontmatter, when present, must match it. The banner is not rewritten from the
library VERSION file: those are different numbers (ADR-0009).
"""

from __future__ import annotations

import re
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
BANNER_RE = re.compile(r"^\*\*Version:\*\*\s*v?(\d+\.\d+(?:\.\d+)?)\s*$", re.MULTILINE)
MAX_DESCRIPTION = 1024
MAX_NAME = 64
MAX_LINES = 400

# Host-specific invocation controls. Portable instructions repeat the same
# restriction in the body; these fields are the supported-host adapter.
DELIBERATE = {
    "ssd-init": "setup writes project files and must be invoked explicitly",
    "feynman": "epistemic audit; automation may propose it and must not start it",
    "software-standards": "broad standards audit; explicit invocation only",
    "codebase-skeptic": "milestone-scale multi-lens audit, not an ordinary diff review",
}


class DuplicateKeyError(Exception):
    pass


def _no_duplicates(loader, node):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=False)
        if key in mapping:
            raise DuplicateKeyError(f"duplicate key {key!r}")
        mapping[key] = loader.construct_object(value_node, deep=False)
    return mapping


def _loader():
    if yaml is None:
        raise RuntimeError("PyYAML is not installed (pip install pyyaml)")

    class Loader(yaml.SafeLoader):
        pass

    Loader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates)
    return Loader


def parse_frontmatter(text: str) -> dict:
    if yaml is None:
        raise RuntimeError("PyYAML is not installed (pip install pyyaml)")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("frontmatter is not the first content (file must start with ---)")
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        raise ValueError("opening --- has no closing ---")
    block = "\n".join(lines[1:end])
    try:
        data = yaml.load(block, Loader=_loader())
    except DuplicateKeyError:
        raise
    except yaml.YAMLError as exc:
        raise ValueError(f"malformed YAML: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("frontmatter must be a mapping")
    return data


def check_file(path: Path) -> dict:
    """Return a result dict with status PASS, FAIL, or ERROR."""
    rel = path
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return {"status": "ERROR", "path": str(rel), "detail": f"cannot read: {exc}"}
    failures = []
    try:
        meta = parse_frontmatter(text)
    except RuntimeError as exc:
        return {"status": "ERROR", "path": str(rel), "detail": str(exc)}
    except DuplicateKeyError as exc:
        return {"status": "FAIL", "path": str(rel), "detail": str(exc)}
    except ValueError as exc:
        return {"status": "FAIL", "path": str(rel), "detail": str(exc)}

    name = meta.get("name")
    if not isinstance(name, str) or not name:
        failures.append("name is missing")
    else:
        if len(name) > MAX_NAME:
            failures.append(f"name is {len(name)} characters (max {MAX_NAME})")
        if not NAME_RE.match(name):
            failures.append(
                "name must be lowercase letters, digits, and single hyphens, "
                "and must not start or end with a hyphen"
            )
        if name != path.parent.name:
            failures.append(f"name {name!r} does not match directory {path.parent.name!r}")

    description = meta.get("description")
    if not isinstance(description, str) or not description.strip():
        failures.append("description is missing or empty")
    else:
        folded = description.strip()
        if len(folded) > MAX_DESCRIPTION:
            failures.append(f"description is {len(folded)} characters (max {MAX_DESCRIPTION})")

    banner = BANNER_RE.search(text)
    meta_version = None
    metadata = meta.get("metadata")
    if isinstance(metadata, dict):
        meta_version = metadata.get("version")
    if meta_version is not None:
        if not isinstance(meta_version, str):
            failures.append("metadata.version must be a string")
        elif banner and meta_version != banner.group(1):
            failures.append(
                f"metadata.version {meta_version} != banner {banner.group(1)} "
                "(banner is the authored skill version)"
            )
        elif not banner:
            failures.append("metadata.version is set but there is no **Version:** banner")

    expected_deliberate = path.parent.name in DELIBERATE
    flag = meta.get("disable-model-invocation")
    if expected_deliberate and flag is not True:
        failures.append(
            "disable-model-invocation must be true "
            f"({DELIBERATE[path.parent.name]})"
        )
    if flag is True and path.parent.name not in DELIBERATE:
        # Allowed, but the body must explain how a person invokes it. Not a failure
        # by itself: ordinary skills may also be manual.
        pass

    line_count = len(text.splitlines())
    if line_count > MAX_LINES:
        failures.append(f"{line_count} physical lines (max {MAX_LINES})")

    if failures:
        return {"status": "FAIL", "path": str(rel), "detail": "; ".join(failures)}
    return {
        "status": "PASS",
        "path": str(rel),
        "detail": f"name={name} lines={line_count}",
    }


def check_tree(root: Path) -> tuple[list[dict], int]:
    if yaml is None:
        return (
            [{"status": "ERROR", "path": str(root), "detail": "PyYAML is not installed (pip install pyyaml)"}],
            1,
        )
    results = []
    errors = 0
    for path in sorted(root.glob("*/SKILL.md")):
        # Fixture and build copies are not library skills.
        if path.parent.name in {"dist", "evals"}:
            continue
        item = check_file(path)
        results.append(item)
        if item["status"] != "PASS":
            errors += 1
    return results, errors


def iter_skill_files(root: Path) -> list[Path]:
    return sorted(p for p in root.glob("*/SKILL.md") if p.parent.name not in {"dist", "evals"})
