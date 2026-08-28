---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: working-tree diff on add-ssd-private-mode (16 paths) + 03-coder-status.md
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 2
  minor: 2
  question: 1
  suggestion: 1
  nit: 1
gate_pass: false
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — ssd-private-mode (iteration A), round 1

**Verdict: `gate_pass: false` — 2 MAJOR.** Both are platform/contract defects in code the coder
phase's own dogfood could not have caught, because the dogfood ran on macOS with a
`selective`-shaped `project.yml`. Neither is a design problem: §5, §6, and §7 of the architect spec
hold up, and the deadlock fix is correct and verified. The MAJORs are in the *seams*.

**Cross-workstream overlap check: skipped.** `current.yml.active[]` has one entry; the check
requires more than one.

## Phase 1 — context

Read [00-brief.md](00-brief.md), [01-architect.md](01-architect.md), and
[03-coder-status.md](03-coder-status.md). Round 1; not a remediation branch, so Phase 1.5 does not
apply. `spec_drift: true` is declared with both drifts amended into the spec — verified by reading
§6 and §8 of the architect spec, where both amendments are present and dated.

Phase 3.5 (Fix-Introduces-Edge-Cases) is the operative phase here: nearly every line in this diff is
a new defensive branch (`mode == "private"`), and the review below treats each as new code rather
than as "the fix." That is where both MAJORs came from.

---

## 🟠 MAJOR-1 — `file_mtime` flag order emits garbage on GNU/Linux; `adr-delta` FAILs on every private Linux project

