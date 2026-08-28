---
skill: architect
version: 1.3.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-private-mode
consumed_by: [coder, systems-designer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0017, ADR-0015]
  risk_assessment: true
  feature_flag: "project.yml.ssd.gitignore_mode: private"
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — ssd-private-mode

Platform: **headless** (`architect/headless/GUIDE.md`). This is a markdown skill library plus four
bash/python tools consumed by the Claude Code CLI — no runtime service, no network surface, no
persistence layer. The headless guide's service-boundary and API-versioning sections do not apply;
its **contract-first** and **idempotency** principles do, and they carry most of the weight below.

---

## 1. Current Scale Baseline

Measured on `main` at library v2.7.0, not estimated.

| Dimension | Now (1x) | 10x target | Comment |
|---|---|---|---|
| `gitignore_mode` values | 2 (`selective`, `blanket`) | 3 (`+private`) | Not a 10x axis — the mode set is deliberately small and closed |
| Gate rules in `gate-rules.sh` | 10 | ~15 | This feature touches **3**, adds 0 |
| Migration-manifest entries | 12 | ~30 | This feature adds 1 (iter B) |
| Skills with a `SKILL.md` | 11 | ~15 | This feature edits **1** (`ssd-init`) |
| Canonical gitignore pattern files | 1 (`selective.gitignore`) | 2–3 | This feature adds 1 (`private.gitignore`) |
| Parity assertions | 83 (83/83 PASS) | ~120 | This feature adds ~8–10 |
| Files hardcoding `docs/decisions/` | **12** (non-`.ssd/`) | — | The number that decides H2 — see §5 |

The 10x-relevant conclusion: **every axis here is small and bounded.** The one number that is
already large is the last row, and it is what rules out the path §5 rejects.

---

## 2. Component Diagram

```
                        .ssd/project.yml
                     ssd.gitignore_mode: private        ← single source of truth
                                 │
        ┌────────────────────────┼────────────────────────┬─────────────────────┐
        ▼                        ▼                        ▼                     ▼
   ssd-init/SKILL.md      methodology/            methodology/          methodology/
   (Steps 3,5,5.5,6,8)    gate-rules.sh           migrate.sh            issue-sync.sh
        │                        │                        │                     │
        │ writes                 │ reads mode             │ reads mode          │ reads mode
        ▼                        ▼                        ▼                     ▼
   .gitignore  ◄────────  no-leaky-state          private-mode         preflight
   (pattern +             (deny-list = ALL         migration           REFUSES when
    sentinel)              SSD output)            (iter B)            mode=private
        ▲                       │                                          │
        │ appended               │ adr-delta  ─── worktree probe           │  H6 interlock
        │ verbatim               │ feynman-clean ─ worktree glob           │
        │                        │ frontmatter-valid ─ already OK          │
   methodology/                  │                                          │
   private.gitignore ────────────┘                                          │
   (canonical single source, sibling of selective.gitignore)                │
                                                                            │
   integrations.github.issue_tracking ── forced off at init ────────────────┘
```

**The invariant the diagram encodes:** exactly one key (`gitignore_mode`) is authoritative, and every
consumer reads it rather than re-deriving the mode from `.gitignore` contents. The **one** exception is
`ssd-init` Step 5.5, which runs *before* Step 6 writes `project.yml` and therefore must detect from
`.gitignore` — the same ordering constraint documented for selective mode, and the reason
`private.gitignore` needs a sentinel line (§4).

---

## 3. Data Model

The "data" here is configuration schema. Three artifacts change shape.

### 3.1 `.ssd/project.yml` — `ssd:` block

```yaml
ssd:
  gitignore_mode: private        # selective | blanket | private        ← CHANGED: 3rd value
  gitignored_state: []           # unchanged; additive-only extension
  branch_pattern: "{slug}"       # CHANGED default under private (was "add-{slug}")

  # Under private mode ONLY, gate inputs live here rather than in committed .ssd/gate.yml,
  # because private mode has no committed .ssd/gate.yml (see ADR-0015 addendum, §7.2).
  test_command: <cmd>            # promoted from commented-placeholder to a real key
  feature_flag_marker: <regex>

integrations:
  - type: github
    issue_tracking: off          # FORCED off under private; init refuses `on` (H6)
```

