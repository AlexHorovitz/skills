---
skill: ssd
version: 2.8.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-private-mode iteration b
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-private-mode iteration B (retrofit)

Iteration A shipped as **v2.8.0** ([ADR-0017](../../../../docs/decisions/ADR-0017-private-mode.md),
PR [#36](https://github.com/AlexHorovitz/skills/pull/36), squash `7a2c389`, tag `v2.8.0`). Greenfield
private mode works end to end: `ssd-init --private` produces a project where a full `/ssd feature`
cycle leaves `git status` clean while `/ssd gate` still verifies six rules.

Iteration A deliberately shipped **no retrofit path**. It never runs `git rm --cached`, so the one
genuinely destructive operation in the whole feature was quarantined behind its own review cycle.
This is that cycle.

## Goal

An existing project can move **into** private mode — deliberately, with full sight of what will be
untracked, and without any possibility of it happening to a project that did not ask.

## The correction that reshapes this iteration

Iteration A recorded a user-ratified decision: *"Retrofit is supported via a `/ssd upgrade` migration
entry."* Implementing that literally is **actively harmful**, and the reason is worth stating
precisely because it inverts the manifest's whole premise.

`methodology/migrations.yml` exists to answer *"what conventions has this project drifted past?"* Every
entry is drift to be closed. Both existing kinds are wrong here:

| Kind | What it would do to private mode |
|---|---|
| `mechanical` | `/ssd upgrade --apply` on **any** project would `git rm --cached` its committed ADRs, briefs, and reviews. A team repo would be swept into privacy because someone ran a routine upgrade. |
| `guided` | Re-surfaces on every run until adopted (R3), so every project is nagged *"adopt private mode"* forever — and `--adopt` would record adoption of a practice the project is not following. |

There is a second-order harm the `mechanical` route also carries: version advancement **stops at the
first outstanding entry**, so every non-private project would have its recorded version frozen below
the private-mode entry and report permanent, unclosable drift.

**Private mode is a choice, not a convention.** The manifest has no vocabulary for that.

**User-ratified resolution (2026-08-28): a third kind, `elective`.** Excluded from the default sweep,
never reported as `PENDING`, never participates in version advancement, and applied **only** when
named explicitly. The `/ssd upgrade` entry point that decision 4 asked for is preserved; what changes
is that the default sweep can never reach it.

## Scope

1. **`kind: elective` in the manifest engine.** `read_manifest` already emits `kind` as a column and
   `migration-manifest-current` does **not** validate the kind vocabulary (verified — it checks id
   uniqueness, ascending `introduced_in`, and `introduced_in <= VERSION` only), so no parser or gate
   change is forced. What is needed: a branch in `migrate.sh`'s report loop that **skips an elective
   entry entirely** unless it was explicitly named — the skip must happen *before* the
   `satisfied`/`advancing` bookkeeping, or the entry will silently pin the recorded version.

2. **The `private-mode` entry.** `introduced_in: 2.9.0`, `kind: elective`, `adr: ADR-0017`.

3. **Explicit invocation.** `migrate.sh` currently has `--apply` (no argument) and `--adopt <id>`;
   there is no way to apply one named migration. Needs new CLI surface — `--elect <id>` mirrors the
   existing `--adopt <id>` shape and is the architect's call. The user-facing form stays
   `/ssd upgrade --apply private-mode`.

4. **`detect_private_mode()` / `apply_private_mode()`.** Detect on the
   `# ssd:gitignore-mode=private` sentinel and/or `project.yml.ssd.gitignore_mode: private`. Apply:
   write `methodology/private.gitignore` verbatim, set the mode, set `branch_pattern: "{slug}"`, force
   `issue_tracking: off`, promote gate inputs into `project.yml`. All four ordering rules from
   `apply_selective_gitignore` carry over (bail-before-mutating, pattern-first-marker-last,
   comment-on-its-own-line, sentinel-guarded append).

5. **The itemized-consent interlock** — the heart of this iteration. Before **any**
   `git rm --cached`:
   `git ls-files docs/decisions docs/runbooks docs/architecture .ssd` → print the **complete** file
   list → require explicit confirmation. Never itemize-and-proceed in one step. A file the user did
   not see named must never be untracked.

6. **The history warning**, in all three places: the migration output, ADR-0017's Consequences, and
   the `/ssd upgrade` report. `git rm --cached` stops *future* tracking; **published history is not
   rewritten.** Not one of the three — all three.

7. **`branch_pattern` plumbing** + `ssd/chapters/workstreams.md`. Iteration A set the default in the
   `ssd-init` template but never documented how the workstream commands consume it under private mode.

8. **Docs + records.** `chapters/upgrade.md` (the `elective` kind and the new invocation),
   **ADR-0013 addendum** (it defined the manifest as `mechanical | guided`; a third kind is a
   contract change and belongs recorded there), ADR-0017 amendment (the elective decision + the
   history limitation), README.

9. **Parity fixtures** + `VERSION` → 2.9.0 + skill banners.

## Hazards

**H1 — the interlock is the only thing standing between a user and data loss.** `git rm --cached` on
`docs/decisions/` in a team repo removes shared design records from tracking. It is recoverable
(the files stay on disk, and `git checkout` restores tracking) but it will look like destruction in a
diff and may be pushed before anyone notices. This needs the most adversarial review in the workstream.

**H2 — an elective entry must be inert in every default path.** Not just `--apply`: the plain
`/ssd upgrade` report, the JSON output, version advancement, and the init-log append. A single path
that treats it as ordinary drift reintroduces the whole problem. Enumerate them; do not sample.

**H3 — `docs/` may hold non-SSD content.** Iteration A established that `.gitignore` alone cannot
untrack anything, so the pattern is inert against tracked files. `git rm --cached` is not. If a
project has non-SSD files under `docs/architecture/`, the interlock must show them and the user must
be able to proceed selectively or abort. Untracking a team's unrelated architecture doc because it
shared a directory would be the worst outcome this feature could produce.

**H4 — idempotency.** Re-running the election on an already-private project must be a clean no-op,
not a second `git rm --cached` pass over an empty set.

**H5 — the recorded-version question.** An elective entry never advances the version, so a project
that elects private mode still records whatever version it was on. Confirm that is coherent: the
project *has* adopted a 2.9.0-era capability without its recorded version reflecting it. Likely fine
(the version tracks conventions, and this is not one), but it should be a stated decision rather than
an accident.

## Explicitly out of scope

- **History rewriting.** No `filter-branch`, no `bfg`. Non-goal in ADR-0017 and unchanged.
- **Moving *out* of private mode.** Re-tracking previously-untracked artifacts is the inverse
  migration and is not requested. Note it as unbuilt rather than implying symmetry.
- **The `parse_active_workstreams` defect** (found at iteration A's ship). `issue-sync-current` can
  never PASS for a workstream carrying a nested list. Real, pre-existing, and **its own PR** — hard
  rule 4 keeps it out of a feature iteration. Same for **QUESTION-2**
  (`committed-gate-yml` / `strict-selective-gitignore` reporting `ERROR` on an absent precondition).

## What shipping looks like

On an existing repo with committed SSD artifacts, `/ssd upgrade` reports drift **without mentioning
private mode**. Running `/ssd upgrade --apply private-mode` names every file it will untrack, waits for
confirmation, says plainly that history is not rewritten, and then leaves a project whose future
commits carry no SSD paper trail. Running plain `/ssd upgrade --apply` on that same repo, or on any
other, never touches privacy. Projects that never elect it are byte-identical to v2.8.0.

## Open for the architect

**Is `elective` the right name, and should it be a `kind` or an orthogonal field?** `kind` currently
means "how is this adopted" (mechanical = automatically, guided = by hand). `elective` answers a
different question — *"is this something every project should adopt?"* — which argues for a separate
field (`optional: true`) rather than a third `kind` value. Against that: a new field means every
consumer must handle its absence, and the 3×2 matrix objection that killed `ssd.privacy` in iteration A
applies here too. Decide and record; the manifest is append-only, so the id survives but the shape is
hard to change later.
