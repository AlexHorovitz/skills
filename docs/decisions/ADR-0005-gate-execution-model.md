# ADR-0005: Gate automation via bash script (`methodology/gate-rules.sh`)

## Status
Accepted — 2026-04-28 — landed in iteration 1 of the ssd-skill-upgrades epic ([01-architect.md](../../.ssd/features/ssd-skill-upgrades/01-architect.md)).

## Context

The `Methodology Enforcement` table in `ssd/SKILL.md` documents six rules that `/ssd gate` is
supposed to verify mechanically:

1. Tests pass
2. No broken features
3. Documentation matches implementation
4. No WIP commits on main
5. Feature behind flag
6. Deployable

In practice none of these have been *executable*. The "checks" are prose descriptions of what a
human (or LLM operator) is supposed to verify. The original upgrade plan called this out explicitly:
*"a documented rule that isn't enforced is decoration. Either run it or remove the claim."*

Two execution-model candidates:

- **Bash script invoked by the orchestrator** (`methodology/gate-rules.sh`). Synchronous; structured
  exit codes; composable with `git`, `grep`, `jq`, project test commands.
- **Orchestrator-internal LLM checks.** The `/ssd` skill's prompt asks the LLM to perform each check
  using its tool access (Bash, Read, Grep, etc.).

## Decision

Implement gate automation as a **bash script: `methodology/gate-rules.sh`**. The orchestrator
invokes it synchronously on `/ssd gate` (and implicitly at the gate boundary inside `/ssd ship`).

The script:
- Reads project metadata from `.ssd/project.yml` (test command, feature flag system marker).
- Runs each rule and emits one structured line per rule (`PASS|FAIL|SKIP <rule-name> :: <detail>`).
- Exits 0 if every applicable rule is PASS or SKIP. Exits non-zero on any FAIL.
- Skips rules whose preconditions don't apply (e.g., no `test_command` in project.yml → skip the
  test rule with `SKIP` status, not FAIL).

Rules implemented:
1. `wip-commits` — `git log <base>..HEAD --grep='WIP\|checkpoint\|TODO.*tomorrow' -i` returns empty.
2. `tests-pass` — runs the project's test command (from `project.yml`). SKIP if absent.
3. `feature-flag-present` — heuristic grep over the diff for the project's flag-system marker
   (`flag_enabled(`, `useFeatureFlag(`, etc., listed in `project.yml`). SKIP for repos without a
   flag system or for infra-only diffs (heuristic: diff touches only `*.md`, `LICENSE`, CI config).
4. `adr-delta` — if the diff touches files outside test / migration / markdown scope above a
   threshold, check for a new or modified ADR in `docs/decisions/`. SKIP for documentation-only
   repos.

Future rules (deferred to later iterations of the SSD-upgrades epic): deployable check
(integration with CI status), more sophisticated flag detection, lint/typecheck rules.

The orchestrator parses the script's stdout to render a pass/fail summary with cited rules and
either passes the gate or refuses with the failing rule named.

## Rationale

- **Composability.** Bash + Unix utilities (`git`, `grep`, `awk`, `jq`) is the right tool for
  whole-repo state checks. Reimplementing `git log --grep` inside an LLM prompt is comically
  inefficient.
- **Reproducibility.** The same script runs identically locally, in CI, on a developer's laptop,
  and inside an LLM session. An LLM-internal check varies with model temperature and context.
- **Testability.** A bash script can have its own tests (synthetic git histories, fixture
  `project.yml` files). LLM-internal checks can't be tested in the same way.
- **Auditability.** The script is the source of truth — `cat methodology/gate-rules.sh` answers
  "what does the gate actually check?" definitively. An LLM check requires reading the orchestrator
  prompt and inferring intent.
- **Speed.** A bash invocation is sub-second. An LLM-internal check requires a full turn.
- **Failure mode.** If the LLM doesn't run a check (forgets, runs out of context, decides it
  already passed), the gate silently succeeds. With a bash script, exit code 1 is exit code 1.

## Consequences

**Easier:**
- The gate is real, not aspirational.
- Anyone can run the gate by hand (`bash methodology/gate-rules.sh`) without invoking `/ssd`.
- CI integration is trivial (call the script in a workflow step).

**Harder:**
- Bash maintenance — the script must work across macOS bash 3.2 and Linux bash 4+. POSIX-compliant
  where possible; bash-specific features documented when used.
- Windows users need WSL or git-bash. Acceptable: the SSD audience uses Unix-flavored shells.
- The script needs to know the project's test command, flag system, etc. — read from
  `project.yml`. If `project.yml` is missing or incomplete, the rule SKIPs with a clear message
  rather than failing.

**What we give up:**
- Dynamic LLM judgment in the gate. The rules are mechanical, not "smart." This is a feature, not
  a bug — the whole point is that the gate is not subject to LLM goodwill.

## Alternatives Rejected

- **Orchestrator-internal LLM checks.** Rejected for all the reasons above: not testable, not
  reproducible, slow, silently skippable. The LLM's job is to *invoke* the gate and *interpret* the
  result, not to *be* the gate.
- **Per-language test runner integration.** (e.g., a pytest plugin that runs the gate.) Rejected
  for iteration 1 — would force every consumer project to install plugins. The bash script is
  language-agnostic.
- **A Go/Python/Rust binary.** Compile target adds friction (cross-platform builds, distribution).
  Bash is already on every Unix machine the audience uses.
- **Configuration-driven engine reading rules from YAML.** Tempting, but premature: we have 4 rules
  today, not 40. A single bash file is more readable than a generic engine + YAML.

## Future Compatibility

The script's stdout format (`STATUS RULE :: DETAIL` lines) is the contract. A future Go/Rust
reimplementation that emits the same format is a drop-in replacement. Calling code (the
orchestrator and CI) only depends on the format, not the implementation language.

## Performance Note

`gate-rules.sh` runs once per `/ssd gate` invocation. On a 100-commit feature branch in a 10k-LOC
repo, all rules complete in <2s. Slowness, when it appears, will be in the project's test command
itself — that's expected and not the gate's problem.
