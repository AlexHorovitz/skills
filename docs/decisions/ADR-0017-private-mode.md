# ADR-0017: `gitignore_mode: private` — SSD with no paper trail in git

## Status

Proposed — 2026-08-28 — designed in the `ssd-private-mode` workstream
([01-architect.md](../../.ssd/features/ssd-private-mode/01-architect.md)).

## Context

SSD has offered two postures toward git since v1.18.0, set by `project.yml.ssd.gitignore_mode`
([ADR-0008](ADR-0008-ssd-commit-split.md)):

- **`selective`** (default) — durable artifacts committed, machine state local.
- **`blanket`** (legacy v1.3.0–v1.17.x) — everything under `.ssd/` gitignored.

Neither supports a genuinely **private** practice. Even on `blanket`:

- `.ssd/gate.yml` is force-committed by an explicit `!.ssd/gate.yml` negation
  ([ADR-0015](ADR-0015-ssd-init-gate-readiness.md), v2.5.0).
- `docs/decisions/`, `docs/runbooks/`, `docs/architecture/` are committed **by design** — ADR-0008
  argues ADRs are durable records that belong in history.
- Outward mechanics are fully visible: `add-{slug}` branch names, and under
  `integrations.github.issue_tracking: on`, `ssd:epic` / `ssd:feature` / `ssd:phase/*` labelled issues
  in a public tracker ([ADR-0014](ADR-0014-github-issue-state-tracking.md)).
- `ssd-init` Step 8 offers to write an "SSD Convention" section into the **committed** `CLAUDE.md`.

A developer wanting to use SSD where the methodology paper trail should not appear — a client
codebase, a shared team repo where SSD is a personal rather than team practice, an OSS contribution,
or simply a project where working notes are nobody else's business — has no supported path. Hand-editing
`.gitignore` works until `ssd-init` re-runs, `/ssd upgrade` reports drift, or a gate rule fights it,
because **nothing records the intent**.

ADR-0008's "Future Compatibility" section anticipated exactly this: *"The `gitignore_mode` opt-out is
forward-compatible. Future modes (`selective-strict`, `selective-with-archive`, etc.) can be added
without breaking existing projects."*

## Decision

**Add `private` as a third `gitignore_mode` value. Under it, nothing SSD produces is tracked by git,
and the outward workflow leaves no SSD fingerprints — while every rail step and gate rule still runs.**

Privacy is a **storage and visibility** posture, never a reduction in rigor.

### What is gitignored

A new canonical single source, `methodology/private.gitignore` (sibling of `selective.gitignore`):

```gitignore
# ssd:gitignore-mode=private      <-- sentinel; Step 5.5 + migrate.sh detect on it
.ssd/
docs/decisions/
docs/runbooks/
docs/architecture/
```

Six lines against selective's forty-plus, and **no `!` negation anywhere** — notably no
`!.ssd/gate.yml`. Selective mode needs a precise allow-list because it commits a subset; private mode
commits nothing, so there is no allow-list to get wrong.

### What else changes under private mode

| Surface | Behavior |
|---|---|
| `branch_pattern` | defaults to `{slug}` instead of `add-{slug}` |
| `integrations.github.issue_tracking` | **forced off**; `ssd-init` refuses `on`, and `issue-sync.sh preflight` refuses at runtime (`exit 4 state=refused reason=private-mode`) |
| `ssd-init` Step 8 | does not offer the committed `CLAUDE.md` SSD section; the pointer lives in gitignored `.ssd/README.md` |
| Gate inputs | `test_command` / `feature_flag_marker` promoted to real keys in `project.yml`, since no committed `gate.yml` exists |
| Attribution footer | **unchanged — kept.** See "The attribution carve-out" below |

### The attribution carve-out

The `🛠️ Crafted with Shippable States Development` commit/PR footer is **deliberately retained** under
private mode. This is the one intentional non-stealth element.

**Privacy here means no SSD mechanics or documentation in the tree. It does not mean anonymity.**
Anyone reading commit trailers can still tell SSD was used, and that is the intended outcome —
attribution is independent of artifact privacy. A `--no-attribution` knob would be a separate decision
and is explicitly **not** folded into this one.

This carve-out requires no code: the footer is a working convention, not codified in the repo. It is
recorded here so a future reader does not mistake the absence of a footer change for an oversight.

### The gate must not go quiet

Four gate rules are diff-scoped. Under private mode no SSD artifact ever appears in a diff. All four
bodies were read rather than assumed:

| Rule | Under private mode | Action |
|---|---|---|
| `frontmatter-valid` | its `.ssd/` grep yields empty → **existing** no-diff branch walks the tree on disk | **no change**; pinned by a fixture |
| `adr-delta` | `arch_lines ≥ 200` + no `docs/decisions/ADR-` in diff → **`emit FAIL`** | 🔴 **must fix** |
| `feynman-clean` | no `feynman.md` in diff → permanent SKIP | 🟠 worktree glob |
| `issue-sync-current` | tracking forced off → SKIPs | correct as-is |

