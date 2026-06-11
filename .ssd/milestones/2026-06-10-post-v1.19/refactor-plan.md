---
skill: refactor
version: 1.2.1
produced_at: 2026-06-10T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: post-v1.19 milestone refactor (first ever for this library)
consumed_by: [code-reviewer, ssd]
input_artifact: .ssd/milestones/2026-06-10-post-v1.19/skeptic-before.md
items:
  - id: R1
    cites: ["Beck: parity-test not run", "Humble: no CI workflow", "F4: Friday-deploy risk on gate-rules.sh"]
    pattern: introduce-ci-gate
    files: [.github/workflows/quality.yml]
    budget_hours: 0.5
    touches_failure_modes: false
    touches_observability: true       # CI is the methodology's observability surface
    touches_deploy_path: true         # this IS the deploy path enforcement
  - id: R2
    cites: ["Humble: missing tags v1.16.0..v1.19.0"]
    pattern: backfill-release-tags
    files: []                          # git tag operations only; no committed files
    budget_hours: 0.25
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: true         # tags are the deploy-history surface
  - id: R3
    cites: ["Fowler: 💀 version-drift in frontmatter examples"]
    pattern: sync-skill-version-examples
    files:
      - architect/SKILL.md
      - coder/SKILL.md
      - code-reviewer/SKILL.md
      - codebase-skeptic/SKILL.md
      - ssd-init/SKILL.md
      - systems-designer/SKILL.md
    budget_hours: 0.25
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R4
    cites: ["Fowler structural-risk recommendation #2", "Wozniak: validator doesn't enforce version"]
    pattern: extend-validator-version-check
    files:
      - methodology/frontmatter-validate.py
      - methodology/schemas/architect.yml
      - methodology/schemas/coder.yml
      - methodology/schemas/code-reviewer.yml
      - methodology/schemas/systems-designer.yml
      - scripts/parity-test.sh        # new fixture demonstrating the new check
    budget_hours: 0.5
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
    depends_on: [R3]                  # must sync versions first or this check fails on existing artifacts
  - id: R5
    cites: ["Jobs: overlap-table-stale"]
    pattern: expand-doc-table
    files: [ssd/SKILL.md]
    budget_hours: 0.5
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R6
    cites: ["Jobs: README polish — dogfood epics list"]
    pattern: improve-doc-discoverability
    files: [README.md]
    budget_hours: 0.25
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R7
    cites: ["Feathers: ssd/SKILL.md banner-lag pattern"]
    pattern: document-policy
    files: [ssd/SKILL.md]
    budget_hours: 0.1
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
  - id: R8
    cites: ["Hohpe: current.yml single-writer concurrency", "F3: incident at 3am on current.yml race"]
    pattern: document-failure-mode
    files: [ssd/SKILL.md]
    budget_hours: 0.25
    touches_failure_modes: true       # documents a known concurrency failure mode
    touches_observability: false
    touches_deploy_path: false
  - id: R9
    cites: ["Feathers: profile-scatter across 5 sub-skills", "F2: new-hire profile risk"]
    pattern: cross-skill-audit
    files:
      - architect/SKILL.md
      - systems-designer/SKILL.md
      - methodology/SKILL.md
      - refactor/SKILL.md
      - coder/SKILL.md
      - code-reviewer/SKILL.md
      - codebase-skeptic/SKILL.md
    budget_hours: 2.0
    touches_failure_modes: false
    touches_observability: false
    touches_deploy_path: false
deferred_items:
  - skeptic_item: 10
    title: Plan future ssd/SKILL.md chapter split (workstream.md, schema.md, profiles.md)
    rationale: |
      Per skeptic synthesis ("voice conflicts: Fowler vs Feathers"), splitting is correct direction
      but should target a future major release (v2.0.0) with explicit deprecation period and
      migration script. Not in-milestone scope.
  - skeptic_item: 11
    title: ADR-0009 candidate — split current.yml.archived[] into separate committed file
    rationale: |
      Evans-voice schema refactor. Real but not urgent; touches the durable-vs-machine boundary
      ADR-0008 just established. Defer to next epic-level design pass.
  - skeptic_item: 12
    title: CONTRIBUTING.md
    rationale: |
      Onboarding doc for hypothetical second contributor. The single-developer reality means
      no immediate pain. Worth doing but doesn't earn this milestone's slot.
