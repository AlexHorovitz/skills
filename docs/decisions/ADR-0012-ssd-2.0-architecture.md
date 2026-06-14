# ADR-0012: SSD 2.0 — radical simplification via progressive disclosure

## Status
**Accepted — 2026-06-14** (proposed 2026-06-13). Tracked on
[issue #15](https://github.com/AlexHorovitz/skills/issues/15). Seeded by the audit
`.ssd/audits/2026-06-13-ssd-2.0-simplification.md` (Design B won 72/90). Recorded under the
[ADR-0011](ADR-0011-decision-record-doctrine.md) pattern; its `Revisit when:` triggers live on #15.

> **Accepted ≠ shipped.** The 2.0 direction — progressive disclosure replacing the profile *concept*
> (NeXTSTEP: guide the newcomer, never take the Terminal from the expert), single surface, verb
> collapse, warnings-not-walls — is now a **committed decision**: the cuts may begin. But 2.0 has
> **not shipped**. The prerequisites done so far are the additive, independent de-riskers: `/ssd
> upgrade` (the deprecation vehicle, #17, complete) and the `ssd/SKILL.md` chapter-split (P1, v1.25.0).
> Durable doctrine (`methodology/core.md`) continues to cite ADR-0011, **not** this ADR, until the 2.0
> cuts actually land. Implementation is tracked on #15.
>
> **Update — 2026-06-14, v2.0.0:** the cuts have begun shipping. Iter A (Pillar 1 — remove the profile
> concept) landed in v2.0.0 (ssd-2.0-cuts); ADR-0004 + ADR-0010 are superseded by this ADR. Iter B
> (single surface + verb collapse) and iter C (deprecation manifest) follow. `methodology/core.md` may
> now cite this ADR.

## Context

The post-v1.19 milestone flagged the surface as "drifting." The `/ssd audit` quantified it:

- `ssd/SKILL.md` is **1331 lines** and brushing some models' context ceiling.
- The profile subsystem (`developer_profile` + `teaching_mode` + bridge flags + R9 per-skill knobs)
  spans **9 of 10** skill files — and its entire purpose is to make a large surface tolerable to a
  newcomer. *Complexity added to manage complexity.*
- The dual conversational+command "perfect parity" doctrine is a standing maintenance tax (two of
  everything, kept in lockstep forever).
- The 8-phase + 3-lifecycle verb set (14 forms, 14 numbered failure modes) leaks the
  *implementation's* vocabulary onto the *user's* desk; the product itself concedes the verbs are
  escape hatches "the user almost never needs."

**The Hard Truth** (from the audit): the single most dangerous thing in a simplification release is
SSD's *own* best rule — a naive "just make it work" 2.0 will quietly trade away "never silently
advance a phase" for magic. *Simpler and wrong* is a worse failure than complex and right.

## Decision (proposed)

**Pillar 1 — Progressive disclosure replaces the profile *concept* (NeXTSTEP model).**
Kill the `novice|standard|expert` enum, the teaching decay counter, auto-promotion prompts, the four
bridge flags, and the R9 per-skill knobs. Replace them with **one system that serves both audiences
without a mode to declare**: it *guides by proposing the next step* (the novice is gently led), and
*every manual step stays invokable and every decision inspectable* (the expert does each step by
hand, depth-on-demand — the Terminal is never taken away). Novice-*safety* behaviors (confirm
destructive ops, etc.) become **unconditional**, not gated behind a tier. The expert is not a mode;
the expert is whoever reaches deeper.

**Pillar 2 — "Never silently advance a phase" reaffirmed as the normative guard, *satisfied by*
Pillar 1.** A system that proposes-and-waits **is** never-silently-advance — guiding by proposal and
refusing to advance without a yes are the same gesture. Progressive disclosure does not fight the
Hard Truth; it is its resolution. Forbidden: any "magic" that *skips* a decision. Permitted: magic
that always *offers* the right next decision. "Fewer verbs" must never mean "fewer decisions."

**Pillar 3 — Single surface.** Kill the dual-surface parity doctrine and the bridge flags.
Conversational is *the* surface; commands survive as a **thin alias** that lowers into the same path
— a power-user shorthand, explicitly *not* a co-equal surface with its own state. The full manual
command set (and its git-safety failure modes) is retained as a discoverable escape hatch; it simply
stops being taught first.

**Pillar 4 — Decisions follow [ADR-0011](ADR-0011-decision-record-doctrine.md)** (ADR +
revisit-aware Issue). The deprecation of removed verbs/flags is itself such an Issue.

**Pillar 5 — Warnings, not walls.** The gate *informs and records*; it does not *block*. SSD
trusts the developer: `/ssd` will let you ship code with open BLOCKER/MAJOR findings — it just makes
that choice **loud and logged** (the gate result is surfaced unmissably at the decision point, the
safe path is the proposed default, and the override leaves a durable trace in `rail_deviations` and,
per Pillar 4, the decision ledger). This is the same gesture as progressive disclosure (Pillar 1):
*propose the safe path, allow the informed override.* It is also consistent with Pillar 2 — "never
*silently* advance" forbids the system sneaking code past you; it never promised the repo *cannot
receive* ungated code. We deliberately reject hard enforcement (branch-protection walls, a required
`gate_pass` merge check): a wall is more machinery and less trust, and discouragement-with-a-record
fits SSD's ethos. The discouragement budget lives in *warning quality + audit trail*, not in a lock.

## Non-negotiable — survives 2.0 untouched

The committed `.ssd/features/` artifact trail, the `gate-rules.sh` BLOCKER/MAJOR gate (as a *loud
signal*, per Pillar 5 — preserved and surfaced, not turned into a wall), and the ADR record. These
*are* the product. 2.0 deletes the scaffolding around the discipline, never the discipline. 2.0 is
**subtraction on the existing core**, not a green-field rewrite.

## Revisit when (reversibility contract — mirrored on #15 per ADR-0011)

- **Profile concept removed** → reopen if onboarding-confusion signal recurs (users repeatedly lost
  without tiered guidance), **or** a non-conversational consumer (CI/automation) emerges needing the
  command surface as a stable contract.
- **Dual-surface doctrine removed** → reopen if a real tool/integration needs the command surface as
  a stable machine API (the parity doctrine's only genuine justification).
- **Verb set collapsed** → reopen if power users report the escape-hatch verbs became undiscoverable
  (i.e., progressive disclosure failed to disclose).
- **Warnings, not walls (Pillar 5)** → reconsider hard enforcement *only* if ungated defects actually
  reach users at a rate the discouragement + audit trail demonstrably fails to catch. Absent that
  evidence, the answer to "should the gate block?" stays no.

## Consequences

- Smaller surface; one system; the `ssd/SKILL.md` chapter-split (P1, deferred to 2.0) becomes
  "decide which chapters shouldn't exist," not merely "split the file."
- A deprecation window + alias-with-warning for removed verbs (so v1 muscle memory and any CI
  shelling `/ssd gate` degrade gracefully, not hard-break).
- The profile-aware work shipped at v1.20.0 (R9) is largely removed — but it was the precondition:
  it made the subsystem *coherent*, which is what let the audit judge it cleanly and what makes the
  removal surgical rather than a fight with a contradictory system.

## Alternatives rejected

- **Hide more complexity (more modes/defaults/auto-detection).** That is precisely what the profile
  subsystem already is; the audit scored it 27/90. Hiding is adding a veil; 2.0 removes the object.
- **Keep everything.** Fails the context-window forcing function and the Jobs/Woz bar; the surface
  only grows.
- **Green-field rewrite.** The architect skill lists "rewrite every 18 months" as a failure mode.
  Rejected in favor of subtraction on the v1.x core.
