---
skill: coder
version: 1.3.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: ssd-profile-audit
consumed_by: [code-reviewer]
files_touched:
  - ssd/SKILL.md
  - architect/SKILL.md
  - methodology/SKILL.md
  - refactor/SKILL.md
  - systems-designer/SKILL.md
  - coder/SKILL.md
  - code-reviewer/SKILL.md
  - codebase-skeptic/SKILL.md
tests_added: []
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: "PASS — 16/16 assertions"
lint_results:
  command: "python3 methodology/frontmatter-validate.py --check-skill-examples ."
  exit_code: 0
  stdout_tail: "8 PASS (all bumped banners match their frontmatter examples), 2 SKIP (methodology: no example; ssd: placeholder)"
type_check_results:
  command: "bash methodology/gate-rules.sh --base main"
  exit_code: 0
  stdout_tail: "all rules PASS/SKIP; skill-version-sync PASS (8 examples match banner)"
feature_flag:
  name: not_applicable
  default: off
spec_drift: false
---

# Coder Status — ssd-profile-audit (R9 → v1.20.0)

Implemented [01-architect.md](01-architect.md) per [ADR-0010](../../../docs/decisions/ADR-0010-profile-aware-subskills.md).
Markdown skills library — the "code" is SKILL.md prose. No runtime, so the test/lint/typecheck slots
above are filled by the library's actual mechanical checks (parity-test, frontmatter example/banner
consistency, gate-rules).

## What was built (build order per the spec)

1. **`ssd/SKILL.md`** — new § "Profile-aware sub-skill behavior" table (7 rows) + normative invariant
   guarantee, after the existing orchestrator "Profile-aware defaults" table. Banner 1.19.1 → 1.20.0
   + changelog. (ssd example is a `<skill-version>` placeholder, so `skill-version-sync` SKIPs it —
   the banner bump doesn't need an example sync.)
2. **Invariant notes** (3 skills): one-line "Profile stance: invariant" blockquote after Purpose +
   banner/example bump + changelog —
   - `architect` 1.2.0 → 1.2.1 (design rigor is absolute)
   - `methodology` 1.6.0 → 1.6.1 (score is absolute; no frontmatter example to sync)
   - `refactor` 1.2.1 → 1.2.2 (plan is substance; verbosity is the orchestrator's)
3. **Profile-aware sections** (4 skills): `## Profile-Aware Behavior` (knob + novice/standard/expert
   delta + invariant guarantee + single-source pointer) + banner/example bump + changelog —
   - `systems-designer` 1.3.0 → 1.4.0 — checklist depth
   - `coder` 1.2.0 → 1.3.0 — `# REVIEW:` marker density
   - `code-reviewer` 1.5.0 → 1.6.0 — MINOR/NIT reporting (BLOCKER/MAJOR always inline; gate_pass profile-independent)
   - `codebase-skeptic` 1.2.1 → 1.3.0 — voice breadth (+ milestone/pre-release full-breadth carve-out)

`VERSION`/`CHANGELOG.md` left for release time per the spec (step 4).

## Notes for the reviewer

- **Invariant guarantee is load-bearing** (ADR-0010 guarantee #2). Each aware skill states explicitly
  that profile never suppresses gate-critical output: code-reviewer keeps BLOCKER/MAJOR inline and
  `gate_pass` profile-independent; codebase-skeptic never suppresses 💀/🔴 severity; systems-designer
  keeps safety-critical gates at every profile; coder halts handoff on genuine blockers at every
  profile. Please verify these clauses against the spec — they are the correctness boundary.
- **codebase-skeptic novice ≤4-voice concern** (raised at design review): resolved with a normative
  **scope exception** — milestone/pre-release audits (this skill's primary use per § "Review Tier
  Selection") run full relevant-voice breadth regardless of profile. The novice cap applies only to
  lighter ad-hoc reviews. Reviewer: confirm this is a sufficient guard against "a voice that didn't
  run can't catch its issue."
- **`refactor` called invariant** (the refactor-plan had it "maybe branch"): deliberate per ADR-0010
  — only verbosity would differ, which is the orchestrator's narration knob, not a 4th aware skill.
- **spec_drift: false** — implementation matches ADR-0010's 3-invariant/4-aware split and the
  architect's table verbatim.
- **No feature flag** — markdown docs, no runtime path to flag. Ships atomically as v1.20.0; the
  `standard`-is-baseline guarantee is the de-facto safety mechanism (existing users see no change).

## Verification run
- `bash scripts/parity-test.sh` → 16/16 PASS.
- `python3 methodology/frontmatter-validate.py --check-skill-examples .` → 8 PASS / 2 SKIP, exit 0.
- `bash methodology/gate-rules.sh --base main` → all PASS/SKIP, `skill-version-sync` PASS.
