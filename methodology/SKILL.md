# SSD Methodology

<!-- License: See /LICENSE -->

**Version:** 1.4.0

## Purpose

Explain and apply the Shippable States Development doctrine. Answer questions about SSD principles, help users evaluate whether they are following SSD correctly, and guide decision-making in ambiguous situations. Also provides the machine-checkable rule source that `/ssd gate` enforces and the self-adherence scoring invoked by `/methodology score`.

## Interface

| | |
|---|---|
| **Input** | User question about SSD doctrine, or the active project's repo/metrics for a `/methodology score` run |
| **Output** | Explanation of the relevant SSD principle (reference mode) OR an SSD-adherence score report (`.ssd/methodology-score-YYYY-MM-DD.md`) |
| **Consumed by** | `ssd` (`/ssd gate` reads doctrine rules from `core.md` for mechanical enforcement) |
| **SSD Phase** | Reference for any phase; `/methodology score` runs on-demand |

## When to Use

Invoke this skill when:
- A user asks "what does SSD say about X?"
- A user wants to understand a specific principle (shippable state, ratchet, feature flags)
- A user is evaluating whether a decision is consistent with SSD
- A user is onboarding to SSD and wants the full doctrine

Do not invoke this skill for active coding sessions — use `/ssd feature` instead.

---

## Reference Files

This skill is organized into three focused files. Load the relevant file based on the user's question:

| File | Contents | Load when |
|---|---|---|
| `core.md` | Iron Law, Five Principles, Decision Framework, Metrics, Mindset | User asks about SSD principles or doctrine |
| `patterns.md` | Five implementation patterns, Advanced topics (dependencies, DB migrations, emergencies) | User asks "how do I implement X with SSD?" |
| `adoption.md` | Getting started checklist, Common objections, Org adoption, Comparisons to Agile/CD/TBD, Resources | User is onboarding a team, handling pushback, or comparing SSD to other methods |
| `gate-rules.sh` | Executable bash routine implementing the methodology gate rules; invoked by `/ssd gate` | Automated — not loaded in conversation. See [ADR-0005](../docs/decisions/ADR-0005-gate-execution-model.md). |
| `frontmatter-validate.py` | Python validator for SSD artifact YAML frontmatter; invoked by the `frontmatter-valid` gate rule | Automated — runs against `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md`. |
| `schemas/<skill>.yml` | Per-skill schema describing required frontmatter fields and types | Read by `frontmatter-validate.py`. One file per consuming skill. |

**Default**: Load `core.md`. It covers the stable doctrine that answers most questions.

**On first invocation**: Read `core.md` and answer from it. If the user's question is about implementation specifics, also read `patterns.md`. If about team dynamics or objections, also read `adoption.md`.

Note: the `adoption.md` file mixes individual-team onboarding with organization-wide change management.
When loading it, select the relevant subsection for the user's audience (team onboarding vs. executive
rollout) and skip the other. If `adoption.md` has been split into `adoption-team.md` and
`adoption-org.md`, load only the one that matches the question.

Methodology comparisons in `adoption.md` (Agile, CD, TBD, etc.) are date-stamped at the top of the
section. If the comparison is > 12 months old, note that to the user and offer to refresh it rather
than repeating it as fact.

---

## `/methodology score` — Self-Adherence Metric

Invoke this mode when the user asks "are we following SSD?" or when `/ssd milestone` wants a baseline
for methodology adherence. The skill reads the repo and computes the five SSD metrics:

| Metric | Source | Target |
|---|---|---|
| Deployment frequency | `git log` on main; deploy markers in CI logs | ≥ 1/day (team); ≥ 1/week (solo) |
| % of new code behind feature flag | Delta of `feature_flags` config; grep for flag decorators | > 90% |
| Test coverage | Project test command with coverage flag | > 70% baseline; trend ≥ 0 |
| Mean time-to-deploy | CI run duration on main | < 15 min |
| Shippable states per week | Count of commits on main that passed `/ssd gate` | ≥ 5 |

Output: `.ssd/methodology-score-YYYY-MM-DD.md` with the score table, trends vs. the prior score (if
any), and the two lowest-scoring metrics flagged as remediation candidates.

---

## Gate Rules — Executable

The `Methodology Enforcement` table in `ssd/SKILL.md` documents the rules `/ssd gate` enforces. As of
v1.3.0 those rules are **executable**: implemented as a bash routine at `methodology/gate-rules.sh`
that the orchestrator invokes synchronously on `/ssd gate` (and at the gate boundary inside
`/ssd ship`).

The script:
- Reads project metadata from `.ssd/project.yml` (test command, feature-flag marker).
- Emits one structured line per rule (`PASS|FAIL|SKIP <rule-name> :: <detail>`).
- Exits 0 if every applicable rule is PASS or SKIP; non-zero on any FAIL.
- Skips rules whose preconditions don't apply (e.g., no `test_command` in `project.yml` → SKIP, not
  FAIL).

Rules implemented in v1.4.0:

