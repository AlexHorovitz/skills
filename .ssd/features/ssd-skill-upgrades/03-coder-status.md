---
skill: coder
version: 1.1.1
produced_at: 2026-04-28T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-skill-upgrades / iteration 1 (P1.6 + P1.7)
consumed_by: [code-reviewer]
files_touched:
  - VERSION
  - CHANGELOG.md
  - ssd/SKILL.md
  - methodology/SKILL.md
  - methodology/gate-rules.sh
  - ssd-init/SKILL.md
  - docs/decisions/ADR-0002-current-yml-split.md
  - docs/decisions/ADR-0005-gate-execution-model.md
  - .ssd/current.yml
  - .ssd/current.notes.yml
  - .ssd/current.yml.bak
tests_added:
  - methodology/gate-rules.sh (smoke-tested in text + JSON modes; both exit 0 with expected SKIP behavior on this repo)
review_markers: 0
test_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: |
    PASS wip-commits :: no WIP/checkpoint commits between main and HEAD
    SKIP tests-pass :: no test_command in .ssd/project.yml
    SKIP feature-flag-present :: no feature_flag_marker in .ssd/project.yml
    SKIP adr-delta :: no diff vs main
lint_results:
  command: "n/a — no linter configured in this skills-library repo"
  exit_code: null
type_check_results:
  command: "n/a — markdown + bash; no static type checker applies"
  exit_code: null
feature_flag:
  name: not_applicable
  default: not_applicable
  rationale: |
    This skills library has no runtime; "feature flags" don't exist as a concept here.
    Explicitly declared not_applicable in the epic architect doc § "Feature Flag Plan."
    Per-iteration shippable state is the equivalent risk control.
spec_drift: false
---

# Iteration 1 Coder Status

## Scope

Per [01-architect.md](01-architect.md) iteration 1: **P1.6 (executable gate automation) + P1.7
(`current.yml` v2 split)**, bundled because they share no dependencies and individually localize.
Authored ADR-0002 and ADR-0005.

## What was built

### P1.6 — Executable gate rules (ADR-0005)

- **New file** `methodology/gate-rules.sh` — bash routine implementing four mechanical checks
  (`wip-commits`, `tests-pass`, `feature-flag-present`, `adr-delta`) over a git diff range. Emits
  one `STATUS RULE :: DETAIL` line per rule and supports a `--json` mode for CI consumption. Exits
  non-zero on any FAIL.
- **`methodology/SKILL.md` (v1.2.1 → v1.3.0)** gained a "Gate Rules — Executable" section
  describing the script, the rule table, and direct-invocation usage. The reference-files table now
  lists `gate-rules.sh` as automated (not loaded into LLM conversation context).
- **`ssd/SKILL.md` (v1.3.0 → v1.4.0)** § "Methodology Enforcement" rewritten to invoke the script
  synchronously on `/ssd gate`. Old prose-rule table replaced with the rule-name → doctrine-cite
  table. Refusal-to-pass behavior preserved; "I know better" override (`/ssd ship --force`) still
  the only escape hatch.

The script reads `.ssd/project.yml` for `test_command` and `feature_flag_marker`. When those keys
are absent (as in this repo), the rules SKIP rather than FAIL. SKIP outcomes are tracked separately
from PASS in the JSON output so downstream tooling can distinguish "rule passed" from "rule didn't
apply."

### P1.7 — `current.yml` v2 split (ADR-0002)

- **`.ssd/current.yml`** is now schema-validated with `schema_version: 2`. Carries `slug`, `phase`,
  `iteration`, `started`, `last_touched`, `budget_hours`, `elapsed_hours`, `gate_rounds`,
  `rail_deviations`, `blockers` per active workstream, plus `archived`.
- **`.ssd/current.notes.yml`** (new) — free-form sidecar for handoff notes, scope changes, questions
  for the next session, and anything else that doesn't fit the schema. Loaded by the orchestrator
  but never validated.
- **`ssd-init/SKILL.md` (v1.2.0 → v1.3.0)** Step 7 split into two paths:
  - **Fresh project**: create both files with templates.
  - **Legacy v1 detected** (no `schema_version`): refuse silent rewrite. Prompt user: `[yes /
    skip-this-session / show-diff]`. On `yes`: write `.bak`, build proposed v2 + notes from the v1
    contents, show user, await explicit confirmation. The `.bak` stays in place after migration.
  - Updated init-log template + Quality Checklist to track both files.
- **`ssd/SKILL.md` § "Session Continuity"** rewritten to document the v2 schema explicitly, the
  free-form notes file, the v1 detection / legacy-mode behavior, and the archive-on-close behavior
  (notes move to `archive/features/<slug>/notes.yml`).

### Forward-compatibility hooks

The v2 schema includes nullable / default-empty fields that future iterations populate without
another schema bump:

