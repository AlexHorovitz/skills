#!/usr/bin/env python3
"""Skill frontmatter lint. Missing PyYAML is a visible failure, not a pass."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from methodology.ssdlib.skillmeta import check_tree  # noqa: E402


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT
    try:
        results, errors = check_tree(root)
    except Exception as exc:
        print(f"ERROR {root} :: {exc}", file=sys.stderr)
        return 2
    for item in results:
        print(f"{item['status']} {item['path']} :: {item['detail']}")
    if any(item["status"] == "ERROR" for item in results):
        return 2
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
