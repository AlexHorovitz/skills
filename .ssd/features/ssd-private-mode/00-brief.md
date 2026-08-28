---
skill: ssd
version: 2.7.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-private-mode
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-private-mode

## Problem

SSD currently offers two postures toward git, both set by
`project.yml.ssd.gitignore_mode` ([ADR-0008](../../../docs/decisions/ADR-0008-ssd-commit-split.md)):

- **`selective`** (default since v1.18.0) — durable artifacts (briefs, architect specs, code
  reviews, deploy logs, milestone records) are committed; machine state stays local.
- **`blanket`** (legacy v1.3.0–v1.17.x) — everything under `.ssd/` is gitignored.

Neither gives a user a genuinely **private** SSD practice. Even on `blanket`:

- `.ssd/gate.yml` is **force-committed** by an explicit `!.ssd/gate.yml` negation
  ([ADR-0015](../../../docs/decisions/ADR-0015-ssd-init-gate-readiness.md), library v2.5.0).
- `docs/decisions/`, `docs/runbooks/`, and `docs/architecture/` are committed **by design** —
  ADR-0008 argues explicitly that ADRs are durable decision records that belong in history.
- The workstream's outward mechanics are fully visible: `add-{slug}` branch names, and — when
  `integrations.github.issue_tracking: on` — `ssd:epic` / `ssd:feature` / `ssd:phase/*` labelled
  issues in a public tracker ([ADR-0014](../../../docs/decisions/ADR-0014-github-issue-state-tracking.md)).
- `ssd-init` Step 8 offers to write an "SSD Convention" section into the **committed** `CLAUDE.md`.

So a developer who wants to use SSD on a repo where the methodology paper trail should not appear —
a client codebase, a shared team repo where SSD is a personal practice rather than a team standard,
an OSS contribution, or simply a project where the working notes are nobody else's business — has no
supported way to do it. They can hand-edit `.gitignore`, but nothing records the intent, so
`ssd-init` re-runs, `/ssd upgrade`, and the gate rules all fight them.

## Goal

A user electing privacy at init gets a project where **no SSD mechanics or documentation are
tracked by git, and the outward workflow leaves no SSD fingerprints** — while the methodology
itself runs completely unchanged. Privacy is a *storage and visibility* posture, never a reduction
in rigor: every rail step still runs, every gate rule still fires, every artifact is still written.
They just aren't committed.

## Scope — user-ratified decisions

Settled with the user before this brief was written. The architect should treat these four as
**given**, not as open questions to relitigate:

1. **Reach = full stealth.** Gitignore all of `.ssd/` (including `gate.yml`) *and* the SSD-produced
   `docs/` trees. Additionally suppress the outward tells: generic branch names instead of
   `add-{slug}`, `issue_tracking` forced off, no SSD section written into committed `CLAUDE.md`.
2. **Config shape = a third `gitignore_mode` value.** `gitignore_mode: selective | blanket |
   private`. One key, one axis, mutually exclusive by construction. This is the path ADR-0008's
   "Future Compatibility" section already reserved ("Future modes (`selective-strict`,
   `selective-with-archive`, etc.) can be added without breaking existing projects").
   **Rejected:** an orthogonal `ssd.privacy:` key — it creates a 3×2 state matrix in which roughly
   two cells are meaningful.
3. **The `🛠️ Crafted with SSD` commit/PR footer is KEPT.** Attribution is deliberately independent
   of artifact privacy. **This is the one intentional non-stealth element** — the user wants no SSD
   paper trail in the repo while still crediting the methodology. Privacy here means *no SSD
   mechanics or documentation in the tree*, **not anonymity**. Anyone reading commit trailers can
   still tell SSD was used, and that is the intended outcome. A future `--no-attribution` knob would
   be a separate decision; do not fold it into this one.
   *Implementation note: the footer is a working convention, not codified anywhere in the repo, so
   "keep it" requires **zero** code change. Recorded here so a reader doesn't mistake the absence of
   a footer change for an oversight.*
4. **Retrofit is supported** via a `/ssd upgrade` migration entry, with an explicit and unmissable
   limitation: `git rm --cached` stops *future* tracking; **already-published history is not
   rewritten**. The migration must state this plainly rather than implying a privacy guarantee it
   cannot deliver.

## Known hazards the design must resolve

These are the parts most likely to produce a defect, and the reason this feature needs an ADR of its
own rather than an ADR-0008 amendment.

