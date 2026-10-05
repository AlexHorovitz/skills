"""Generate JSON Schema from the authored YAML schemas.

The YAML files under methodology/schemas/ are the only authored contract.
Generation is deterministic: keys are sorted, optional constraints that the
YAML does not express are recorded as notes rather than invented.
"""

from __future__ import annotations

import json
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

TYPE_TO_JSON = {
    "string": {"type": "string"},
    "int": {"type": "integer"},
    "bool": {"type": "boolean"},
    "list": {"type": "array"},
    "dict": {"type": "object"},
    "timestamp": {"type": ["string", "object"], "description": "ISO-8601 string or a YAML timestamp"},
}


def load_authored(schemas_dir: Path) -> list[dict]:
    if yaml is None:
        raise RuntimeError("PyYAML is not installed (pip install pyyaml)")
    docs = []
    for path in sorted(schemas_dir.glob("*.yml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or "skill" not in data:
            continue
        data["_file"] = path.name
        docs.append(data)
    return docs


def to_json_schema(doc: dict) -> dict:
    required = doc.get("required") or {}
    optional = doc.get("optional") or {}
    properties = {}
    for key in sorted(required):
        properties[key] = dict(TYPE_TO_JSON.get(required[key], {"type": "string"}))
    for key in sorted(optional):
        properties[key] = dict(TYPE_TO_JSON.get(optional[key], {"type": "string"}))
    notes = [
        "Generated from methodology/schemas/*.yml. Do not hand-edit.",
        "Nested field shapes (for example finding_counts members) are documented in the skill, not in the authored YAML. They are not dropped; they were never encoded as required top-level types.",
        "Schema validity is not a gate result and is not authorization.",
    ]
    if doc.get("notes"):
        notes.append(str(doc["notes"]))
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"ssd://schemas/{doc['skill']}",
        "title": doc["skill"],
        "type": "object",
        "additionalProperties": True,
        "required": sorted(required),
        "properties": properties,
        "x-ssd-applies-to": list(doc.get("applies_to") or []),
        "x-ssd-source": doc.get("_file"),
        "x-ssd-notes": notes,
    }


def canonical_bytes(doc: dict) -> bytes:
    schema = to_json_schema(doc)
    return (json.dumps(schema, indent=2, sort_keys=True) + "\n").encode("utf-8")


def generate(schemas_dir: Path, out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for doc in load_authored(schemas_dir):
        target = out_dir / f"{doc['skill']}.schema.json"
        target.write_bytes(canonical_bytes(doc))
        written.append(target)
    return written


def in_sync(schemas_dir: Path, out_dir: Path) -> list[str]:
    """Return human-readable drift messages. Empty means byte-for-byte sync."""
    problems = []
    authored = load_authored(schemas_dir)
    expected = {f"{doc['skill']}.schema.json": canonical_bytes(doc) for doc in authored}
    if not out_dir.is_dir():
        return ["JSON schema directory is missing"]
    found = {p.name for p in out_dir.glob("*.schema.json")}
    for name, payload in expected.items():
        path = out_dir / name
        if not path.is_file():
            problems.append(f"missing {name}")
            continue
        if path.read_bytes() != payload:
            problems.append(f"drift {name}")
    extra = found - set(expected)
    for name in sorted(extra):
        problems.append(f"unexpected {name}")
    return problems
