---
skill: architect
version: 1.3.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-private-mode#b
consumed_by: [coder, systems-designer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0017, ADR-0013]
  risk_assessment: true
  feature_flag: "migrations.yml private-mode entry (elective — inert until named)"
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — ssd-private-mode iteration B (elective retrofit)

Platform: **headless** (`architect/headless/GUIDE.md`) — a bash migration engine invoked by the Claude
Code CLI. No service, no network, no persistence. The guide's contract-first and idempotency
principles carry the weight; its service-boundary and API-versioning sections have no referent.

---

## 1. Current Scale Baseline

Measured on `main` at v2.8.0.

| Dimension | Now (1x) | 10x | Note |
|---|---|---|---|
| Manifest entries | **12** (7 mechanical, 5 guided) | ~30 | This iteration adds **1** |
| `apply_*` functions | 7 | ~15 | Adds **1** |
| `read_manifest` consumers | **2** (migrate.sh:494, :524) | 2–4 | **The 8th-column blast radius** — both must change |
| `apply_dispatch` call sites | **1** (migrate.sh:546) | 1–2 | Adds **1** (the elect path) |
| `migrate.sh` | 603 lines | ~900 | Adds ~120 |
| Parity assertions | 128 | ~150 | Adds ~12 |
| Destructive operations in the whole engine | **0** | — | **Adds the first one** |

The last row is the one that matters. Iteration B introduces the **only** operation in `migrate.sh`
that can remove something from git. Every design choice below is downstream of that.

---

## 2. Component Diagram

Two entry paths. The whole design is the guarantee that the left one can never reach the right one.

```
   /ssd upgrade [--apply]                    /ssd upgrade --apply private-mode
   (the DEFAULT SWEEP)                       (EXPLICIT ELECTION)
            │                                            │
            ▼                                            ▼
   migrate.sh --apply                          migrate.sh --elect private-mode [--confirm]
            │                                            │
            ▼                                            ▼
   ┌────────────────────┐                    ┌──────────────────────────────┐
   │  report loop       │                    │  elect short-circuit         │
   │  (line ~524)       │                    │  (BEFORE the loop, mirrors   │
   │                    │                    │   the --adopt path at ~494)  │
   │  elective? ────────┼── continue ──┐     │                              │
   │      │ no          │              │     │  1. validate id              │
   │      ▼             │              │     │     · exists in manifest     │
   │  mechanical/guided │              │     │     · elective: true         │
   │  · PENDING/APPLIED │              │     │     · kind: mechanical       │
   │  · satisfied/      │              │     │  2. DRY-RUN (no mutation):   │
   │    advancing       │              │     │     enumerate + print the    │
   │  · JSON emit       │              │     │     FULL file list + the     │
   │  · init-log append │              │     │     history warning          │
   └────────────────────┘              │     │  3. no --confirm → exit 10   │
            │                          │     │  4. --confirm → apply:       │
            ▼                          │     │     a. pattern + config      │
        exit 0 / 3                     │     │     b. git rm --cached       │
                                       │     └──────────────────────────────┘
   private-mode is NEVER ◄─────────────┘                  │
   listed, applied, or                                    ▼
   version-pinning here                        exit 0 / 2 / 3 / 10
```

**The invariant:** one `continue` in the report loop, placed **before** the `satisfied=0` line, makes
the entry inert in every default path at once — because the report emit, the JSON emit, the
`satisfied`/`advancing` bookkeeping, and the `applied_log` append **all live inside that loop**
(verified by reading it, not assumed). That is why H2 is a one-line guarantee rather than a
four-place audit.

---

## 3. Data Model

### 3.1 Manifest entry — new `elective` field

```yaml
  - id: private-mode
    introduced_in: "2.9.0"
    applies_to: project
    kind: mechanical          # HOW it is adopted — unchanged vocabulary
    elective: true            # NEW — WHETHER every project should adopt it
    adr: ADR-0017
    title: "private mode retrofit (gitignore_mode: private + untrack SSD artifacts)"
    detect: "project.yml.ssd.gitignore_mode is `private` AND .gitignore carries the private sentinel"
    apply: "write private.gitignore verbatim, set gitignore_mode/branch_pattern/issue_tracking, promote gate inputs, then (only with --confirm) git rm --cached the tracked SSD paths"
```

