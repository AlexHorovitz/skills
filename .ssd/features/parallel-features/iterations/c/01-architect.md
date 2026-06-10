---
skill: architect
version: 1.2.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: parallel-features iteration C — overlap detection + touches backfill + gate-rules base
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: inherited            # iter A epic-level
  data_model: inherited                    # iter A schema; no new fields
  api_contract: refined                    # new OVERLAP-N finding format spec'd here
  integration_contract: refined            # gate-rules.sh + git ls-files
  adrs: []                                  # ADR-0007 covers iter C; no new ADR
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: inherited
quality_gate_pass: true
---

# Architect Spec — Iteration C (parallel-features)

## Delta over iter A's architect

Iter A's architect § "Overlap Warning — How `touches:` Surfaces at Gate Time" already specified
the algorithm. This doc:

1. Resolves iter C's three open questions from the brief.
2. Specifies the exact prose conventions for the new `code-reviewer/SKILL.md` § "Cross-Workstream
   Overlap Check."
3. Defines the touches-backfill flow at gate time.
4. Specifies the (minimal) `gate-rules.sh` change.

No new ADRs. No new schema fields.

## Open questions resolved

### Q1: `gate-rules.sh` base detection scope

**Resolution.** Keep `--base main` as the default. Do NOT introduce automatic workstream-base
derivation in this iteration. The orchestrator, when invoking `gate-rules.sh` on behalf of a
workstream, passes `--base <ref>` explicitly (typically `origin/main`). Document the
workstream-base pattern in `gate-rules.sh` comments and in `ssd/SKILL.md` § "Methodology
Enforcement" so future iter-D work has a known seam.

**Rationale.** Auto-deriving the base from `current.yml` couples the gate script to the
orchestrator's state. The script today is happily standalone (CI-friendly, dogfood-friendly,
`bash methodology/gate-rules.sh --base main` works without `.ssd/current.yml`). Keep that
clean separation; let the orchestrator be the smart caller.

### Q2: OVERLAP-N tier severity

**Confirmed: SUGGESTION.** Not BLOCKER, not MAJOR, not even MINOR. Overlap is often intentional
(layered features). The user has context the orchestrator doesn't. SUGGESTION is the right
severity for "you may want to know this," and per ADR-0007 the rejected-alternatives section
explicitly rejects MAJOR-tier overlap warnings.

The new `code-reviewer/SKILL.md` prose must say so explicitly so a future reviewer doesn't
"upgrade" it on speculation.

### Q3: Glob intersection mechanism

**Confirmed approach:** for each workstream's touch list, resolve globs against the current tree
via `git ls-files <glob>`. Intersect the resulting file sets. Empty intersection = no overlap.
Non-empty = OVERLAP-N finding.

**Edge case: `**` globs.** Standard `**/*.ts` works fine in `git ls-files`. The orchestrator
treats globs case-sensitively (POSIX default). Document.

**Edge case: untracked files.** `git ls-files` returns tracked files by default. If a workstream
declares `touches: [src/foo.ts]` but the file is untracked (new), it won't appear in
ls-files. This is a known limitation; iter C doesn't add `--others` because that would include
unrelated untracked files like editor swap files. Workstreams that need to declare future-file
touches can list them explicitly; ls-files won't match them until they exist.

**Edge case: workstream's own slug.** A workstream's `touches:` must NEVER be intersected
against itself. Self-exclusion is the third acceptance-criteria from the brief.

## Implementation breakdown

### `code-reviewer/SKILL.md` edits

**New § "Cross-Workstream Overlap Check"** inserted between existing § "Review Tier Selection"
material and § "Severity Levels" (or wherever the existing "When to Block" / "Approve" guidance
lives — coder picks the best fit, ideally adjacent to severity discussion). ~40-50 lines:

```
## Cross-Workstream Overlap Check (added v1.17.0)

(See ssd/SKILL.md § "Workstream Lifecycle Commands" and ADR-0007 for the parallel-features
context.)

When invoked via `/ssd gate <slug>`, code-reviewer additionally consults
`.ssd/current.yml.active[]` to detect file-touch overlap between the gated workstream and
other active workstreams. The output is an informational warning, NEVER a blocker.

**Trigger.** Run during Phase 2 (High-Level Review) or as part of the standard phase
ordering. Conditional on:
- `current.yml.active[]` has more than one entry, AND
- The gated workstream has non-empty `touches:`, AND
- At least one other active workstream has non-empty `touches:`.

If any condition is false, skip — no findings emitted.

**Algorithm.**
1. Let `gated` = the workstream under review (matched via the orchestrator's branch → slug
   resolution per ssd/SKILL.md § "/ssd (no-arg) — Auto-Detect" Step 0).
2. For each other workstream `O` in `current.yml.active`:
   a. Resolve `gated.touches` against the working tree: `git ls-files <each glob>` to produce
      `gated_files` (a set of paths).
   b. Resolve `O.touches` similarly to produce `O_files`.
   c. Compute the intersection `overlap = gated_files ∩ O_files`.
   d. If `overlap` is non-empty, emit one OVERLAP-N finding (see format below).

**OVERLAP-N finding format** (added to the existing severity-level vocabulary alongside the
six standard tiers):

| Prefix | Meaning | Blocks Merge? |
|---|---|---|
| `🔗 OVERLAP:` | Files touched by another active workstream | No |

Output structure:

```yaml
findings:
  - id: OVERLAP-1                       # sequential per review
    severity: suggestion                # NOT blocker/major/minor — overlap is informational
    category: cross-workstream-overlap
    title: "Touches files modified by parallel workstream `<other-slug>`"
    files:
      - path: <path>
        also_modified_by: [<other-slug>]
    suggestion: |
      Workstream `<other-slug>` (currently in phase `<phase>`, branch `<branch>`) declares
      overlapping touches. Consider serializing with the other workstream (rebase onto its
      merge before this gate) OR confirm the overlap is intentional (e.g., layered changes).
      This is not a blocker; the gate still passes if blocker == 0 AND major == 0.
```

**Self-exclusion guarantee.** The algorithm step 2 explicitly iterates "other workstream `O`
in `current.yml.active`" — never including the gated workstream itself. Documented.

**Failure modes (informational, never block):**

- Working tree has no commits diverging from base → still works; `git ls-files <glob>` resolves
  against the tree.
- Workstream's `touches:` includes a glob that matches no files yet → no overlap (correct;
  future files don't trigger spurious warnings).
- Multiple OVERLAP findings (3+ active workstreams all overlap on the same file) → one
  OVERLAP-N per pairing, listing all overlapping workstreams in `also_modified_by`.

**Why SUGGESTION not MAJOR.** ADR-0007 § "Alternatives Rejected" specifies this. Overlap can
be intentional (one feature extends a file the other added). The user has context the
orchestrator doesn't. A future reviewer should NOT upgrade this finding to MAJOR on
speculation.
```

### `ssd/SKILL.md` edits

**§ "Methodology Enforcement"** — add one paragraph mentioning the new overlap check:

> **Cross-workstream overlap (v1.17.0+).** When `/ssd gate` runs on a workstream that has
> peers in `current.yml.active[]`, `code-reviewer` additionally consults the peers' `touches:`
> fields and emits informational OVERLAP-N findings (SUGGESTION tier) for any file-set
> intersections. The gate is NOT blocked by overlap. See `code-reviewer/SKILL.md` § "Cross-Workstream
> Overlap Check" for the algorithm and ADR-0007 for the rationale.

**§ "Session Continuity" / `current.yml` v2 schema** — extend the existing `touches:` field
comment to document the gate-time backfill:

> `touches` (list of glob strings) — populated by `architect` (intent at design time) and
> unioned by `coder` at each `/ssd gate` invocation (`git diff --name-only <base>...HEAD`
> unioned into the list). Used by `code-reviewer` to emit OVERLAP-N findings on cross-
> workstream file overlap (added v1.17.0; see § "Methodology Enforcement").

**Changelog entry:** v1.17.0, matching v1.16.0 tone/length.

**Version banner:** 1.16.0 → 1.17.0.

### `methodology/gate-rules.sh` edits

Minimal. Document the workstream-base pattern in a comment block near the existing `--base`
parser, noting that the orchestrator should pass `--base <ref>` explicitly when calling the
script for a non-main workstream. No default-behavior change; the script remains standalone.