[methodology/gate-rules.sh:177-179](../../../methodology/gate-rules.sh#L177)

```bash
file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo ""
}
```

The BSD form is tried **first**. Verified on this machine:

| Invocation | Platform | rc | stdout |
|---|---|---|---|
| `stat -c %Y f` | BSD (macOS) | 1 | **empty** — clean failure |
| `stat -f %m f` | BSD (macOS) | 0 | `1787923268` |
| `stat -f %m f` | **GNU** | non-zero | **filesystem info block** |

On GNU coreutils `-f` is `--file-system`, so `stat -f %m "$1"` parses as *two operands*: a file
literally named `%m` (fails) and the real path (succeeds, printing a filesystem status block to
**stdout**). Because one operand failed, the exit status is non-zero, so `||` fires and
`stat -c %Y` runs too — but the garbage has already been written. `mt` becomes a multi-line string,
and at [gate-rules.sh:428](../../../methodology/gate-rules.sh#L428):

```bash
[[ "$mt" -ge "$base_epoch" ]] && rcount=$((rcount + 1))
```

`[[ garbage -ge N ]]` raises an arithmetic error (stderr, non-zero), the `&&` never fires, `rcount`
stays `0`, and `adr-delta` emits **FAIL** on every private project on Linux — including CI runners,
which are overwhelmingly Linux.

**This is the same defect class as the `find -newermt` bug the coder phase caught, on the opposite
platform.** That bug was masked by a GNU-compatible `find` shim; this one is masked by developing on
macOS. The lesson the coder-status drew — "the design phase asserted this mechanism from knowledge;
the test caught it" — did not go far enough: the *replacement* mechanism was also asserted from
knowledge, and the fixture only ever runs on one platform.

**Ordering alone is not a sufficient fix.** Reversing to GNU-first is necessary (BSD fails `-c`
cleanly, verified above) but leaves the probe trusting whatever lands on stdout. Validate the output
is a bare integer before using it, so no `stat` variant on any platform can have its output mistaken
for a timestamp:

```bash
file_mtime() {
  local v
  v=$(stat -c %Y "$1" 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; return; }
  v=$(stat -f %m "$1" 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; return; }
  echo ""
}
```

The `unreadable` counter at [gate-rules.sh:424](../../../methodology/gate-rules.sh#L424) then does
its job: an empty return becomes an honest `SKIP … mtime unreadable`, never a false FAIL.

Add a fixture asserting `file_mtime` returns a bare integer — that is the platform-independent part
of the contract and the only piece testable from one OS.

---

## 🟠 MAJOR-2 — private mode silently drops `gitignored_state`, contradicting documentation added in this same diff

[methodology/gate-rules.sh:574-586](../../../methodology/gate-rules.sh#L574)

The private branch builds its deny-list from `private_baseline` alone. The selective path below it
unions the project's own patterns at [gate-rules.sh:612](../../../methodology/gate-rules.sh#L612):

```bash
done < <(yaml_get_list "$PROJECT_YML" "gitignored_state")
```

The private branch `return`s before ever reaching that. So a private project declaring

```yaml
ssd:
  gitignore_mode: private
  gitignored_state: [".env.local", "secrets/**"]
```

gets **no enforcement on those patterns at all** — silently.

This contradicts the contract as documented, including the `enforcement.md` row **added in this very
diff** ([ssd/chapters/enforcement.md:22](../../../ssd/chapters/enforcement.md#L22)), which states the
rule denies the deny-list *"plus project-supplied `project.yml.ssd.gitignored_state`"*. The
`project.yml` template comment likewise promises *"additive only — projects cannot shrink the
baseline."* Both remain true for `selective` and false for `private`.

Severity is MAJOR, not MINOR, for three compounding reasons:

1. It is **silent**. No SKIP, no warning — the patterns simply never match.
2. It removes the documented user extension point in **the one mode where this rule is
   load-bearing**. ADR-0017 and the chapter both argue that under `private`, `no-leaky-state` is the
   primary enforcement of the privacy boundary; `gitignored_state` is how a user extends that
   boundary to their own secrets.
3. It is **the same failure shape as H1**, the hazard this whole workstream was organized around: a
   mode-specific branch that quietly narrows what a safety rule checks. Reintroducing it one screen
   below the fix is the finding this review most needed to catch.

Fix: hoist the `additional` read above the mode branch and union it into `private_baseline`, or read
it inside the private branch. One factored deny-list assembly for both modes is preferable to two
call sites that can drift — the drift being exactly what happened here.

---

## 🟡 MINOR-1 — `feynman-clean` worktree glob is broader than the diff-scoped patterns it replaces

[methodology/gate-rules.sh:820](../../../methodology/gate-rules.sh#L820)

Worktree scope (private mode):

```bash
find …/.ssd/features …/.ssd/milestones …/docs/audits \( -name 'feynman.md' -o -name 'feynman-*.md' \)
```

Diff scope (every other mode), unchanged below it:

```bash
.ssd/features/*/feynman.md|.ssd/milestones/*/feynman.md|docs/audits/feynman-*.md
```

The `feynman-*.md` pattern is applied to **all three** directories under worktree scope, but only to
`docs/audits/` under diff scope. So `.ssd/features/auth/feynman-draft.md` or
`.ssd/milestones/m1/feynman-old.md` — a draft, a backup, a superseded report — is picked up under
private mode and, if it carries `contradicted: 2`, **FAILs the gate**, while the identical file is
ignored on a selective project.

The two scopes should recognize the same artifact set; the mode should change *where the rule looks*,
not *what counts as a report*. Restrict `feynman-*.md` to `docs/audits/` and match only bare
`feynman.md` under `.ssd/`, mirroring the case patterns exactly.

---

## 🟡 MINOR-2 — `apply_gate_inputs_present` private branch omits the `^ssd:` guard both sibling appliers use

[methodology/migrate.sh:302](../../../methodology/migrate.sh#L302)

The new private branch calls `insert_under_ssd "$pj"`, whose awk inserts only after a line matching
`/^ssd:/`. With no `ssd:` block the awk prints the file unchanged, the insert **no-ops**, and the
function still `return 0`s.

Both sibling appliers guard for exactly this ([migrate.sh:220](../../../methodology/migrate.sh#L220)
and [:234](../../../methodology/migrate.sh#L234)):

```bash
grep -qE '^ssd:' "$pj" || return 1
```

Traced the consequence rather than assuming it: the caller is
`apply_dispatch "$id" && detect "$id"` ([migrate.sh:493](../../../methodology/migrate.sh#L493)), so a
no-op insert surfaces as `ERROR :: apply ran but convention still absent — inspect manually`. **Not
silent** — which is why this is MINOR and not MAJOR. But it degrades an actionable failure into a
vague one, and it is gratuitously inconsistent with the two functions immediately above it. Add the
guard.

---

## 💭 QUESTION-1 — pre-existing: a commented placeholder can never satisfy `detect`, so "no test framework detected" always reports ERROR

`apply_gate_inputs_present` writes `# test_command: <cmd>` when no framework is detected, then
returns 0. `detect gate-inputs-present` deliberately does **not** match commented keys (documented at
[migrations.yml](../../../methodology/migrations.yml): *"A commented placeholder is intentionally NOT
a match"*). So `apply_dispatch && detect` fails and the entry reports `ERROR` rather than something
like "PENDING — no test framework detected; placeholder written."

**This predates the diff** — it is reachable on `selective` at v2.7.0 — and the private branch merely
inherits the shape. Flagging so it is on the record, not asking this workstream to fix it. Worth its
own issue.

---

## 💡 SUGGESTION-1 — the mirror fixture cannot catch the failure mode it exists to prevent

`deny-list-mirrors-pattern-file` asserts the four *current* entries appear in both
`gate-rules.sh` and `private.gitignore`. It is a spot-check of known values, not a mirror test: adding
a fifth pattern to one file only leaves the fixture green, because the fixture never learns about the
fifth. The coder-status names this limitation honestly, which is good, but the risk table rates
pattern/deny-list drift M×H — the second-highest in the design.

Stronger and not much harder: parse the non-comment, non-negation lines out of `private.gitignore`
and assert **set equality** against the `private_baseline` array extracted from `gate-rules.sh`. Then
adding a pattern to one side fails the suite by construction. Not blocking — MAJOR-2 shows the real
drift risk is between *code paths*, not between these two files.

---

## 📝 NIT-1

Two comment lines at [gate-rules.sh:818-819](../../../methodology/gate-rules.sh#L818) sit at the end
of the `while` body, immediately before `done`, but describe the `find` in the `done < <(…)`
redirect. Syntactically fine, reads as misplaced. Move above the `while`.

---

## What I verified and did not flag

Checked deliberately, found correct — recorded so the next reviewer need not redo it:

| Claim | How verified |
|---|---|
| `adr-delta` deadlock is genuinely fixed | Read both rule bodies; re-ran the dogfood: 254 arch lines + untracked ADR → `PASS`, gate exit 0. Correct **on macOS** — MAJOR-1 is why that qualifier matters. |
| `frontmatter-valid` needs no change | Read the rule: the `.ssd/` grep yields empty under private, falling to the existing no-diff branch that walks the tree. Confirmed by the dogfood's "1 artifact(s) validated". Not an assumption. |
| Unrecognized-mode FAIL precedes the no-diff SKIP | Read the order. A config typo FAILs even on a clean tree — louder than spec'd, and correct. |
| `blanket` still SKIPs | Fixture `unrecognized-gitignore-mode` asserts both arms. The loud error is scoped to *unrecognized* values only. |
| `matches_deny_pattern` handles bare dir prefixes | Trailing-slash branch is prefix-match; `.ssd/` matches `.ssd/features/x/00-brief.md`. Same mechanism the pre-existing `.ssd/archive/` entry uses. |
| No `!` negation in `private.gitignore` | Fixture asserts `grep -qE '^[[:space:]]*!'` finds nothing. This is the mechanical expression of the no-committed-`gate.yml` decision. |
| Step 5.5 detection order | private → selective → blanket, documented as load-bearing with the reason (a private `.gitignore` also contains a bare `.ssd/`). Correct and non-obvious. |
| `emit` prefix change is scoped | `REFUSED` only when `state == refused`; JSON path untouched; `needs-confirm` keeps `OK`, so the close-lifecycle fixtures are unaffected — all 83 prior assertions pass. |
| Relative link depths | Spot-checked `ssd/chapters/*` (`../../`), `ssd-init/` (`../`), README/CHANGELOG (root). The off-by-one class that produced a MAJOR in `ssd-skill-chapter-split` is not present. |
| `set -e` interaction in `detect()` | `migrate.sh` is `set -uo pipefail`, no `-e`, so `is_private_mode && return 0` falling through to the next line is safe. Checked because it would have been a silent mis-detection. |
| `touches` lists two unmodified iter-B files | Confirmed `chapters/workstreams.md` and `migrations.yml` are unchanged. Coder flagged this pre-emptively; correct, and not a finding — `touches` is epic-level intent. |

## Scope discipline

Iteration A does not run `git rm --cached` anywhere in the diff — confirmed by grep. The §8 boundary
rationale is honored, and it is the right call: the destructive operation gets its own review cycle.

## Required to close

MAJOR-1 and MAJOR-2 must be fixed. MINOR-1 and MINOR-2 should be — both are small and in files
already open. SUGGESTION-1 is optional; QUESTION-1 is out of scope and belongs on its own issue.

Round 2 must verify each closure against the code, not against a claim.