| Rule | Doctrine cite | What it checks |
|---|---|---|
| `wip-commits` | core.md §4 (No WIP on main) | `git log <base>..HEAD --grep='WIP\|checkpoint\|TODO.*tomorrow\|FIXME.*later' -i` is empty |
| `tests-pass` | core.md §1 (Constant Production Parity) | Project's `test_command` (from `project.yml`) exits 0 |
| `feature-flag-present` | core.md §3 (Feature flags for new code) | Project's `feature_flag_marker` (from `project.yml`) appears in non-doc changed files |
| `adr-delta` | core.md §2 (Documentation matches implementation) | If architectural diff exceeds threshold (200 lines outside test/doc/migration scope), `docs/decisions/` has a new or modified ADR |
| `frontmatter-valid` | structured output requirement (SSD/SKILL.md § "Structured Output Requirements") | Every changed `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md` artifact has YAML frontmatter that validates against its skill's schema in `methodology/schemas/<skill>.yml`. SKIPs if Python 3 or PyYAML are missing (graceful degradation). |

The script is the source of truth — `cat methodology/gate-rules.sh` answers "what does the gate
actually check?" Direct invocation is supported for CI integration:

```bash
bash methodology/gate-rules.sh --base main          # text mode
bash methodology/gate-rules.sh --base main --json   # structured output for jq
```

See [ADR-0005](../docs/decisions/ADR-0005-gate-execution-model.md) for the rationale on bash vs.
LLM-internal vs. compiled-binary execution.

Future rules: deployable check (CI status integration), more sophisticated flag detection,
lint/typecheck rules. Schema-level enhancements: per-field enum/regex validation, sub-dict shape
validation (currently `frontmatter-valid` checks only top-level field types).

### Frontmatter validator

The `frontmatter-valid` rule shells out to `methodology/frontmatter-validate.py`. The validator:

- Walks `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md` (or specific paths
  passed as arguments).
- Parses the YAML frontmatter at the top of each file.
- Matches the file to a schema in `methodology/schemas/<skill>.yml` based on filename suffix
  (e.g., `01-architect.md` → `architect.yml`).
- Validates field presence and top-level type. Schemas are deliberately scoped to structural
  validation in v1; sub-field shape and enum/regex constraints are documented in each
  SKILL.md's "Required output frontmatter" block but not yet enforced here.

Direct invocation:

```bash
python3 methodology/frontmatter-validate.py                  # walks .ssd/ from cwd
python3 methodology/frontmatter-validate.py path1.md path2.md  # specific files
python3 methodology/frontmatter-validate.py --json           # structured output
```

Requires Python 3.8+ and PyYAML. Both gate-rules.sh and the validator emit clear messages and
SKIP rather than FAIL when either is missing.

Schemas live in `methodology/schemas/`. Adding a new skill's schema is a 5-line YAML file —
see existing schemas for format. Adding a new validator type (beyond `string`/`int`/`bool`/`list`/`dict`/`timestamp`) is a one-line addition to `TYPE_MAP` in the validator.

---

## Changelog

- **1.4.0** (2026-04-29) — Frontmatter schema validator. New file
  `methodology/frontmatter-validate.py` (Python 3 + PyYAML) and schema directory
  `methodology/schemas/` with per-skill schemas (architect, coder, code-reviewer,
  systems-designer). New `frontmatter-valid` gate rule (5th rule in `gate-rules.sh`) validates
  every `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md` artifact's frontmatter
  against its skill schema. SKIPs if Python 3 or PyYAML are unavailable. Two new fixtures in
  `scripts/parity-test.sh` (valid + invalid frontmatter); harness now runs 14 assertions, all
  passing. Iter A of the open-deferred-items work that closes the epic's "frontmatter validator"
  ambition.
- **1.3.1** (2026-04-28) — `gate-rules.sh` round-2 fixes from iteration-1 code review:
  (a) `feature-flag-present` now greps the diff's added lines (`^+[^+]`) instead of file contents,
  closing a silent-false-PASS when unflagged code is added to a file that already contained a flag
  marker elsewhere (MAJOR-1).
  (b) Both `feature-flag-present` and `adr-delta` build a properly-quoted bash array of changed
  files instead of unquoted `$(echo ... | tr)` substitution, closing a silent-SKIP on filenames
  with spaces or shell metacharacters (MAJOR-2).
  (c) `--base` argument validation rejects missing values and adjacent flags
  (`--base --json` → exit 2, MINOR-2).
  (d) `yaml_get` now skips comment lines so `# test_command: pytest` documentation is no longer
  read as a value (MINOR-1).
  Synthetic tests for both MAJORs confirmed: file with pre-existing flag + unflagged addition →
  correct FAIL; spaced directory + ADR-less architectural change → correct FAIL.
- **1.3.0** (2026-04-28) — Gate rules became executable: new file `methodology/gate-rules.sh`
  implements four mechanical checks (`wip-commits`, `tests-pass`, `feature-flag-present`,
  `adr-delta`) with structured stdout (`STATUS RULE :: DETAIL`) and `--json` mode for CI
  consumption. Added `Gate Rules — Executable` section to this SKILL.md. Reference: ADR-0005.
  Iteration 1 of the ssd-skill-upgrades epic.
- **1.2.1** (2026-04-28) — Working-tree path references updated from `ssd/` to `.ssd/` per repo-wide convention change. See repo CHANGELOG [1.4.0]. No behavior change.

- **1.2.0** (2026-04-18) — Clarified that methodology now provides machine-checkable rule source for
  `/ssd gate` enforcement (M1); added `/methodology score` self-adherence metric invocation (M2);
  documented audience-split expectation for `adoption.md` (M3); required date-stamped comparisons to
  other methodologies with 12-month refresh prompt (M4).
- **1.1.0** — Split into `core.md`, `patterns.md`, `adoption.md`.
- **1.0.0** — Initial release.