total_budget_hours: 4.6
release_vehicle: v1.19.1 (single patch release bundling R1–R8); R9 → v1.20.0
gate_pass: true
---

# Refactor Plan — Post-v1.19 Milestone

**Input:** [skeptic-before.md](skeptic-before.md) — 14 findings (1 💀, 4 🔴, 7 ⚠, 2 💭) + 4 forward-looking.

**Scope of this plan:** R1–R9. The skeptic's prioritized table items 10–12 are deferred (see
`deferred_items` in frontmatter); they're planning-grade work that doesn't fit milestone-refactor
scope.

**Confirms skeptic's recommendation** that R1–R3 (the parity-test/CI/version-sync cluster) are the
highest-leverage interventions. **Revises sequencing**: skeptic suggested "top-4 as a v1.19.1
doctrine-tightening patch"; this plan does R1–R8 in v1.19.1 (~2.6 hrs) and pulls R9 (profile-audit,
2 hrs by itself) out to v1.20.0 as its own release. The profile audit touches 7 sub-skills and is
its own design conversation — bundling it into a doctrine-tightening patch undersells it.

**Per the SSD milestone playbook, each item below is a separate PR from feature work.** R2 is
the one exception — git tag operations don't go through PRs.

---

## Total budget & release vehicle

- **Total work:** ~4.6 hours across 9 items (one is git-only, no PR).
- **R1–R8 in one patch:** v1.19.1 doctrine-tightening (~2.6 hours). Eight PRs landing in sequence.
- **R9 as next minor:** v1.20.0 profile-audit (~2.0 hours). Separate planning conversation because
  it touches the most sub-skills and may surface new design questions.

**Test discipline reminder** (per `/ssd milestone` § "Refactor planning"): *"Write tests first if
coverage is insufficient."* This library's only mechanical test is `scripts/parity-test.sh` (14
assertions against `gate-rules.sh`). Coverage of the *.md doctrine itself is not testable in any
mechanical sense — the closure is via `codebase-skeptic` at `/ssd verify` time. **For R4 (validator
extension), add a new parity-test fixture demonstrating the version-mismatch FAIL before changing the
validator.** No other item in this plan needs test-first because they're all documentation /
configuration / tag operations.

**Systems-designer coordination** (per refactor Step 6): R1 touches the deploy path (it IS the
deploy-pipeline gate); R2 touches the deploy-history surface (tags); R8 documents a failure mode.
None of these introduce a new failure mode — they document or enforce existing ones — so no
re-invocation of `systems-designer` is required. Noted in each item's `touches_*` flags.

---

## R1 — Add `.github/workflows/quality.yml` for PR + push CI

**Cites:** `Beck: parity-test not run`, `Humble: no CI workflow`, `F4: Friday-deploy risk on gate-rules.sh`

**Title:** `ci: add quality workflow running gate-rules + parity-test on PR/push`

**PR effort:** ~30 minutes.

**Files:**
- NEW: `.github/workflows/quality.yml`

**Acceptance criteria:**
- Workflow runs `bash methodology/gate-rules.sh --base origin/main` on every PR against `main`.
- Workflow runs `bash scripts/parity-test.sh` on every push to `main` AND every PR.
- Both jobs use a sane Ubuntu runner image with bash 4+, Python 3, PyYAML.
- The workflow's exit code blocks merge if either job FAILs.
- README updated with a CI status badge linking to the workflow.

**Test plan:**
- Open a PR that violates `no-leaky-state` (e.g., `git add -f .ssd/current.yml`). CI must FAIL.
- Open a PR with valid changes. CI must PASS.
- Push a commit that breaks the parity-test (e.g., regress the deny-pattern matcher). CI must FAIL.

**Dependencies:** none. **Land first** — every subsequent PR benefits from CI catching regressions.

**Closure check** (refactor Step 5): re-run skeptic's Beck and Humble lenses. The "parity-test
exists but isn't run" finding is closed when CI invokes it. The "encode the ratchet in CI"
core.md § 4 doctrine is satisfied.

---