**`adr-delta` is a hard deadlock, not a degradation.** On any change over 200 architectural lines it
FAILs demanding a committed ADR delta, while `no-leaky-state` — now denying `docs/decisions/` — FAILs if
one is force-added. **Both branches FAIL; the gate becomes unpassable.** 200 lines is an ordinary
feature, so private mode would be unusable on real work.

Resolution: an `artifact_scope()` helper returns `worktree` under private mode and `diff` otherwise.
`adr-delta` then probes for an `ADR-*.md` with mtime newer than the base commit; `feynman-clean` globs
reports on disk. Both are weaker than a diff and their detail strings must say so — but the alternative
is an unpassable gate.

This is non-negotiable because SSD shipped ADR-0015 precisely to stop `/ssd gate` from exiting 0 having
verified almost nothing — *"a green signal that attests to less than the reader believes."* Shipping
private mode with a hollow gate would reproduce SSD's own worst documented failure, deliberately, one
release later.

### Unrecognized mode values become loud

`no-leaky-state` currently emits `SKIP "unknown gitignore_mode: '$mode' (expected selective|blanket)"`.
A typo (`privat`) silently disables SSD's leak-detection rule. Under a mode whose purpose *is* privacy,
a typo that turns protection off without saying so is unacceptable. An unrecognized value becomes a
**loud error**, not a SKIP.

### Migration-manifest mode-awareness

Two existing mechanical entries probe for artifacts private mode must not have —
`committed-gate-yml` (wants `!.ssd/gate.yml` in `.gitignore`) and `strict-selective-gitignore` (wants
the `.ssd/features/**` deep-deny). On a private project both fail forever: `/ssd upgrade` would report
**permanent, unfixable drift**, and `--apply` would re-add the `!.ssd/gate.yml` negation, **actively
breaking privacy**. Both are **N/A under private mode**.

### Where SSD's docs live — and a correction

Private mode ignores the shared `docs/` paths as-is rather than relocating SSD docs under `.ssd/docs/`
or introducing a configurable `ssd.docs_root`.

A technical correction underpins this, because the design brief had it wrong:

> **`.gitignore` has no effect on already-tracked files.** Adding `docs/decisions/` to `.gitignore` does
> *not* untrack a committed ADR — git keeps tracking it and it keeps appearing in diffs.

So "silently untracks pre-existing non-SSD content" **cannot happen from the pattern alone**. It can
only happen via `git rm --cached`, which exists solely in the retrofit path — where its interlock
belongs. On greenfield there is nothing to untrack; on retrofit the pattern is inert against tracked
files.

The `docs_root` indirection was rejected on measurement: **12 non-`.ssd/` files hardcode
`docs/decisions/`**, including `rails.md` invariant 7, `gate-rules.sh`'s `adr-delta`, `parity-test.sh`,
and seven sub-skill `SKILL.md` files. ADR-0008 already rejected this same move for this same reason —
*"Migration cost is high; the path-rename touches every skill. Rejected — keep the paths, change the
gitignore."* That ruling is reaffirmed, not relitigated.

**Revisit when:** a second consumer needs a configurable docs root for a reason unrelated to privacy —
e.g. a monorepo placing ADRs under `packages/*/docs/decisions/`. One privacy use case does not justify a
12-file indirection; two independent use cases would.

### Retrofit

Supported via a `/ssd upgrade` migration entry (`private-mode`, mechanical, `introduced_in: 2.8.0`),
delivered in iteration B with two mandatory safeguards:

1. **Itemized consent.** Before any `git rm --cached`, run
   `git ls-files docs/decisions docs/runbooks docs/architecture .ssd`, print the **full file list**, and
   require explicit confirmation. Never itemize-and-proceed in one step.
2. **History warning.** `git rm --cached` stops *future* tracking; **published history is not
   rewritten.** This must appear in the migration output, in these Consequences, and in the
   `/ssd upgrade` report — not one of the three.

## Rationale

- **The enum already existed.** ADR-0008 created `gitignore_mode` and reserved room for future values.
  A third value is the cheapest correct expression, mutually exclusive by construction. An orthogonal
  `ssd.privacy:` key was rejected: it creates a 3×2 matrix of which roughly two cells are meaningful.
- **A single authoritative key.** Every consumer reads `gitignore_mode`; only `ssd-init` Step 5.5
  detects from `.gitignore`, because `project.yml` does not exist yet at that point — the same ordering
  constraint already documented for selective mode, and the reason the pattern file carries a sentinel.
- **Nothing-committed is simpler than a subset.** Private mode's six lines cannot develop an allow-list
  bug, which is the failure class `strict-selective-gitignore` (v2.6.0) had to repair for selective mode.
- **Defense in depth on the outward mirror.** `project.yml` is hand-editable, so refusing
  `issue_tracking: on` at init is a single point of failure; the script refuses at runtime too.