**Field-level notes**

| Field | Required | Default | Constraint |
|---|---|---|---|
| `gitignore_mode` | no | `selective` | one of exactly 3 literals; anything else is an error, not a silent SKIP (§7.1) |
| `branch_pattern` | no | `add-{slug}` / `{slug}` under private | must contain `{slug}` |
| `test_command` | no (private: **yes**) | — | absent under private ⇒ `tests-pass` cannot run at all |
| `issue_tracking` | no | `off` | `on` + `private` is rejected at init and refused at runtime |

**Not a schema-version bump.** `current.yml.schema_version` stays `2` — exactly the reasoning
ADR-0008 used for the same class of change (a new `project.yml` value is not a `current.yml` schema
change).

### 3.2 `methodology/private.gitignore` (new canonical single source)

```gitignore
# SSD private mode (ADR-0017). NOTHING SSD produces is tracked.
# CANONICAL SINGLE SOURCE. `ssd-init` Step 5 and `migrate.sh` (apply_private_mode) append this
# file's contents verbatim. Edit only here.
# ssd:gitignore-mode=private            <-- SENTINEL: do not remove; Step 5.5 + migrate.sh detect on it
.ssd/
docs/decisions/
docs/runbooks/
docs/architecture/
```

Six lines against selective's forty-plus. That asymmetry is the point: selective mode needs a
precise allow-list because it commits a *subset*; private mode commits **nothing**, so there is no
allow-list to get wrong. **No `!` negation appears anywhere** — in particular no `!.ssd/gate.yml`,
which is the mechanical expression of §7.2.

### 3.3 Deny-list (in `gate-rules.sh`, mirroring 3.2)

```bash
private_baseline=( ".ssd/" "docs/decisions/" "docs/runbooks/" "docs/architecture/" )
```

ADR-0008's "Future Compatibility" warning applies with full force: **3.2 and 3.3 are the same set in
two syntaxes, and a forgotten side is a silent privacy leak.** Parity fixtures assert they agree (§9).

---

## 4. Interface Contract

The contracts between the four components. This is where a defect would actually land.

### 4.1 Mode resolution — the single rule

> Every consumer resolves the mode by reading `project.yml.ssd.gitignore_mode`, defaulting to
> `selective` when absent. `ssd-init` Step 5.5 is the **only** permitted exception and detects on the
> `.gitignore` sentinel, because `project.yml` does not yet exist at that point in the init flow.

### 4.2 Sentinel contract

| Mode | Sentinel line detected in `.gitignore` |
|---|---|
| `selective` | `!.ssd/features/**/01-architect.md` (existing, functional line) |
| `private` | `# ssd:gitignore-mode=private` (**new**, comment sentinel) |
| `blanket` | bare `.ssd/` with neither of the above |

Private mode's sentinel must be a comment, because private mode's pattern set contains no line
distinctive enough to serve: `.ssd/` alone is indistinguishable from blanket mode, and `docs/decisions/`
could plausibly appear in an unrelated project's `.gitignore`. Detection order is
**private → selective → blanket**; private must be tested first because a private `.gitignore`
also contains a bare `.ssd/` line and would otherwise be misread as blanket.

### 4.3 Idempotency contract (all writers)

Carried over from `apply_selective_gitignore`'s hard-won ordering rules — these are not
suggestions, each encodes a shipped defect:

1. **Bail before mutating** if `private.gitignore` is missing (broken install) → `return 1`. Prevents
   the MINOR-1 "silent-incomplete APPLIED" class.
2. **Pattern first, marker key last.** `detect()` probes the marker, so marker-last means a crash
   mid-apply leaves the project *detectably* un-migrated. Prevents MAJOR-3.
3. **Comment on its own line, never inline after a value.** `yaml_get` now strips inline comments, but
   the convention stands repo-wide. Prevents MAJOR-4.
4. **Sentinel-guarded append** so re-running never duplicates the block.

### 4.4 `issue-sync.sh preflight` — new exit condition (H6)

```
exit 4  state=refused  reason=private-mode
```

