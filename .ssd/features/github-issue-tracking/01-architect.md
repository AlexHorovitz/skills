---
skill: architect
version: 1.3.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: github-issue-tracking
consumed_by: [coder, systems-designer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: true
  adrs: [ADR-0014]
  risk_assessment: true
  feature_flag: integrations.github.issue_tracking
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — github-issue-tracking

**Platform:** headless (Claude Code skills library — orchestrator prose + a bash helper, no runtime
application code). Brief: [`00-brief.md`](00-brief.md). Decision: [ADR-0014](../../../docs/decisions/ADR-0014-github-issue-state-tracking.md).

## Current Scale Baseline
- **Projects using SSD issue-tracking today:** 0 (feature does not exist). Opt-in.
- **Active workstreams per project (this repo, peak):** 1–3 (`current.yml.active[]`; ADR-0007 model).
- **ADRs in this repo:** 14. **`gh` calls per phase advance (tracking on):** 1–3 (ensure-epic,
  ensure-feature, relabel).
- **10x target (mechanical):** ~30 active workstreams, ~140 ADRs, ≤30 `gh` calls per advance. All are
  individual idempotent CLI calls — no batching, pagination, or rate-limit design needed at 10x (gh's
  default 5000 req/hr authenticated ceiling is ~167x the 10x peak). No scale work required.

## Component Diagram
```
  /ssd phase advance (orchestrator)
            │  reads .ssd/project.yml  → integrations.github.issue_tracking ?
            │                          → integrations.github.auto_close ?
            ▼
   ┌─────────────────────────┐   off / gh absent
   │ issue_tracking gate      │ ───────────────────►  no-op (zero network, today's behavior)
   │ (toggle + gh preflight)  │
   └───────────┬─────────────┘  on + gh ok
               ▼
   ┌─────────────────────────────────────┐        ┌──────────────────────┐
   │ methodology/issue-sync.sh            │  gh    │  GitHub Issues       │
   │  ensure-epic   <ADR-NNNN> <title>    │ ─────► │  ssd:epic   #E        │
   │  ensure-feature <slug> <phase> <#E>  │ ─────► │  ssd:feature #F ──┐   │
   │  set-phase     <#F> <phase>          │ ─────► │   └ ssd:phase/* ──┘   │
   │  close-feature <#F>  [--confirm]     │ ─────► │  (linked to #E)      │
   │  close-epic    <#E>  [--confirm]     │ ─────► └──────────────────────┘
   └───────────┬─────────────────────────┘
               ▼ writes back resolved numbers
   .ssd/current.yml  active[].epic: E   active[].issue: F   (lazy cache; branch: precedent)
```

## Data Model

### `.ssd/project.yml` — new keys (both optional, safe-by-omission)
```yaml
integrations:
  - type: github
    enabled: true
    issue_tracking: off      # NEW. off (default) → entire feature dormant, zero network calls.
    auto_close: false        # NEW. false (default) → closes prompt once; true → close automatically.
```
Omission ≡ `off`/`false`. The existing `integrations` list-of-maps shape is preserved.

### `.ssd/current.yml` — new optional fields on `active[]` (no schema_version bump)
| Field | Type | Meaning | Backfill |
|---|---|---|---|
| `epic:` | int \| null | parent epic issue number (the ADR's issue) | lazy, on first sync (`branch:` precedent) |
| `issue:` | int \| null | this workstream's feature issue number | lazy, on first sync |

Reuses the **existing** `adrs_authored:` list to resolve which ADR → which epic. No new state for the
ADR binding itself — title-convention discovery + this cache (ADR-0014 Q1).

### GitHub issue shapes (the convention)
| | Epic | Feature |
|---|---|---|
| **Label** | `ssd:epic` | `ssd:feature` + exactly one `ssd:phase/<phase>` |
| **Title** | `[ADR-NNNN] <decision title>` | `<slug>: <one-line>` |
| **Link** | — | references epic via `Epic: #E` body line + task-list entry on the epic |
| **Body** | ADR summary + revisit ledger (ADR-0011) | machine-managed block (see below) |

Phase labels (one per SSD rail phase): `ssd:phase/brief`, `/design`, `/code`, `/review`, `/gate`,
`/deploy`, `/done`. `ssd:epic`, `ssd:feature`, `ssd:phase/design` already exist in the repo; the
helper ensures the rest via `gh label create --force` (idempotent) on first use.

### Machine-managed feature-issue body block
The helper owns a delimited region; everything outside it is human-editable and preserved:
```
<!-- ssd:begin -->
**Workstream:** github-issue-tracking · **Phase:** design · **Gate rounds:** 0
**Branch:** add-github-issue-tracking · **Epic:** #<E>
_Synced from .ssd/current.yml — do not edit inside this block._
<!-- ssd:end -->
```
Re-sync replaces only the `ssd:begin..ssd:end` span (sed-style), never the user's discussion.

## API / Interface Contract — `methodology/issue-sync.sh`
Mirrors `gate-rules.sh`/`migrate.sh`: standalone, CI-friendly, `--json` capable, exit-code driven.

| Subcommand | Args | Action | Idempotency key |
|---|---|---|---|
| `preflight` | — | verify `gh` present + authed + repo resolvable; else exit 3 (caller no-ops) | — |
| `ensure-epic` | `<ADR-NNNN> <title>` | search `--label ssd:epic --search "[ADR-NNNN] in:title"`; create if absent; echo number | `[ADR-NNNN]` title prefix |
| `ensure-feature` | `<slug> <phase> <epic#>` | search `--label ssd:feature --search "<slug>: in:title"`; create+link if absent; echo number | `<slug>:` title prefix |
| `set-phase` | `<issue#> <phase>` | remove other `ssd:phase/*`, add `ssd:phase/<phase>`; refresh body block | label set is convergent |
| `close-feature` | `<issue#> [--confirm]` | close iff `auto_close` or `--confirm`; else print intent + exit 10 | close is convergent |
| `close-epic` | `<epic#> [--confirm]` | close iff all child `ssd:feature` issues closed AND (`auto_close` or `--confirm`) | close is convergent |

Output: `--json` emits `{action, issue, state, skipped_reason?}` per call. Exit codes: `0` ok,
`3` gh-unavailable (caller treats as no-op SKIP), `10` close-needs-confirmation (caller prompts).

### Orchestrator integration (prose, in `ssd/chapters/`)
On every phase advance, when `issue_tracking: on` and `preflight` == 0:
1. `ensure-epic` for each `adrs_authored` ADR → cache `epic:`.
2. `ensure-feature <slug> <phase> <epic>` → cache `issue:`.
3. `set-phase <issue> <new-phase>`.
4. On advance to `done`: `close-feature`; then `close-epic` if it was the epic's last open child.
Steps 4's closes obey the `auto_close`/confirm gate (ADR-0014 Q2). Each step is **surfaced** in the
orchestrator's proposal (rule-zero): the user sees "syncing issue #F → phase/code" before it happens.

## Integration Contract (this feature *is* an integration — required, Universal Principle 6)
- **Idempotency.** Every write is search-or-create / edit-in-place; the title prefix is the dedupe
  key. Re-running a phase, or two `/ssd` invocations racing, converges to one issue (last-write-wins
  on labels/body — both writers compute the same target state from `current.yml`).
- **Ordering.** Phase advances are user-driven and serial (SSD enforces one Claude session per
  project — `chapters/state.md` concurrency note). No out-of-order delivery to design for; the
  label set is convergent regardless.
- **Schema evolution.** The body block is delimited (`ssd:begin/end`) so its internal format can
  change across versions without touching human content. New phase labels are `--force`-created
  lazily; old labels are never deleted.
- **Failure / degradation.** `gh` absent, unauthenticated, offline, or rate-limited → `preflight`
  (or any subcommand) exits non-zero, the orchestrator **warns once and continues the phase** (a
  sync failure NEVER blocks SSD work — the mirror is best-effort). The local `.ssd/` state is
  authoritative and unaffected.
- **No DLQ / no retry queue.** A failed sync is simply re-attempted on the next phase advance
  (self-healing via idempotency); there is no durable outbox. Documented as acceptable because the
  issue is a mirror, not a transaction log.
- **Sync vs async boundary.** Synchronous (the `gh` call completes before the phase proposal
  returns), tolerated because it's ≤3 sub-second CLI calls; timeout 10s per call, on timeout →
  treat as degradation (warn + continue).

## Decision Log
- **[ADR-0014](../../../docs/decisions/ADR-0014-github-issue-state-tracking.md)** — the convention
  (ADR=epic, workstream=feature issue), one-way authority, and the three open-question resolutions
  (title+cache binding, toggle-as-consent with gated close, staged informational gate rule).
- No new always-ADR topic is triggered: no DB, no auth strategy change (reuses `gh` auth), no
  monolith/services, no new deployment target. Third-party (`gh`) is already adopted.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Duplicate issues on race / re-run | M | M | search-or-create with title-prefix idempotency key; verified by a parity fixture |
| Accidental epic close (notification fan-out, premature) | L | H | `close-epic` requires *all* children closed **and** `auto_close`/explicit confirm (ADR-0014 Q2) |
| `gh` absent/unauth crashes a phase | M | H | `preflight` exit-3 → orchestrator warns + continues; sync is best-effort, never blocking |
| Default-on by accident → surprise network calls | L | H | default `off`; gate-rules `no-leaky-state` unaffected; parity fixture asserts off-path is silent |
| Body-block clobbers human discussion | L | M | edits confined to `ssd:begin..ssd:end` span; everything else preserved |

**Top 3:** accidental epic close · `gh`-absent crash · duplicate issues — all mitigated above; the
first two are also the systems-designer's first checklist items if a production-runtime variant is
ever built (N/A here).

## Feature Flag Plan
- **Flag:** `integrations.github.issue_tracking` in `.ssd/project.yml` (the toggle *is* the flag —
  config-level, not runtime, appropriate for a no-runtime library).
- **Default:** `off` → feature fully dormant, zero network, today's behavior byte-for-byte.
- **Rollout stages:** (1) off everywhere = ship the helper + prose dark; (2) **this repo opts in**
  and dogfoods (epic + feature issue for ADR-0014); (3) documented in README as opt-in for downstream
  projects. No "remove the flag" stage — the toggle is a permanent user choice, not temporary scaffolding.

## Deployment / CI path
"Ships" by tagging a version + pushing to GitHub (per `project.yml.notes`). `issue-sync.sh` joins the
existing bash helpers; add it to whatever shellcheck/CI quality gate covers `methodology/*.sh`.
Walking-skeleton-deployable today: the off-path is a no-op, so merging the helper dark is always
shippable.

## Suggested iteration split (coder + orchestrator)
- **Iter A (now):** project.yml keys + current.yml `epic:`/`issue:` fields + `issue-sync.sh`
  (`preflight`/`ensure-epic`/`ensure-feature`/`set-phase`) + orchestrator prose for auto-sync on
  advance + **dogfood bootstrap** (create ADR-0014 epic + this feature issue by hand). Closes are
  prompt-only.
- **Iter B:** `close-feature`/`close-epic` automation behind `auto_close`, the `issue-sync-current`
  gate rule (ADR-0014 Q3), a `migrations.yml` entry for the new project.yml keys, README convention docs.