| Field | Values | Default when absent | Meaning |
|---|---|---|---|
| `kind` | `mechanical` \| `guided` | — (required) | *How* it is adopted |
| `elective` | `true` | **false** (swept) | *Whether* every project should adopt it |

**Not a manifest schema-version bump.** `schema_version: 1` stays: the field is additive and absent-is-false, exactly as `obsoleted_in` was added in v2.2.0.

### 3.2 `read_manifest` — 8-column contract

Currently 7 tab-separated columns (`id iv ap kd ad ti ob`), with `obsoleted_in` last and a standing
comment warning that *"every `read -r … ob` consumer must list it."* The new column appends as the
**8th**, after `ob`:

```
id  introduced_in  applies_to  kind  adr  title  obsoleted_in  elective
```

Both consumers must be updated in the same commit — `migrate.sh:494` (`--adopt` validation) and
`:524` (report loop). There are exactly two; a missed one silently shifts fields.

> **Implementation correction (coder phase, 2026-08-28) — the record delimiter had to change.**
> This section specified appending the column to the existing **tab**-separated record. That does not
> work, and the failure is silent: **tab is IFS *whitespace*, so bash collapses consecutive tabs** and
> every field after an empty one shifts left. The 7-column form was safe only because its one optional
> field (`obsoleted_in`) was **last**, where a trailing empty field is harmless. Appending `elective`
> after it made every entry lacking an `obsoleted_in` — i.e. **all of them** — read `elective` into the
> `ob` slot, so `--elect private-mode` rejected its own manifest entry as "not an elective migration."
>
> Shipped with the record delimiter changed to **`\x1f`** (ASCII unit separator), which is not IFS
> whitespace and therefore preserves empty fields — verified empirically before adopting. This makes
> the change to `read_manifest` larger than "append a column": the delimiter is part of its contract,
> so **all three** consumers (the elect block added a third) move together. Pinned by the
> `read-manifest-empty-middle-field` fixture, which asserts the observable symptom rather than the
> delimiter choice, so a future delimiter change is free as long as empty fields survive.

### 3.3 What the interlock builds (transient, never persisted)

```
tracked_ssd_paths = git ls-files -- .ssd docs/decisions docs/runbooks docs/architecture
```

Not written to disk, not cached. Recomputed on every invocation so the dry-run and the confirmed run
cannot disagree about what will be untracked.

---

## 4. Interface Contract

### 4.1 `--elect <id>` — placement and validation

Placed as a **short-circuit before the report loop**, mirroring `--adopt` (which validates one id,
acts, and exits). This is not merely stylistic: it guarantees the elect path and the sweep never
interleave.

Validation, in order, each a distinct exit-2 message:

1. `<id>` exists in the manifest.
2. The entry has `elective: true` — electing a swept entry is a usage error, not a shortcut.
3. The entry has `kind: mechanical` — a guided entry has no `apply_` function to run.

### 4.2 Dry-run by default — the safety inversion

> **`--elect <id>` mutates nothing. It prints what would change and exits 10 (needs-confirm).
> `--elect <id> --confirm` acts.**

This inverts the default for the engine's only destructive operation, and it follows this repo's own
precedent: [ADR-0013](../../../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)
iteration A shipped `/ssd upgrade` as *"a pure dry-run, so the corruption risk of a bad migration
cannot fire."* Iteration B's operation is strictly more dangerous than the one that justified that
stance.

Rejected: *phase 1 (config) unconfirmed, phase 2 (`git rm --cached`) confirmed*. It is defensible —
phase 1 is non-destructive and every other `apply_*` mutates without confirmation — but it leaves a
project whose config says `private` while its artifacts are still tracked. That state is loud rather
than silent (`no-leaky-state` FAILs and itemizes), which was the appeal. It still loses: a user who
runs the command to *see* what it would do should not come back to a modified repo. **Dry-run means
dry.**

**Exit codes** (10 = needs-confirm matches `issue-sync.sh`'s existing convention, so the library has
one meaning for "surface this and re-run confirmed"):