Defense in depth: `ssd-init` refuses the `on` + `private` combination, **and** the script refuses at
runtime, because `project.yml` is hand-editable and a mirror to a public tracker is the loudest
possible violation of the mode's promise. Init-time validation alone would be a single point of failure.

### 4.5 Integration Contract — `not_applicable`

No queues, events, webhooks, retries, or cross-process calls. Universal Principle 6's five concerns
have no referent here; idempotency, the one that transfers, is specified in §4.3 rather than duplicated.
`gh` is the only network dependency and is already gated by preflight.

---

## 5. Decision: H2 — where SSD's docs live under private mode

**The brief called this the central design decision. It is, and the answer inverts once you measure it.**

First, a technical correction to the brief's framing, which changes the risk materially:

> **`.gitignore` has no effect on already-tracked files.** Adding `docs/decisions/` to `.gitignore`
> does *not* untrack a committed ADR — git keeps tracking it and it keeps appearing in diffs.

So the "silently untracks pre-existing non-SSD content" hazard **cannot occur from the pattern alone**.
It can only occur via `git rm --cached`, which lives exclusively in the iter-B retrofit path. On a
greenfield private init there is nothing to untrack; on a retrofit the pattern is inert against tracked
files. H2's hazard is therefore **narrower and entirely contained in iter B** — which is where its
interlock belongs (§8).

**Options considered**

| | Approach | Blast radius | Verdict |
|---|---|---|---|
| (a) | Ignore the shared `docs/` paths as-is | `private.gitignore` + deny-list | **CHOSEN** |
| (b) | Relocate SSD docs to `.ssd/docs/` under private | path change in every writer | Rejected |
| (c) | Configurable `ssd.docs_root` indirection | **12 non-`.ssd/` files** hardcode `docs/decisions/` | Rejected (for now) |

**(c) is the seductive one and it is a trap.** It reads as the "clean ownership" answer — SSD would
only ever ignore paths it owns. But the measurement in §1 shows twelve non-`.ssd/` files hardcode
`docs/decisions/`, including `rails.md` invariant 7, `gate-rules.sh`'s `adr-delta`, `parity-test.sh`,
and seven sub-skill `SKILL.md` files. Worse, ADR-0008 **already rejected this exact move** for this
exact reason:

> *"Move durable artifacts into `docs/features/<slug>/` (out of `.ssd/` entirely). Cleaner conceptually
> but breaks every existing sub-skill that loads artifacts from `.ssd/features/<slug>/`. Migration cost
> is high; the path-rename touches every skill. **Rejected — keep the paths, change the gitignore.**"*

"Keep the paths, change the gitignore" is settled doctrine in this repo. Option (a) follows it; (b) and
(c) relitigate it for a strictly smaller benefit than the original proposal had.

**Chosen: (a).** With the corrected git semantics, (a) is not merely cheaper — it is *sufficient*. The
only residual exposure is the retrofit `git rm --cached`, handled by iter B's itemized-consent interlock.

**Revisit when** (falsifiable, per [ADR-0011](../../../docs/decisions/ADR-0011-decision-record-doctrine.md)):
a second consumer needs a configurable docs root for a reason unrelated to privacy — e.g. a monorepo
placing ADRs under `packages/*/docs/decisions/`. One privacy use case does not justify a 12-file
indirection; two independent use cases would.

---

## 6. Decision: the gate must not go quiet — the finding that reshapes iter A

The brief did not catch this, and it is more consequential than H2.

Four gate rules are **diff-scoped**: they read `git diff <base>...HEAD --name-only`. Under private
mode, no SSD artifact ever appears in a diff. I read all four bodies rather than assuming:

| Rule | Behavior under private mode | Verdict |
|---|---|---|
| `frontmatter-valid` | `files` after the `.ssd/` grep is empty → falls to the **existing no-diff branch**, which walks `.ssd/features/` + `.ssd/milestones/` on disk | ✅ **already correct** — no change needed |
| `adr-delta` | `arch_lines ≥ 200` and no `^docs/decisions/ADR-` in diff → **`emit FAIL`** | 🔴 **false red / deadlock** |
| `feynman-clean` | no `feynman.md` in diff → permanent `SKIP "no feynman report in scope"` | 🟠 silently toothless |
| `issue-sync-current` | tracking forced off → SKIPs | ✅ correct, not degraded |

