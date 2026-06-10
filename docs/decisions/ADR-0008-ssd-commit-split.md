# ADR-0008: Selective `.ssd/` commit split — durable artifacts vs. working state

## Status
Proposed — 2026-05-24 — landed in iteration A of the ssd-commit-split epic ([01-architect.md](../../.ssd/features/ssd-commit-split/01-architect.md)).

## Context

`.ssd/` has been blanket-gitignored since v1.3.0 (when the working-tree convention moved from
visible `ssd/` to hidden `.ssd/`). At the time the reasoning was sound: working artifacts —
intermediate briefs, transient reviews, machine-managed state — shouldn't pollute the
committed history. ADRs and runbooks got their own committed homes in `docs/decisions/` and
`docs/runbooks/`. Everything else was treated as ephemeral.

Two things have changed.

**First, the artifacts under `.ssd/features/<slug>/` are not ephemeral.** A brief describes
the work. An architect spec records the design and the alternatives rejected. A code review
documents what was found and how it was closed. These are durable records of engineering
decisions — the same class of artifact that justifies committing ADRs. Today they live in
`.ssd/` and are invisible to PR review, milestone audits, external onboarding, and any
future code-archaeology effort. A new contributor cloning the repo sees the code but not
the reasoning. The reasoning was written; it's just hidden by `.gitignore`.

**Second, the parallel-features epic (ADR-0007, v1.15–v1.17) added cross-user surface area.**
Multiple workstreams per user is now first-class; teams are starting to use SSD across
multiple contributors. With multiple people editing the same repo, the cost of invisible
artifacts compounds — "what did Alice's architect spec say?" becomes a Slack message instead
of a PR comment.

But not everything under `.ssd/` is durable.

`current.yml` is **machine-managed state** with absolute paths (`worktree: /Users/ahorovit/...`)
and per-user profile data (`developer_profile`, `teaching_mode.invocations_remaining`).
Committing it produces meaningless merge conflicts between contributors and leaks
machine-specific paths into history.

`current.notes.yml.features.<slug>.handoff_notes` is **personal drafts**. "Stopped here
because I was tired" doesn't belong in a public PR. Committing creates social pressure that
makes the field useless: people self-censor, the notes become sanitized and stop conveying
useful state.

`init-log.md`, `archive/`, and `audits/` are similarly working artifacts: machine logs,
historical state, sensitive vendor evaluations.

The blanket gitignore is wrong because it treats two distinct categories as one. The
all-committed alternative is also wrong because it treats them as one in the other direction.

## Decision

**Split `.ssd/` along the durable-vs-working line. Selective gitignore patterns enforce the
split. Layered defenses prevent accidental leakage.**

### What gets committed

Under `.ssd/`, the following are committed:

- `.ssd/features/<slug>/00-brief.md`
- `.ssd/features/<slug>/01-architect.md`
- `.ssd/features/<slug>/02-systems-designer.md`
- `.ssd/features/<slug>/03-coder-status.md`
- `.ssd/features/<slug>/04-code-review*.md` (including round-2+ files)
- `.ssd/features/<slug>/05-deploy.md`
- `.ssd/features/<slug>/iterations/<iter>/{brief,coder-status,deploy}.md`
- `.ssd/features/<slug>/iterations/<iter>/code-review/round-*.md`
- `.ssd/milestones/<topic>/{skeptic-before,refactor-plan,refactor-prs,skeptic-after,verification}.md`

These are **design documents** in the same class as ADRs. They describe what was decided,
considered, and built. They belong in PR review and in the project's permanent record.

### What stays gitignored

- `.ssd/current.yml` — machine state with absolute paths and per-checkout context.
- `.ssd/current.notes.yml` — personal handoff drafts.
- `.ssd/init-log.md` — first-run housekeeping log.
- `.ssd/archive/` — historical workstream state (committed artifacts of archived features
  stay in their original `features/<slug>/` location and remain tracked).
- `.ssd/audits/` — software-standards comparative audits (often name vendors, surface
  sensitive opinions).
- `.ssd/milestones/<topic>/{sha-before,metrics-before.yml}` — snapshot machinery, not
  durable docs.
- `.ssd/features/<slug>/iterations/<iter>/deferred.yml` — workstream-internal carry-over
  ledger, machine-managed.
- `.ssd/project.yml` — contains `developer_profile`, `teaching_mode`, paths, integrations,
  and other per-user/per-checkout configuration.
- Any future machine-managed `.bak` files (`current.yml.bak` etc.).

### Enforcement layers

1. **Gitignore patterns (the floor).** `.ssd/*` blanket-blocked, with explicit
   `!.ssd/features/`, `!.ssd/milestones/`, and per-file allow-lists for the durable artifacts.
