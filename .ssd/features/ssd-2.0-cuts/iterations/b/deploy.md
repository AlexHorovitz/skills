---
skill: systems-designer
version: 1.5.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#b
consumed_by: [ssd]
deploy_ready: true
---

# Deploy Readiness — ssd-2.0-cuts iter B (v2.1.0)

`systems-designer` is **N/A in substance** for this change: the SSD skills library is markdown with no
runtime, no migrations, no infra. The standard production-readiness checklist (rollback, observability,
load, secrets, blue/green) does not map. The library "ships" by merging to `main`, tagging a version,
and pushing to GitHub (distribution channel: `direct-install`, per `.ssd/project.yml`).

## Readiness checklist (adapted to a docs/skills release)

- **Gate clean** — `/ssd gate` PASS round 1, blocker=0/major=0; parity 53/53; gate-rules exit 0
  (`skill-version-sync` PASS, `migration-manifest-current` PASS @ 2.1.0). ✓
- **Version coherent** — `VERSION` 2.1.0; `ssd` banner 2.1.0; CHANGELOG 2.1.0 entry present and ordered
  above 2.0.0. ✓
- **Non-breaking** — no `project.yml` key removed; every v1 invocation still works (NeXTSTEP held). A v1
  project consuming this library sees only a reorganized front-page; no migration required. ✓
- **Rollback** — trivial: revert the merge commit. No state, no data, no infra to unwind. ✓
- **Selective-commit hygiene** — `.ssd/current.yml` + `project.yml` (machine state) stay gitignored;
  the durable iter-B artifacts under `.ssd/features/ssd-2.0-cuts/iterations/b/` are committed. ✓
- **Distribution** — on merge + tag `v2.1.0`, users `git pull` / re-install to `~/.claude/skills/`. ✓

## Deploy steps

1. Commit the branch `add-ssd-2.0-cuts-b` (content + iter-B artifacts).
2. Push; open PR → `main`.
3. Merge; tag `v2.1.0`; push the tag.

deploy_ready: **true**.