**`adr-delta` is a hard deadlock, not a degradation.** On any change over 200 architectural lines,
`adr-delta` FAILs demanding a committed ADR delta — while `no-leaky-state`, now denying
`docs/decisions/`, would FAIL if the user force-added one. **Both branches FAIL. The gate becomes
unpassable.** A private project could not ship a substantial change at all.

This is not a corner case; 200 lines is an ordinary feature. It must be fixed **in iter A**, or private
mode is dead on arrival.

**Fix — one helper, three call sites.** Add a scope-resolving sibling to `diff_files()`:

```bash
# Under private mode SSD artifacts are never in a diff, so diff-scoping a rule that reads them
# makes it structurally unable to fire. These rules fall back to worktree scope. (ADR-0017 §6)
artifact_scope() {   # echoes "diff" | "worktree"
  [[ "$(gitignore_mode)" == "private" ]] && echo "worktree" || echo "diff"
}
```

- **`adr-delta`** under worktree scope: probe for an `ADR-*.md` under `docs/decisions/` with mtime
  newer than the base commit. Weaker than a diff (an mtime is touchable) and the detail string must
  **say so**. Compare against: today's alternative is an unpassable gate.

  > **Implementation correction (coder phase, 2026-08-28).** This spec originally named
  > `git log -1 --format=%cI "$BASE"` piped to **`find -newermt`**. That mechanism is **wrong on
  > macOS**: BSD `find` cannot parse the `@epoch` form at all (`Can't parse date/time`), and the ISO
  > form is not portable either — so the probe would have been a permanent FAIL on stock macOS,
  > trading the deadlock this fallback fixes for a different unpassable gate. Shipped instead as a
  > portable `stat -f %m` / `stat -c %Y` (BSD/GNU) mtime read over a plain glob, with **one second of
  > slack** because mtimes are second-granular and `-newermt`/`-nt` are strictly-greater (an ADR
  > written in the same second as the base commit would not have counted). Caught by parity fixture
  > `adr-delta-private-no-deadlock`; masked during design by an interactive GNU-compatible `find`
  > shim. Contract unchanged — only the mechanism.
- **`feynman-clean`** under worktree scope: glob `.ssd/{features,milestones}/*/feynman.md` on disk
  instead of filtering the diff. Cheap and strictly better.
- **`frontmatter-valid`**: **no change.** Its existing fallback already does the right thing. Add a
  parity fixture pinning that, so a future refactor of that branch cannot silently break private mode.

**Why this belongs in iter A, on doctrine:** the brief's Goal states privacy is "never a reduction in
rigor." More pointedly, this repo already shipped [ADR-0015](../../../docs/decisions/ADR-0015-ssd-init-gate-readiness.md)
because `/ssd gate` exited 0 with one of nine rules having verified anything — "a green signal that
attests to less than the reader believes." Shipping private mode with a knowingly-hollow gate would
reproduce SSD's own worst documented failure, deliberately, one release after fixing it.

---

## 7. Decision Log

### 7.1 ADR-0017 (new) — private mode
Authored with this spec: the mode, the `.gitignore` semantics correction (§5), the four-rule gate
analysis (§6), the attribution carve-out, and the retrofit limits. Status **Proposed**.

Includes one **strictness change** beyond the brief: an *unrecognized* `gitignore_mode` value must be a
loud error, not today's `SKIP "unknown gitignore_mode"`. A typo (`privat`) currently disables SSD's
leak-detection rule silently — and under a mode whose entire purpose is privacy, a typo that turns
protection off without saying so is unacceptable. Fixing the guard while adding the third value costs
one branch.

### 7.2 ADR-0015 — addendum required (H3)
ADR-0015 moved gate inputs into a **committed** `.ssd/gate.yml` to fix root cause P2: *"those inputs
live in gitignored `project.yml`, so gate config is per-checkout: a second contributor silently gets a
weaker gate."*