## R2 — Backfill missing git tags (v1.16.0–v1.19.0)

**Cites:** `Humble: missing tags v1.16.0..v1.19.0`

**Title:** N/A (no PR — git tag operations only)

**Effort:** ~15 minutes.

**Operations** (run from `main` after `git fetch origin`):

```bash
git tag -a v1.16.0 098d35e -m "v1.16.0 — Iteration B of parallel-features (orchestrator commands)"
git tag -a v1.17.0 0ce2953 -m "v1.17.0 — Iteration C of parallel-features (overlap detection; epic complete)"
git tag -a v1.17.1 a0ff836 -m "v1.17.1 — Documentation: canonical-reference + cross-linking pass"
git tag -a v1.18.0 810d64e -m "v1.18.0 — Iteration A of ssd-commit-split (selective .ssd/ gitignore + no-leaky-state rule)"
git tag -a v1.19.0 264c69d -m "v1.19.0 — Iteration B of ssd-commit-split (pre-commit hook + dogfood; epic complete)"
git push origin v1.16.0 v1.17.0 v1.17.1 v1.18.0 v1.19.0
```

**Acceptance criteria:**
- `git tag --list 'v1.*'` shows v1.15.0 through v1.19.0 (gaps filled).
- GitHub's Releases page generates entries for each tag (auto-from-tag if no release notes set).
- `git checkout v1.18.0` resolves to commit `810d64e`.

**Test plan:**
- After `git push origin <tag>`, verify on GitHub that the tag appears in the Releases dropdown.
- Verify `git fetch origin --tags` on a fresh clone retrieves them.

**Dependencies:** none. Can land anytime, but recommend running **before R1 ships** so v1.19.1
isn't yet another untagged release in the gap pattern.

**Closure check:** Humble lens re-applied. "Missing tags" closes when all five tags exist on
origin.

**Note on R2's nature.** This is the one item that isn't a PR. Tag creation doesn't require a
branch or merge. The orchestrator should add a step to `/ssd ship` documentation: "After PR
merge, tag the release: `git tag -a v<version> <merge-sha> -m '<one-line>' && git push origin
v<version>`." That documentation change is a separate item — folded into R7 (banner-lag pattern
documentation), see below.

---

## R3 — Sync `version:` in each sub-skill's required-frontmatter example to the banner

**Cites:** `Fowler: 💀 version-drift in frontmatter examples`

**Title:** `docs(skills): sync required-frontmatter version examples to skill banner`

**PR effort:** ~15 minutes.

**Files:**
- `architect/SKILL.md` — example `version:` `1.1.0` → `1.2.0`
- `coder/SKILL.md` — example `version:` `1.1.0` → `1.2.0`
- `code-reviewer/SKILL.md` — example `version:` `1.3.0` → `1.5.0`
- `codebase-skeptic/SKILL.md` — example `version:` `1.2.0` → `1.2.1`
- `ssd-init/SKILL.md` — example `version:` `1.0.0` → `1.8.0` (the biggest gap, off by 8 minors)
- `systems-designer/SKILL.md` — example `version:` `1.2.0` → `1.3.0`

**Acceptance criteria:**
- Each touched SKILL.md has its required-frontmatter example `version:` matching the file's banner.
- `grep -n "^version:" <skill>/SKILL.md` shows the synced value.
- No other content in the SKILL.md changes (this is a mechanical 6-line patch).

**Test plan:**
- Manual verify each file. The grep above (returns one line per file) should match the banner above
  it.
- `bash methodology/gate-rules.sh --base origin/main` still PASSes (no regressions).
- Until R4 lands, the validator won't enforce the match — but the artifacts produced going forward
  carry correct versions.

**Dependencies:** none. Can land in parallel with R1/R2.