| Code | Meaning |
|---|---|
| 0 | elected and applied (or already private — idempotent no-op) |
| 2 | usage/validation error (unknown id, not elective, not mechanical) |
| 3 | apply ran and failed |
| 10 | **needs-confirm** — dry-run complete, nothing changed |

### 4.3 The itemized-consent interlock (H1)

The protocol, in order. Every step is mandatory; none may be merged with another.

1. **Enumerate** via `git ls-files` over the four SSD path roots.
2. **Display the complete list.** Never truncate, never sample, never summarize as a count. If it is
   400 files, print 400 lines. A file the user did not see named must never be untracked.
3. **Classify.** Split the list into *SSD-produced* versus everything else, and call the second group
   out under its own heading — this is H3, the difference between "untracking my own paper trail" and
   "untracking my team's architecture doc."

   > **Implementation correction (coder phase).** This step originally said the second group was
   > "`docs/` files SSD did not create," and named runbooks/architecture as SSD-recognizable. Neither
   > holds: runbook and architecture filenames are feature-named and therefore **indistinguishable**
   > from any other doc, so the first implementation flagged SSD's *own* runbooks. A warning that fires
   > on the tool's own output trains the user to ignore it, destroying the signal the interlock exists
   > to give.
   >
   > Shipped with a **third signal** — SSD frontmatter (a `skill:` key in the leading `---` block, per
   > `chapters/state.md`) — so runbooks and architecture docs are recognized by content when naming
   > cannot do it. And the heading now reads **"UNCONFIRMED as SSD-produced"** rather than asserting
   > the file was not SSD's: the probe cannot establish authorship, and the output must not claim more
   > than the probe supports.
4. **Warn about history**, verbatim and unconditionally: `git rm --cached` stops *future* tracking;
   **published history is not rewritten.**
5. **Require `--confirm`.** Exit 10 otherwise.
6. **Act**, then re-verify: `git ls-files` over the same roots must come back empty (excluding any
   paths the user was told would be retained).

**Never itemize-and-proceed in one invocation.** The list and the action are two separate runs, so
the user has read the list before the second one exists.

### 4.4 Idempotency (H4)

`detect_private_mode()` is the guard. On an already-private project, `--elect private-mode --confirm`
must:
- skip the pattern append (sentinel-guarded, as `apply_selective_gitignore` does),
- skip the config writes (keys already present),
- find zero tracked SSD paths and therefore run **no** `git rm --cached`,
- exit 0 reporting "already private; nothing to do."

Carried forward from iteration A's ordering rules: bail-before-mutating if `private.gitignore` is
missing; pattern first, marker key last; comments on their own line; sentinel-guarded append.

### 4.5 Integration Contract — `not_applicable`

No queues, events, webhooks, retries, or cross-process calls. Idempotency, the one Principle-6
concern that transfers, is specified in §4.4 rather than duplicated here.

---

## 5. Decision: `elective` is an orthogonal field, **not** a third `kind`