**Private mode reopens P2 by construction.** No committed `gate.yml` can exist. Verified graceful:
`gate_input()` reads `project.yml` first, then `gate.yml`, so an absent `gate.yml` degrades to
`project.yml` rather than erroring — which is why §3.1 **promotes `test_command` /
`feature_flag_marker` from commented placeholders to real keys** under private mode. Without that
promotion, `tests-pass` and `feature-flag-present` SKIP and the gate loses two more rules.

The residual cost is real and stated, not hidden: **a private project's gate config does not travel to a
second clone or a CI runner.** For a solo/private practice — the mode's entire audience — the P2 blast
radius is close to nil, because there is no second contributor. That is the trade, and ADR-0015 gets an
addendum recording it rather than leaving a future reader to discover the contradiction.

### 7.3 ADR-0008 — cited, not superseded
Private mode is the third value in the enum ADR-0008 created, exactly as its "Future Compatibility"
section anticipated. §5 *reaffirms* its "keep the paths, change the gitignore" ruling. No supersession.

### 7.4 Migration-manifest mode-awareness (found while reading `migrate.sh`)
Two existing mechanical entries probe for artifacts private mode must not have:

- `committed-gate-yml` — detects `.ssd/gate.yml` **and** `!.ssd/gate.yml` in `.gitignore`
- `strict-selective-gitignore` — detects the `.ssd/features/**` deep-deny line

On a private project both probes fail forever, so `/ssd upgrade` would report **permanent, unfixable
drift** and `--apply` would try to re-add the `!.ssd/gate.yml` negation — actively breaking privacy.
`migrate.sh` must treat both as **N/A under private mode**. This is a defect in the *existing* upgrade
path that private mode would trip, so it belongs in iter A alongside the mode, not in iter B with the
rest of the retrofit work.

### 7.5 Always-ADR topics — applicability
Of the eight always-ADR decisions: database, auth, sync/async, monolith-vs-services, deployment
target, and schema migration have **no referent** in a markdown library with no runtime.
**Third-party vs build** — no new dependency (bash/awk/git/python3 already required).
**Licensing** — unchanged. The mode itself is the one consequential decision, and it is ADR-0017.

---

## 8. Iteration Plan

Two iterations. Iter A is independently shippable and delivers working greenfield private mode.

### Iter A — the mode, and the gate that must survive it
1. `methodology/private.gitignore` — new canonical source + sentinel (§3.2)
2. `gate-rules.sh`:
   - `no-leaky-state` accepts `private`; private deny-list (§3.3); **loud error on unknown mode** (§7.1)
   - `artifact_scope()` helper; `adr-delta` + `feynman-clean` worktree fallback (§6)
3. `issue-sync.sh preflight` → `exit 4 state=refused reason=private-mode` (§4.4)
4. `migrate.sh` — `committed-gate-yml` + `strict-selective-gitignore` N/A under private (§7.4)
   - **Added in coder phase (not in this list as first written):** `apply_gate_inputs_present` must
     also write to `project.yml` rather than `.ssd/gate.yml` under private mode. Without it,
     `migrate.sh` and `ssd-init` disagree about where a private project's gate config lives — the
     dual-source drift ADR-0013's extraction work exists to prevent — and `--apply` would create a
     `.ssd/gate.yml` that [ADR-0017](../../../docs/decisions/ADR-0017-private-mode.md) states cannot
     exist in this mode. Small, in-scope, and a reviewer would have flagged its absence as MAJOR.
5. `ssd-init/SKILL.md` — `--private` flag; Step 5 4th case; Step 5.5 third branch + detection order
   (§4.2); Step 6 template (§3.1, incl. promoted gate inputs + forced `issue_tracking: off`);
   Step 3 note; Step 8 skip (§10 H4)
6. `docs/decisions/ADR-0017-*.md` + ADR-0015 addendum (§7.2)
7. Docs: `chapters/artifacts.md` (mode column), `chapters/enforcement.md` (private-mode rule
   semantics), `README.md`, `methodology/SKILL.md`
8. Parity fixtures (§9); `VERSION` → **2.8.0**; skill banners