2. **`ssd-init` writes the right patterns.** New projects get the selective pattern by
   default. Existing projects with the blanket `.ssd/` get prompted to migrate (with `.bak`
   backup, idempotent, matches ADR-0002's migration UX).
3. **New gate rule `no-leaky-state`** in `methodology/gate-rules.sh`. Reads `git diff
   <base>...HEAD --name-only` against a deny-list (the patterns above). FAILs the gate if
   any forbidden path appears in the diff. Catches force-add (`git add -f current.yml`),
   edited `.gitignore` regressions, and new file types not yet in the gitignore.
4. **Optional pre-commit hook** in `methodology/hooks/`. Same deny-list, fires before
   commit lands. Teams opt in by symlinking; solo devs can skip.
5. **CI integration is the user's choice.** `bash methodology/gate-rules.sh --base origin/main`
   in CI catches what slipped through Layers 1–4. Not mandated by SSD; documented as the
   recommended backstop.

### Opt-out

A solo developer who genuinely prefers the all-gitignored status quo sets
`project.yml.ssd.gitignore_mode: blanket` (default: `selective`). `ssd-init` and `gate-rules.sh`
respect this. The blanket mode is the previous v1.3.0+ behavior; the new selective mode is
the v1.18.0+ default.

## Rationale

- **Briefs and architect specs are design documents.** They have the same audit and onboarding
  needs as ADRs. ADRs are committed; consistency says briefs and architect specs should be
  too. The class-of-artifact reasoning is direct, not inferred.
- **`current.yml` has machine-specific data.** Absolute worktree paths, per-user profile,
  invocation counters. Committing it produces noise and conflicts with no benefit. The
  per-user data isn't shared state; it's per-checkout state.
- **`handoff_notes` need to be candid to be useful.** Public-committed handoff notes get
  sanitized. Sanitized handoff notes don't convey the state the next session needs. Keeping
  them local preserves the affordance.
- **Layered enforcement matches the SSD pattern.** ADR-0005 already established the "doctrine
  + executable rule + documented opt-out" pattern for gate rules. This ADR follows it.
- **Opt-out preserves single-user simplicity.** A solo developer who likes the v1.3.0 blanket
  behavior gets it with one config line. No upgrade-induced churn.
- **Dogfood-able.** This repo will commit its own `.ssd/features/{ssd-skill-upgrades,
  parallel-features, ssd-commit-split}/` artifacts as part of iter C. The SSD methodology's
  own history becomes a worked example for users.

## Consequences

**Easier:**
- Briefs and architect specs land in PR review. Reviewers see the *why* alongside the *what*.
- New contributors get full project state from `git clone`.
- Milestone audits can read prior architect specs directly from git history.
- CI can enforce things like "architect spec exists for feature `<slug>`" (future capability).
- SSD's own history becomes a worked example.

**Harder:**
- The gitignore pattern is longer and more complex (~12 lines vs 1).
- Migrating existing repos requires a one-time `ssd-init --migrate-gitignore` step.
- Briefs/architect-specs now go through PR review — small social-process change. People who
  treated them as scratch space will need to treat them as docs.
- Larger PR diffs on feature work (the brief + architect + coder-status + code-review all
  land in the same PR as the code). Generally acceptable since they describe the same work.

**What we give up:**
- The simplicity of "everything under `.ssd/` is local." Now there's a categorization to
  remember. Mitigation: enforcement layers + clear `.gitignore` patterns make the categorization
  visible.
- The freedom to write rough draft briefs that won't be seen. Mitigation: use
  `current.notes.yml` for rough notes (still gitignored); promote to brief only when ready
  to share.

## Alternatives Rejected

- **All-committed `.ssd/`.** Treats `current.yml`'s absolute paths as committed data. Produces
  merge conflicts on `last_touched` timestamps and noisy commits on every state write.
  Rejected.
- **All-gitignored `.ssd/` (status quo).** Loses the briefs and architect specs from history,
  PR review, and onboarding. Rejected per the Context section.
- **Move durable artifacts into `docs/features/<slug>/`** (out of `.ssd/` entirely). Cleaner
  conceptually but breaks every existing sub-skill that loads artifacts from
  `.ssd/features/<slug>/`. Migration cost is high; the path-rename touches every skill.
  Rejected — keep the paths, change the gitignore.
- **Per-file `.gitkeep` markers** to opt artifacts in. Inverts the default and creates
  per-file maintenance burden. Rejected.
- **Hook-only enforcement** without the gate rule. Hooks are bypassable (`--no-verify`); the
  gate rule is not. Layer 3 is mandatory; Layer 4 is optional polish.
- **A separate `committed.ssd/` directory** alongside `.ssd/`. Doubles the artifact tree and
  forces every skill to know about both paths. Rejected.
- **`schema_version: 3` bump on `current.yml`.** The split doesn't change `current.yml`'s
  schema. No version bump needed.

## Future Compatibility

- The deny-list (Layer 3) and the gitignore pattern (Layer 1) are the same set in different
  syntax. Future additions to the artifact tree go in both places; a forgotten place is a
  silent leak. Document this in `ssd/SKILL.md` § "The SSD Artifact Tree."
- The `gitignore_mode` opt-out is forward-compatible. Future modes (`selective-strict`,
  `selective-with-archive`, etc.) can be added without breaking existing projects.
- The `no-leaky-state` rule joins the standard gate-rules set. Future gate rules follow the
  same `PASS|FAIL|SKIP <rule-name> :: <detail>` contract.

## Scale Note

A typical SSD project running this convention has, per feature:
- 1 brief (~50–150 lines)
- 1 architect spec (~200–500 lines)
- 1 systems-designer doc (~100–300 lines, when applicable)
- 1 coder-status (~80–200 lines)
- 1–3 code-review files (~100–300 lines each)
- 1 deploy log (~30–80 lines)

Per-feature footprint: ~500–1500 committed markdown lines. For a project that ships 50
features over its lifetime, ~25k–75k markdown lines of feature artifacts. Comparable to a
moderately-documented monorepo's `/docs/`. Acceptable.
