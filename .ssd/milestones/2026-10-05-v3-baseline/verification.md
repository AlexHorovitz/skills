---
skill: ssd
version: 2.14.0
produced_at: 2026-10-05T18:10:00Z
produced_by: implementation-agent
project: InsanelyGreat's SSD Skills Library
scope: T00 baseline inventory before any v3 behavior change
consumed_by: [ssd]
verification_result: recorded
---

# T00 — Baseline inventory and compatibility (unchanged product)

**Source revision:** `e732a935d6e76eb8c4ca29acc72985fdd505da8c` (`e732a93`, "updating gitignore (#57)").
**Library version file:** `2.14.0`.
**Recorded:** 2026-10-05, before any skill, prompt, hook, schema, or orchestrator edit.
**Plan reported the same revision.** Reconfirmed, not assumed.

This file separates observed facts, source-reported findings, and unverified assumptions.
No skill behavior and no user configuration was changed to produce it.

## Observed facts

| Fact | Evidence |
| --- | --- |
| Checkout matches the plan's reported baseline | `git rev-parse HEAD` = `e732a935d6e76eb8c4ca29acc72985fdd505da8c` on `main` |
| Library version | `VERSION` contains `2.14.0` |
| Eleven skills | `architect`, `code-reviewer`, `codebase-skeptic`, `coder`, `feynman`, `methodology`, `refactor`, `software-standards`, `ssd`, `ssd-init`, `systems-designer` |
| Frontmatter present on only two skills | `codebase-skeptic/SKILL.md`, `feynman/SKILL.md` start with `---`. The other nine start with a title |
| Entrypoints over 400 physical lines | `ssd-init` 987, `systems-designer` 677, `code-reviewer` 632, `feynman` 490, `software-standards` 429 |
| Entrypoints at or under 400 | `refactor` 328, `architect` 314, `ssd` 311, `coder` 308, `codebase-skeptic` 304, `methodology` 228 |
| Executable referees present | `methodology/gate-rules.sh`, `methodology/autorun.sh`, `methodology/deviation.sh`, `methodology/frontmatter-validate.py`, `scripts/parity-test.sh` |
| `gate-rules.sh --json` exists | Usage comment and implementation at the emit section. Not a guessed flag |
| Gate input key | `test_command` (`.ssd/gate.yml`). Not `test`, `tests`, or `testCommand` |
| Storage modes | `selective`, `blanket`, `private` (`gitignore_mode`) |
| Next ADR number | ADR-0020 is the last (`docs/decisions/`). Next authored record is ADR-0021 |
| License | Shareware, personal and internal use, © 2026 Alex Horovitz (`LICENSE`) |
| Default branch | `main` |
| Host at inventory | Linux 6.12.94+, Python 3.12.3, PyYAML 6.0.1, bash 5.2.21, git 2.43.0. `claude` CLI absent. `shellcheck` absent at inventory time (later installed in this environment only) |
| Unvalidated artifacts | `frontmatter-validate.py` on this tree: 112 PASS, 13 SKIP (no schema). The 13 are skeptic reports, refactor plans, `review-*.md`, `refactor-prs.md`, `verification.md` |
| Parity suite on the unchanged tree | `bash scripts/parity-test.sh` → **PASS 375/375**, exit 0 |
| Gate on the unchanged tree vs `main` | exit 0. 5 PASS, 8 SKIP, 0 FAIL. `tests-pass` ran `bash scripts/parity-test.sh` |

Skill version banners are per-skill (ADR-0009), not copies of the library version, except `ssd/SKILL.md`, whose banner tracks the library version at the last edit of that file (2.14.0).

## Stop and failure registry (extracted, not invented)

Source: `ssd/chapters/autonomy.md` and `methodology/autorun.sh`. These identifiers keep these meanings.