### Iter B — retrofit + remaining stealth
1. `migrations.yml` `private-mode` entry (`introduced_in: 2.8.0`, mechanical, ADR-0017) +
   `detect_private_mode()` / `apply_private_mode()`
2. **The itemized-consent interlock** — the one place H2's real hazard lives. Before any
   `git rm --cached`: run `git ls-files docs/decisions docs/runbooks docs/architecture .ssd`, print the
   **full file list**, require explicit confirmation, and print the history warning unmissably.
   Never itemize-and-proceed in one step.
3. **History warning** (ratified decision 4): `git rm --cached` stops *future* tracking; published
   history is **not** rewritten. Must appear in the migration output, the ADR Consequences, and the
   `/ssd upgrade` report — not one of the three.
4. `branch_pattern: "{slug}"` default under private + `chapters/workstreams.md`

**Boundary rationale:** iter A never runs `git rm --cached`, so it cannot destroy tracking state — the
one genuinely dangerous operation is quarantined behind its own review cycle.

---

## 9. Test Plan (parity fixtures)

`scripts/parity-test.sh`, 83/83 passing today. Target ~93.

| # | Fixture | Asserts |
|---|---|---|
| 1 | `private-gitignore-sentinel` | pattern file exists; sentinel present; **no `!` negation anywhere** |
| 2 | `no-leaky-state-private-runs` | mode=private → rule **runs** (not SKIP) |
| 3 | `no-leaky-state-private-denies-docs` | tracked `docs/decisions/ADR-*.md` in diff → FAIL |
| 4 | `unknown-gitignore-mode-errors` | `privat` → loud error, **not** silent SKIP (§7.1) |
| 5 | `adr-delta-private-no-deadlock` | mode=private, >200 arch lines, ADR on disk → **PASS not FAIL** (§6) |
| 6 | `frontmatter-valid-private-walks-tree` | pins the existing fallback so a refactor can't break it |
| 7 | `feynman-clean-private-worktree` | on-disk `feynman.md` with a contradicted claim → FAIL |
| 8 | `issue-sync-refuses-private` | preflight → exit 4 |
| 9 | `migrate-private-na-entries` | `committed-gate-yml` + `strict-selective-gitignore` → N/A (§7.4) |
| 10 | `deny-list-mirrors-pattern-file` | §3.2 and §3.3 agree — the ADR-0008 dual-maintenance trap |

Fixture 10 is the one that matters most long-term: it is the only mechanical defense against the
"forgotten place is a silent leak" failure ADR-0008 explicitly warned about.

**Regression floor:** all 83 existing assertions must still pass. Selective and blanket projects are
untouched by construction — every change is inside a `mode == "private"` branch.

---

## 10. Risk Assessment

**Top 3 flagged first**, per the skill's Risk Assessment contract.

| # | Risk | L | I | Mitigation |
|---|---|---|---|---|
| **1** | **Users read "private" as a security guarantee.** It is not: no encryption, and `git rm --cached` never rewrites published history. A user could believe a client repo was scrubbed when it is not. | **H** | **H** | Name it a *visibility* posture everywhere. Non-goals are explicit in ADR-0017 and the brief. Iter B's itemized-consent interlock forces the user to see the exact files before anything is untracked. |
| **2** | **Pattern file and deny-list drift apart** (§3.2 vs §3.3) — a new artifact type added to one only. Under private mode that is a privacy leak, not commit noise. | M | **H** | Parity fixture 10 asserts agreement. Both files cross-reference each other and ADR-0017 §3. Exactly the ADR-0008 dual-maintenance warning. |
| **3** | **The `adr-delta` deadlock ships unnoticed** (§6) — private mode becomes unusable on any real change. | M (H without §6) | **H** | Fixture 5 pins it. Fix is in iter A, not deferred. |
| 4 | Typo in the mode value silently disables leak detection | M | H | §7.1 — loud error on unrecognized value |
| 5 | `/ssd upgrade` reports permanent drift on private projects | **H** without §7.4 | M | §7.4 — both entries N/A under private; iter A |
| 6 | `issue_tracking: on` hand-edited into a private project | L | **H** | §4.4 — runtime refusal in addition to init-time |
| 7 | Private mode's gate config doesn't reach CI (§7.2) | H | L | Accepted, documented, ADR-0015 addendum. Blast radius ≈ nil for a solo practice. |
| 8 | Discoverability: no committed `CLAUDE.md` pointer (H4) | H | **L** | Resolved below — advisory only |
| 9 | Step 5.5 misdetects private as blanket | M | M | §4.2 detection order: private **before** blanket |

