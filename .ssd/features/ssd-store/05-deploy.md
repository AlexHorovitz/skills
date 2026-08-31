---
skill: ssd
version: 2.10.1
produced_at: 2026-08-31T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-store (v2.10.0 + v2.10.1)
consumed_by: []
---

# Deploy Log — ssd-store (the private artifact store, ADR-0018)

## Status

**Both versions are merged, tagged, and installed.** The release is closed.

`chapters/phases.md` § `/ssd ship` states the orchestrator does **not** auto-tag, because tagging
pushes to the remote and outward-facing actions stay under explicit human control. Both tags were
created on explicit instruction, on the merge commit, by hand — the process held.

| | v2.10.0 | v2.10.1 |
|---|---|---|
| Branch | `add-ssd-store` | `fix-store-key-collision` |
| Commit | squash `c445d08` | `8ef1821` |
| PR | [#43](https://github.com/AlexHorovitz/skills/pull/43) — **merged** | [#44](https://github.com/AlexHorovitz/skills/pull/44) — **merged** `f8cb746`, 2026-08-31T19:44Z |
| Tag | `v2.10.0` ✓ | `v2.10.1` ✓ → `f8cb746`, annotated + GPG-signed, pushed |
| Review | **none at merge time** (see deviations) | round 1 post-hoc `gate_pass: false`, round 2 `gate_pass: true` |

This log is written once for both, because v2.10.1 is not a separate feature — it is the fix for the
one MAJOR that v2.10.0's missing review would have caught.

## Gate at ship

Run on `fix-store-key-collision` **after committing**, `--base main`:

```
PASS wip-commits                 no WIP/checkpoint commits between main and HEAD
PASS tests-pass                  `bash scripts/parity-test.sh` exit 0 (264/264)
SKIP feature-flag-present        no feature_flag_marker in .ssd/project.yml or .ssd/gate.yml
SKIP adr-delta                   architectural diff 73 lines below threshold 200
PASS frontmatter-valid           2 artifact(s) validated against schemas
PASS no-leaky-state              no gitignored-by-policy files in diff
SKIP store-link-sane             no store link (.ssd is a project-local directory)
PASS skill-version-sync          9 skill example(s) match banner; 2 exempt
PASS migration-manifest-current  manifest valid (13 entries; ≤ VERSION 2.10.1)
SKIP feynman-clean               no feynman report in scope (vs main)
SKIP issue-sync-current          no active workstream has an issue binding
GATE 6 pass · 5 skip · 0 fail    EXIT=0
```

Committed **before** running the gate. On an uncommitted branch `git diff main...HEAD` is empty, the
diff-scoped rules SKIP, and the result reads as a false green — the lesson from ADR-0017 iteration A,
applied rather than re-learned.

### On the five skips — and the one that undercuts this release's own claim

- **`feature-flag-present`** — N/A by design. `project.yml` deliberately omits `feature_flag_marker`
  (a markdown library; the key would false-positive every doc edit). The store's flag is the absence
  of the `store_*` keys: unconfigured ⇒ inert.
- **`adr-delta`** — N/A. The v2.10.1 diff carries an ADR-0018 addendum and is below the 200-line
  architectural threshold, so the rule correctly declines to demand more.
- **`store-link-sane`** — **this is the important one.** The rule this release exists to fix **SKIPs in
  this repo**, because this repo does not use the store (`.ssd` is a real directory here). So the live
  gate **cannot confirm the fix**. The confirmation comes from the fixture, not from this gate line,
  and the SKIP must not be read as evidence.
- **`feynman-clean`** — N/A. **A SKIP means "no failing audit in this change set", not "the project's
  beliefs are calibrated."** No `/feynman` ran this cycle, and not running it is not a violation.
- **`issue-sync-current`** — SKIP for the *correct* reason this time (zero active workstreams, so no
  binding to check), not the `parse_active_workstreams` fragmentation that made it lie at v2.9.0's
  ship. But see deviation 4: because `ssd-store` never had an issue binding at all, the gate is
  structurally unable to notice the mirror gap. A rule that cannot see a gap is not a rule that
  cleared it.

## Verification

| | Result |
|---|---|
| Parity | **264/264**, exit 0 (258 → 264, **+6** for `store-keys-dont-collide`) |
| Typecheck | `bash -n` on `store.sh`, `gate-rules.sh`, `parity-test.sh` — exit 0 |
| Lint | `shellcheck` **exit 127 — not installed.** Pre-existing environment gap, recorded identically since v2.8.0 |
| Red-first | All 4 new assertions were **red against shipped v2.10.0 code** |
| Reversion | Renaming back to bare `root`/`dir` re-fails the fixture |

**The fixture is behavioural, not a grep.** `store-keys-dont-collide` builds a real git repo, creates a
real `.ssd` symlink into a real store directory, writes a `project.yml` that carries `project.root`
exactly as `ssd-init` emits it, and runs the actual gate rule against it. Three of its four assertions
would pass on a "fix" that simply deleted the dead check; the fourth — **"genuine drift IS caught"** —
is the one that would not, and it is the assertion that proved the `DRIFT` check had been *unreachable*
rather than merely mis-keyed.

## Rail deviations

| Step | Reason |
|---|---|
| `systems-designer` (design) | Markdown/bash library — no production runtime, observability, or migration surface. `phases.md` § `/ssd design` sanctions skipping the bundled design pass for a skills library. |
| `systems-designer` (ship checklist) | Same. The library ships by tagging a version and pushing (`distribution.channel: direct-install`); no platform deploy checklist applies. |
| Rollout-advance / flag-removal (rail steps 7–8) | The `store_*` config keys are permanent configuration surface, not a transitional flag. They are never removed. |
| **Code review (rail step 4) — v2.10.0 shipped without one** | **A real violation, not a judgment call.** PR #43 merged with no `04-code-review` artifact; rails invariant 4 was never satisfied for the release. Second occurrence in this epic (#41 was the first). A later `/ssd gate` found it, the post-hoc review found a MAJOR on its first pass, and v2.10.1 is that fix. The deviation is recorded here rather than quietly closed by the existence of the review that now sits beside it. |
| **ADR-0014 mirror (issue sync) — never ran for this workstream** | `issue_tracking: on`, yet `ssd-store` archived with `epic: null, issue: null`. ADR-0018 is the only ADR in this series with no epic issue, so the GitHub record has a hole where the store feature should be. Left as the user's call: creating and immediately closing two issues is outward-facing and its value is a complete public record, not process hygiene. |

## Record accuracy

`03-coder-status.md` names its feature flag as *"`project.yml.ssd.store` block (absent ⇒ inert)"* — the
**nested** form, which is what v2.10.0 actually shipped and what v2.10.1 renamed away. That artifact is
a point-in-time record and has been left alone on purpose; correcting it would falsify what was built.
The current config surface is `store_root` / `store_dir` / `store_auto_commit`, documented in
`ssd-init/SKILL.md`, `chapters/phases.md`, `chapters/artifacts.md`, README, and the ADR-0018 addendum.

## Outstanding — recorded, deliberately not fixed (hard rule 4)

1. ~~**Installed-clone drift (hard rule 6, production parity).**~~ **Closed at ship.**
   `~/.claude/skills` is a git clone that sat on `main` at `e039961` — two commits behind
   (`c445d08` #43 and `8ef1821`), so `methodology/store.sh` **did not exist in the user's actual
   tooling** while the store was being called shipped. It *did* carry the
   `parse_active_workstreams` and epic-close-guard fixes (both at or before `e039961`), so the drift
   was narrower than first reported — a correction made in the ship report rather than left standing.
   Fast-forwarded to `f8cb746` and verified as *working*, not merely present: **264/264** from the
   installed tree and `bash methodology/store.sh status` returning `linked=no mode=selective` exit 0.

   **The lasting finding is that no rule caught this.** The gate reads the repo and never the
   install, so for a `distribution.channel: direct-install` library SSD leaves its own distribution
   channel unverified — the one place hard rule 6 is actually about. An `install-parity` rule
   (compare `~/.claude/skills` HEAD against `origin/main`) is the obvious candidate and is **not
   built**; it needs its own PR under hard rule 4.
2. **QUESTION-2** — `committed-gate-yml` / `strict-selective-gitignore` report `ERROR` for an absent
   precondition, reachable only when a ≥2.4.0 project has no `.gitignore` at all. In `migrate.sh`.
3. **QUESTION-1 (gate review)** — an inconsistent list indent inside one `active:` block would
   silently skip later workstreams. The rewritten parser fixed fragmentation, not this.
4. **Store features not built**, and stated as such rather than implied: worktree fan-out, an `unlink`
   verb (moving *out* of the store), and a `migrations.yml` entry for the store.

## Post-merge — done

| Step | Result |
|---|---|
| Merge #44 | `f8cb746` on `main`, squash, 2026-08-31T19:44Z |
| Tag | `git tag -a v2.10.1 f8cb746 -F -` → tag object `9b663e3`, signed; pushed to `origin` |
| Install (hard rule 6) | `git -C ~/.claude/skills pull --ff-only`: `e039961` → `f8cb746`, VERSION `2.9.0` → `2.10.1` |
| Install verified | installed tree runs **264/264**; `store.sh status` exit 0 |
| Release chain | all twelve `v2.*` tags resolve to real commits — no gaps remain from the earlier backfill |

Use `-F` for the tag message, not `-m`: backticks inside a double-quoted `-m` string are
command-substituted by the shell, which mangled the `v2.10.0` annotation.

## Still open, and each needs its own PR

Nothing blocks the release. Carried forward: the **ADR-0014 mirror gap** (deviation 6 — ADR-0018 has
no epic issue; the maintainer's call, commands above), **QUESTION-2**, **QUESTION-1**, the four
unbuilt store features, and the new **`install-parity` gate rule** from outstanding item 1.