**Closure check:** Fowler version-drift lens re-applied. Six skills synced; the historical record
of all artifacts produced *after* this PR will carry correct versions. (Pre-existing artifacts still
have the stale values; we don't rewrite history.)

---

## R4 — Extend `frontmatter-validate.py` + per-skill schemas to enforce version-banner match

**Cites:** `Fowler structural-risk recommendation #2 (forward-defense)`, `Wozniak: validator doesn't enforce version`

**Title:** `feat(validator): enforce frontmatter version matches skill banner`

**PR effort:** ~30 minutes (including the parity-test fixture per "tests first").

**Files:**
- `methodology/frontmatter-validate.py` — extend `match_schema` and field-check logic to read the
  skill's banner via a simple regex on `<skill>/SKILL.md` and assert `frontmatter.version ==
  <banner>`.
- `methodology/schemas/architect.yml`, `coder.yml`, `code-reviewer.yml`, `systems-designer.yml`,
  `codebase-skeptic.yml`, `ssd-init.yml` (if present) — add `version_assertion: banner-match` flag
  per schema (the validator reads this flag and dispatches to banner-check).
- `scripts/parity-test.sh` — new fixture: `version-mismatch-fails` (a fixture artifact with
  `version: 1.0.0` in its frontmatter when the skill's banner is `1.2.0`; the validator should
  FAIL). Add to the 14-assertion run.

**Acceptance criteria:**
- New parity-test fixture demonstrates the mismatch FAIL before the validator change ships.
- After the change, the validator emits `FAIL <path> :: version mismatch (frontmatter=X.Y.Z,
  skill-banner=A.B.C)` on artifacts with stale versions.
- The `frontmatter-valid` gate rule's count of PASSing artifacts is unchanged at HEAD (R3 already
  synced all current SKILL.md examples; produced artifacts post-R3 ship correct).
- The parity-test run now has 15 assertions, all PASSing.

**Test plan:**
- Write the fixture first (`version-mismatch-fails/`) — verify it FAILs against the *current*
  validator with a clear error.
- Make the validator change. Re-run the fixture — must now match the expected FAIL message.
- Re-run all 15 parity-test assertions. All PASS.
- `bash methodology/gate-rules.sh --base origin/main` on this PR's diff PASSes (the frontmatter the
  PR introduces in its own artifacts is fresh, with current version).

**Dependencies:** R3 must land first (or the validator change will FAIL on the current state's
artifacts that R3 has yet to sync).

**Closure check:** Fowler's structural-risk recommendation #2 satisfied. Future
version-drift caught mechanically at gate time.

---

## R5 — Expand `ssd/SKILL.md` § "Resolving Skill Overlap" with the 4 latent pairs

**Cites:** `Jobs: overlap-table-stale`

**Title:** `docs(ssd): document latent skill-overlap pairs (refactor vs reviewer, design bundle, methodology cross-ref, skeptic+refactor)`

**PR effort:** ~30 minutes.

**Files:**
- `ssd/SKILL.md` — append four rows to the § "Resolving Skill Overlap" table:
  1. `refactor` vs `code-reviewer` in remediation contexts (Phase 1.5 priority)
  2. `architect` vs `systems-designer` in `/ssd design` (systems-designer is purely additive)
  3. `methodology` vs everything (reference-tier; direct invocation rare)
  4. `codebase-skeptic` vs `refactor` in `/ssd verify` (skeptic produces; refactor consumes)

**Acceptance criteria:**
- The four rows are added with the same format as the existing three (Generic | Specific | Priority).
- Each new row's priority rule is unambiguous (does not require interpretation).
- The two-paragraph intro to the table is updated to reflect "7 known overlap pairs."

**Test plan:**
- Read through the table top-to-bottom — every pair has a Priority column entry.
- Each new pair has a "When NOT to use" cross-reference, per the existing convention.

**Dependencies:** none. Pure docs.

**Closure check:** Jobs overlap-table-stale lens re-applied. Table now documents 7 pairs covering
the major coordination surfaces.

---

## R6 — Add dogfood epics list to README

**Cites:** `Jobs: README polish — dogfood epics list`

**Title:** `docs(readme): list dogfooded SSD epics under .ssd/features/`

**PR effort:** ~15 minutes.

**Files:**
- `README.md` — after the existing dogfood paragraph (added in v1.19.0), add a 3-bullet list:
  - `ssd-skill-upgrades/` — 9-iteration epic implementing v1.5–v1.14 (5 ADRs)
  - `parallel-features/` — multi-feature workflow (3 iterations, v1.15–v1.17)
  - `ssd-commit-split/` — the convention that makes this list visible (2 iterations, v1.18–v1.19)
- Each bullet links directly to that epic's `01-architect.md` so a visitor sees a real spec.

**Acceptance criteria:**
- README renders the list with working GitHub links to the three architect specs.
- No other README content changes.

**Test plan:**
- Visit the rendered README on GitHub after merge; click each link; confirm it lands on a real
  architect spec.

**Dependencies:** none. Pure docs.

**Closure check:** Jobs README-polish satisfied; the dogfood is now *discoverable*, not just
referenced.

---

## R7 — Document the `ssd/SKILL.md` banner-lag pattern + the tag-after-merge step

**Cites:** `Feathers: ssd/SKILL.md banner-lag pattern`, plus the tag-after-merge documentation that
fell out of R2's note

**Title:** `docs(ssd): clarify banner-version divergence pattern + add tag-after-merge step`

**PR effort:** ~6 minutes.

**Files:**
- `ssd/SKILL.md` — add a one-line note near the version banner (top of file): "Skill version
  tracks library version when the skill changes; otherwise it diverges and re-aligns on next
  change to this skill."
- `ssd/SKILL.md` § "/ssd ship" — append a "Tag the release" step: `git tag -a v<version>
  <merge-sha> -m '<one-line>' && git push origin v<version>`. Reference the post-merge ratchet
  from `methodology/core.md` § 4.

**Acceptance criteria:**
- Both notes added; no other content changes.
- The tag-after-merge step explicitly says "this should be done by hand or via a script; the
  orchestrator does not auto-tag because tags push to remote."

**Test plan:**
- Read through ssd/SKILL.md § "/ssd ship" — the tagging step is the last bullet.
- Read through the changelog entry that mentions this — references R7 by cite.

**Dependencies:** none. Pure docs.

**Closure check:** Feathers banner-lag observation closes when the divergence-and-realign pattern
is named. The R2 follow-up (tag-after-merge) is captured in doctrine so future releases don't
silently un-tag again.

---

## R8 — Document the single-Claude-session-per-project concurrency assumption

**Cites:** `Hohpe: current.yml single-writer concurrency`, `F3: incident at 3am on current.yml race`

**Title:** `docs(ssd): document single-Claude-session-per-project assumption + incident notes`

**PR effort:** ~15 minutes.

**Files:**
- `ssd/SKILL.md` § "Session Continuity" — add a paragraph explicitly stating:
  - Doctrine: one Claude session per project at a time.
  - The atomic-write claim ("write to temp file + rename") is a prose contract, not a runtime
    guarantee.
  - If two terminals run `/ssd` simultaneously and write to `current.yml`, the second writer
    silently replaces the first.
  - Recovery: git history of `current.notes.yml` (when committed) preserves human notes; the
    `current.yml.bak` migration backup from ADR-0002 is the rollback artifact for v1→v2.
  - Future ADR-0009 candidate: introduce a lockfile or version-counter scheme if parallel
    sessions become a real use case.

**Acceptance criteria:**
- Paragraph added; no schema changes (the assumption is documented, not enforced).
- The incident-time playbook in the new paragraph names the rollback artifact.

**Test plan:**
- Read through ssd/SKILL.md § "Session Continuity" — the new paragraph is the last subsection.

**Dependencies:** none. Pure docs.

**Closure check:** Hohpe concurrency-doctrine documented; F3 incident-readiness note in the
playbook.

**Touches failure modes:** YES (documents a known concurrency failure). `touches_failure_modes:
true` in frontmatter above. No `systems-designer` re-invocation needed — we're documenting an
existing failure mode, not introducing a new one.

---

## R9 — Audit each profile-blind sub-skill: should it branch on `developer_profile`?

**Cites:** `Feathers: profile-scatter across 5 sub-skills`, `F2: new-hire profile risk`

**Title:** `feat(skills): profile-awareness audit + branches across sub-skills`

**PR effort:** ~2 hours (the largest item in this milestone; cross-skill).

**Files:**
- `architect/SKILL.md` — audit: ADR-completeness requirements should be profile-aware? Recommend:
  no (architects produce ADRs regardless of profile). Add explicit "this skill's behavior is
  profile-invariant" note.
- `systems-designer/SKILL.md` — audit: deploy-checklist depth should be profile-aware? Possibly
  yes (novice gets more guidance; expert gets terse). Add per-profile guidance if needed.
- `methodology/SKILL.md` — audit: `/methodology score` self-adherence metric should be
  profile-aware? Recommend: no (scoring is absolute). Add explicit invariance note.
- `refactor/SKILL.md` — audit: budget-hours-warning verbosity could be profile-aware. Possibly
  yes. Add per-profile guidance.
- `coder/SKILL.md` — audit: REVIEW marker count threshold could be profile-aware (novice gets more
  REVIEW markers for safety; expert gets fewer for terseness). Currently only 1 mention. Expand.
- `code-reviewer/SKILL.md` — audit: severity-discipline strictness could be profile-aware (novice
  gets more MINORs called out; expert gets terser review). Currently only 1 mention. Expand.
- `codebase-skeptic/SKILL.md` — audit: voice activation could be profile-aware (novice gets fewer
  voices; expert gets all 10). Currently only 1 mention. Expand.

**Acceptance criteria:**
- Each of the 7 listed sub-skills has either:
  - (a) An explicit "this skill is profile-invariant" note in its SKILL.md, with rationale, OR
  - (b) Per-profile behavior branches added with explicit table entries.
- The Profile-aware defaults table in `ssd/SKILL.md` gains any new columns introduced (e.g.,
  `coder.review_marker_threshold`, `code-reviewer.minor_strictness`).
- No regression in existing behavior for `developer_profile: standard` users.

**Test plan:**
- Manual: read through each touched SKILL.md and confirm the profile branch is consistent with
  the ssd/SKILL.md table.
- Mechanical: re-run `bash methodology/gate-rules.sh --base origin/main`. All rules PASS.
- Optional: simulate a fresh-init project for each of `novice`, `standard`, `expert` and verify
  the orchestrator's behavior differs as documented.

**Dependencies:** none directly, but R5 (overlap-table expansion) and R7 (banner-lag note) should
land first so this PR doesn't re-touch the same files.

**Closure check:** Feathers profile-scatter satisfied; F2 ("new-hire breaks because most sub-skills
are profile-blind") closed because every sub-skill now either branches or explicitly opts out.

**Release vehicle:** **NOT in v1.19.1**. This is its own minor release as **v1.20.0** because it
touches 7 sub-skills' SKILL.md prose and may surface new design questions (e.g., should profile
be saved as a skill-level invariant flag in the schema?). The doctrine-tightening patch
v1.19.1 should ship cleanly first; v1.20.0 follows as a deliberate audit pass.

---

## Sequencing & PR pipeline

Recommended order for landing the v1.19.1 patch:

| # | Item | Effort | Depends on | Release |
|---|---|---|---|---|
| 1 | **R2** — backfill tags (git only) | 15m | — | (immediate; not in v1.19.1 itself) |
| 2 | **R1** — CI workflow PR | 30m | — | v1.19.1 |
| 3 | **R3** — sync version examples PR | 15m | — | v1.19.1 |
| 4 | **R4** — validator-enforces-version PR (test-first) | 30m | R3 | v1.19.1 |
| 5 | **R5** — overlap table expansion PR | 30m | — | v1.19.1 |
| 6 | **R6** — README dogfood list PR | 15m | — | v1.19.1 |
| 7 | **R7** — banner-lag + tag-after-merge doc PR | 6m | — | v1.19.1 |
| 8 | **R8** — single-Claude assumption doc PR | 15m | — | v1.19.1 |
| Total | | **~2h 36m** | | **v1.19.1** |
| 9 | **R9** — profile-audit | 2h | R5, R7 | v1.20.0 (separate) |

**R2 ships first** (no PR, just git tag operations). The other v1.19.1 PRs land in any order
respecting R3→R4 dependency. After PR #N+1 = R8 merges, tag v1.19.1.

**R9 deferred** to v1.20.0. Don't bundle into v1.19.1 — too much surface area for a
doctrine-tightening patch.

---

## Test-first reminder (per `/ssd milestone` playbook)

> "Write tests first if coverage is insufficient."

Most items in this plan are docs/configuration only. The one item with testable behavior is **R4**:
the validator extension. Per the refactor SKILL.md § "Step 1: Ensure Test Coverage," the parity-test
fixture must be added FIRST and demonstrated to FAIL against the current validator before the
validator change ships. The PR sequence enforces this: R3 ships the synced versions, then R4 ships
the test fixture + the validator change together (so the fixture is meaningful — it tests something
that *would* have caught the drift R3 just fixed).

All other items: documentation. The "test" for documentation refactors is `codebase-skeptic` at
`/ssd verify` — the loop closes when re-running the milestone audit shows the cited findings
addressed.

---

## Loop closure plan (per refactor Step 5)

After each PR merges, record the closure in
`.ssd/milestones/2026-06-10-post-v1.19/refactor-prs.md`:

```markdown
| PR | Cites | Status | Closed in commit |
|---|---|---|---|
| #N (R1) | Beck: parity-test, Humble: no CI, F4 | ✅ closed | <merge-sha> |
| (R2)    | Humble: missing tags                 | ✅ closed | (5 tags pushed) |
| #N+1 (R3) | Fowler: 💀 version-drift           | ✅ closed | <merge-sha> |
| ...
```

A `🔄 partial` or `❌ abandoned` row requires explicit residue notes per the refactor SKILL.md
discipline. **No silent closures.** If R9 takes longer than 2h and gets cut, mark it `🔄 partial`
with the deferred portion named and the unfinished sub-skill audits enumerated.

---

## Systems-designer coordination (per refactor Step 6)

| Item | Touches failure-mode? | Observability? | Deploy path? | Re-run systems-designer? |
|---|---|---|---|---|
| R1 | No | Yes (CI is the methodology's observability) | Yes (CI gates merge) | **No** — the existing systems-designer skill's deploy checklist for CI is light; this CI workflow follows ADR-0005 (gate-rules.sh executable) and ADR-0006 (frontmatter validator); no new failure modes. |
| R2 | No | No | Yes (tag-history surface) | No |
| R3–R7 | No | No | No | No |
| R8 | **Yes** (documents `current.yml` concurrency failure) | No | No | No — documents an existing failure mode rather than introducing a new one |
| R9 | No | No | No | No |

No re-invocations of systems-designer needed for this milestone.

---

## After R1–R8 ship (v1.19.1 close)

Per `/ssd milestone` step 5: invoke `/ssd verify`. The verify pass:

1. Re-runs `codebase-skeptic` on the same scope as `skeptic-before.md` → produces
   `skeptic-after.md`.
2. Diffs the frontmatter: each finding gets ✅ closed / 🔄 partial / ❌ unaddressed / 🆕
   new-regression.
3. Re-runs `code-reviewer` on the cumulative refactor diff with `remediation_mode: true`.

**Verification passes** if all original 💀 / 🔴 findings are ✅ closed (R3 closes the structural
risk; R1+R4 cover the validator+CI; R5+R6+R7+R8 close the documentation problems) AND no new
BLOCKER regressions surface. The 4 forward-looking findings (F1–F4) get re-assessed: F4 (Friday
deploy) is closed by R1+CI; F1–F3 remain open but documented.

If verification surfaces a 🆕 regression at BLOCKER severity, the milestone is NOT complete; return
to refactor. Per ADR-0008 § "Decision," the `no-leaky-state` rule already runs in `gate-rules.sh`,
so any PR in this refactor batch that accidentally staged forbidden state would have been caught
at gate time — but `/ssd verify`'s skeptic-after.md catches structural regressions the per-PR gate
doesn't.

---

## Handoff to `code-reviewer`

Each of the 8 PRs in this plan goes through `/ssd gate` with `remediation_mode: true` in the
code-review's frontmatter. Same gate as feature work: no BLOCKER/MAJOR. Record each PR in
`.ssd/milestones/2026-06-10-post-v1.19/refactor-prs.md` as it lands.

The new `no-leaky-state` rule (R1's beneficiary) catches any policy-violating commits across this
batch. The new validator-version-enforcement rule (R4) catches version-drift in any *new* artifacts
the PRs introduce — which means R3 must land first (sync existing) before R4 ships (enforce going
forward).

End of plan.