**H4 resolved (risk 8 downgraded to L).** The brief worried that suppressing the committed `CLAUDE.md`
SSD section costs the agent its convention pointer. It does not: `/ssd`'s actual prerequisite is
`.ssd/project.yml` (`ssd/SKILL.md` § Prerequisite), and `ssd-init` Step 8 already describes the section
as a pointer the user "may want to add." **It is advisory, not functional.** Under private mode Step 8
skips the offer and the pointer lives in `.ssd/README.md`, which Step 4 already writes and which is
gitignored. The cost is human discoverability in a repo the user is deliberately keeping quiet —
self-consistent. **No dependency on `CLAUDE.local.md`**, whose loading behavior I did not verify and
which this design therefore does not rely on. It may be mentioned as an optional user convenience;
nothing depends on it.

**CI/CD + deployment path.** Unchanged: the library ships by tagging a version and pushing to GitHub
(`project.yml.distribution.channel: direct-install`). `parity-test.sh` is the test harness and gates
the release. No deployment surface changes.

---

## 11. Feature Flag Plan

| | |
|---|---|
| **Flag** | `project.yml.ssd.gitignore_mode: private` |
| **Default** | `selective` — absent or unset ⇒ **byte-identical** behavior to v2.7.0 |
| **Type** | Config-valued, not boolean; the mode enum *is* the flag |
| **Kill switch** | Set back to `selective` / `blanket`. Reverses all *future* behavior; already-untracked files need re-adding by hand (iter B states this) |

**Rollout stages** (adapted honestly to a direct-install library with no runtime):

1. **Internal** — iter A merged; this repo stays `selective`. Private mode exercised only by parity
   fixtures. **Zero** production exposure.
2. **Beta** — dogfood on a throwaway repo: `ssd-init --private`, run a full `/ssd feature` cycle, assert
   `git status` clean and `/ssd gate` still verifying (this is the §6 acceptance test, run for real).
3. **100%** — iter B ships retrofit; documented in `README.md` as a supported mode.

**Flag removal: never.** This is a permanent user-facing configuration axis, not a transitional flag —
the same status as `selective` and `blanket`. Rail step 8 (flag removal) therefore records a
`rail_deviation` rather than executing.

**This repo will not adopt private mode.** It dogfoods SSD *in public* — its `.ssd/` artifact history
is a stated deliverable of ADR-0008. Iter A's dogfood target is a scratch repo (stage 2).

---

## 12. Self-Verification

1. **Every Quality Gate section has real content?** Yes. `integration_contract` is the one
   `not_applicable`, with the reason stated in §4.5 rather than left blank.
2. **Adapted to the actual stack, or copy-pasted platform defaults?** Adapted. The data model is a
   config schema because there is no database; the API contract is inter-script contracts because there
   is no network boundary. Scale baseline is measured (§1), not placeholder.
3. **Read the sources rather than pattern-matching?** Yes, and it changed three conclusions: the
   `.gitignore`/tracked-files semantics inverted H2 (§5); reading all four rule bodies found the
   `adr-delta` deadlock the brief missed **and** corrected my own initial assumption that
   `frontmatter-valid` was broken (it is not); reading `migrate.sh` found §7.4.
4. **ADR exists for each applicable always-ADR topic?** Six have no referent (§7.5); the two that do
   are unchanged. ADR-0017 + the ADR-0015 addendum are the deliverables.
5. **Scale baseline has real numbers?** Yes — §1, measured on `main` at v2.7.0.

**Handoff note for `coder`:** §6 is the non-obvious part and the one most likely to be under-built.
Fixture 5 (`adr-delta-private-no-deadlock`) is the acceptance test for the whole feature: if it fails,
private mode cannot ship a >200-line change, which makes the mode useless in practice.
