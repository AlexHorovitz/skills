# ADR-0004: `developer_profile` field semantics + teaching-mode decay

## Status
Accepted — 2026-04-29 — landed in iteration 8 of the ssd-skill-upgrades epic ([epic plan on disk](../../.ssd/features/ssd-skill-upgrades/01-architect.md)).

## Context

Two distinct audiences want different things from SSD:

- **Newcomers** want the system to make decisions for them. They want plain-English narration ("I
  ran the architect skill because we're at phase=design"), confirmation prompts before destructive
  actions, and one-question-per-turn discoverability.
- **Experienced engineers** want every step explicit and reproducible. They want
  tab-completable commands, structured (JSON) output for piping, no confirmations on routine ops,
  and zero narration overhead on every turn.

Without a way to distinguish these audiences, every default serves the average — which serves no
one. Either novices drown in YAML and command surface they don't understand, or experts get
slowed by hand-holding they don't need.

The earlier rails.md (iter 7) named the canonical sequence both audiences walk. This iteration
names *how* each audience walks it.

## Decision

Add a `developer_profile` field to `.ssd/project.yml`:

```yaml
developer_profile: novice | standard | expert    # default: standard
```

Profile-aware defaults (suggestions, not gates):

| Profile | Default surface | Phase commands | Confirmations | Narration | YAML editing |
|---|---|---|---|---|---|
| **novice** | conversational | rejected with hint | yes, on irreversible steps | full | discouraged (`current.notes.yml` only) |
| **standard** | conversational | accepted | only on destructive ops | concise | allowed |
| **expert** | command (or conversational, user choice) | accepted | none | minimal | expected |

**Profile is a hint, not a gate.** The orchestrator never refuses an action based on profile alone
— it only adjusts defaults. A novice can always do anything an expert can; discoverability is via
`/ssd --explain "<intent>"`, not gatekeeping.

**Teaching mode** (decaying narration for first N invocations):

```yaml
teaching_mode:
  enabled: true|false                # default: true if developer_profile=novice; auto-set true for first 5 invocations on standard
  invocations_remaining: <int>       # decay counter; defaults to 5
```

When teaching mode is enabled, the orchestrator adds a one-line *"under the hood: I called
`architect` because we're at phase=design"* to every turn's narration. After each conversational
turn, `invocations_remaining` decrements. At 0, teaching mode disables itself.

User overrides:
- `/ssd --teach` re-enables teaching mode (resets counter to 5).
- `/ssd --no-teach` disables it permanently for this project (sets `enabled: false`).
- Successful command-surface invocation triggers a one-time prompt: *"Looks like you're driving
  directly. Switch to expert profile?"* (decays cleanly — never asks twice).

**Bridge flags** (every surface can reveal the other):

| Flag | Surface | Effect |
|---|---|---|
| `--explain` | conversational | Dry-run the conversational call; emit the exact command sequence it would invoke. Lets a novice graduate by watching the machinery; lets an expert audit a conversational call before committing. |
| `--narrate` | command | Emit the conversational summary alongside structured output. Useful for capturing human-readable CI logs. |
| `--raw` | conversational | Dump raw `current.yml` instead of the 3-sentence summary. Same data, raw rendering. |
| `--teach` | both | Re-enable teaching mode (resets counter). |

No surface hides anything from the other. There are no commands that exist only in conversational
mode and no state that exists only in command mode.

## Rationale

- **Two audiences, one engine.** The plan's Part II strategic reframing (rails + profile +
  teaching) reconciles "Jobs surface for newcomers" with "A/UX surface for experts." Without
  profile-aware defaults, you serve neither — you serve the average, which is no one.
- **Profile is a hint.** Hard gates based on profile would feel paternalistic and would fork the
  product into a "beginner edition" and "expert edition." A novice should always be able to drive
  the command surface if they want to learn; an expert should always be able to flip to
  conversational if they're tired. The defaults adapt; the capability is uniform.
- **Teaching mode decays.** A novice graduates to standard by using the system, not by reading
  docs. The decay counter is the mechanism: after 5 invocations, the user has internalized the
  basics, narration becomes noise, and it auto-disables. Re-enable with `/ssd --teach` if they
  start a new project or come back after a long break.
- **Bridge flags prevent surface lock-in.** A user on conversational who sees `--explain` learns
  the underlying commands without leaving their comfort surface. An expert on command who hits
  `--narrate` gets human-readable logs without abandoning structured output. Each surface is a
  view onto the same engine.

## Consequences

**Easier:**
- Novices get a system that meets them where they are.
- Experts get a system that doesn't slow them down.
- Onboarding is the system itself, not a tutorial document.
- The two-surface architecture has a real implementation.

**Harder:**
- Per-skill behavior must check the profile + teaching state. Mitigated: the orchestrator owns
  surface concerns; sub-skills' content is profile-agnostic. Only the orchestrator's narration
  layer changes.
- A novice who never invokes the command surface won't auto-promote. Acceptable — they're getting
  good output and the system works for them.

**What we give up:**
- A single uniform UX. The product becomes adaptive. This is the point.

## Alternatives Rejected

- **No profile; always conversational with full narration.** Slow for experts. Encourages building
  CI integrations on the LLM's narration text rather than structured output.
- **No profile; always command-surface, conversational as a wrapper.** Crushes novices. The
  conversational surface IS what makes SSD approachable; demoting it to a wrapper undoes that.
- **Profile as a hard gate.** Forks the product. A novice who wants to learn the command surface
  shouldn't have to lie about being expert. A hint adapts; a gate forks.
- **Teaching mode permanently on for novice profile.** A novice who has been using SSD for months
  doesn't need "under the hood: I called architect" on every turn. Decay is the right answer.
- **Teaching mode never auto-suggests expert.** A standard user who has directly edited
  `current.yml` more than twice has demonstrated they're ready. The one-time prompt is cheap
  and respectful (it asks once, decays, never nags).

## Auto-Promotion Triggers

The orchestrator suggests a profile change in three situations:

1. `developer_profile: novice` and the user has successfully invoked `/ssd <command>` (any
   command-surface call): suggest `standard`. Decays — never asks twice on this project.
2. `developer_profile: standard` and the user has directly edited `current.yml` more than twice:
   suggest `expert`. Decays.
3. `developer_profile: expert` is never auto-suggested back down. Experts who want to dial back
   set the field manually.

Auto-promotion is a one-line prompt at the end of a turn ("looks like you're driving directly
— switch to expert profile?"). The user accepts, declines, or ignores. The orchestrator never
reasks.

## Future evolution

If a fourth profile is needed (e.g., `auditor` for read-only review use), it slots in as another
row of the table. If teaching mode needs richer behavior (e.g., per-phase tutorials), `rails.md`
gets per-step teaching annotations. The schema is intentionally minimal in v1.0 to avoid
over-design.