Concretely: 4-6 line comment addition near `BASE="main"` declaration, citing ADR-0007.

### `code-reviewer/SKILL.md` invocation order

The new section goes BEFORE § "Severity Levels" if possible (so OVERLAP-N is defined when
severity is introduced) OR immediately after § "Severity Levels" if there's a natural seam.
Coder picks. Either is acceptable.

## Touches backfill mechanism (where does it run?)

The backfill is an orchestrator-side action that happens during `/ssd gate` BEFORE code-reviewer
runs. Sequence:

1. User runs `/ssd gate <slug>` (or `/ssd gate` with auto-detect).
2. Orchestrator resolves the workstream.
3. **NEW (v1.17.0):** Orchestrator computes `diff_paths = git diff --name-only <base>...HEAD`
   (where `<base>` defaults to the recorded workstream base or `origin/main`).
4. **NEW (v1.17.0):** Orchestrator updates `current.yml.active[<slug>].touches` =
   union(existing, diff_paths). Architect-intent paths that haven't been touched yet are
   preserved.
5. Orchestrator runs `methodology/gate-rules.sh --base <ref>`.
6. Orchestrator invokes `code-reviewer` on the diff (which now reads the updated `touches:`
   and performs the cross-workstream check).

The backfill is recorded in the workstream's `touches:` for both this gate and future gates.
A workstream's first gate may add 10 paths; the second gate adds 2 more. This builds up a
faithful record over the workstream's lifetime.

**Documentation location.** Document the backfill behavior in two places:
- `ssd/SKILL.md` § "Methodology Enforcement" — as part of what `/ssd gate` does.
- `ssd/SKILL.md` § "Session Continuity" `touches:` field comment.

Don't introduce a new section just for backfill.

## Risk assessment (iter C specific)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `git ls-files <glob>` resolves slowly on huge repos | L | L | The intersection is set-based; even 100k files resolves in <1s. Document; defer optimization. |
| OVERLAP findings flood reviews when many active workstreams overlap on common files (CHANGELOG, README) | M | M | Already mitigated: workstreams typically don't declare `touches: [CHANGELOG.md]` — only architecturally-important paths. Doc note: keep `touches:` focused on meaningful files. |
| `code-reviewer` invocations OUTSIDE `/ssd gate` (e.g., ad-hoc PR review) shouldn't read `current.yml` | M | M | Coder gates the new check on "invoked via `/ssd gate`" — adhoc reviews skip cleanly. Document the trigger conditions explicitly. |
| Backfill silently captures stray edits (CI config, formatter passes) into `touches:` | M | L | Acceptable — overlap warnings are informational, false positives at SUGGESTION tier are low-cost. Document that `touches:` is "what the workstream touched," not "what it intended to touch." |
| Workstream branch with no commits (just architect spec) → `git diff --name-only <base>...HEAD` empty → nothing to backfill | L | L | Correct behavior. Workstream's `touches:` remains architect-only until code lands. |

## Quality Gate

| Item | Status |
|---|---|
| Platform | ✓ markdown skills library; standard for this project |
| ADRs | ✓ inherited (ADR-0007); no new ADRs |
| Data model | ✓ inherited |
| API contract | ✓ this doc plus iter A's spec define the full OVERLAP-N format |
| Auth | N/A |
| Async | N/A |
| Feature flag | N/A |
| CI/CD | N/A |
| Risk assessment | ✓ |
| Scale baseline | inherited |
| Walking Skeleton deployable | ✓ ships as v1.17.0 |

## Handoff to coder

Next: implement per § "Implementation breakdown" above. Three files:
- `code-reviewer/SKILL.md` — new § "Cross-Workstream Overlap Check" with OVERLAP-N format
- `ssd/SKILL.md` — § "Methodology Enforcement" paragraph + `touches:` field comment + changelog + version banner
- `methodology/gate-rules.sh` — short comment block about workstream-base pattern

Plus the usual:
- `CHANGELOG.md` v1.17.0 entry
- `VERSION` bump
- `.ssd/features/parallel-features/iterations/c/coder-status.md`

No new scripts, no new bash logic in gate-rules.sh — just a documentation comment. All real
behavior is implemented in markdown that the LLM reads and executes.
