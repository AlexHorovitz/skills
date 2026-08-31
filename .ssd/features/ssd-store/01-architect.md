---
skill: architect
version: 1.3.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-store
consumed_by: [coder, systems-designer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0018]
  risk_assessment: true
  feature_flag: "project.yml.ssd.store block (absent ⇒ feature inert)"
  scale_baseline: true
quality_gate_pass: true
---

# Architect Spec — ssd-store

Platform: **headless**. A new bash helper plus one gate rule and two pattern-file edits, consumed by
the Claude Code CLI. Contract-first and idempotency carry the weight.

---

## 1. Current Scale Baseline

Measured on `main` at v2.9.0 (post-#42).

| Dimension | Now (1x) | 10x | Note |
|---|---|---|---|
| `methodology/*.sh` helpers | 3 (`gate-rules`, `migrate`, `issue-sync`) | ~6 | Adds **1** (`store.sh`) |
| Gate rules | 10 | ~15 | Adds **1** (`store-link-sane`) |
| Canonical pattern files | 2 (`selective`, `private`) | 2–3 | Edits **both** |
| `no-leaky-state` deny-lists | 2 (selective baseline, private baseline) | 2 | Edits **both** |
| Tools that resolve the project root | 3, all via `git rev-parse` from cwd | 3 | **Edits 0** — see §2 |
| Destructive operations in the library | 1 (`git rm --cached`, v2.9.0) | — | Adds **1** (`link` moves a directory) |
| Parity assertions | 205 | ~230 | Adds ~15 |

The last two rows set the design. One new destructive operation means `link` inherits iteration B's
discipline; **zero** changes to root resolution is the finding that makes the whole mechanism cheap.

---

## 2. Component Diagram

```
  PROJECT (gitignore_mode: private)              PRIVATE STORE (one git repo)
  /Users/…/Development/foo/                      /Users/…/Development/private-ssd/
  ├── .gitignore   ← bare `.ssd` line            ├── .git/            ← the history
  │                  (H1: `.ssd/` cannot         ├── .gitignore       ← MINIMAL (H3)
  │                   match a symlink)           ├── README.md
  ├── app.py                                     ├── foo/   ←──────────┐  project foo's tree
  └── .ssd ──────────────────────────────────────┘  ├── project.yml   │
        symlink, ABSOLUTE, never committed          ├── current.yml    │  everything committed
                                                    └── features/      │
                                                    └── bar/ …         │
                                                                       │
  ┌──────────────────────────────────────────────────────────────┐     │
  │ EVERY existing consumer is UNCHANGED:                        │     │
  │   PROJECT_ROOT="$(git rev-parse --show-toplevel)"  ← from cwd │     │
  │   then reads "$PROJECT_ROOT/.ssd/…"  ────────────────────────┼─────┘
  │ The symlink is followed transparently. VERIFIED: no tool     │
  │ anywhere cd's into .ssd/, so none can resolve the STORE's    │
  │ git root by mistake (H2 closed by inspection, not assumed).  │
  └──────────────────────────────────────────────────────────────┘

  methodology/store.sh   — the ONLY writer of the symlink (init · link · status · commit · push)
  gate rule store-link-sane — the guard: ignored? not tracked? target exists?
```

**The invariant:** the **symlink is the single source of truth** for where the store is. `project.yml`
records it too, but `project.yml` *lives inside the store*, so it can never be the authority — reading
it already required following the link. That inversion is why `store.sh status` uses `readlink`, and
why a `project.yml` that disagrees with the link is drift to report, not a value to trust.

---

## 3. Data Model

### 3.1 `project.yml.ssd.store` (new block, descriptive)

```yaml
ssd:
  artifact_root: .ssd/          # unchanged — the path every skill uses
  store:                        # NEW; absent ⇒ feature inert
    root: /Users/ahorovit/Development/private-ssd   # the private git repo
    dir: skills                                     # subdirectory within it
    auto_commit: true                               # commit on phase advance (LOCAL only)
```

| Field | Required | Default | Meaning |
|---|---|---|---|
| `root` | yes (if block present) | — | absolute path to the private repo |
| `dir` | no | project's repo basename | subdirectory inside `root` |
| `auto_commit` | no | `false` | commit the store on every phase advance. **Never pushes.** |

Recorded for **drift detection**, not resolution: `store-link-sane` compares it against `readlink`.

### 3.2 Store repo layout

```
<root>/                  ← git init here; ONE repo for all projects (user-ratified)
├── .git/
├── .gitignore           ← MINIMAL — see below
├── README.md            ← says what this repo is and that it is private
└── <dir>/               ← one per project; the project's .ssd content verbatim
```

**The store's `.gitignore` must be minimal, and this is not cosmetic (H3).** `selective.gitignore`
deliberately excludes exactly the files the store exists to preserve — `current.yml`, `project.yml`,
`archive/`, `audits/`, `*.bak`, snapshot machinery. Copying SSD's project-side ignores into the store
would silently drop the machine state whose *history* is the whole point. The store ignores only
noise:

```gitignore
.DS_Store
*.tmp
```

Note `*.bak` is **not** ignored: `migrate.sh` writes `.bak` files before mutating, and in the store
their history is evidence rather than clutter.

### 3.3 The symlink

`<project>/.ssd` → **absolute** `<root>/<dir>`. Absolute because a relative target breaks git worktrees
at other depths (ADR-0007), and it is safe precisely because §5's three layers prevent it ever being
committed.

---

## 4. Interface Contract — `methodology/store.sh`

Exit codes match the library's existing vocabulary (`issue-sync.sh`, `migrate.sh`): **0** ok · **2**
usage/validation · **3** failure · **10** needs-confirm.

| Verb | Behavior |
|---|---|
| `status` | Reports link presence, `readlink` target, whether the target exists, whether it is inside a git repo, uncommitted-change count, and any `project.yml` drift. Read-only; always exit 0 unless unreadable. |
| `init <root>` | Create `<root>` if absent; `git init` if it is not already a repo; write `README.md` + the minimal `.gitignore` if absent. **Idempotent** — never touches an existing repo's config. |
| `link <root> [--dir <name>] [--confirm]` | **DRY-RUN BY DEFAULT.** Enumerates what would move and exits 10. With `--confirm`: moves an existing `.ssd/` into `<root>/<dir>/`, then creates the symlink. |
| `commit [-m <msg>] [--auto]` | Commits the project's store subdir. **Local only — never pushes.** `--auto` is the phase-advance path: silent when there is nothing to commit. |
| `push` | Explicit, outward. Never called by `commit` or by any phase. |

### 4.1 `link` safety (H7 — the second destructive operation in the library)

Ordered, and each step is mandatory:

1. **Refuse to clobber.** If the destination exists and is non-empty *and* a real `.ssd/` also exists,
   abort (exit 2). Merging two artifact trees is not something a migration should guess at.
2. **Enumerate and print** every path that would move. Complete list, never truncated — the same rule
   as ADR-0017's interlock.
3. **Dry-run unless `--confirm`** (exit 10).
4. **Move, never copy-then-delete.** `mv` is atomic within a filesystem; a copy+`rm` has a window where
   a crash loses data. If `mv` fails (cross-device), fall back to copy **and leave the original in
   place** — never delete on the fallback path.
5. **Create the symlink only after the move succeeds**, and verify by reading a known file through it.
6. **Add the bare `.ssd` line to `.gitignore`** if absent, before reporting success.

### 4.2 Auto-commit contract

Called by the orchestrator at each phase advance when `store.auto_commit` is true:

```
store.sh commit --auto -m "<phase>: <slug>[#<iter>]"
```

- **Local only.** No network. The distinction is deliberate: committing is bookkeeping, pushing is an
  outward action that stays under explicit control.
- **Silent no-op** when the store has no changes, so a phase that wrote nothing produces no commit.
- **Never fails a phase.** A store-commit failure warns and continues, exactly as `issue-sync.sh`
  preflight does — the local `.ssd/` write already succeeded and is the authoritative state.

### 4.3 Integration Contract — `not_applicable`

No queues, events, or cross-process calls. Idempotency (the one transferable Principle-6 concern) is
specified per-verb above.

---

## 5. The safety story (H1) — three layers, because two were blind

Verified empirically before designing (§brief H1). A symlinked `.ssd` defeated **both** existing
protections:

| Layer | Before | Fix |
|---|---|---|
| `.gitignore` pattern | `.ssd/` matches **directories only**; a symlink is a file to git → **not ignored** | add a **bare `.ssd`** line to `selective.gitignore` *and* `private.gitignore` |
| `no-leaky-state` deny-list | `matches_deny_pattern ".ssd" ".ssd/"` → **no match** | add an **exact `.ssd`** entry to *both* baselines |
| gate rule | none existed | **new `store-link-sane`** |

> **Correction (coder phase).** This section originally said both pattern files change. Testing showed
> otherwise, twice over. A bare `.ssd` in `selective.gitignore` **destroys selective mode** — a bare
> pattern excludes the directory, and gitignore cannot re-include a file under an excluded parent, so
> every `!.ssd/features/**/…` negation goes inert and the project commits nothing under `.ssd/`
> (verified: `git add -A` staged only `.gitignore`, while all 205 assertions still passed). And it is
> moot anyway: `git add` through a symlink fails outright — *"pathspec … is beyond a symbolic link"* —
> so **the store is incompatible with selective mode by construction**. The bare line ships only in
> `private.gitignore`; `store.sh link` refuses on `selective`; `store-link-sane` FAILs on it. The
> deny-list entry is safe in both baselines because it only adds a deny.

### `store-link-sane`

| Condition | Verdict |
|---|---|
| `.ssd` is not a symlink | **SKIP** — "no store link (project-local .ssd)". The common case. |
| symlink is **tracked** by git | **FAIL** — the leak has already happened; names the target |
| symlink is **not gitignored** | **FAIL** — it is one `git add -A` from leaking |
| target does not exist | **FAIL** — dangling link; SSD is writing into nothing |
| `project.yml.ssd.store` disagrees with `readlink` | **FAIL** — recorded intent and reality differ |
| otherwise | **PASS** — reports the target and whether the store is a git repo |

FAIL rather than SKIP on every failure mode, because each one is a *silent* leak or data-loss path.
This is the rule that makes the mechanism safe rather than merely documented.

---

## 6. Decision Log

- **[ADR-0018](../../../docs/decisions/ADR-0018-ssd-artifact-store.md)** (new) — the store, the
  symlink-is-authoritative inversion, the three-layer leak defence, one-repo layout, auto-commit-local
  /push-explicit split, and the non-goals.
- **ADR-0017 relationship:** complementary, not superseding. ADR-0017 governs *visibility* (what the
  project tracks); this governs *durability* (where the tree lives). Private mode is the expected
  companion but **not** a prerequisite — a `selective` project may use a store, which is why both
  pattern files change.
- **ADR-0007 relationship (H5):** worktrees. Each linked worktree needs its own `.ssd` symlink to the
  same store, which makes state genuinely shared and is arguably *better* than ADR-0007's
  "authoritative `.ssd` at the main checkout". Creating those links is **not** automatic in this
  iteration; documented, not built.
- **Always-ADR topics:** six have no referent (no database, auth, sync/async boundary, service split,
  deployment target, or schema migration). Third-party vs build: no new dependency (`git`, `bash`,
  `readlink`). Licensing: unchanged.

---

## 7. Risk Assessment

**Top 3 first.**

| # | Risk | L | I | Mitigation |
|---|---|---|---|---|
| **1** | **The store path leaks into the project repo** — committing an absolute symlink publishes the user's home path and the private store's location, in the repo they are keeping private. Verified reachable with the *current* pattern files. | **H** without the fix | **H** | §5's three layers. Two of them are fixes to existing blind spots, not new features. |
| **2** | **`link` loses artifacts.** It moves a directory — the second destructive operation in the library. | M | **H** | §4.1: refuse-to-clobber, full enumeration, dry-run default, `mv` not copy+rm, **never delete on the cross-device fallback**, verify-through-link before reporting success. |
| **3** | **Dangling store.** The target is deleted or the volume is unmounted; SSD writes into a broken path or silently into a new directory. | M | **H** | `store-link-sane` FAILs on a missing target. `commit --auto` warns and never fails a phase. |
| 4 | Store repo inherits SSD's selective ignores and drops the very files it exists to keep (H3) | M | **H** | §3.2 minimal `.gitignore`; `*.bak` deliberately kept |
| 5 | `project.yml.store` and the actual link diverge | M | M | `store-link-sane` compares them and FAILs |
| 6 | Auto-commit pushes something outward unasked | L | **H** | §4.2: `commit` has no network path at all; `push` is a separate verb |
| 7 | Worktrees lack their own link (H5) | M | L | Documented; each worktree links to the same store |
| 8 | A tool resolves the *store's* git root instead of the project's (H2) | **L** | H | **Closed by inspection:** no tool `cd`s into `.ssd/`; all three resolve `PROJECT_ROOT` from the invocation cwd. Zero code changes needed. |

**CI/CD:** unchanged — the library ships by tagging and pushing; `parity-test.sh` gates it.

---

## 8. Feature Flag Plan

| | |
|---|---|
| **Flag** | presence of `project.yml.ssd.store` **and** a symlinked `.ssd` |
| **Default** | absent ⇒ **inert**. A project with a real `.ssd/` directory behaves byte-identically to v2.9.0. |
| **Kill switch** | `store.sh` has no unlink verb by design — reversing is `mv` the store content back and delete the symlink, which the docs state. Automating an unlink would be a second destructive operation for no gain. |

**Rollout:** (1) merged, exercised by fixtures only; (2) dogfood on a throwaway project *and* on a real
one; (3) documented in README. **Flag removal: never** — permanent configuration surface.

---

## 9. Test Plan

| # | Fixture | Asserts |
|---|---|---|
| 1 | `store-symlink-is-ignored` | with the fixed pattern files, `git check-ignore .ssd` succeeds — **red before the bare-`.ssd` fix** |
| 2 | `store-symlink-not-committed` | `git add -A` leaves `.ssd` out of the index |
| 3 | `deny-list-catches-symlink` | `matches_deny_pattern ".ssd" …` matches in **both** baselines |
| 4 | `store-link-sane-skips-plain` | real `.ssd/` directory → SKIP, not FAIL |
| 5 | `store-link-sane-fails-tracked` | force-added symlink → FAIL |
| 6 | `store-link-sane-fails-unignored` | symlink with no ignore rule → FAIL |
| 7 | `store-link-sane-fails-dangling` | target removed → FAIL |
| 8 | `store-link-sane-passes` | ignored + untracked + target present → PASS |
| 9 | `store-init-idempotent` | second `init` does not reinitialise or overwrite |
| 10 | `store-link-dry-run` | no `--confirm` → exit 10, **nothing moved**, no symlink created |
| 11 | `store-link-confirm` | content moved, symlink created, readable through it, `.gitignore` updated |
| 12 | `store-link-refuses-clobber` | non-empty destination + real `.ssd/` → exit 2, nothing moved |
| 13 | `store-commit-local-only` | `commit` produces a commit and performs **no** network call |
| 14 | `store-commit-auto-noop` | `--auto` with no changes → exit 0, no commit created |
| 15 | `store-gitignore-minimal` | the store's `.gitignore` contains none of `selective.gitignore`'s SSD patterns |

**Fixture 1 is the acceptance test.** If a symlinked `.ssd` is not ignored, the feature leaks by
default and should not ship. **Fixture 15** guards H3 — the store silently dropping the machine state
whose history is the entire point.

**Regression floor:** all 205 existing assertions pass.

---

## 10. Self-Verification

1. **Every gate section real?** Yes; `integration_contract: not_applicable` with the reason stated.
2. **Adapted, not copy-pasted?** Yes — data model is config + on-disk layout because there is no
   database; API contract is verbs and exit codes because there is no network.
3. **Read the sources?** Yes, and it decided three things: H1 (tested the gitignore and deny-list
   behavior rather than assuming), H2 (grepped for `cd .*\.ssd` and found none — so zero consumer
   changes), H3 (listed exactly what `selective.gitignore` excludes to see what the store must not).
4. **ADR exists?** ADR-0018 is the deliverable.
5. **Baseline has real numbers?** Yes — §1, measured at v2.9.0.

**Handoff for `coder`:** write fixtures **1, 3 and 10** first and watch them fail. Fixture 1 fails
against today's pattern files, 3 against today's deny-lists, and 10 only if `link` is built dry-run
first. Everything else in this spec is downstream of those three being right. This workstream has
produced three fixtures that passed because they fabricated input the system never generates — build
these against the *real* pattern files and the *real* `matches_deny_pattern`.
