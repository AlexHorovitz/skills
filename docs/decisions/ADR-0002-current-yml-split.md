# ADR-0002: Split `current.yml` into machine-managed state + human-notes sidecar

## Status
Accepted — 2026-04-28 — landed in iteration 1 of the ssd-skill-upgrades epic ([01-architect.md](../../.ssd/features/ssd-skill-upgrades/01-architect.md)).

## Context

`.ssd/current.yml` (v1) carries two distinct kinds of information in one file:

- **Machine state** the orchestrator owns and validates: `slug`, `phase`, timestamps, hour budgets,
  blockers list, archived workstreams.
- **Human context** the user writes for the next session: handoff notes, scope-change explanations,
  questions for the next session, prose like "carried_to_pr_3c: [...]".

The file header says *"Managed by the /ssd orchestrator. Do not edit manually unless you know what
you're doing."* In practice users edit it constantly — observed in the athena project's
`talentos-reimagined-phase3-ui` feature, where the file accumulated keys outside the documented
schema (`pr_3a_ship`, `gate_round_1`, `carried_to_pr_3c`, `phase2_handoff_notes`) because the human
context had nowhere else to live. The "do not edit" rule was honored in spirit only.

Consequences of the mixing:
- The orchestrator can't schema-validate the file without rejecting valid human notes.
- A future programmatic consumer (a future `/ssd state get/set` command, a parity test harness)
  can't reason about the file's shape.
- Critics looking at SSD adherence can't tell which fields are doctrine and which are improvisation.

## Decision

Split `.ssd/current.yml` into two files:

1. **`.ssd/current.yml` (v2)** — machine-managed only. Schema-validated. Every field is documented
   in `ssd/SKILL.md` § "Session Continuity." Carries a `schema_version: 2` field.
2. **`.ssd/current.notes.yml` (NEW)** — free-form. Loaded as context by the orchestrator but never
   schema-validated. Lives alongside `current.yml`.

Detection: a file with no `schema_version` field is treated as v1. The orchestrator surfaces this
on the next invocation and offers a one-shot, prompted migration:

- Write `current.yml.bak` with the original contents (no overwrite if `.bak` already exists —
  refuse and ask the user).
- Move documented machine fields to the new `current.yml` v2.
- Move undocumented / free-form fields to `current.notes.yml`.
- The user reviews and confirms before the new files replace the old.

If the user declines migration, the orchestrator continues reading v1 (legacy path) and re-prompts
on next invocation. No silent rewrites, ever.

## Rationale

- **Pick one or the other.** Either the file is machine-owned or it isn't. The status quo is
  neither.
- **Schema validation becomes possible.** v2 has no human-edited fields by definition; the
  orchestrator can refuse a malformed v2 and tell the user exactly what's wrong.
- **Human notes get a home.** The notes file is explicitly free-form so users stop inventing keys
  in `current.yml`.
- **Forward-compatible with iteration 2.** v2 schema includes nullable fields (`iteration`,
  `gate_rounds`, `rail_deviations`) that the iteration-substrate iteration will populate without
  another schema bump.
- **Reversible.** A user can always read their `.bak` and revert manually. The migration writes
  files; it does not delete the original until the user confirms.

## Consequences

**Easier:**
- Programmatic consumers can rely on `current.yml` shape.
- Schema validation can be added (yamllint with a schema, or a custom check in `gate-rules.sh`).
- Future `/ssd state get/set` and the parity test harness work without parsing prose.

**Harder:**
- Two files to keep mentally synchronized when reasoning about a workstream's state.
- Tooling (e.g., editors, IDE plugins) that assumed one file needs to look in both.

**What we give up:**
- The (illusory) simplicity of a single file. The mixing was already costing us; making the cost
  explicit is the win.

## Alternatives Rejected

- **Keep v1 and document it harder.** Status quo. Doesn't fix the leak; users will continue
  improvising keys.
- **Strict v1 schema with no notes allowed.** Loses the human context that's load-bearing for the
  next session. Users would just write notes in commit messages or session transcripts and lose the
  per-feature locality.
- **Embed notes inside structured fields** (e.g., a `notes:` block per active entry). Still
  mixed concerns: a future `/ssd state set blockers` command would have to skip past prose to find
  the structured fields. Half-measure.
- **Auto-migrate without prompting.** Disrespects user data; could lose information if migration
  logic has a bug. One-shot prompted migration with `.bak` preserves trust.

## Migration Path Summary

```
v1 detected (no schema_version)
   ↓
orchestrator surfaces: "Migrate to v2 split? [yes/skip-this-session]"
   ↓ yes
write current.yml.bak (refuse if .bak exists)
   ↓
emit proposed current.yml (v2) and current.notes.yml
   ↓
user reviews → confirms
   ↓
old current.yml replaced; current.notes.yml created
   ↓
schema_version: 2 in current.yml from now on
```

Refusing migration is a permitted state — legacy v1 readers in the orchestrator continue to work
indefinitely. Migration is a feature, not a forced upgrade.
