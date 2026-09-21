---
skill: deploy
version: 2.14.0
produced_at: 2026-09-21T22:10:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-autonomy (v2.14.0)
consumed_by: []
---

# Deploy Log — ssd-autonomy (the autonomy ladder, ADR-0020)

## Status

**Merged and tagged. The release is closed.**

| | |
|---|---|
| Branch | `add-ssd-autonomy`, stacked on `add-adr-dir` |
| PRs | [#54](https://github.com/AlexHorovitz/skills/pull/54) → `add-adr-dir`, **merged** `0284fbae` 2026-09-21T21:59:13Z · [#53](https://github.com/AlexHorovitz/skills/pull/53) → `main`, **merged** (squash) `04bd1ea` 2026-09-21T22:00:19Z |
| Tag | `v2.14.0` → `04bd1ea`, annotated + GPG-signed (EDDSA `…523A318AC32CE8C8`), pushed |
| Review | round 1 `gate_pass: false` (2 MAJOR) · round 2 `gate_pass: true` · round 3 closed both round-2 MINORs before push |

`chapters/phases.md` § `/ssd ship` states the orchestrator does **not** auto-tag, because tagging
pushes to the remote and outward-facing actions stay under explicit human control. The tag was
created on explicit instruction, on the merge commit, with `-F -` rather than `-m` — the process
held.

## The merge shape, recorded because it is not what the PRs describe

**#54 was merged into #53's branch before #53 merged to main, and #53 was squashed.** So `main` has
**one** commit carrying **both** workstreams, and its subject line names only the `adr-delta` fix.

This was checked rather than assumed:

- `main`'s tree object and `add-ssd-autonomy`'s tree object are the **same hash** (`7eef7a2`) — the
  merged content is exactly what was reviewed, not merely equivalent to it.
- The squash **preserved both full commit messages** in the commit body, so the v2.14.0 release notes
  are in the history; only the subject line is misleading. This tag's annotation carries the real
  summary, which is the place that fixes it.
- **The combined content was CI-verified before it landed.** The risk with merging a child first is
  that the combination reaches `main` unchecked — precisely the failure v2.11.3 fixed. It did not
  recur: CI ran on `0284fbae` (both commits) at 21:59:18 and passed, and #53 merged from that head
  61 seconds later.

Nothing was lost. The split between the two workstreams survives in the PR records and in the commit
body, not in `git log --oneline`.

## Gate at ship

Run against `main` with `--base 80f2785` (the release boundary):

```
PASS wip-commits                 no WIP/checkpoint commits
PASS tests-pass                  `bash scripts/parity-test.sh` exit 0 (375/375)
SKIP feature-flag-present        no feature_flag_marker in .ssd/project.yml or .ssd/gate.yml
PASS adr-delta                   1 ADR file(s) changed in docs/decisions/ for 1245 architectural lines
PASS frontmatter-valid           artifact(s) validated against schemas
PASS no-leaky-state              no gitignored-by-policy files in diff
SKIP store-link-sane             no store link (.ssd is a project-local directory)
PASS skill-version-sync          9 skill example(s) match banner; 2 exempt
PASS migration-manifest-current  manifest valid (15 entries; ≤ VERSION 2.14.0)
PASS rails-walked                1 feature dir(s) carry a code review with gate_pass: true
PASS deviations-recorded         every in-scope rail step walked or recorded (production_runtime=false)
SKIP feynman-clean               no feynman report in scope
SKIP issue-sync-current          issue_tracking not on (mirror dormant)
GATE 9 pass · 4 skip · 0 fail
```

**On `feynman-clean`'s SKIP.** It means *no failing audit is in this change set* — **not** that this
project's beliefs are calibrated. Not running `/feynman` is not a violation; it is also not evidence.
Said here because the rule's own documentation asks for it to be said.

## Verification

Run on the merged `main`, in an isolated worktree, not on the branch that produced it:

- `bash scripts/parity-test.sh` → **375/375 assertions**
- `shellcheck -S warning methodology/*.sh scripts/*.sh` → clean
- `bash methodology/autorun.sh preflight` on this repo (no `autonomy:` block) → `state=ok mode=propose`.
  The feature is installed and inert, which is the intended default.
- All eight `chapters/*.md` referenced by the spine resolve on disk, including the new
  `chapters/autonomy.md`.

Two verifications done earlier that this release rests on, recorded so they are not re-litigated:

- **The runbook was verified by executing it**, not by reading it: a crash was simulated (start → one
  transition → no finish) and the stale-lock recovery Steps A–D were run verbatim, including deleting
  `current.yml.bak` first to isolate the claim that `clear` writes one.
- **The migration was verified end to end** on a pre-2.14 project: `PENDING` → `--apply` → the
  commented block → `SKIP-present` → re-apply is a no-op → `preflight` reports `mode=propose`.

## Rail steps out of scope for this project

Not a deviations table, deliberately. A step that never applied is **scope**, not a skipped step, and
recording it as a deviation is how thirteen deploy logs came to carry near-identical paragraphs citing
the very sanction that made them unnecessary (v2.12.0, Feynman audit post-v2.11.0 D17).

- **Step 2, `systems-designer`** — `production_runtime: false` in the committed `.ssd/gate.yml`.
  It was nonetheless **run** for this feature, because the risk surface was failure modes, a lock and
  crash recovery. Running an out-of-scope step is not a deviation either.
- **Steps 7–8, rollout-advance and flag removal** — there is no runtime flag to advance. The
  feature's "flag" is `project.yml.ssd.autonomy.mode`, a permanent configuration surface whose
  absence is the off state. Per `01-architect.md` § Feature Flag Plan, removal is **never**.

`current.yml.active[].rail_deviations` for this workstream is `[]`, and that is the true value, not a
gap.

## Record accuracy

One thing in this workstream's history is worth stating plainly rather than leaving in a scrollback:
**a debug command of mine, with an empty `cd`, overwrote `.ssd/project.yml` and `.ssd/current.yml` in
the real repo** during the code phase. Both are gitignored, so git had no copy. They were
reconstructed from the session transcript and verified against PyYAML **and** the gate's own
`parse_active_workstreams`.

`current.yml.bak` was **no help**, because the damage came from `cat >` rather than from a script that
backs up before writing. The state-recovery runbook's Step 3 assumes a `.bak` written by the tool that
did the damage; that assumption now has a counterexample. Filed here rather than fixed — it belongs to
the runbook, not to this feature.

## Outstanding — recorded, deliberately not fixed

1. **NIT-1** (round 2): `elapsed_minutes = since_start_minutes` is a redundant alias in the wall-clock
   check. Cosmetic, scoped out on purpose.
2. **PR #53 shipped without a `VERSION` bump or a `CHANGELOG` entry of its own.** The `adr-delta`
   change is now on `main` and is described only in the squashed commit body and in this release's
   tag. It was pre-existing uncommitted work that this session separated rather than authored, so no
   release notes were invented for it.
3. **Seven of the last eight releases are untagged** — v2.11.1, v2.11.2, v2.11.3, v2.12.0, v2.12.1,
   v2.13.0, and (until this log) v2.14.0. `methodology/core.md` §4's ratchet reads *"Every release is
   tagged on its merge commit."* The post-v1.19 milestone closed this drift for v1.16.0 and later and
   the ship playbook warns to treat that as scoped rather than finished — **the drift has reopened at
   the top and run for four releases.** Backfilling is its own decision and its own change.
4. **`synced/` is untracked** and belongs to neither workstream — third-party synced skills. It wants
   a `.gitignore` line or a decision.

## Post-merge — done

- [x] `v2.14.0` tagged on `04bd1ea`, annotated, GPG-signed, pushed
- [x] Merged content verified against the reviewed tree by object hash
- [x] Tests and gate re-run on merged `main` in isolation
- [x] Deploy log written (this file)
- [ ] `add-adr-dir` and `add-ssd-autonomy` deleted from the remote — housekeeping, not done here
