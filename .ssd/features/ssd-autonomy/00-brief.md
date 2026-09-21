---
skill: brief
version: 2.13.0
produced_at: 2026-09-21T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: ssd-autonomy
consumed_by: [architect]
---

# Brief — ssd-autonomy (the autonomy ladder)

**Source.** `PRD-ssd-autonomy.md`, supplied with the `/ssd feature ssd-autonomy` invocation on
2026-09-21. That document is a combined PRD (§1–5) and functional spec (§6–12) and is the normative
input for design. This brief is not a summary of it — it states the intent, the boundary, and the
things that were **measured** before design starts. Where the two differ, the PRD wins on requirements
and this brief wins on the state of the repo, because the latter was verified here.

## Why now

The highest-frequency, lowest-judgment interaction in a mature SSD project is the mechanical
coder → reviewer → coder loop until `gate_pass: true`. Every ingredient of a safe agent loop already
exists in this library: the gate is executable ([ADR-0005](../../../docs/decisions/ADR-0005-gate-execution-model.md)),
sub-skill outputs carry machine-readable frontmatter ([ADR-0006](../../../docs/decisions/ADR-0006-frontmatter-validator.md)),
and the rails are a named canonical sequence ([ADR-0003](../../../docs/decisions/ADR-0003-rails-as-canonical-path.md)).
What is missing is a **sanctioned posture** in which the orchestrator may execute its own proposal,
and a **durable record** of what it did unattended.

Two prior failures in this repo set the constraints, and neither is hypothetical:

1. **`--force`.** An override documented in four files for eleven releases that no script implemented
   and nothing logged. Struck in v2.11.0. The lesson is not "document it better" — it is that a
   mechanism described only in prose is a mechanism that does not exist. Autonomy must write its
   trace **before** it acts, and the writer must be something that runs.
2. **Pillar 5** ([ADR-0012](../../../docs/decisions/ADR-0012-ssd-2.0-architecture.md)): enforcement is
   warnings, not walls; SSD trusts the developer. Autonomy must not quietly convert trust of the
   *developer* into trust of an *agent*. That is why the ceiling is `gate` and why it is not
   configurable.

## What this must produce

1. A three-rung ladder — `propose` (today's default, unchanged) · `advance` (bare `/ssd` executes its
   own unambiguous top proposal, one phase, then stops) · `run` (`/ssd run <slug>` walks the rails to
   a ceiling). **An absent `autonomy:` block must produce byte-identical behavior to v2.13.0.**
2. **Announce → log → act**, in that order, for every transition. Rule-zero forbids *silence*, not
   autonomy: a decision that is narrated and durably recorded before it executes has been surfaced.
   A decision that is merely narrated has not.
3. A **delegation wall** at `gate`. The two judgment-bearing decisions that bound a feature — the
   brief at the start, the ship at the end — stay human. `--until ship` is a refusal, not a setting.
4. A **normative refusal set** (runs that never start) and **stop set** (runs that hand back), each
   enumerated, each with a rationale a reader can argue with.
5. **Zero autonomous rail deviations, by construction.** The need for a deviation is a stop condition.
   An agent that can record its own deviations can rationalize its own shortcuts.

## Scope boundary, and why this brief exists at all

**The record is the feature.** The ladder without the auto-run record is `--force` again with a larger
blast radius: a mechanism that acts, and nothing that says it acted. If design pressure forces a cut,
cut a rung — not the record, not the refusals, not the ceiling.

The second boundary is the one the PRD states as NG5 and this brief restates because it is the easy
thing to relax later: an auto-run writes **no** `rail_deviations` entries. `methodology/deviation.sh`
(ADR-0019, landed v2.13.0) is the only writer, and an auto-run never calls it.

## Deliberately out of scope

- Any autonomy past `gate` — no auto-deploy, auto-rollout, auto-flag-removal. Not configurable.
- Parallel auto-runs / multi-worktree. One auto-run per project, matching the existing
  one-session-per-project concurrency doctrine.
- Auto-`ssd-init`. Committing to the SSD convention stays a user decision.
- New daemons, lock files, or protocols. State lives in the existing YAML files.
- A new gate rule in this release (an informational `auto-run-recorded` rule is a noted follow-up).
- Record archival/rotation, configurable `stop_at:`.

## Verified at brief time

Three checks were run against this repo before writing, because each one changes the design:

1. **The hard dependency is satisfied.** `methodology/deviation.sh` exists and writes
   `rail_deviations` (ADR-0019, v2.13.0); `deviations-recorded` in `gate-rules.sh` reads it. The PRD's
   landing-order blocker is cleared. **But** `deviation.sh` writes into `.ssd/current.yml`, and this
   project **had no `current.yml` at all** — it is created by this invocation, with `archived: []`,
   because no prior state file exists to recover history from. The writer landed into a project with
   nothing to write to, and nothing noticed for three weeks.
2. **`auto-runs/*.md` is gitignored today.** `git check-ignore -v` resolves a sample record path to
   `.gitignore:20: .ssd/features/**`. FR-6.2 says the record is *committed* under
   `gitignore_mode: selective`; that requires a negation in **both** `.gitignore` (the canonical copy)
   and `methodology/selective.gitignore` (appended verbatim by `migrate.sh`). The PRD's file manifest
   (FR-7) lists neither. A record the gate cannot see is the `--force` failure mode wearing a filename.
3. **The crude parser resolves the nested key.** `yaml_get` matches `^[[:space:]]*mode:` at any
   indentation, so `ssd.autonomy.mode` reads correctly, and `gitignore_mode:` does **not** collide
   (prefix, not match) — probed directly, not reasoned about. FR-1.5's landing-time check therefore
   passes as of 2.13.0. The standing hazard is unchanged: the key is unique by luck, and any future
   `mode:` anywhere in `project.yml` silently shadows it.

## Open questions for the architect

1. **Does a script write the record, or an instruction?** This is the central question and ADR-0019
   already answered its own version of it (D2: *"a script writes it, not an instruction"*). NG4 forbids
   daemons, lock files and protocols — it does not forbid a `deviation.sh`-shaped helper. Weigh that
   against the fact that execution itself is the orchestrator following prose, and that the `--force`
   lesson is specifically about prose mechanisms.
2. **What is the lock, really?** `active[].auto_run` lives in a gitignored, machine-local file that,
   as of today, did not exist. Define behavior for absent, malformed, and stale-after-crash — the
   third is documented (FR-8), the first two are not.
3. **Record-before-act under failure.** If the record write itself fails, does the phase run? The
   ordering claim in FR-6.1 is only worth something if a failed log aborts the act.
4. **`systems-designer`: run it anyway?** `production_runtime: false` in the committed `.ssd/gate.yml`
   puts rail step 2's second half out of scope for this project — and this feature's entire risk
   surface is failure modes, a lock, and crash recovery, which is exactly what that skill is for.
   Recommendation: run it. If it is skipped, it is **scope, not a deviation** — do not file it under
   `## Rail deviations` (v2.12.0, D17).
5. **Do `advance` and `run` satisfy the rails to the gate's eye?** `rails-walked` and
   `deviations-recorded` both inspect artifacts, not who produced them. Confirm an auto-run's output
   is indistinguishable to those rules, or say why it should not be.
6. **Where does the announce text live before the phase runs?** FR-6 puts the announce lines verbatim
   in the record's prose body; FR-6.1 puts the transition entry ahead of the act. If the body is
   written at hand-back, a crash loses the narration while keeping the structured trace — decide
   whether that is acceptable or whether both are written ahead.