- **Additive by construction.** Every change sits inside a `mode == "private"` branch. `selective` and
  `blanket` projects are byte-identical to v2.7.0.

## Consequences

**Easier**
- SSD becomes usable on client work, shared team repos, and OSS contributions where a methodology paper
  trail is unwelcome.
- The intent is *recorded*, so `ssd-init` re-runs, `/ssd upgrade`, and the gate rules cooperate with it
  instead of fighting a hand-edited `.gitignore`.
- `no-leaky-state` becomes genuinely load-bearing: under `blanket` it SKIPs because nothing needs
  protecting; under `private` it is the primary enforcement of the privacy promise.

**Harder**
- A third mode to reason about, and a second pattern file to keep in sync with the gate's deny-list.
  **The pattern file and the deny-list are the same set in two syntaxes; a forgotten side is a silent
  privacy leak.** A parity fixture asserts they agree — this is ADR-0008's dual-maintenance warning
  with higher stakes.
- Two gate rules carry a weaker worktree-scoped probe under private mode, and must say so in their
  output.

**What we give up**
- **Gate config portability (ADR-0015's root cause P2 reopened).** No committed `gate.yml` can exist, so
  a private project's gate config does not travel to a second clone or a CI runner. Verified graceful:
  `gate_input()` reads `project.yml` first, then `gate.yml`, so an absent `gate.yml` degrades rather than
  errors — which is why gate inputs are promoted to real `project.yml` keys under this mode. For a
  solo/private practice — this mode's entire audience — P2's blast radius is close to nil, because there
  is no second contributor. **ADR-0015 receives an addendum** recording this rather than leaving a
  future reader to discover the contradiction.
- **`adr-delta` and `feynman-clean` precision.** An mtime probe is touchable in a way a diff is not.
- **Human discoverability.** No committed `CLAUDE.md` pointer tells a collaborator the project uses SSD.
  Self-consistent with the mode's purpose. Note this is *advisory only*: `/ssd`'s actual prerequisite is
  `.ssd/project.yml`, so nothing functional is lost. This design does **not** depend on
  `CLAUDE.local.md`, whose loading behavior was not verified.
- **Not history rewriting, not encryption, not anonymity.** See Non-Goals.

## Non-Goals

- **Not history rewriting.** No `filter-branch`, no `bfg`. The retrofit untracks and warns.
- **Not encryption or at-rest protection.** Private means *untracked*, not *secret*. Artifacts sit in
  plaintext on disk.
- **Not anonymity.** The attribution footer stays; see the carve-out.
- **Not a reduction in rigor.** Every rail step and gate rule still runs.
- **Not a change to `selective` or `blanket`.**

> **This is a visibility posture, not a security guarantee.** A user must not read "private" as "this
> repo has been scrubbed." Already-published history is untouched, and `git rm --cached` cannot undo a
> push. This is the highest-likelihood, highest-impact risk in the design, which is why iteration B
> forces the user to see the exact file list before anything is untracked.

## Alternatives Rejected

- **Orthogonal `ssd.privacy:` key.** Expressive but produces a 3×2 state matrix with ~2 meaningful
  cells. Rejected in favor of a third enum value.
- **Init-flag only, no `project.yml` key.** Nothing durable recorded ⇒ `/ssd upgrade`, `gate-rules.sh`,
  and `ssd-init` re-runs cannot detect the mode. This is precisely the hand-edited-`.gitignore` problem
  the ADR exists to solve. Rejected.
- **Relocate SSD docs to `.ssd/docs/` under private mode.** Cleaner on ownership; changes well-known
  paths that 12 non-`.ssd/` files hardcode, including `rails.md` invariant 7. Rejected.
- **Configurable `ssd.docs_root`.** The general form of the above, same 12-file blast radius. Rejected
  *for now* with a falsifiable revisit trigger above.
- **Extend `blanket` instead of adding a mode.** Would silently change behavior for every existing
  `blanket` project — an opt-out becoming a stealth mode without consent. Rejected.
- **Ship private mode with the four diff-scoped rules degraded, loudly.** Honest, and it would leave
  `adr-delta` deadlocked — an unpassable gate is not a degradation. Rejected.
- **Suppress the attribution footer** (bundled into the original "full stealth" option). User-ratified
  to keep it; see the carve-out. A separate `--no-attribution` decision may revisit it.
- **`schema_version: 3` bump on `current.yml`.** A new `project.yml` value is not a `current.yml` schema
  change — the same reasoning ADR-0008 applied. No bump.

## Scale Note

Private mode adds ~6 lines of pattern, ~4 deny-list entries, one `artifact_scope()` helper, and three
mode branches across `gate-rules.sh`, plus one `ssd-init` case and one migration entry. Measured against
the library at v2.7.0: 10 gate rules, 12 migration entries, 11 skills, 83 parity assertions. Every axis
is small and bounded; the mode enum is deliberately closed at three.