- `iteration` — populated by P1.1 in iteration 2.
- `gate_rounds` — incremented by P1.2 in iteration 3.
- `rail_deviations` — populated by P2.A in iteration 7.

This keeps athena's eventual migration to v2 a one-time event rather than a sequence of bumps.

## Dogfooding

This repo's own `.ssd/current.yml` was migrated v1 → v2 as part of this iteration:

- `.ssd/current.yml.bak` written from the v1 contents.
- New `.ssd/current.yml` contains only documented schema fields.
- New `.ssd/current.notes.yml` carries the workstream's `iteration_plan`, `next_iteration`,
  `notes`, and `handoff_notes` fields (all of which were undocumented in v1).
- `.bak` retained for reversibility per ADR-0002.

The migration was performed manually (not via the prompted `ssd-init` flow) since this is the
repo authoring the migration logic itself — chicken-and-egg. Athena and other consumer projects
will go through the prompted flow when they pick up v1.5.0.

## Spec drift

**None.** Implementation matches the epic architect doc:

- Rule names and behavior match § "Per-iteration scope and exit criteria" / Iteration 1.
- v2 schema fields match § "Data Model / `.ssd/current.yml` (v2 — machine-managed only)".
- Migration flow matches § "Back-Compat Story" requirement: migration is opt-in, prompted,
  reversible.
- ADR numbering matches the architect doc's pre-numbered table.

`spec_drift: false` in the frontmatter.

## Verification performed (in lieu of `tests_added`)

