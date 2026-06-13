---
skill: systems-designer
version: 1.22.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-upgrade#b
consumed_by: [ssd]
deliverables:
  component_diagram: false
  data_model: false
  api_contract: false
  adrs: [ADR-0013]
  risk_assessment: true
  readiness_checklist: complete
---

# Deploy Readiness — ssd-upgrade iteration B → v1.22.0

**Platform:** markdown skills library + bash/awk helpers. No runtime/network/data store. "Deploy" =
tag a version + push to GitHub (per `.ssd/project.yml` `distribution.channel: direct-install`).
`systems-designer` is otherwise N/A; this artifact records release readiness only.

## Gate status

| Check | Result |
|---|---|
| `bash scripts/parity-test.sh` | **PASS 37/37** (was 20) |
| `bash methodology/gate-rules.sh --base main` | exit 0 — all PASS/SKIP |
| `bash -n methodology/migrate.sh` | syntax ok |
| Code review (round 1 + inline round-2) | **gate_pass: true**; MINOR-1/MINOR-2 closed; 0 BLOCKER/MAJOR |

## Risk recap (ADR-0013)

- **R1 (corruption)** — held airtight: dry-run remains the default; `--apply` writes a `.bak` per
  mutated file, re-confirms via `detect`, and never deletes. `current-yml-v2` DEFERs rather than
  half-implementing the risky v1→v2 split.
- **R3 (guided silently ignored)** — held: the version bump stops below the first outstanding entry,
  so guided practices re-surface every run until adopted (verified on the drifted fixture).
- **R2 (manifest drift)** — unchanged; closed by iter C's `migration-manifest-current` gate rule.

## Backward compatibility

- Detect-only path (`/ssd upgrade` with no `--apply`) is byte-for-byte unchanged — existing fixtures
  13/14 pass untouched. Projects that never run `--apply` see zero behavior change.
- No `current.yml`/`project.yml` schema bump; no new manifest entry (iter B adds no project-visible
  convention, only the apply capability).

## Release steps (post-merge, human-run)

1. Merge PR to `main`.
2. `git tag -a v1.22.0 <merge-sha> -m "v1.22.0 — /ssd upgrade --apply (ssd-upgrade iter B)"`
3. `git push origin v1.22.0`

## Outstanding (tracked, not blocking)

- `ssd-init` → `migrate.sh` prose-extraction (closes SUGGESTION-1 pattern duplication; Hard Rule 4
  deferral) — separate follow-up PR, issue #17.
- Iter C (v1.23.0): guided-adoption tracking decoupled from the version gate + `migration-manifest-current`
  gate rule (R2).
