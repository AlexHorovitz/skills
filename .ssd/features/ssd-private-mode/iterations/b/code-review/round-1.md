---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: working-tree diff on add-ssd-private-mode-b (13 paths) + iterations/b/coder-status.md
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 2
  minor: 2
  question: 0
  suggestion: 1
  nit: 0
gate_pass: false
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — ssd-private-mode#b, round 1

**Verdict: `gate_pass: false` — 2 MAJOR.** Both live in `elect_private_mode`, the one destructive path
in `migrate.sh`, and both were found by feeding it a filename the fixtures never try. The design holds
up: the elective concept, the two-layer sweep guarantee, and the dry-run inversion are all correct and
verified. The defects are in what happens when the *input* is unusual.

No `deferred.yml` for this iteration (verified absent) → the deferred-findings phase does not apply and
`deferred_handled` is correctly omitted.

**Cross-workstream overlap check: skipped.** One active workstream.

Phase 3.5 is the operative phase — nearly every line in this diff is new destructive or defensive code.
Both MAJORs came from it.

---

## 🟠 MAJOR-1 — `git ls-files` C-quotes unusual paths; the retrofit then fails outright

[migrate.sh `tracked_ssd_paths`](../../../../../methodology/migrate.sh)

`git ls-files` does **not** emit raw paths. Any path containing non-ASCII bytes (and other specials) is
returned **C-quoted**. Reproduced on a scratch repo:

```
$ git ls-files -- .ssd docs/decisions
.ssd/features/quote'name.md
.ssd/project.yml
docs/decisions/ADR-0001-with space.md
"docs/decisions/ADR-0002-h\303\251llo.md"        ← quoted + octal-escaped
```

Three consequences, in increasing severity:

1. **Misclassification.** The quoted string starts with `"`, so it cannot match
   `docs/decisions/ADR-*.md`. A legitimate ADR is reported under "UNCONFIRMED as SSD-produced."
2. **The frontmatter probe cannot run.** `[[ -f "$ROOT/$pth" ]]` is false for the quoted string, so
   signal 3 is silently unavailable for exactly the files that need it most.
3. **`git rm --cached` fails completely.** Verified:

```
fatal: pathspec '"docs/decisions/ADR-0002-h\303\251llo.md"' did not match any files
migrate: git rm --cached failed; configuration was written but paths remain tracked.
rc=3
```

`git rm` validates all pathspecs before acting, so **nothing** is untracked. A single non-ASCII
filename anywhere under the four SSD roots makes the retrofit impossible, and the error message names
git's complaint rather than the cause.

Spaces and apostrophes happen to survive (they are not quoted, and `read -r` + `"$pth"` handle them),
so the failure is *narrow but not exotic* — an accented word in an ADR title is enough. `docs/` in a
non-English project would hit this immediately.

**Fix:** enumerate NUL-delimited, which disables quoting entirely:

```bash
tracked_ssd_paths() { git -C "$ROOT" ls-files -z -- "${SSD_TRACKED_ROOTS[@]}" 2>/dev/null; }
# consumers: while IFS= read -r -d '' pth; do … done < <(tracked_ssd_paths)
```

Verified `-z` returns the raw path (`docs/decisions/ADR-0002-héllo.md`). Note this changes the
function's contract from newline- to NUL-delimited, so the sort, both classifier loops, the `rm`
array, and the re-verify all move together — and `sort` needs `-z`.

---

## 🟠 MAJOR-2 — configuration is written before the destructive step is validated, so a failure leaves a half-migrated repo

[migrate.sh `elect_private_mode`](../../../../../methodology/migrate.sh) — the `--confirm` branch
calls `apply_private_mode_config` **first**, then `git rm --cached`.

When the `rm` fails (MAJOR-1 is one trigger, but any pathspec or permission problem does it), the repo
is left in a state that neither mode describes:

```
config:  gitignore_mode: private        ← written
pattern: # ssd:gitignore-mode=private   ← written
tracked: every SSD artifact              ← unchanged
```

This is a distinct defect from MAJOR-1, not a symptom of it: **the destructive step is the only thing
that can fail, and it runs last, after the irreversible-looking writes.** Fixing the quoting removes
one trigger; the ordering hazard remains for every other.

**The mitigation is weaker than the coder-status implies.** I checked whether the gate makes this state
loud, and it is *conditional*:

```
SKIP no-leaky-state :: no diff (vs main)
```

`no-leaky-state` is diff-scoped, so on a repo with nothing committed since the base it **SKIPs** and the
half-migrated state is invisible. It FAILs only once there is a diff. So "loud" is true sometimes, not
by construction.

**Fix:** pre-flight the destructive step before mutating anything. `git rm` supports `--dry-run`
(verified: `git rm --cached --dry-run -- README.md` → `rm 'README.md'`, index untouched):

```bash
git -C "$ROOT" rm --cached --dry-run -q -- "${arr[@]}" || {
  echo "migrate: cannot untrack the enumerated paths; nothing has been changed." >&2
  return 3
}
apply_private_mode_config || return 3
git -C "$ROOT" rm --cached --quiet -- "${arr[@]}" || return 3
```