This is a markdown skills library — no formal test harness exists yet (that's iteration 9). Manual
verification:

| Check | Method | Result |
|---|---|---|
| `gate-rules.sh` runs in text mode | `bash methodology/gate-rules.sh --base main` | exit 0; 1 PASS + 3 SKIP |
| `gate-rules.sh` runs in JSON mode | `bash methodology/gate-rules.sh --base main --json` | exit 0; valid JSON; same rule outcomes |
| Script handles missing `project.yml` keys | `test_command` and `feature_flag_marker` absent → both rules SKIP, not FAIL | confirmed |
| Script handles non-git scenarios | `is_git_repo` guard returns SKIP for `wip-commits` | code path verified by reading; not exercised in this run |
| `current.yml` v2 parses as YAML | inspected file | well-formed; would parse with PyYAML / yaml.v3 / etc. |
| `current.notes.yml` parses as YAML | inspected file | well-formed |
| `.bak` written before migration | `ls -la .ssd/current.yml.bak` | present, matches v1 contents |
| ssd-init Step 7 documents the migration prompt | inspected SKILL.md edit | present, includes refuse-if-bak-exists guard |
| methodology SKILL.md changelog references ADR-0005 | grep | confirmed |
| ssd SKILL.md changelog references ADR-0002 | grep | confirmed |
| Repo VERSION = 1.5.0 | `cat VERSION` | confirmed |
| All three touched skills bumped a minor | grep `^\*\*Version:` | ssd 1.4.0, methodology 1.3.0, ssd-init 1.3.0 |

## Known limitations / future-iteration handoff

- **`adr-delta` rule on dirty trees**: when invoked on `main` with uncommitted changes (as in this
  iteration before commit), `git diff main...HEAD` is empty, so the rule SKIPs rather than checks
  the staged delta. The intended use is on a feature branch before merge; that's the case the rule
  is designed for. Future enhancement: a `--dirty` mode that includes uncommitted changes. Out of
  scope for iteration 1.
- **bash 3.2 vs 4+ portability**: smoke-tested on macOS bash 3.2. Some idioms (e.g., `local` outside
  functions) caused an early bug; fixed before commit. No `set -e` so all rules run regardless of
  upstream failure — this is intentional but worth a code-reviewer pass.
- **Rule heuristics are simple**: `feature-flag-present` and `adr-delta` use grep + size thresholds.
  False negatives possible (e.g., a flag invoked through indirection). Acceptable for v1.3.0; a
  later iteration can refine.
- **No fixture tests for the script**: a proper test harness (synthetic git repos, fixture
  `project.yml` files) is iteration 9. For now, the script is exercised via `/ssd gate` invocations
  on real repos.
- **The `notes` field migration is feature-scoped**: when v1 has unscoped keys (not tied to any
  feature), they go under `features.unscoped.handoff_notes` per ADR-0002 step 4. Iteration 1's
  ssd-init implementation describes this in prose but doesn't enforce it programmatically.
  Implementing the actual migration logic (vs documenting it) is part of the prompted-migration UX
  delivered by future ssd-init enhancements; for now the prompt and the file shape are documented,
  and migrations are operator-driven.

## Round 2 — closing the iteration-1 review findings

Code review ([04-code-review.md](04-code-review.md)) emitted 2 MAJOR findings on `gate-rules.sh`,
both within the gate-enforcement tool itself. Round 2 closes both, plus two trivial MINORs that
were related and cheap to fix in the same pass. QUESTIONs and SUGGESTION routed to the notes
sidecar for resolution across later iterations.

### Closed in round 2

- **MAJOR-1 (false PASS in `feature-flag-present`)** — closed. Rule now runs
  `git diff $BASE...HEAD -- "${non_doc_array[@]}" | grep -E "^\+[^+]"` and matches the marker
  against the diff's added lines, not file contents. **Synthetic test**: feature branch adds
  `def new_unflagged():` to a file that contained `flag_enabled("legacy")` from main → rule
  correctly emits `FAIL: marker not present in added code lines`, exit 1.
- **MAJOR-2 (silent SKIP/FAIL on paths with spaces or shell metachars)** — closed. New helper
  `read_lines_into_array <name>` builds a properly-quoted bash array (bash 3.2 compatible, no
  `mapfile`). Both `feature-flag-present` and `adr-delta` now pass the array via
  `"${array[@]}"` to `git diff`. **Synthetic test**: spaced path `src dir/mod.py` with flagged
  addition + 250-line architectural file lacking ADR → `feature-flag-present` PASS, `adr-delta`
  FAIL on the missing ADR. Exit 1.
- **MINOR-1 (`yaml_get` matches commented keys)** — closed. Awk now does
  `$0 ~ /^[[:space:]]*#/ { next }` before the key match. Verified: a YAML containing both
  `# test_command: rm -rf /` and `test_command: echo real_value` returns `echo real_value`.
- **MINOR-2 (`--base` accepts adjacent flags)** — closed. Argument parser rejects empty value
  AND `--*` prefixed value with exit code 2 and an explanatory stderr message.

### Routed to current.notes.yml (not blocking iteration 1)

- **MINOR-3** (CHANGELOG `.ssd/` links 404 on GitHub) → `NOTES-1`, decision needed before iter 2.
- **QUESTION-1** (`eval` trust model for `test_command`) → `NOTES-2`, deferred indefinitely;
  current behavior matches CI industry default.
- **QUESTION-2** (hard-coded `adr-delta` threshold of 200) → `NOTES-3`, target iteration 6.
- **SUGGESTION-1** (`( set -e )` subshell per rule) → `NOTES-4`, target iteration 9 alongside
  the parity test harness.

### Files touched in round 2

- `methodology/gate-rules.sh` (the four fixes; ~30 lines net change)
- `methodology/SKILL.md` (v1.3.0 → v1.3.1, changelog entry)
- `CHANGELOG.md` (round-2 fixes appended to the [1.5.0] entry)
- `.ssd/current.notes.yml` (deferred items NOTES-1 through NOTES-5 added)
- `.ssd/features/ssd-skill-upgrades/03-coder-status.md` (this section)

`spec_drift: false` still holds — round 2 was bug-fix work on the just-shipped script, not a
deviation from the architect doc.

### Verification commands run

```bash
# Smoke 1, 2: text + JSON modes still work on this repo (1 PASS + 3 SKIP, exit 0)
bash methodology/gate-rules.sh --base main
bash methodology/gate-rules.sh --base main --json

# Smoke 3: --base validation
bash methodology/gate-rules.sh --base                 # exit 2: '--base requires a value (got <empty>)'
bash methodology/gate-rules.sh --base --json          # exit 2: '--base requires a value (got --json)'

# Smoke 4: yaml_get rejects commented keys (verified manually)

# Synthetic 1: MAJOR-1 reproduces and closes
# (feature branch adds unflagged code to file with existing flag → FAIL, exit 1)

# Synthetic 2: MAJOR-2 reproduces and closes
# (spaced directory + 250-line arch change without ADR → ADR-delta FAIL, exit 1)
```

All passed.

---

## Recommended next action

`/ssd gate` re-run on the round-2 diff. Code-reviewer should re-verify MAJOR-1 and MAJOR-2 are
closed (multi-round gate substrate doesn't exist yet — that's iteration 3 — so this is an inline
re-verification rather than a `code-review/round-2.md` artifact). On clean re-review, iteration 1
ships and iteration 2 (P1.1, first-class iterations) opens.

The original "Recommended next action" was: code-reviewer should focus on:

1. **`methodology/gate-rules.sh`** — bash correctness, edge cases, portability (macOS 3.2 vs Linux
   4+).
2. **`ssd-init/SKILL.md` Step 7 prose** — does the migration UX make sense to a fresh reader?
3. **`ssd/SKILL.md` Session Continuity rewrite** — does the v2 schema + notes-sidecar + v1 fallback
   read coherently?
4. **The two ADRs** — do they meet the "context → decision → rationale → consequences →
   alternatives" template?
5. **Forward-compat fields** (`iteration`, `gate_rounds`, `rail_deviations`) — are they correctly
   nullable / default-empty so v2 ships even though their consumers don't exist yet?

After code-review clears, iteration 1 can land and iteration 2 (P1.1, first-class iterations) can
begin.
