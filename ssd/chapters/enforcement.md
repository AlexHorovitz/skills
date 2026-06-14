<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

## Methodology Enforcement (runs on /ssd gate)

Before `/ssd gate` passes, the orchestrator invokes the executable gate-rules script and refuses to
pass on any FAIL:

```bash
bash methodology/gate-rules.sh --base <base-branch> --json
```

The script (defined in `methodology/SKILL.md` § "Gate Rules — Executable") emits structured results
per rule. Each rule maps to a principle in `methodology/core.md`.

| Rule (script) | Doctrine cite | What it checks |
|---|---|---|
| `wip-commits` | core.md §4 | `git log <base>..HEAD --grep='WIP\|checkpoint\|TODO.*tomorrow\|FIXME.*later' -i` is empty |
| `tests-pass` | core.md §1 | Project's `test_command` (from `.ssd/project.yml`) exits 0 |
| `feature-flag-present` | core.md §3 | Project's `feature_flag_marker` appears in non-doc changed files (skipped for documentation/config-only diffs) |
| `adr-delta` | core.md §2 | If architectural diff > 200 lines outside test/doc/migration scope, `docs/decisions/` has a new or modified ADR |
| `frontmatter-valid` | ADR-0006 | Every changed `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md` artifact validates against its skill schema (via `methodology/frontmatter-validate.py`) |
| `no-leaky-state` | [ADR-0008](../../docs/decisions/ADR-0008-ssd-commit-split.md) | No file matching the `.ssd/` selective-commit deny-list (machine state: `current.yml`, `init-log.md`, `archive/`, `audits/`, etc., plus project-supplied `project.yml.ssd.gitignored_state`) appears in the diff. Catches force-add and edited-gitignore bypasses. SKIPs cleanly on `gitignore_mode: blanket` projects. |
| `skill-version-sync` | core.md §2 | Each `<project-root>/*/SKILL.md`'s required-frontmatter example `version:` matches that file's `**Version:**` banner (via `frontmatter-validate.py --check-skill-examples`). SKIPs files using a placeholder example or projects with no in-repo SKILL.md example blocks. |
| `migration-manifest-current` | [ADR-0013](../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md) | (v1.24.0+) `methodology/migrations.yml` is structurally healthy: required fields per entry, unique `id`s, ascending `introduced_in` (append-only), none newer than `VERSION`. Closes R2 (manifest drift) at the structural level. SKIPs cleanly in any project without `methodology/migrations.yml` (i.e. everything except the SSD skills-library repo itself). The "a convention changed but no entry was added" judgment remains a documented human release obligation. |

Rule outputs:
- `PASS` — rule applied and verified.
- `SKIP` — rule didn't apply (no test command in `project.yml`, no diff vs base, doc-only change, etc.).
- `FAIL` — rule applied and was violated.

The script exits non-zero on any FAIL. The orchestrator parses the structured output, names the
failing rule with its doctrine cite, and refuses to pass the gate.

"I know better" is not an override — use `/ssd ship --force` (logged) if the team has a deliberate
exception. Direct invocation of the script is supported for CI:

```bash
bash methodology/gate-rules.sh --base main           # text mode
bash methodology/gate-rules.sh --base main --json    # JSON for jq / CI parsing
```

See [ADR-0005](../../docs/decisions/ADR-0005-gate-execution-model.md) for why this is a bash script
rather than orchestrator-internal LLM checks.

**Cross-workstream overlap check (v1.17.0+).** When `/ssd gate` runs on a workstream that has
peers in `current.yml.active[]`, the orchestrator additionally (a) updates the gated workstream's
`touches:` by unioning `git diff --name-only <base>...HEAD` into the recorded list, and (b)
invokes `code-reviewer` which consults the peers' `touches:` fields and emits informational
OVERLAP-N findings (SUGGESTION tier) for any file-set intersections. The gate is NOT blocked
by overlap. See [`code-reviewer/SKILL.md`](../../code-reviewer/SKILL.md) § "Cross-Workstream Overlap
Check" for the full algorithm and [ADR-0007](../../docs/decisions/ADR-0007-parallel-features.md)
for the design rationale.

**Workstream-aware base detection (v1.17.0).** The default `--base main` for `gate-rules.sh`
is kept by design — the script remains standalone and CI-friendly. The orchestrator, when
invoking the script on behalf of a workstream, passes `--base <ref>` explicitly (typically
`origin/main`). Future iteration D's `/ssd workstream` commands may introduce a `base:` field
on the workstream entry; until then the orchestrator computes the appropriate base from the
git context.

---