| ID | Meaning |
| --- | --- |
| STOP-1 | Gate still fails after `max_review_loops` coder↔reviewer rounds |
| STOP-2 | Next action would leave the rails. An auto-run writes zero deviations |
| STOP-3 | `budget_transitions`, `budget_wall_minutes`, or the workstream `budget_hours` exceeded |
| STOP-4 | Would have to guess: ambiguous brief/spec, missing prerequisite, or `--from` disagrees with the recorded phase |
| STOP-5 | User interjection. Best-effort; the script has no signal handler |
| STOP-6 | Phase-level hard failure. No retry |
| STOP-7 | `--until` ceiling reached. Not a verdict. Pair with `gate_result` and `outcome` |
| FM-1 | Workstream unresolvable. Run never starts |
| FM-2 | An auto-run is already in flight (or, on `transition`, no run is in flight) |
| FM-3 | Nothing to run (`done`, or already at/past the ceiling) |
| FM-4 | `--until` is `ship`, `deploy`, `rollout-advance`, `rollout`, or `flag-removal` |
| FM-5 | `autonomy.mode` is not `propose`, `advance`, or `run` |
| FM-6 | `finish --phase-reached gate` without `--gate-output` or `--gate-result` |

`outcome`: `green` = STOP-7 and `gate_result: pass`; `red` = STOP-1, STOP-6, or STOP-7 with `gate_result: fail`; `incomplete` = STOP-2, STOP-3, STOP-4, STOP-5, or STOP-7 with no gate result. A lock coordinates work. It does not authorize shipping.

## Source-reported findings (attributed to the plan, then checked here)

| Report claim | What this tree shows |
| --- | --- |
| v2.14.0 at `e732a93` | Confirmed |
| Skills missing portable frontmatter | Confirmed for 9 of 11. Two already have `name`/`description` |
| Entrypoints over a 400-line local contract | Confirmed for the five files above |
| Skeptic artifacts have no schema | Confirmed (`skeptic-before.md`, `skeptic-after.md` SKIP) |
| External project does not resolve library scripts | Confirmed by inspection: `frontmatter-valid` looks up `methodology/frontmatter-validate.py` under the **project** root only. An external project therefore SKIPs that rule instead of using the installed library. Reproduction is an executable test in the v3 suite, added with the fix |
| `gate-rules.sh --json` might not exist | It does exist. Later work may use it; it was not assumed before this read |

## Unverified assumptions

- No live model was called. Routing, review quality, and user-task success of the unchanged product are **not** measured here.
- `claude` is not installed, so native plugin validation, in-session `AGENTS.md` loading, and hook delivery inside Claude Code are not executed.
- Official platform docs were re-fetched on 2026-10-05 (Agent Skills spec, Claude Code skills, hooks, plugin manifest). They are documentation checks, not runtime tests. Notes live in `docs/releases/3.0.0/platform-notes.md` once that file lands.
- The two HTML roadmaps were not required and were not opened.

## Existing-check outcomes (unchanged product)

```text
command: bash scripts/parity-test.sh
cwd: repository root
revision: e732a935d6e76eb8c4ca29acc72985fdd505da8c
result: PASS
detail: PASS — 375/375 assertions
exit: 0
```

```text
command: bash methodology/gate-rules.sh --base main
cwd: repository root
revision: e732a935d6e76eb8c4ca29acc72985fdd505da8c
result: PASS
detail: GATE 5 pass · 8 skip · 0 fail
exit: 0
```

SKIPs are checks that did not run (no diff against `main` at this revision, no feature-flag marker, issue mirror off, no store link). They are not successes.

## Task record

```yaml
task_id: T00
status: completed
revision: e732a935d6e76eb8c4ca29acc72985fdd505da8c
changed_files:
  - .ssd/milestones/2026-10-05-v3-baseline/verification.md
acceptance_results:
  - check: inventory separates facts, source-reported findings, and assumptions
    result: PASS
    command: inspection recorded in this file
    evidence: .ssd/milestones/2026-10-05-v3-baseline/verification.md
  - check: every canonical stop identifier has its repository definition
    result: PASS
    command: extracted from ssd/chapters/autonomy.md and methodology/autorun.sh
    evidence: .ssd/milestones/2026-10-05-v3-baseline/verification.md
  - check: existing checks recorded, including known failures
    result: PASS
    command: bash scripts/parity-test.sh ; bash methodology/gate-rules.sh --base main
    evidence: this file; no known failing check on this revision
  - check: no skill behavior or user configuration changed during inventory
    result: PASS
    command: git status at inventory time was clean except this new record
    evidence: this file
runtime_environment: Linux 6.12 / Python 3.12.3 / PyYAML 6.0.1 / bash 5.2.21 / git 2.43.0 / no claude CLI
known_limitations:
  - Live model behavior was not measured.
  - shellcheck was not installed at the moment the parity suite ran.
blocked_by: []
review_artifact: null
human_decision_required: null
```
