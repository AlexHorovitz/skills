# ADR-0009: `skill-version-sync` — enforce SKILL.md example/banner consistency

## Status
Proposed — 2026-06-11 — landed in the post-v1.19 milestone refactor (item R4, see
[refactor-plan.md](../../.ssd/milestones/2026-06-10-post-v1.19/refactor-plan.md)).

## Context

The first milestone audit of this library ([skeptic-before.md](../../.ssd/milestones/2026-06-10-post-v1.19/skeptic-before.md))
surfaced a 💀-severity Fowler finding: the `version:` value in each sub-skill's
required-output-frontmatter **example** had drifted from that file's `**Version:**` banner.
Eight of ten skills were stale — `ssd-init` by eight minor versions. Wozniak's lens added the
companion finding: the frontmatter validator (`methodology/frontmatter-validate.py`, ADR-0006)
checks artifact field presence and type but does not enforce version at all, so nothing
mechanically prevents the drift from recurring.

Refactor R3 synced the eight examples. R4 is the forward-defense: a mechanical check so the
drift cannot silently return. The question was *what* to check.

## Decision

Add a gate rule `skill-version-sync`, backed by a new `frontmatter-validate.py
--check-skill-examples [ROOT]` mode, that asserts: for each `ROOT/*/SKILL.md`, the
required-frontmatter example's `version:` equals that file's `**Version:**` banner.

The rule SKIPs cleanly when there is nothing to check — a file with no banner, no example
block, or an example using a non-semver placeholder (e.g. `ssd/SKILL.md`'s generic
`version: <skill-version>` template), and any downstream project that consumes SSD skills
without vendoring `*/SKILL.md` sources. It therefore enforces a real invariant inside this
skills library and is a no-op everywhere else.

## Alternatives rejected

**Assert `artifact.version == current skill banner`** (the literal wording of the R4 plan
item). Rejected. The validator walks `.ssd/features/**` and `.ssd/milestones/**` artifacts;
on a no-diff full walk (which `/ssd verify` performs) it validates *all* of them. A historical
architect spec produced by `architect` v1.0.0 legitimately carries `version: 1.0.0` even after
the skill advances to v1.2.0 — you do not rewrite the version that produced an artifact.
Asserting equality with the *current* banner would FAIL every historical artifact and break
the gate, directly contradicting R4's own acceptance criterion ("count of PASSing artifacts
unchanged at HEAD"). The thing that actually drifted was the skill's *documentation example*,
not its artifacts — so the documentation example is what the check targets.

**Fold the check into the existing `frontmatter-valid` rule.** Rejected. That rule is
artifact-scoped and diff-restricted (it validates only changed `.ssd/` files on a PR). Skill
examples live in `*/SKILL.md`, outside `.ssd/`, and want to be checked on every gate
regardless of which files changed. A separate rule keeps each rule's scope single and its
output ("N skill example(s) match banner") legible.

**Add a `version_assertion: banner-match` flag per schema** (also in the R4 plan). Rejected as
unnecessary: the check is global to the skills library, not per-artifact-schema, so there is
nothing for a per-skill schema flag to gate.

## Consequences

- Version drift between a skill's banner and its documented frontmatter example is now caught
  mechanically at `/ssd gate` and in CI (via R1's `quality.yml`), not by manual vigilance.
- The check is intentionally narrow: it does not verify that an artifact's `version` is
  plausible, nor that the banner itself is correct — only that a skill's own example agrees
  with its own banner. Broader version governance is out of scope.
- Test coverage: two parity-test fixtures (`skill-version-match` → PASS, `skill-version-drift`
  → FAIL) added test-first; the harness is now at 16 assertions.

## Note — adjacent drift found while implementing

Two pre-existing documentation gaps were fixed opportunistically and are recorded here so they
are not mistaken for scope creep:
1. `methodology/SKILL.md`'s gate-rules table was missing the `no-leaky-state` rule (shipped
   v1.18.0). Backfilled.
2. The `adr-delta` rule's "test code" exclusion regex (`tests?/|/test_|_test\.`) does not
   recognize `scripts/parity-test.sh` (a `-test.sh` file under `scripts/`), so the parity-test
   diff counts as architectural. Left as-is for now; noted for the milestone's `skeptic-after`
   pass as a candidate refinement.