The brief reserved this for design ("is `elective` the right name, and should it be a `kind` or an
orthogonal field?"). The ratified substance — *excluded from the sweep, never PENDING, never pins the
version, runs only when named* — is preserved exactly either way. The illustrative preview in that
decision showed `kind: elective`; the shape below differs from it and every ratified property holds.

**Decisive argument — a third `kind` value destroys information the elect path needs.**
`apply_dispatch` is called at exactly **one** site today (`migrate.sh:546`, inside the report loop).
The elect path adds a second call site. With `kind: elective`, the manifest would no longer record
that `private-mode` is *mechanically* applicable, and the elect handler would have to **assume**
elective ⇒ mechanical. That is the conflation, not a stylistic preference: `kind` answers *how* it is
adopted, `elective` answers *whether every project should*.

**The 2×2 is fully meaningful**, which is what separates this from the `ssd.privacy` matrix iteration A
rejected (where ~4 of 6 cells were meaningless):

| | swept (default) | elective |
|---|---|---|
| **mechanical** | `selective-gitignore` — every project should be on it, auto-appliable | **`private-mode`** — a choice, auto-appliable once chosen |
| **guided** | `decision-record-doctrine` — every project should adopt, by hand | a future practice only some projects should adopt |

`kind: elective` cannot express the fourth cell at all.

**Cost, honestly stated:** an 8th `read_manifest` column and two consumer updates. Bounded and
enumerated (§3.2). The `obsoleted_in` addition in v2.2.0 is the precedent — same shape, and its review
recorded it as a *"7th column + 1-line select guard."*

**Name:** `elective`, not `optional`. Every migration is "optional" under warnings-not-walls;
`elective` says the specific thing — *must be explicitly elected.*

---

## 6. Decision Log

### 6.1 ADR-0013 addendum — required
ADR-0013 defines the manifest as `mechanical | guided` and describes the sweep as answering *"what has
this project drifted past?"* An entry that is deliberately **not** drift is a contract change to that
ADR, and the `elective` field belongs recorded there — not only in ADR-0017. Must state: what
`elective` means, that absent-is-false (so all 12 existing entries are unaffected), that it is
orthogonal to `kind`, and that it is inert in the default sweep by construction.

### 6.2 ADR-0017 amendment — required
Two items: (a) the retrofit is **elective**, correcting iteration A's ratified "via a `/ssd upgrade`
migration entry" — the entry point survives, the sweep can never reach it, with the `mechanical`/`guided`
harm analysis recorded so the correction is not relitigated; (b) the **history limitation** in
Consequences — `git rm --cached` stops future tracking, published history is not rewritten.

### 6.3 Always-ADR topics
Of the eight: database, auth, sync/async, monolith-vs-services, deployment target, and schema
migration have **no referent** in a bash migration engine with no runtime. **Third-party vs build** —
no new dependency (`git`, `awk`, `bash` already required). **Licensing** — unchanged. The two
consequential decisions are §5 and the interlock, covered by 6.1 and 6.2.

### 6.4 Deliberately NOT in this iteration
The `parse_active_workstreams` fragmentation defect and QUESTION-2 both remain out — hard rule 4.
Recording again here because both are tempting: `migrate.sh` is open in this iteration and QUESTION-2
lives in it. Resist; they are not this feature's work.

---

## 7. Risk Assessment

**Top 3 first.**

| # | Risk | L | I | Mitigation |
|---|---|---|---|---|
| **1** | **A user untracks files they did not know about** — `docs/architecture/` holds a team doc SSD never created, and it disappears from tracking in a commit nobody reviews carefully. | M | **H** | §4.3: full list, never truncated, **plus** a separate heading for `docs/` files SSD did not create. Dry-run by default means the list is read in a run that changed nothing. |
| **2** | **"Private" is heard as "scrubbed."** History is not rewritten; a pushed artifact stays pushed. Inherited from iteration A, but iteration B is where a user acts on the belief. | **H** | **H** | §4.3 step 4: verbatim, unconditional warning in the dry-run *and* the confirmed run. ADR-0017 Consequences. Never phrase the outcome as "removed." |
| **3** | **An elective entry leaks into a default path** — one place treating it as ordinary drift converts a team repo to private on a routine `--apply`. | L | **H** | §2: all four default behaviors live inside the report loop, so a single `continue` before the `satisfied` bookkeeping covers them. Fixture asserts `private-mode` appears in **no** default report and does **not** pin the version. |
| 4 | 8th column added to one `read_manifest` consumer but not the other → silent field shift | M | M | §3.2 names both sites; fixture parses the manifest and asserts field alignment |
| 5 | Dry-run and confirmed run disagree about the file list (repo changed between them) | L | M | §3.3: recompute, never cache. Re-verify after acting (§4.3 step 6) |
| 6 | Idempotency failure → second `git rm --cached` pass | L | M | §4.4 `detect_private_mode()` guard + zero-path short-circuit |
| 7 | `introduced_in: 2.9.0` > `VERSION` fails `migration-manifest-current` | **H** if VERSION not bumped | L | Bump `VERSION` to 2.9.0 in the same commit; the gate rule catches it immediately |
| 8 | Recorded version never advances for an elective entry (H5) | — | L | **Stated decision, not a bug:** the recorded version tracks *conventions adopted*, and an elective capability is not one. A project that elects private mode keeps its prior recorded version and reports no drift. |

**CI/CD & deployment path:** unchanged — the library ships by tagging and pushing
(`distribution.channel: direct-install`). `parity-test.sh` gates the release.

---

## 8. Feature Flag Plan

| | |
|---|---|
| **Flag** | the `private-mode` manifest entry itself, `elective: true` |
| **Default** | **inert.** Absent an explicit `--elect private-mode`, behavior is byte-identical to v2.8.0 for every project |
| **Type** | Manifest-data flag — not a code branch. The entry exists but no default path reads it |
| **Kill switch** | Remove `--confirm`, or never elect. Post-election reversal is **not built** (see below) |

**Rollout stages**, adapted to a direct-install library:

1. **Internal** — merged; exercised only by parity fixtures. Zero project exposure, because no project
   elects it by default.
2. **Beta** — dogfood on a throwaway repo *that has committed SSD artifacts* (the retrofit case iter A's
   greenfield dogfood could not cover): run the dry-run, verify the list is complete and correctly
   classified, then `--confirm` and verify `git status` + `no-leaky-state`.
3. **100%** — documented in README as the supported retrofit path.

**Flag removal: never.** Like `gitignore_mode` itself, this is permanent configuration surface. Rail
step 8 records a `rail_deviation` rather than executing.

**Not built, and say so rather than implying symmetry:** moving *out* of private mode (re-tracking
previously-untracked artifacts). A user can do it by hand (`git add` the paths and revert the mode);
there is no inverse migration.

---

## 9. Test Plan

| # | Fixture | Asserts |
|---|---|---|
| 1 | `elective-absent-from-default-report` | plain `--from/--to` report never mentions `private-mode` |
| 2 | `elective-not-applied-by-sweep` | `--apply` on a repo with tracked SSD artifacts leaves them **tracked** (the catastrophic case) |
| 3 | `elective-does-not-pin-version` | recorded version advances past 2.9.0 with `private-mode` unelected |
| 4 | `elect-dry-run-mutates-nothing` | `--elect` without `--confirm`: exit 10, `.gitignore`/`project.yml`/index all byte-identical |
| 5 | `elect-lists-every-tracked-file` | every tracked SSD path appears in the output; no truncation |
| 6 | `elect-flags-non-ssd-docs` | a hand-made `docs/architecture/team.md` is listed under the "not created by SSD" heading |
| 7 | `elect-history-warning-present` | the warning appears in **both** the dry-run and the confirmed run |
| 8 | `elect-confirm-untracks` | with `--confirm`: paths untracked, **files still on disk**, `no-leaky-state` PASSes |
| 9 | `elect-idempotent` | second `--elect --confirm` → exit 0, no second `git rm`, no duplicated pattern |
| 10 | `elect-validation` | unknown id / swept id / guided id → exit 2, distinct messages |
| 11 | `read-manifest-8-columns` | both consumers see aligned fields; `elective` absent ⇒ falsy |
| 12 | `manifest-current-accepts-elective` | `migration-manifest-current` PASSes with the new field |

**Fixture 2 is the acceptance test for the whole iteration.** If a default `--apply` untracks
anything, the feature is worse than not shipping.

**Regression floor:** all 128 existing assertions pass.

---

## 10. Self-Verification

1. **Every gate section real?** Yes. `integration_contract: not_applicable` with the reason stated
   (§4.5), not left blank.
2. **Adapted, not copy-pasted?** Yes — the data model is a manifest schema because there is no
   database; the API contract is CLI + exit codes because there is no network. Baseline measured (§1).
3. **Read the sources?** Yes, and it decided §5: `apply_dispatch` having exactly one call site is what
   makes `kind: elective` lossy. Also verified the two `read_manifest` consumers, that all four default
   behaviors live inside the report loop, that `migration-manifest-current` does not validate `kind`,
   and that `--adopt` is a pre-loop short-circuit.
4. **ADRs for applicable always-ADR topics?** Six have no referent (§6.3); the two live decisions are
   the ADR-0013 addendum and the ADR-0017 amendment.
5. **Baseline has real numbers?** Yes — §1, measured at v2.8.0.

**Handoff note for `coder`:** the risk is concentrated in §4.3. Fixture 2
(`elective-not-applied-by-sweep`) and fixture 5 (`elect-lists-every-tracked-file`) are the two that
must be written **first** and seen to fail before the implementation exists — this workstream has now
produced five instances of a check that could not fail, and this iteration is the one where such a
check would cost a user their tracked files.
