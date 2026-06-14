<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

> **⚠️ 2.0 deletion candidate (ADR-0012 Pillar 1).** This entire chapter — the
> `novice|standard|expert` enum, teaching-mode decay, auto-promotion, and the bridge flags — is slated
> for **removal** in SSD 2.0, replaced by progressive disclosure (the no-arg Auto-Detect in the spine
> already *is* that replacement; safety behaviors become unconditional). It was **relocated here, not
> deleted**, by the v1.25.0 chapter-split (path A) so the 2.0 cut is a one-file `rm` + removing the
> spine stub. The removal is the contested cut, gated on **accepting ADR-0012** — do not delete on the
> 1.x line. Until then this remains the live, authoritative profile doctrine.

## Developer Profile + Teaching Mode

Two audiences use SSD: newcomers who want the system to decide for them, and experienced
engineers who want every step explicit. The `developer_profile` field in `.ssd/project.yml`
adjusts defaults without forking the product. See
[ADR-0004](../../docs/decisions/ADR-0004-developer-profile-and-teaching-mode.md) for the rationale.

### Profile values

```yaml
# .ssd/project.yml
developer_profile: novice | standard | expert    # default: standard
teaching_mode:
  enabled: true|false                            # auto-true for first 5 invocations
  invocations_remaining: <int>                   # decay counter; default 5
```

**Profile is a hint, not a gate.** A novice can always invoke any command an expert can; the
orchestrator only adjusts defaults (confirmations, narration verbosity, prompt-for-or-skip).
Discoverability via `/ssd --explain "<intent>"`, never gatekeeping.

### Profile-aware defaults

| Profile | Default surface | Phase commands | Confirmations | Narration | YAML editing | `switch_note_default` |
|---|---|---|---|---|---|---|
| novice   | conversational | rejected with hint | yes, on irreversible steps | full | discouraged (`current.notes.yml` only) | `prompt` |
| standard | conversational | accepted           | only on destructive ops      | concise | allowed | `prompt` |
| expert   | command (or conversational, user choice) | accepted | none | minimal | expected | `auto` |

The `switch_note_default` column (added v1.15.0, [ADR-0007](../../docs/decisions/ADR-0007-parallel-features.md))
controls the handoff-note capture behavior of `/ssd switch <slug>` (iteration B). The per-profile
default can be overridden in `.ssd/project.yml.ssd.switch_note_default` (values: `prompt | auto | skip`).

### Profile-aware sub-skill behavior

The table above is the **orchestrator's** profile knobs. The sub-skills are profile-aware only where
profile changes output *substance* (which markers, findings, voices, or checklist items are
produced) — never mere tone, which stays the orchestrator's job. See
[ADR-0010](../../docs/decisions/ADR-0010-profile-aware-subskills.md) for the boundary rule. This table
is the single source of truth; each sub-skill's SKILL.md points back here.

**How a sub-skill learns the profile:** when the orchestrator invokes a profile-aware sub-skill, it
states the active `developer_profile` (read from `.ssd/project.yml`) in the invocation context. This
is a prose contract, like the rest of the methodology — there is no separate machine parameter. A
sub-skill invoked ad hoc (outside the orchestrator) defaults to `standard` behavior.

| Sub-skill | novice | standard (baseline) | expert |
|---|---|---|---|
| `architect` | *profile-invariant* — design rigor is absolute | *(unchanged)* | *(unchanged)* |
| `methodology` | *profile-invariant* — `/methodology score` is an absolute metric | *(unchanged)* | *(unchanged)* |
| `refactor` | *profile-invariant* — the refactor plan is substance; verbosity is the orchestrator's | *(unchanged)* | *(unchanged)* |
| `systems-designer` | full annotated checklist — every item + the "why" | standard checklist | terse: core items only |
| `coder` | more `# REVIEW:` markers — flag every uncertainty | markers on genuine uncertainties | minimal — only blocking unknowns |
| `code-reviewer` | MINOR **and** NIT reported inline (teaching) | MINOR inline, NIT summarized | MINOR/NIT summarized; focus on BLOCKER/MAJOR |
| `codebase-skeptic` | focused voice subset (≤4 most relevant) | relevant voices (today's behavior) | all relevant voices |

**Invariant guarantee (normative).** Profile tunes *teaching breadth*, never correctness. A
`code-reviewer` BLOCKER/MAJOR and a `codebase-skeptic` 💀/🔴 finding surface at **every** profile,
the `gate_pass` computation is profile-independent, `systems-designer` safety-critical gates
(rollback, migration safety, observability) apply at every profile, and `coder` halts handoff on a
genuine blocker at every profile. `standard` behavior is unchanged from pre-v1.20.0 — `novice` and
`expert` are deltas around it. A future skill declares its profile
stance (invariant or which knob) at creation, the same way it declares a priority rule in
§ "Resolving Skill Overlap".

### Teaching mode

When enabled, the orchestrator appends a one-line *"under the hood: I called `architect` because
we're at phase=design"* to every conversational turn. `teaching_mode.invocations_remaining`
decrements per turn; at 0, teaching mode disables itself.

- `/ssd --teach` re-enables (resets counter to 5).
- `/ssd --no-teach` disables permanently for this project.
- Auto-promotion: a successful command-surface invocation while on `novice` triggers a one-time
  prompt to switch to `standard`; >2 manual edits to `current.yml` while on `standard` triggers a
  one-time prompt to switch to `expert`. Each prompt asks at most once per project; decay is
  permanent.

### Bridge flags

Either surface can reveal the other:

| Flag | Surface | Effect |
|---|---|---|
| `--explain` | conversational | Dry-run; emit the exact command sequence the orchestrator would invoke. |
| `--narrate` | command | Emit the conversational summary alongside structured output (good for CI logs). |
| `--raw` | conversational | Dump raw `current.yml` instead of the 3-sentence summary. |
| `--teach` | both | Re-enable teaching mode (resets counter). |

No surface hides anything from the other. No commands exist only in one surface. No state lives
only in one surface.

---

