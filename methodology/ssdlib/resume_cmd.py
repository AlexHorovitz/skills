#!/usr/bin/env python3
"""autorun.sh resume subcommand. Prints the same state= line the other subcommands print."""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("SSD_LIB") or Path(__file__).resolve().parents[2])
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from methodology.ssdlib.resume import resume  # noqa: E402


def main() -> int:
    project = Path(os.environ.get("AR_ROOT") or os.getcwd())
    run_id = os.environ.get("AR_RUN_ID") or ""
    alive = os.environ.get("SSD_WORKER_ALIVE", "unknown")
    result = resume(project, run_id, snapshot=os.environ.get("AR_FINGERPRINT") or None, worker_alive=alive)
    print(f"state={result['state']} reason={result['reason']}", flush=True)
    print("autorun: " + result["detail"], file=sys.stderr)
    if result.get("consumed_transitions") is not None:
        print(f"  consumed_transitions={result['consumed_transitions']}", file=sys.stderr)
    if result.get("shipping"):
        print(f"  shipping={result['shipping']}", file=sys.stderr)
    return 0 if result["state"] == "ok" else 2


if __name__ == "__main__":
    sys.exit(main())