Then a pathspec problem aborts with the repo **untouched**, which is what a user who ran a migration
expects from a failure. Keep the existing post-`rm` re-verify — it guards the remaining window.

---

## 🟡 MINOR-1 — `set_yaml_scalar` is unscoped, reintroducing a defect class already hardened next door

[migrate.sh `set_yaml_scalar`](../../../../../methodology/migrate.sh) rewrites the **first** indented
`<key>:` line anywhere in the file. Twelve lines below it, `bump_recorded_version` carries this comment:

> *Scoped to the `ssd:` block (**review MINOR-2**): only the indented `version:` BETWEEN `^ssd:` and the
> next top-level key is rewritten, so a nested `version:` under an earlier block in a consuming
> project's file can't be hit by mistake.*

That scoping exists because a prior review demanded it. The new helper has none, and is used for keys in
**two different scopes**:

- `gitignore_mode`, `branch_pattern` — under `ssd:`. No collision in today's template.
- `issue_tracking` — under a **list item** inside `integrations:`. The current `ssd-init` template gives
  it only to the `- type: github` entry, so first-match happens to be right. Add `issue_tracking` to the
  jira entry (or reorder the list) and the migration silently rewrites the wrong integration.

Not a demonstrated failure today, hence MINOR — but it is the same class of latent bug this file already
paid a review round to fix, and `issue_tracking`'s list-item scope makes the assumption genuinely
fragile rather than theoretically so. Either scope the helper (block-aware, like its neighbour) or take
a scope argument.

---

## 🟡 MINOR-2 — no fixture exercises an unusual filename, which is exactly why MAJOR-1 shipped

Ten new fixtures, all using ASCII names (`00-brief.md`, `ADR-0001-a.md`, `app.py`). The interlock's job
is to enumerate *whatever is actually in the repo*, and the suite never tests a path git would quote.

This is the coverage gap that let a total-failure bug through a red-first, reversion-verified test pass.
The coder-status is rightly proud of the red-first discipline — and MAJOR-1 shows that red-first on the
*cases you thought of* is not the same as coverage. Add a fixture with a non-ASCII path (and keep the
space and apostrophe cases, which currently pass and should stay passing).

---

## 💡 SUGGESTION-1 — `--confirm` is global but inert outside `--elect`

`--confirm` is parsed unconditionally, so `migrate.sh --apply --confirm` is accepted and silently does
nothing. Harmless, but a user who reads "confirm" as "yes, really apply" gets no feedback that the flag
had no effect. Either reject `--confirm` without `--elect`, or note in `--help` that it only qualifies
`--elect`. Non-blocking.

---

## What I verified and did not flag

| Claim | How verified |
|---|---|
| The elective entry is inert in the default sweep | Reproduced on a team repo: full-window `--apply` left the index byte-identical and the mode `selective` |
| The two-layer guarantee is real | Reverted each layer separately: the `continue` alone → 3 assertions fail; `continue` + dispatcher registration → 4 more. The coder-status's claim is accurate |
| The `\x1f` delimiter fix is correct and pinned | Reverted to tab → `read-manifest-empty-middle-field` fires. The fixture tests the observable symptom, so a future delimiter change stays free |
| `elect-dry-run-mutates-nothing` is a real test now (it passed vacuously pre-implementation) | Made the dry-run call `apply_private_mode_config` → 3 assertions fire |
| Idempotent re-run | `--confirm` twice → "already private; nothing to do", exit 0, pattern block not duplicated |
| Files survive on disk | Confirmed after `--confirm`: every untracked artifact still present |
| `issue-sync` refuses post-retrofit | `REFUSED … exit 4`, measured without a pipe |
| Empty-array handling under `set -u` | `printf '%s' "${owned[@]}"` is guarded by `${#owned[@]} -gt 0` in both branches |
| Empty enumeration | `<<< ""` yields one empty line; the `[[ -z "$pth" ]] && continue` handles it |
| `backup_pj` overwrites an existing `.bak` | Pre-existing behavior of a shared helper, not introduced here. Not a finding for this diff |
| Exit codes | 0 / 2 / 3 / 10 all reachable and correct; 10 matches `issue-sync.sh`'s needs-confirm convention |

**Scope discipline:** `parse_active_workstreams` and QUESTION-2 remain untouched — correct under hard
rule 4, and notable restraint given QUESTION-2 lives in the very file this iteration rewrites.

## Self-verification

Read every function I cite. Both MAJORs were established by **execution** — I built a repo with an
accented filename and watched `git rm` fail and the config persist — not by reading. The one claim I
initially assumed and then checked was the coder-status's implication that a half-migrated state would
be loud; it is only conditionally loud, and MAJOR-2 says so rather than repeating the assumption. No
sub-agents, so no unverified escalation.

## Required to close

MAJOR-1 and MAJOR-2 must both be fixed, and the fix for MAJOR-2 should be independent of MAJOR-1's
(pre-flight validation protects against every failure cause, not just quoting). MINOR-1 and MINOR-2
should be. SUGGESTION-1 is optional.

Round 2 must verify each closure against the code, and MINOR-2's fixture must be seen to fail against
the unfixed enumerator.
