#!/usr/bin/env python3
"""
methodology/frontmatter-validate.py — validate YAML frontmatter on SSD artifacts.

Walks `.ssd/features/<slug>/` and `.ssd/milestones/<topic>/` (or paths passed as
arguments), parses the YAML frontmatter at the top of each Markdown file,
matches it to the appropriate schema in `methodology/schemas/<skill>.yml`, and
checks every required field is present with the expected top-level type.

This is structural validation only. Sub-field shape (e.g., the contents of
`deliverables` for architect, or `finding_counts` for code-reviewer) is
documented in each SKILL.md but not enforced here. v2 of the validator may
tighten that.

Output format (one line per file checked):
    PASS <path>
    FAIL <path> :: <reason>
    SKIP <path> :: <reason>          # not matched to any schema, etc.

Exit code: 0 if every file is PASS or SKIP. Non-zero on any FAIL.

Usage:
    python3 methodology/frontmatter-validate.py                  # walk .ssd/
    python3 methodology/frontmatter-validate.py path1.md path2.md  # specific files
    python3 methodology/frontmatter-validate.py --json           # structured output

Requires: Python 3.8+ and PyYAML. The `frontmatter-valid` rule in
`methodology/gate-rules.sh` SKIPs (rather than FAILs) if either is missing —
graceful degradation matches the rest of the gate's precedent.

License: see /LICENSE.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import sys
from fnmatch import fnmatch
from pathlib import Path

try:
    import yaml
except ImportError:
    print("FAIL <runtime> :: PyYAML not installed (pip3 install pyyaml)", file=sys.stderr)
    sys.exit(2)


# Schemas live next to the script — resolve through symlinks so the fixture
# harness can symlink the script into a tmp dir and still find the schemas.
SCHEMAS_DIR = Path(__file__).resolve().parent / "schemas"
# The "project root" for default artifact discovery is the current working
# directory, NOT the script's location. This lets the same validator be used
# from any project that happens to have the schemas symlinked in.
PROJECT_ROOT = Path.cwd()

# `timestamp` accepts datetime, date, or string. PyYAML auto-parses ISO-8601
# strings to datetime objects, so the produced YAML in the wild is always one
# of these three. The schema is permissive on representation but strict on
# field presence.
TYPE_MAP: dict[str, tuple[type, ...]] = {
    "string": (str,),
    "int": (int,),
    "bool": (bool,),
    "list": (list,),
    "dict": (dict,),
    "timestamp": (_dt.datetime, _dt.date, str),
}


def load_schemas() -> list[dict]:
    """Read every *.yml in methodology/schemas/. Each describes one skill's
    required frontmatter shape."""
    schemas = []
    if not SCHEMAS_DIR.is_dir():
        return schemas
    for path in sorted(SCHEMAS_DIR.glob("*.yml")):
        with path.open() as fh:
            schema = yaml.safe_load(fh)
        if not isinstance(schema, dict) or "skill" not in schema:
            print(f"WARN: malformed schema {path} — skipping", file=sys.stderr)
            continue
        schema["_source"] = str(path)
        schemas.append(schema)
    return schemas


def match_schema(file_path: Path, schemas: list[dict]) -> dict | None:
    """Find the schema whose `applies_to` patterns match this file path.

    Patterns match the file path's tail. A pattern like `01-architect.md`
    matches any file whose path ends with `/01-architect.md` or which IS
    `01-architect.md`. A pattern like `code-review/round-*.md` matches any
    path containing a `code-review/round-*.md` segment near the end.
    """
    file_str = str(file_path)
    for schema in schemas:
        for pattern in schema.get("applies_to", []):
            # fnmatch handles the glob characters in patterns like round-*.md
            # We test both "ends with /<pattern>" and "==<pattern>" via fnmatch
            # against the right-hand side of the path.
            if fnmatch(file_str, f"*/{pattern}") or fnmatch(file_str, pattern):
                return schema
    return None


def parse_frontmatter(path: Path) -> dict | None:
    """Return the parsed YAML frontmatter, or None if the file has none.

    Frontmatter is a YAML block delimited by `---` on the first line and a
    matching `---` line later. Anything before the first `---` (e.g.,
    leading whitespace) is tolerated.
    """
    try:
        with path.open() as fh:
            text = fh.read()
    except OSError as exc:
        raise RuntimeError(f"cannot read {path}: {exc}")

    lines = text.splitlines()
    # Find first non-empty line; must be '---'.
    start = None
    for i, line in enumerate(lines):
        if line.strip() == "":
            continue
        if line.strip() == "---":
            start = i
        break
    if start is None:
        return None

    # Find closing '---'.
    end = None
    for j in range(start + 1, len(lines)):
        if lines[j].strip() == "---":
            end = j
            break
    if end is None:
        raise RuntimeError("opening --- found but no closing ---")

    block = "\n".join(lines[start + 1 : end])
    try:
        parsed = yaml.safe_load(block)
    except yaml.YAMLError as exc:
        raise RuntimeError(f"YAML parse error: {exc}") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("frontmatter must be a YAML mapping (dict)")
    return parsed


def validate(frontmatter: dict, schema: dict) -> list[str]:
    """Return a list of human-readable failure reasons. Empty list = pass."""
    failures: list[str] = []
    required = schema.get("required", {})
    for field, type_name in required.items():
        if field not in frontmatter:
            failures.append(f"missing required field `{field}` (expected {type_name})")
            continue
        expected_types = TYPE_MAP.get(type_name)
        if expected_types is None:
            failures.append(f"schema lists unknown type `{type_name}` for `{field}`")
            continue
        value = frontmatter[field]
        # bool is a subclass of int in Python; reject the cross-type cases explicitly.
        if type_name == "int" and isinstance(value, bool):
            failures.append(f"field `{field}` should be int, got bool")
            continue
        if type_name == "bool" and not isinstance(value, bool):
            failures.append(f"field `{field}` should be bool, got {type(value).__name__}")
            continue
        if not isinstance(value, expected_types):
            failures.append(
                f"field `{field}` should be {type_name}, got {type(value).__name__}"
            )
    return failures


def discover_files(roots: list[Path]) -> list[Path]:
    """Walk paths. If a path is a directory, find every .md file under it."""
    files: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        if root.is_file():
            if root.suffix == ".md":
                files.append(root)
            continue
        for path in root.rglob("*.md"):
            files.append(path)
    return sorted(set(files))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate SSD artifact frontmatter against per-skill schemas.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Files or directories to check. Default: .ssd/features/ and .ssd/milestones/",
    )
    parser.add_argument(
        "--json", action="store_true", help="Emit JSON instead of text"
    )
    args = parser.parse_args()

    if args.paths:
        roots = [Path(p) for p in args.paths]
    else:
        roots = [PROJECT_ROOT / ".ssd" / "features", PROJECT_ROOT / ".ssd" / "milestones"]

    schemas = load_schemas()
    if not schemas:
        print("FAIL <runtime> :: no schemas found in methodology/schemas/", file=sys.stderr)
        return 2

    files = discover_files(roots)
    results: list[dict] = []
    fail_count = 0

    for path in files:
        rel = path.relative_to(PROJECT_ROOT) if path.is_relative_to(PROJECT_ROOT) else path
        schema = match_schema(path, schemas)
        if schema is None:
            results.append({"status": "SKIP", "path": str(rel), "detail": "no matching schema"})
            continue
        try:
            frontmatter = parse_frontmatter(path)
        except RuntimeError as exc:
            results.append({"status": "FAIL", "path": str(rel), "detail": str(exc)})
            fail_count += 1
            continue
        if frontmatter is None:
            results.append(
                {"status": "FAIL", "path": str(rel), "detail": "no frontmatter found"}
            )
            fail_count += 1
            continue
        failures = validate(frontmatter, schema)
        if failures:
            results.append(
                {
                    "status": "FAIL",
                    "path": str(rel),
                    "schema": schema["skill"],
                    "detail": "; ".join(failures),
                }
            )
            fail_count += 1
        else:
            results.append(
                {"status": "PASS", "path": str(rel), "schema": schema["skill"]}
            )

    if args.json:
        print(
            json.dumps(
                {"fail_count": fail_count, "results": results},
                indent=2,
            )
        )
    else:
        for r in results:
            line = f"{r['status']} {r['path']}"
            if "schema" in r:
                line += f" [{r['schema']}]"
            if "detail" in r:
                line += f" :: {r['detail']}"
            print(line)

    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
