---
skill: architect
version: 1.3.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-2.0-cuts#c
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: false
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0013]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: not_applicable
quality_gate_pass: true
---

# Architect Spec — ssd-2.0-cuts iter C (the deprecation path)

> Markdown skills library + a bash/awk migration engine. `systems-designer` N/A. Most standard
> architect deliverables (component diagram, scale baseline, feature flag, integration contract) are
> N/A for a manifest/doc change; the load-bearing sections here are the **Data Model** (the
> `migrations.yml` schema) and the **Interface Contract** (the `migrate.sh` selection semantics).
> Final iteration of the 2.0 subtraction ([ADR-0012](../../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md),
> issue #15); closes the epic at **2.2.0**.

## Governing decision

Iter A removed two *project-visible* conventions (`developer_profile` / `teaching_mode`); iter B
reshaped which surface is taught first. The manifest (`methodology/migrations.yml`) is how a v1-era
project *learns* a convention changed when it runs `/ssd upgrade`. Today it would do the **opposite**
of what 2.0 wants: its `dev-profile-keys` mechanical entry (`introduced_in: 1.10.0`) still tells a
project to **add** `developer_profile` — the exact key 2.0 ignores — and on `--apply` would re-add it.
Iter C makes the deprecation path coherent: *teach the removals, and stop teaching the dead key.*

This splits into three resolved decisions (D1–D3) plus a sequencing note. D1 carries a scope
implication and is flagged for user ratification at the end.

---

## Data Model — `methodology/migrations.yml` changes

The manifest is the data model. Two additions + one neutralization.

### New guided entries (both `kind: guided`, `introduced_in: 2.0.0`, `detect: null`)

```yaml
  - id: profile-concept-removed
    introduced_in: "2.0.0"
    applies_to: project
    kind: guided
    adr: ADR-0012
    title: "developer_profile / teaching_mode removed from project.yml (now ignored)"
    detect: null
    guidance: "SSD 2.0 removed the profile concept. Delete the `developer_profile` key and the
      `teaching_mode:` block from .ssd/project.yml — 2.0 ignores them (no crash), but they are dead
      config. Progressive disclosure (no-arg `/ssd` Auto-Detect) replaces tiered guidance; the
      escape-hatch chapters replace `expert` depth-on-demand."

  - id: single-surface-doctrine
    introduced_in: "2.0.0"
    applies_to: project
    kind: guided
    adr: ADR-0012
    title: "one surface, progressively disclosed — commands are a thin alias, not a co-equal surface"
    detect: null
    guidance: "SSD 2.0 collapsed the dual-surface 'perfect parity' doctrine. The conversational/no-arg
      `/ssd` path is primary; `/ssd <verb>` is a thin alias that lowers into it, not a separate
      stateful surface. The full verb set is retained as a discoverable escape hatch in
      ssd/chapters/. No project.yml change is required — this entry exists so a v1-era project learns
      the doctrine shift on `/ssd upgrade` (R3 re-surfacing)."
```

Both are **guided, not mechanical** — see **D1**. They carry no `detect` probe (a doctrine/guidance
item can't be auto-probed), so they re-surface every run until the project asserts adoption with
`/ssd upgrade --adopt <id>` (the iter-B/C `adopted_guided` mechanism, already shipped).

### Neutralize the stale `dev-profile-keys` mechanical entry — **D1**

`dev-profile-keys` must stop being offered to projects upgrading **to a 2.x target**, or `--apply`
will re-add a key 2.0 just removed. The id is stable and append-only (header contract: "never
renamed/reused"), so we annotate, not delete. **Recommended: add an `obsoleted_in` field** + a
one-line engine guard (see Interface Contract):

```yaml
  - id: dev-profile-keys
    introduced_in: "1.10.0"
    obsoleted_in: "2.0.0"          # NEW — convention retired in 2.0 (ADR-0012); see profile-concept-removed
    applies_to: project
    kind: mechanical
    adr: ADR-0004
    title: "developer_profile + teaching_mode keys in project.yml"
    detect: "project.yml ssd block has 'developer_profile'"
    apply: "add developer_profile: standard + teaching_mode block (defaults) if absent (non-destructive merge)"
```

`obsoleted_in` reads as: *this convention existed from `introduced_in` and was retired in
`obsoleted_in`.* A project upgrading **to a target `>= obsoleted_in`** no longer sees it (the
convention doesn't exist in the destination world). A project staging an upgrade to a pre-removal
target (`--to 1.25.0`) **still** sees it — correct, that target still had the key. The "delete it if
you have it" message for 2.x targets is carried by the new `profile-concept-removed` guided entry.

This is the honest, generalizable model: 2.0 is a multi-removal release, and any future convention
removal reuses the same field instead of inventing a new hack each time. The cost is one field, one
`migrate.sh` guard line, one `read_manifest` column, and one parity fixture — all inside iter C.

> **D1 alternative (rejected, documented):** flip `dev-profile-keys` to `applies_to: library`. The
> engine already skips non-`project` entries (`migrate.sh:347`), so this neutralizes with **zero
> code change**. Rejected because it overloads the `applies_to` category — a reader of this
> reference manifest would see a clearly project-scoped convention mislabeled "library." For a
> *methodology* artifact that downstream projects copy, the honest `obsoleted_in` model is worth the
> small code cost. (If the user prefers a pure-manifest, zero-engine 2.2.0, this fallback is viable
> and I will switch D1 on request — that is the scope decision flagged below.)

---

## Interface Contract — `methodology/migrate.sh`

Only the `obsoleted_in` path (D1-recommended) touches the engine. Two surgical changes; the gate
rule `migration-manifest-current` needs **no** change (its awk ignores unknown fields), though it
*may* optionally learn to validate `obsoleted_in >= introduced_in` (nice-to-have, not required).

1. **`read_manifest()`** — extract a 7th column `obsoleted_in` (default empty). Add the line
   `/^    obsoleted_in:/ { ob=val($0); next }` and append `"\t"ob` to both `print` statements; reset
   `ob` in the new-entry rule.

2. **Selection loop** — after the existing `--to` upper-bound check (`migrate.sh:349`), add:

   ```bash
   # An obsoleted convention is not offered when upgrading to a target at/after its removal
   # (it no longer exists in the destination world). Staged upgrades to a pre-removal --to still see it.
   if [[ -n "$ob" ]] && [[ -n "$TO" ]] && ! ver_gt "$ob" "$TO"; then continue; fi
   ```

   (`TO` defaults to the installed `VERSION`, so it is effectively always set; the guard is belt-and-suspenders.)

No new flags, no status changes, no change to `--apply` / `--adopt` / `--json`. `GUIDED`,
`GUIDED-ADOPTED`, and the contiguous-version-bump logic are unchanged — see **D3**.

---

## Resolved open questions

### D1 — guided vs. mechanical, and how to neutralize the stale entry
Resolved above. **New entries: guided.** Rationale: (a) the manifest's mechanical contract is
explicitly *non-destructive* ("add keys / rewrite-with-backup; never delete"); a deletion-apply is a
new ADR-0013-R1 corruption hazard for marginal benefit; (b) the dead keys are *ignored*, so leaving
them is harmless — that is the profile of an advisory (guided) item, not a must-converge (mechanical)
one; (c) deleting two keys by hand is trivial and the guidance states exactly what to remove.
**Stale entry: `obsoleted_in: 2.0.0`** (recommended) — see D1 alternative for the zero-code fallback.

### D2 — the ADR-0011 revisit-tracking Issue (ADR-0012 Pillar 4)
ADR-0012 § "Revisit when" already states its four reversibility triggers are *"mirrored on #15 per
ADR-0011"* and Pillar 4 says "the deprecation of removed verbs/flags is itself such an Issue."
**Recommendation: verify/formalize on #15 — do not open a new issue** (ADR-0012 explicitly anchors
the ledger on #15; a second issue fragments it). The obligation is met when #15 carries the four
triggers as a tracked, falsifiable checklist (the deprecation-window ledger):

1. Profile concept removed → reopen if onboarding-confusion signal recurs, **or** a non-conversational
   consumer (CI/automation) needs the command surface as a stable contract.
2. Dual-surface doctrine removed → reopen if a real tool/integration needs the command surface as a
   stable machine API.
3. Verb set collapsed → reopen if power users report the escape-hatch verbs became undiscoverable.
4. Warnings-not-walls (Pillar 5) → reconsider hard enforcement only on evidence ungated defects reach
   users at a rate the audit trail demonstrably fails to catch.

This is **outward-facing (`gh`)** → execution stays under explicit human control (do not auto-post).
The coder phase prepares the exact comment body; the user posts it. Acceptance is satisfied by the
ledger existing on #15 (verify first — it may already be there) and recording that fact in
`iterations/c/coder-status.md`.

### D3 — guided-entry interaction with the contiguous version bump (`--adopt` / gate)
No new mechanism needed; the iter-B/C engine already handles it. The two new 2.0.0 guided entries are
**unadopted by default** → `status: GUIDED` → they break the contiguous-advance run at 2.0.0
(`migrate.sh:373-377`), so a project's recorded version pins **below 2.0.0** until it asserts adoption
— exactly the R3 re-surfacing we want. A caught-up 2.x project runs `/ssd upgrade --adopt
profile-concept-removed` and `--adopt single-surface-doctrine`; both then report `GUIDED-ADOPTED`
(satisfied), the contiguous run completes through `--to`, and the recorded version advances to `--to`
itself (`migrate.sh:395-397`) → **zero drift**. The `migration-manifest-current` gate passes provided
`introduced_in` stays ascending (2.0.0 after 1.20.1 ✓; two equal 2.0.0 entries are allowed by the
rule's `vle` ≤ check ✓) and ≤ `VERSION` (2.2.0 ✓).

### D4 (dogfood) — this repo's own state
`.ssd/project.yml` records `ssd.version: 1.24.0` and already has `adopted_guided:
[decision-record-doctrine]`; it carries **no** `developer_profile` (cleaned). After iter C ships,
`/ssd upgrade --from 1.24.0` on this repo shows: `dev-profile-keys` skipped (obsoleted ≤ 2.2.0),
`profile-concept-removed` + `single-surface-doctrine` GUIDED. Adopting both (the keys are already
absent — adoption is a truthful assertion) records the repo at 2.2.0. This is the iter-C self-proof;
do it in the deploy step, not the coder step (keeps the code PR free of a project.yml version bump).

---

## Decision Log
- **ADR-0013 addendum** (iter-C implementation decision) — add the `obsoleted_in` manifest field to
  model convention *retirement* (the append-only manifest could express "introduced" but not
  "removed"). Mirrors the iter-B addendum precedent. Records the rejected `applies_to: library`
  alternative. *No new top-level ADR* — this extends ADR-0013's manifest schema, it doesn't reverse a
  decision. (If D1-fallback is chosen, this addendum shrinks to "no schema change; stale entry parked
  under `applies_to: library`," and `adrs:` frontmatter still lists ADR-0013 for the manifest edit.)

## Risk Assessment

| Risk | L | I | Mitigation |
|---|---|---|---|
| **R1 — `obsoleted_in` guard wrong-direction** (skips entries it shouldn't, or fails to skip) | M | M | Parity fixture: a project `--from 1.5.0 --to 2.2.0` must NOT list `dev-profile-keys`; the same project `--to 1.25.0` MUST still list it. Code-review verifies both directions against the `ver_gt` guard. |
| **R2 — re-adding the dead key** (the bug iter C exists to prevent) slips through | L | H | The R1 fixture's `--to 2.2.0` case is the regression test; `--apply` on a pre-1.10 project to 2.2.0 must not write `developer_profile`. |
| **R3 — manifest-gate regression** from the new rows | L | M | `introduced_in` ascending + ≤ VERSION already enforced by `migration-manifest-current`; run `/ssd gate` — it catches an out-of-order or future-dated entry. |
| **R4 — guided entries never converge** (pin recorded version forever) | L | L | By design (R3 re-surfacing); `--adopt` is the documented exit. D3 confirms the path; D4 dogfoods it. |
| **R5 — scope creep** (D1 turns a manifest edit into an engine change) | M | L | D1 fallback (zero-code `applies_to: library`) is pre-specified; user ratifies the trade at the end of this spec. |

## Version & sequencing plan
`VERSION` → **2.2.0**; CHANGELOG 2.2.0 entry (manifest deprecation entries + `obsoleted_in` field +
epic close). No skill banner changes are *required* (no SKILL.md behavior change) → `skill-version-sync`
is satisfied trivially; if any banner is touched, bump its frontmatter example in lockstep. The
ssd-upgrade chapter (`chapters/upgrade.md`) gets a one-paragraph note that `obsoleted_in` exists and
how retired conventions behave. Iter C closes epic #15 → archive `ssd-2.0-cuts` on ship.

## Self-verification
1. Every deliverable in scope has real content (data model = manifest rows; interface = engine diff). ✓
2. Adapted to the actual stack (bash/awk engine line numbers cited, not generic patterns). ✓
3. ADRs: ADR-0013 addendum for the schema field; ADR-0012/0004 referenced, none deleted. ✓
4. NeXTSTEP: no capability removed — iter C *documents* removals and helps migration; verbs/keys are
   not reintroduced and nothing reachable is taken away. ✓
5. Scale baseline / feature flag / integration contract correctly marked N/A for a manifest change. ✓
