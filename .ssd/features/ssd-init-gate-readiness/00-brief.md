---
skill: ssd
version: 2.4.0
produced_at: 2026-08-05T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-init-gate-readiness
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-init-gate-readiness

## Ledger
Tracked under [ADR-0015](../../../docs/decisions/ADR-0015-ssd-init-gate-readiness.md), authored
alongside this brief per the [ADR-0011](../../../docs/decisions/ADR-0011-decision-record-doctrine.md)
decision-record doctrine. Source proposal (`ssd-init-gate-readiness.md`) drafted during the SSD
adoption of `cryostat_chip_console` (2026-08-03 → 2026-08-05); lifted into the ADR.

## Problem
A greenfield adoption of SSD ran `/ssd-init`, cleared the blockers it reported, shipped a fix, and ran
`/ssd gate`. **The gate exited 0. Of nine rules, exactly one had verified anything** — `no-leaky-state`.
The other eight SKIPped, and nothing in the output distinguished a *legitimately N/A* rule from one
that *should* have run but couldn't. Running the frontmatter validator by hand immediately found a real
defect the green gate had passed over (`03-coder-status.md` missing eight required schema fields).

This is the exact failure mode SSD exists to prevent — a green signal that attests to less than the
reader believes — occurring in SSD's own tooling. Five root causes, all originating in `ssd-init`:

- **P1** — `ssd-init` never writes the gate's inputs (`test_command`, `feature_flag_marker`), so
  `tests-pass` and `feature-flag-present` SKIP in *every* project SSD has ever initialized.
- **P2** — those inputs live in gitignored `.ssd/project.yml`, so gate config is per-checkout: a second
  contributor silently gets a weaker gate.
- **P3** — the library is assumed to live at the repo root; for a user-level install
  (`~/.claude/skills/`) the printed hook-install command produces a hook that **blocks the first commit**.
- **P4** — no CI-usable validation path: `frontmatter-validate.py` + schemas must travel together, and
  `ssd-init` offers no way to get them to a runner, so artifact validation stays local-only/optional.
- **P5** — Step 9's prerequisite checks never test the gate itself: `ssd-init` writes the gate's config
  and then never verifies its own output can run.

## Goal
`ssd-init` must leave the gate **functional, not merely present**. After init, a project's gate should
verify something on day one, that configuration should travel to every clone and CI runner, the printed
hook command should work in the environment it was printed for, and any rule that *cannot run* must be
as loud as a rule that *fails* — the "cannot run" vs. "did not apply" distinction the current output
collapses.

## Scope — six decisions (from ADR-0015)
1. **Step 6 detects & writes `test_command`** (fixes P1) — Makefile `test:` / `npm test` / `pytest` /
   `go test` / `cargo test` / xcode·swift, most-specific-first, prompt on ambiguity, commented
   placeholder + MAJOR log entry when undetected. `feature_flag_marker` written when a known flag lib
   is present; else tied to the existing flag-system BLOCKER.
2. **Committed `.ssd/gate.yml`** (fixes P2) — new committed file holding only portable gate inputs;
   `!.ssd/gate.yml` added to `selective.gitignore`; companion `gate-rules.sh` `yaml_get` fallback chain
   (`project.yml` → `gate.yml`, local override wins).
3. **Record `ssd.library_root` + `library_version`** (P3, ssd-init half) — resolve `$SSD_LIB` →
   repo-root `methodology/` → running-skill dir → prompt; Step 5.5 prints the resolved absolute path or
   emits a wrapper hook when the library is not at the repo root. **Companion change** to
   `pre-commit-no-leaky-state.sh` (P3 cannot be fixed in `ssd-init` alone).
4. **Step 9 Gate Readiness check that runs the gate** (fixes P5) — execute `gate-rules.sh` at init and
   classify each rule into three buckets: PASS / SKIP-not-applicable (INFO) / **SKIP-misconfigured
   (MAJOR)**. Step 11's recommendation becomes conditional: while any bucket-three rule remains, the
   recommended next step is *fix the gate*, not `/ssd start` / `/ssd feature`. `gate-rules.sh` prints
   the bucket-three count in its summary.
5. **Emit the workflow rules the tooling can't enforce** (P4, partial) — write to `CLAUDE.md`/runbook:
   "gate a committed branch, not a staged tree" (under `--staged`, `feature-flag-present` and
   `adr-delta` cannot function), and which rules this project structurally cannot run.
6. **Offer to vendor the validator for CI** (fixes P4) — opt-in copy of `frontmatter-validate.py` +
   `schemas/` into `tools/ssd/` with a provenance header + drift check, offered only when the library
   is unreachable from CI.

## Out of scope (deliberately)
- Real `--staged` support for `feature-flag-present` / `adr-delta` in `gate-rules.sh` (the P4 "related
  but out of scope" note). Decision 5 documents the limitation; fixing it is a separate `gate-rules.sh`
  change. Retire Decision 5's first workflow rule via `obsoleted_in` when that lands.
- Turning any SKIP into a FAIL (rejected alternative — punishes incremental adoption; the reporting fix
  gets visibility without the false red).
- Teaching `ssd-init` to vendor the whole library (rejected — multiplies drift; resolve+record plus one
  opt-in stdlib script gets the same coverage).

## Iteration plan (shippable slices)
- **Iter A — Gate inputs travel.** Decisions 1 + 2 + companion `gate-rules.sh` fallback + migrations
  `gate-inputs-present`, `committed-gate-yml`. Delivers "the gate verifies something on day one."
- **Iter B — Library location & hook.** Decision 3 + companion `pre-commit-no-leaky-state.sh` change +
  migration `library-root-recorded`. Regression-fixes the blocked first commit (P3).
- **Iter C — Gate readiness reporting.** Decision 4 + Step 11 conditional + `gate-rules.sh`
  bucket-three summary + migration `gate-readiness-reported`.
- **Iter D — Docs & CI vendoring.** Decisions 5 + 6 + migration `ci-artifact-validation`.

Each iteration is independently shippable and leaves `ssd-init` more honest than before. Decomposition
proposed for user ratification before build begins.

## Success criteria (from ADR-0015 § Acceptance)
1. Fresh `ssd-init` on a project with a detectable test command → `tests-pass` PASSes on the next gate.
2. Fresh `ssd-init` where the library is not at the repo root → the printed hook command, run verbatim,
   produces a hook that exits 0 on a clean commit. *(Regression test for the blocked first commit.)*
3. Cloning an initialized project and gating it yields the same rule set as the original checkout.
4. The init log lists every rule in one of the three buckets; any bucket-three rule appears at MAJOR
   with a named remedy.
5. Step 11 recommends fixing the gate — not `/ssd start` / `/ssd feature` — while any bucket-three rule
   remains.
6. Re-running `ssd-init` on a project already satisfying 1–5 changes no file (idempotency).
7. `/ssd upgrade` on a pre-change project detects and applies `gate-inputs-present`,
   `committed-gate-yml`, and `library-root-recorded` idempotently.