**H1 — `no-leaky-state` goes dark on `private` unless its guard is updated.**
[gate-rules.sh:456-461](../../../methodology/gate-rules.sh#L456) accepts only `selective` and
`blanket`; anything else emits `SKIP "unknown gitignore_mode: '$mode' (expected selective|blanket)"`.
Shipping a third value without touching that guard silently degrades SSD's leak-detection rule to
SKIP on **every** private project. This is precisely the MAJOR-4 defect class from the ssd-upgrade
iter-B review (an unparsed `gitignore_mode` value turning a safety rule into a no-op), and it would
be worse here: under `private`, a leaked artifact is a **privacy** failure, not merely commit noise.

**The semantic inversion this implies:** under `blanket` the rule SKIPs because nothing needs
protecting. Under `private` the rule must **run, and run hardest** — it becomes the primary
enforcement layer for the privacy promise, with a deny-list expanded to all of `.ssd/` plus the SSD
`docs/` trees. Private mode is the one mode where this rule is load-bearing.

**H2 — SSD does not own `docs/`.** Gitignoring `docs/decisions/`, `docs/runbooks/`, and
`docs/architecture/` is safe in a greenfield SSD project and actively dangerous in a retrofit: a
project may already have non-SSD content at those paths, which private mode would silently untrack.
The architect must choose between (a) gitignoring the shared paths and detecting/refusing on
pre-existing content, or (b) relocating SSD-produced docs under `.ssd/docs/` in private mode so SSD
only ever ignores paths it owns. Option (b) is cleaner on ownership but changes well-known artifact
paths that sub-skills and `rails.md` invariant 7 ("ADRs in `docs/decisions/`") reference — a wider
blast radius. **This is the central design decision of the feature.**

**H3 — private mode contradicts ADR-0015's premise.** ADR-0015 moved `test_command` /
`feature_flag_marker` into a *committed* `.ssd/gate.yml` specifically so gate configuration would
travel to every clone and CI runner (its root cause P2). Private mode cannot have a committed
`gate.yml`. The consequence is real and must be stated in the ADR, not hidden: **a private project's
gate config does not travel** — a second clone or CI runner gets a weaker gate, which is the exact
failure ADR-0015 was written to fix. Options: accept it as the documented cost of privacy; or have
`ssd-init` emit a CI-side config path that carries the inputs without committing them. Either way,
ADR-0015 needs an addendum recording that private mode reopens its P2 in exchange for privacy.

**H4 — `CLAUDE.md` is both committed and the file Claude actually reads.** Suppressing the SSD
section keeps the repo clean but costs the agent its convention pointer. Likely resolution: write it
to a gitignored `CLAUDE.local.md`. Needs confirming against current Claude Code file-loading
behavior rather than assumed.

**H5 — Step 5.5's hook logic skips every non-selective mode.**
[ssd-init/SKILL.md Step 5.5](../../../ssd-init/SKILL.md) detects mode by grepping `.gitignore` for
the selective marker and skips the pre-commit hook offer otherwise. Under `private` the hook is
*more* valuable than under `selective` — it is the pre-commit privacy backstop. Needs a third branch,
and a private-mode marker line to detect on.

**H6 — `issue_tracking: on` + `private` is a hard contradiction.** ADR-0014 mirrors workstream state
to a public tracker. The design must decide whether `private` forces it off, or refuses the
combination at init with an explicit error. Silently leaving it on would leak phase-by-phase
workstream state — the loudest possible violation of the mode's promise.

## Surface to change

Indicative, for sizing — the architect owns the final list.

| Area | Change |
|---|---|
| `methodology/private.gitignore` | **new** canonical pattern file, parallel to `selective.gitignore` |
| `methodology/gate-rules.sh` | `no-leaky-state` accepts `private`; expanded deny-list (H1) |
| `methodology/migrations.yml` + `migrate.sh` | new `private-mode` entry: `detect_`/`apply_` fns, `git rm --cached`, history warning (decision 4) |
| `ssd-init/SKILL.md` | Step 5 third case + `--private` flag; Step 5.5 third branch (H5); Step 6 template; Step 8 (H4) |
| `ssd/chapters/artifacts.md` | commit-split table gains a `private` column |
| `ssd/chapters/enforcement.md` | `no-leaky-state` row: private-mode semantics |
| `ssd/chapters/workstreams.md` | branch-pattern override under private |
| `docs/decisions/ADR-00NN` | **new ADR** — private mode; supersedes part of ADR-0008, addends ADR-0015 (H3) |
| `README.md`, `methodology/SKILL.md` | mode docs + script catalog |
| `scripts/parity-fixtures/` | fixtures for detect/apply + the H1 guard regression |
| `VERSION` + skill banners | minor bump; `skill-version-sync` keeps banners honest |

## What shipping looks like

`ssd-init --private` (or the interactive Step 5 choice) on a fresh repo produces a project where
`git status` is clean after a full `/ssd feature` cycle — brief, architect spec, ADR, code review,
and deploy log all written and all invisible to git — while `/ssd gate` runs the **same** rules with
`no-leaky-state` actively enforcing the privacy boundary rather than skipping. `/ssd upgrade --apply`
moves an existing project into the mode, untracks what it can, and says plainly what it cannot undo.
`gitignore_mode: selective` and `blanket` projects behave **exactly** as before — this is additive.

## Non-goals

- **Not** history rewriting. No `filter-branch`, no `bfg`. The migration untracks and warns.
- **Not** encryption or at-rest protection. Private means untracked, not secret.
- **Not** anonymity — see decision 3. The commit footer stays.
- **Not** a reduction in methodology rigor. Every rail step and gate rule still runs.
- **Not** a change to `selective` or `blanket` behavior.

## Open question for the architect

**Is this one cycle or two iterations?** A defensible split: **iter A** = the mode itself
(`private.gitignore`, the `gitignore_mode` value, `ssd-init --private`, the H1 guard fix, docs, ADR)
— shippable and complete on its own; **iter B** = retrofit + stealth toggles (`/ssd upgrade`
migration, branch-pattern override, `issue_tracking` interlock, H4). Iter A delivers the user's
core ask; iter B delivers decision 4 and the remaining stealth surface. Architect decides.
