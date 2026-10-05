#!/usr/bin/env python3
"""Event adapter around the existing referees.

Reads a Claude Code hook payload on stdin and prints a decision. Exit 0 with
JSON is the decision path. A missing or malformed payload does not grant
permission. Post-tool output is feedback, not prevention. This process does
not run the project test suite.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from methodology.ssdlib.authz import classify_command  # noqa: E402


def decide(payload: dict) -> dict:
    event = payload.get("hook_event_name") or payload.get("hookEventName") or ""
    if event == "PreToolUse":
        tool = payload.get("tool_name") or payload.get("tool_input", {}).get("command") and payload.get("tool_name")
        name = payload.get("tool_name") or ""
        command = ""
        tool_input = payload.get("tool_input") or {}
        if isinstance(tool_input, dict):
            command = str(tool_input.get("command") or "")
        if name == "Bash" and command:
            classified = classify_command(command)
            if classified["decision"] == "deny":
                return {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": classified["reason"] + " A hook denial is not the only boundary.",
                    }
                }
        return {"systemMessage": "ssd pre-tool: no publish/release pattern; normal permission flow continues"}
    if event == "PostToolUse":
        return {"systemMessage": "ssd post-tool: feedback only; the tool already ran"}
    if event in {"SessionStart", "Setup"}:
        return {"systemMessage": "ssd session: read /ssd doctor for state. This hook did not modify the project."}
    if event == "Stop":
        if payload.get("stop_hook_active"):
            return {"systemMessage": "ssd stop: already stopping; not looping"}
        return {"systemMessage": "ssd stop: if an auto-run lock is held, read its record before clearing it"}
    return {"systemMessage": f"ssd hook: event {event or 'missing'} has no decision; not an approval"}


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        # No project payload. Stay fast and do not approve anything.
        print(json.dumps({"systemMessage": "ssd hook: empty payload; no decision"}))
        return 0
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        print(json.dumps({"systemMessage": "ssd hook: malformed JSON; no permission granted"}))
        return 0
    if not isinstance(payload, dict):
        print(json.dumps({"systemMessage": "ssd hook: payload is not an object; no permission granted"}))
        return 0
    print(json.dumps(decide(payload)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
