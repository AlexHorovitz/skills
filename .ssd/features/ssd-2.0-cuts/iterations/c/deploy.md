---
skill: ssd
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#c
phase: ship
version: 2.2.0
gate_pass: true
gate_rounds: 1
---

# Deploy — ssd-2.0-cuts iter C (v2.2.0) — epic close

Final iteration of the SSD 2.0 subtraction (ADR-0012, issue #15). Gate PASS round-1
(blocker=0/major=0; QUESTION-1 + SUGGESTION-1 non-blocking, recorded). Parity 59/59.

## Ship checklist (markdown skills library — "ship" = tag + push to GitHub)

- [x] `/ssd gate` clean — executable rules + code-reviewer, gate_pass: true
- [x] Parity harness green (59/59)
- [x] `migration-manifest-current` PASS (VERSION 2.2.0)
- [x] Branch `add-ssd-2.0-cuts-c` committed (e9934fc)
- [ ] **Push branch + open PR** (outward — awaiting user approval)
- [ ] **Merge PR** → tag `v2.2.0` on the merge commit
- [ ] **D2** — post the revisit-ledger comment on #15 (ADR-0012 Pillar 4 / ADR-0011), or confirm present
- [ ] **D4** — dogfood `--adopt` on this repo so it records 2.2.0 (zero drift):
      `bash methodology/migrate.sh --adopt profile-concept-removed`
      `bash methodology/migrate.sh --adopt single-surface-doctrine`
- [ ] Archive `ssd-2.0-cuts` workstream (epic #15 complete)

## Post-merge tag command

```bash
git tag -a v2.2.0 <merge-sha> -m "v2.2.0 — SSD 2.0 iter C: deprecation path (obsoleted_in); epic complete"
git push origin v2.2.0
```

## Epic close note

With iter C, the ssd-2.0-cuts epic (ADR-0012, #15) is complete: iter A (v2.0.0, profile removal),
iter B (v2.1.0, single surface + verb collapse), iter C (v2.2.0, deprecation path). The reversibility
contract (ADR-0012 § "Revisit when") lives on #15 as the ADR-0011 revisit-aware ledger.
