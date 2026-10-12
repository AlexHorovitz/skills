"""Review findings are evidence. A model-supplied gate_pass is not a gate result.

Blocking counts come from validated findings on the snapshot that was reviewed.
Test results come from a runner record, not from prose in the review.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

BLOCKING = {"BLOCKER", "MAJOR"}
STATUSES = {"confirmed", "unverified", "suggestion"}


def snapshot_id(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file() and not p.is_symlink()):
        digest.update(str(path.relative_to(root)).encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def blocking_findings(report: dict, *, snapshot: str) -> list[dict]:
    if report.get("reviewed_snapshot") != snapshot:
        return []
    found = []
    for item in report.get("findings") or []:
        if not isinstance(item, dict):
            continue
        if item.get("severity") in BLOCKING and item.get("verification_status") == "confirmed":
            if item.get("location") and item.get("evidence"):
                found.append(item)
    return found


def certify(report: dict, *, snapshot: str, runner: dict | None) -> dict:
    """Return PASS, FAIL, ERROR, or NOT_RUN. Ignores report['gate_pass']."""
    if report.get("reviewed_snapshot") != snapshot:
        return {
            "status": "FAIL",
            "reason": "review snapshot does not match the tree being certified",
            "authoritative_gate_pass": False,
        }
    if not isinstance(report.get("findings"), list):
        return {"status": "ERROR", "reason": "findings is missing", "authoritative_gate_pass": False}
    blocking = blocking_findings(report, snapshot=snapshot)
    if runner is None:
        return {
            "status": "NOT_RUN",
            "reason": "no runner record; missing tests are not a pass",
            "blocking": len(blocking),
            "authoritative_gate_pass": False,
        }
    if runner.get("snapshot") != snapshot:
        return {
            "status": "FAIL",
            "reason": "runner snapshot does not match the review snapshot",
            "authoritative_gate_pass": False,
        }
    if runner.get("status") not in {"PASS", "FAIL", "ERROR", "NOT_RUN"}:
        return {"status": "ERROR", "reason": "runner status is not a known result", "authoritative_gate_pass": False}
    if runner.get("status") != "PASS" or blocking:
        return {
            "status": "FAIL",
            "reason": f"runner={runner.get('status')} blocking={len(blocking)}",
            "authoritative_gate_pass": False,
        }
    return {
        "status": "PASS",
        "reason": "runner passed and no confirmed blocking finding is current",
        "authoritative_gate_pass": False,
        "ignored_model_gate_pass": report.get("gate_pass"),
    }


def grade_review(report: dict, inventory: dict) -> dict:
    """Score a review against a hidden defect inventory.

    ``inventory`` maps defect id -> {severity, present, file}. The review's
    findings carry ``id`` values. This grades a report; it does not invent one.
    """
    findings = {item.get("id"): item for item in (report.get("findings") or []) if isinstance(item, dict)}
    expected = [k for k, v in inventory.items() if v.get("present")]
    absent = [k for k, v in inventory.items() if not v.get("present")]
    critical = [k for k in expected if inventory[k].get("severity") == "critical"]
    detected = [k for k in expected if k in findings]
    missed = [k for k in expected if k not in findings]
    false_pos = [k for k in absent if k in findings and findings[k].get("severity") in BLOCKING]
    blocking_true = [k for k in detected if inventory[k].get("severity") in {"critical", "major"}]
    blocking_pred = [k for k, item in findings.items() if item.get("severity") in BLOCKING]
    precision_den = len(blocking_pred)
    precision_num = len([k for k in blocking_pred if k in blocking_true or (k in inventory and inventory[k].get("present"))])
    return {
        "detected": detected,
        "missed": missed,
        "false_positives": false_pos,
        "critical_missed": [k for k in critical if k in missed],
        "precision_blocking": (precision_num / precision_den) if precision_den else None,
        "precision_denominator": precision_den,
        "recall_denominator": len(expected),
    }
