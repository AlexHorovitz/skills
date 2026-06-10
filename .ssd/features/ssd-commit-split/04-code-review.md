---
skill: code-reviewer
version: 1.5.0
produced_at: 2026-05-24T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: branch add-ssd-commit-split vs main (uncommitted working-tree diff + 1 new ADR + 3 new .ssd/features artifacts that the iter-A gitignore change makes trackable)
consumed_by: [coder]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 0
  suggestion: 2
  nit: 1
gate_pass: true
remediation_mode: false
round: 1
closed_from_previous_round: []
round_2_inline: true
round_2_closed: [MINOR-1]
round_2_deferred_with_assent: [SUGGESTION-1, SUGGESTION-2, NIT-1]
round_2_finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 0
  suggestion: 0
  nit: 0
round_2_gate_pass: true
---

# Iteration A — Code Review (Round 1)

## Scope verified

- **Modified tracked files:** 6 (`.gitignore`, `VERSION`, `CHANGELOG.md`, `ssd/SKILL.md`,
  `ssd-init/SKILL.md`, `methodology/gate-rules.sh`).
- **New committed:** `docs/decisions/ADR-0008-ssd-commit-split.md`.
- **New trackable (under iter A's new selective gitignore):** the 3 ssd-commit-split artifacts
  (`00-brief.md`, `01-architect.md`, `03-coder-status.md`). 16 historical artifacts under
  `.ssd/features/{parallel-features,ssd-skill-upgrades}/` ALSO become trackable but are
  **deferred to iter C** — coder's staging boundary verified below.
- **Methodology gate:** PASS / SKIP / SKIP / SKIP / PASS / SKIP — clean. The
  `no-leaky-state` rule SKIPs because the diff is uncommitted; will fire correctly post-commit.
- **Frontmatter-valid:** 13 artifacts validate.

## Verdict

🟢 **Gate passes.** Zero BLOCKER, zero MAJOR. The work is high-quality: the new gate rule is
correctly bounded (PASS/FAIL/SKIP semantics match precedent), the matcher is smoke-tested,
the migration UX preserves user agency, and the self-justifying iter A is correctly bounded
to ssd-commit-split's own artifacts (not the historical 16). The substantive critique is one
MINOR around regex-escape edge cases in `matches_deny_pattern`, plus two SUGGESTIONS and a
NIT — all defer-able.

---

## Findings

### 🟡 MINOR-1 — `matches_deny_pattern` doesn't escape regex metacharacters beyond `.`

**Where:** [methodology/gate-rules.sh — `matches_deny_pattern` function](../../../methodology/gate-rules.sh)

**Current implementation:**
```bash
regex="${regex//./\\.}"
regex="${regex//\*\*/§§}"
regex="${regex//\*/[^/]*}"
regex="${regex//§§/.*}"
regex="${regex//\?/[^/]}"
```

Only escapes `.`. Other bash regex metacharacters (`+`, `(`, `)`, `|`, `^`, `$`, `{`, `}`,
`\`) pass through unescaped. If a project supplies `gitignored_state: ["secrets+test/**"]`
in `project.yml`, the `+` is interpreted as "one or more of the preceding character" rather
than literal `+`. The match would be subtly wrong.

**Why this slipped through smoke tests.** All 8 smoke-test patterns are from the hard-coded
baseline deny-list (which is clean of these metacharacters). The user-extensible
`gitignored_state[]` slot accepts arbitrary patterns, and that's the path where this matters.

**Suggested fix.** Escape the full set of bash regex metacharacters before the glob-to-regex
conversion. Pre-glob escape pass:

```bash
# Escape all bash regex metacharacters that are literal in gitignore semantics.
# (Leaving '*', '?', and '[]' alone for the glob conversion below; gitignore's
# character classes [abc] happen to work as bash regex char classes.)
local regex="$pattern"
regex="${regex//\\/\\\\}"   # backslash
regex="${regex//./\\.}"
regex="${regex//+/\\+}"
regex="${regex//(/\\(}"
regex="${regex//)/\\)}"
regex="${regex//\{/\\{}"
regex="${regex//\}/\\}}"
regex="${regex//|/\\|}"
regex="${regex//\^/\\^}"
regex="${regex//\$/\\$}"
# Now the glob → regex conversion (** before * is critical):
regex="${regex//\*\*/§§}"
regex="${regex//\*/[^/]*}"
regex="${regex//§§/.*}"
regex="${regex//\?/[^/]}"
[[ "$path" =~ ^${regex}$ ]]
```

That's ~9 lines added. Worth doing in iter A because the rule ships to users who can
configure `gitignored_state[]` immediately.

**Why MINOR not MAJOR.** Hard-coded baseline patterns are clean; the bug only triggers on
user-supplied patterns containing these metacharacters, which is a narrow case. False
positives at the deny-list match site (wrongly flagging a file as forbidden) are recoverable
— the user adjusts the pattern or temporarily opts out. False negatives (failing to catch a
forbidden file) are bounded by the rest of the layers (gitignore itself, optional
pre-commit hook).

---

### 💡 SUGGESTION-1 — ADR-0008's "Scale Note" estimate is unverified

**Where:** [docs/decisions/ADR-0008-ssd-commit-split.md § "Scale Note"](../../../docs/decisions/ADR-0008-ssd-commit-split.md)

ADR-0008 claims: *"For a project that ships 50 features over its lifetime, ~25k–75k markdown
lines of feature artifacts. Comparable to a moderately-documented monorepo's `/docs/`.
Acceptable."* The per-feature breakdown (50–150 line brief, 200–500 line architect, etc.)
is plausible but not yet measured. This repo's own data after a few epochs would let us
either confirm or revise the estimate.

**Suggested action.** Add a `questions_for_next_session` entry in `.ssd/current.notes.yml`
to revisit the estimate ~6 months after iter A ships, using this repo's actual artifact
volume as the ground-truth sample.

**Why SUGGESTION.** Forward-looking polish; doesn't block. Same pattern as
parallel-features's SUGGESTION-2 (4-workstream ceiling).

---

### 💡 SUGGESTION-2 — Migration prompt's file-listing could be long for active projects

**Where:** [ssd-init/SKILL.md § "Migration from blanket gitignore"](../../../ssd-init/SKILL.md)

The migration UX says: *"Print a summary of files that will now be trackable
(`git ls-files --others --exclude-standard .ssd/features/`)."*

For a project that's been running on blanket for many features (say 30+ workstreams ×
4 artifacts each = 120 files), the "summary" becomes a 120-line dump that no one will read
carefully. Consider:

- Truncate to N (e.g., 20) with a `…and X more files` suffix.
- Group by feature slug: `5 files under .ssd/features/parallel-features/`.
- Or just count: `42 .ssd/features artifacts will become trackable; review with git status
  before staging.`

**Suggested action.** Add to the migration prompt prose: *"For projects with many existing
artifacts, the summary lists the first 20 with a count of any remaining."* (Implementation
deferred — orchestrator-side concern, not a script change in iter A.)

**Why SUGGESTION.** Solo developers and small projects won't hit this. Important for adoption
in larger teams; iter B's polish is the natural place to address.

---

### 📝 NIT-1 — `yaml_get_list` shares `yaml_get`'s same-named-key ambiguity

**Where:** [methodology/gate-rules.sh — `yaml_get_list` function](../../../methodology/gate-rules.sh)

If `project.yml` has multiple `gitignored_state:` keys at different nesting levels (e.g., one
under `ssd:` and one accidentally elsewhere), the function reads BOTH lists in document
order and prints all items. The pre-existing `yaml_get` (scalar reader) has the same
limitation. By convention, `project.yml` should not have duplicate keys — but bash YAML
parsing here is heuristic.

**Suggested action.** Document the convention in a comment block, OR upgrade to a proper YAML
parser via Python (already a soft dependency for `frontmatter-validate.py`). Deferred —
inherited limitation, not iter A's to fix.

**Why NIT.** Hypothetical and easily avoidable by following the documented schema.

---

## Coder's items addressed

| # | Question | Answer |
|---|---|---|
| 1 | Self-justifying iter A boundary | ✓ Verified. Coder explicitly documented the iter A vs iter C boundary in coder-status. Staging should include the 3 ssd-commit-split artifacts (00-brief, 01-architect, 03-coder-status) plus the 6 modified tracked files + ADR-0008. Excludes the 16 historical artifacts under parallel-features and ssd-skill-upgrades. Reviewer confirms this is the architect-spec-conformant boundary. |
| 2 | `matches_deny_pattern` glob conversion | See **MINOR-1** above — additional regex escaping needed for `gitignored_state[]` user patterns. Baseline patterns are safe. |
| 3 | `yaml_get_list` correctness | Correct for the documented schema. NIT-1 raises the multi-key edge case (inherited from `yaml_get`). |
| 4 | Migration UX preserves user agency | ✓ Verified. Explicit "do NOT auto-stage or auto-commit" in the prose; user controls the next commit. `.gitignore.bak` provides rollback. Three-option prompt with permanent opt-out path. |
| 5 | `gitignore_mode: blanket` opt-out path is fully wired | ✓ Verified across three signals: project.yml documents the key, ssd-init writes/respects it, `no-leaky-state` rule SKIPs cleanly with the right detail message. Consistent. |
| 6 | Retroactive `frontmatter-valid` row | Fine in iter A's scope. The new row is adjacent to the `no-leaky-state` row coder added and fills a doc gap from v1.14.0. Reviewer accepts as scope adjacent, not drift. |

---

## Substantive checks performed

| Check | Result |
|---|---|
| `--rules` filter doesn't break existing rules | ✓ Verified. Empty filter (no `--rules` arg) returns 0 immediately from `should_run`. Smoke-tested both `gate-rules.sh --base main` (all 6 rules) and `gate-rules.sh --base main --rules no-leaky-state` (only that rule). Output formats unchanged. |
| `no-leaky-state` rule SKIP semantics on `blanket` mode | ✓ Verified by reading the rule logic: reads `gitignore_mode`, defaults to `selective`, emits explicit SKIP with detail when set to `blanket`. |
| Selective `.gitignore` pattern is correctly bounded | ✓ Verified via `git check-ignore -v` on representative paths. Allow-listed artifact files are trackable; machine state files are ignored. Pattern is auditable (block-then-allow with explicit per-file rules). |
| ADR-0008 quality | ✓ Full template (Status/Context/Decision/Rationale/Consequences/Alternatives Rejected/Future Compatibility/Scale Note). Alternatives section is substantive (6 explicit rejections). Tone matches ADR-0001..0007. SUGGESTION-1 raises the scale-baseline estimate. |
| Migration UX preserves user agency | ✓ Verified — see coder's item 4 above. |
| ssd-init/SKILL.md selective pattern matches `.gitignore` verbatim | ✓ Diff'd both — identical. Symmetric pattern across init template and the actual repo's gitignore. |
| Scope discipline | ✓ Nothing from iter B (pre-commit hook) or iter C (dogfood) leaked in. The `--rules` flag landed in iter A because the iter B hook depends on it — architecturally sound dependency, documented in the architect spec § "Q4 — Pre-commit hook install mechanism." |
| Tone consistency | ✓ Matches existing SSD voice. Coder-status follows the established format. New SKILL.md prose is terse and concrete, not marketing-speak. |
| Doctrine cite in `no-leaky-state` rule | ✓ Source comment includes "ADR-0008 § 'Decision'" — same pattern as the other rules' doctrine cites. |
| Bash 3.2 compatibility | ✓ Uses `${additional[@]+"${additional[@]}"}` guard for empty-array expansion under `set -u`; `read_lines_into_array` already established this pattern (pre-existing). |

---

## Self-Verification (per code-reviewer/SKILL.md)

1. **Read actual files cited?** Yes — read the modified `.gitignore`, `methodology/gate-rules.sh`,
   `ssd-init/SKILL.md`, ADR-0008, and the coder-status end-to-end.
2. **MAJOR/BLOCKER claims traced?** N/A — zero MAJOR/BLOCKER findings.
3. **Citations correct?** Line numbers from working-tree files at review time.
4. **Stated assumptions?** Yes — MINOR-1 assumes a user could legitimately supply
   `gitignored_state[]` patterns containing regex metacharacters. SUGGESTION-2 assumes
   "large project" scenarios where the file list exceeds visual reading capacity.
5. **Sub-agents?** None.
6. **Downgraded speculative claims?** Considered making MINOR-1 a MAJOR because incorrect
   regex matching is a real correctness gap. Downgraded because (a) the baseline patterns
   are clean, (b) `gitignored_state[]` is rarely used and explicitly project-supplied (user
   controls input), (c) false-positive matches (wrongly flagging files) at SUGGESTION-tier
   severity (the rule itself is FAIL but the *finding* about the rule is just MINOR).
7. **Phase 3.5 (Fix-Introduces-Edge-Cases)?** Applied — the new `rule_no_leaky_state` adds
   defensive code (the deny-list match loop). Inventoried:
   - Empty deny-list → covered (matches nothing, PASS).
   - Empty diff → covered (SKIP).
   - blanket mode → covered (SKIP).
   - Project supplies `gitignored_state[]` with regex metacharacters → MINOR-1.
   - `yaml_get_list` finds no key → returns empty, additional[] empty, baseline still applies.
   - Bash 3.2 unset-array expansion → handled with `${additional[@]+...}` guard.
8. **Remediation mode?** No (round 1).

---

## Return-to-coder instructions

Gate passes. Coder MAY address MINOR-1 in this round (recommended; ~9 lines of regex
escaping in `matches_deny_pattern`) or defer. SUGGESTION-1 (scale baseline revisit) is a
notes-file entry. SUGGESTION-2 (file-list truncation) is iter B polish. NIT-1 is optional.

**If addressing MINOR-1 now:** simple addition before the existing glob→regex conversion.
Smoke test with a pattern containing `+` to confirm.

**Recommended:** address MINOR-1 now, defer the rest. Then stage iter-A-only files, commit,
push, open PR.

---

# Round 2 Update — 2026-05-24 (inline)

**Verdict: 🟢 GATE PASSES.** MINOR-1 closed. SUGGESTION-1, SUGGESTION-2, NIT-1 deferred with
reviewer assent.

### ✅ MINOR-1 — `matches_deny_pattern` regex-metachar escaping

Closed with **caveat-and-recovery**: the first patch (escaping all metachars including `{`
and `}`) had a bash brace-parsing bug. The substitution `${regex//\}/\\}}` parsed as
`(${regex//\}/\\})` + literal `}`, appending a spurious `}` to the regex and breaking ALL
patterns containing `.`. Caught on smoke-test re-run (3/14 cases failed including the
baseline `**/iterations/**/deferred.yml`).

**Final fix:** drop `{` and `}` from the escape list. These chars are literal in bash regex
outside `{n,m}` quantifier context, so leaving them un-escaped is safe for gitignore-style
patterns. Documented inline in the function:

```bash
# Curly braces intentionally NOT escaped: bash parameter expansion has brace-parsing
# ambiguity with `${var//\}/...}` syntax, AND bash regex treats { } as literal outside
# {n,m} quantifier context...
```

Re-tested 14 cases (baseline + 6 metachar + 3 typical gitignore). All 14/14 PASS. The
real-world risk of a user supplying `{abc}` in a gitignored_state pattern (gitignore brace
expansion isn't a thing) is essentially zero; if needed, char classes `[abc]` work as a
bash-native alternative.

### 🟡 SUGGESTION-1 — Scale baseline revisit (deferred)

Adding to `.ssd/current.notes.yml` as a `questions_for_next_session` entry for review ~6
months post-iter-A-ship.

### 🟡 SUGGESTION-2 — Migration file-list truncation (deferred to iter B)

Iter B's polish work is the natural place. The orchestrator's `ssd-init` invocation can add
the truncation in iter B alongside the pre-commit hook documentation.

### 📝 NIT-1 — `yaml_get_list` same-name key ambiguity (deferred)

Inherited from `yaml_get`. Documented in the function comments. Acceptable per the
"project.yml has documented schema" convention.

## Post-round-2 gate-rules.sh

```
PASS wip-commits :: no WIP/checkpoint commits between main and HEAD
SKIP tests-pass :: no test_command in .ssd/project.yml
SKIP feature-flag-present :: no feature_flag_marker
SKIP adr-delta :: no diff vs main (uncommitted)
PASS frontmatter-valid :: 14 artifact(s) validated against schemas
SKIP no-leaky-state :: no diff vs main (uncommitted)
exit: 0
```

## Self-verification (round 2)

1. MINOR-1 closure verified against the diff? Yes — re-read the function, smoke-tested 14
   cases (including the regression that the first fix introduced, now fixed).
2. New regressions from the round-2 edit? The first fix DID introduce a regression
   (caught by re-running the smoke test). Lesson: always re-run smoke tests after a fix,
   not just verify the new behavior. The final fix (drop `{}` escape) passes ALL cases.
3. `closed_from_previous_round` accurate? Yes — `round_2_closed: [MINOR-1]`; the three
   deferred items are in `round_2_deferred_with_assent`.

**Gate decision: PASS.** Iter A ready to ship as v1.18.0. Coder may proceed with selective
staging (3 iter-A artifacts + 6 modified + ADR-0008), commit, push, open PR.
