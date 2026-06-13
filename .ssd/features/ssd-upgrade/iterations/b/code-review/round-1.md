---
skill: code-reviewer
version: 1.6.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: add-ssd-upgrade-b (vs main)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 2
  question: 0
  suggestion: 1
  nit: 1
gate_pass: true
remediation_mode: false
round: 2
closed_from_previous_round: [MINOR-1, MINOR-2]
---

# Code Review — ssd-upgrade iteration B (`/ssd upgrade --apply`), round 1

**Profile: expert** — BLOCKER/MAJOR foregrounded; MINOR/NIT summarized.

## Verdict: **GATE PASS** (blocker=0, major=0)

The `--apply` path is non-destructive (add/insert/rewrite-with-backup, never delete), `.bak`-backed
per mutated file, and re-confirmed via `detect` after each apply. The detect-only path is byte-for-byte
unchanged (existing fixtures 13/14 still pass). Verified by trace + execution: parity 37/37,
`gate-rules.sh --base main` exit 0, and two manual end-to-end runs (drifted `from 1.9.0` → applies 3,
bumps to 1.18.0, idempotent re-run; v1 `from 1.3.0` → `current-yml-v2` DEFER, `current.yml` untouched).

## No BLOCKER / MAJOR findings.

Phase 3.5 (fix-introduces-edge-cases) applied to every mutating branch: backup guards, multi-line
insert, re-detect confirmation, version-bump regex, partial-failure ordering, idempotency. Nothing
rises to gate-blocking.

## MINOR (summarized, expert profile)

- **MINOR-1 — `selective-gitignore`: set the marker key *last*, after the `.gitignore` rewrite.**
  [migrate.sh:151-194](../../../../../methodology/migrate.sh#L151). `apply_selective_gitignore`
  writes `gitignore_mode: selective` into `project.yml` *before* rewriting `.gitignore`, and
  `detect()` confirms on the `project.yml` key alone. If the process dies between the two writes, a
  re-run sees `detect=present` → `SKIP-present` and never finishes the `.gitignore` — leaving a
  project *recorded* as selective but still on a blanket `.gitignore`. Fix: rewrite `.gitignore`
  first, set the marker key last (marker-last is the standard idempotency ordering). Low likelihood
  (requires a crash mid-function); the `.bak` makes it recoverable, so it's MINOR not MAJOR.
- **MINOR-2 — `bump_recorded_version` targets the first indented `version:` in the whole file**, not
  the one scoped to the `ssd:` block. [migrate.sh:208-217](../../../../../methodology/migrate.sh#L208).
  Safe in the SSD-managed schema (verified: this repo's `project.yml` has exactly one indented
  `version:`, under `ssd:`), but a consuming project with a nested `version:` under an earlier block
  would have the wrong line rewritten. Recommend scoping the `sub` to lines after `^ssd:`. Shares the
  "controlled-format" caveat the manifest parser already documents.

## SUGGESTION / NIT

- **SUGGESTION-1** — the selective `.gitignore` pattern is duplicated between `ssd-init/SKILL.md`
  (prose) and `migrate.sh` (heredoc) — a drift surface. The coder already logged this; it is the exact
  thing the deferred `ssd-init`→engine extraction unifies. Track it on issue #17 so the extraction
  closes both at once.
- **NIT** — `.gitignore.bak` is written at the consuming project's repo root and is not itself
  gitignored; it can show up as untracked. Acceptable for a deliberate backup artifact; mention in the
  `/ssd upgrade --apply` output so the user knows to clean it up.

## Scope/design confirmations

- `current-yml-v2 → DEFER` is the right call: re-implementing the v1→v2 split here would duplicate the
  logic the deferred extraction unifies and risk R1. The sentinel (`return 9`) correctly does **not**
  advance the recorded version, so a v1 project stays pinned until it runs `/ssd-init`.
- Guided re-surfacing (R3) is preserved by the contiguous-advance-stops-at-first-outstanding rule —
  verified: recorded version pins at 1.18.0 below the guided 1.20.1, which re-surfaces every run.
- Deferring the `ssd-init` prose-extraction out of this iteration (Hard Rule 4: no refactor mixed with
  feature work) is correct and is documented in the brief + changelog.

## Self-verification

1. Read the actual files cited (migrate.sh in full, parity-test.sh fixtures, ssd/SKILL.md diff). ✓
2. No BLOCKER/MAJOR to trace; MINORs traced to specific line ranges + a real partial-failure/scope path. ✓
3. Citations checked against current line numbers. ✓
4. MINOR-2's "safe in this repo" claim verified against `.ssd/project.yml` (one indented `version:`). ✓
5. No sub-agents. ✓  6. No speculative MAJORs (both MINORs are concrete, not "could be"). ✓
7. Phase 3.5 applied to every defensive/mutating branch. ✓  8. remediation_mode false → Phase 1.5 N/A. ✓

---

## Round-2 (inline) — MINOR closures, same session

The gate passed at round 1 (minors don't block), but both MINORs were cheap, concrete robustness fixes
on a tool that mutates arbitrary projects' files, so they were closed in-session per the reviewer
skill's inline-round-2 allowance (≤3 closures).

- **MINOR-1 closed** — `apply_selective_gitignore` now rewrites `.gitignore` first and sets the
  `gitignore_mode` marker key **last** ([migrate.sh:151-199](../../../../../methodology/migrate.sh#L151)).
  Verified against the code: a crash between the two writes now leaves the project `detect`-able as
  un-migrated, so a re-run completes it.
- **MINOR-2 closed** — `bump_recorded_version` is now scoped to the `ssd:` block
  ([migrate.sh:208-221](../../../../../methodology/migrate.sh#L208)). Regression-tested with a decoy
  `stack.version: "9.9.9"` ahead of `ssd:` → decoy untouched, only `ssd.version` bumped to 1.18.0.

Re-verified after the fixes: `parity-test.sh` **37/37**, `gate-rules.sh --base main` exit 0,
`bash -n migrate.sh` clean. SUGGESTION-1 (pattern duplication) + NIT (`.gitignore.bak`) remain open,
tracked on issue #17 for the `ssd-init` extraction follow-up.
