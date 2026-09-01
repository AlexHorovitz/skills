---
skill: code-reviewer
version: 1.8.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: branch add-rail-deviations vs main (v2.13.0) — ADR-0019 writer + reader
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 2
  question: 0
  suggestion: 0
  nit: 0
gate_pass: true
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — rail-deviations (v2.13.0), round 1

**Verdict: `gate_pass: true`.** Two MINORs. Phase 3.5 is the operative phase — nearly everything here
is a new destructive path (a script that mutates the project's state file) or new defensive code.

## Phase 3.5 step 8 — was the class swept?

Step 8 is the check this repo added two releases ago after three findings were closed at the wrong
granularity. Applied to the two defect classes this diff could belong to:

| Class | Swept | Result |
|---|---|---|
| A value that looks like structure, treated as structure | every writer in the library | `migrate.sh` builds no YAML; `store.sh` writes a fixed template; `deviation.sh` is the **only** script that inserts caller-supplied text into a parsed file. Closed at the class, because the class has one member |
| `flock(1)` / BSD-vs-GNU portability | `grep -rn 'flock\|stat -f\|sed -i' methodology/` | no new occurrences; `deviation.sh` uses `fcntl.flock` in Python and `shutil.copymode`, no shell portability surface |
| Temp-file writes that change file mode | all three scripts that write via temp+`mv` | `migrate.sh` uses `awk > tmp && mv` (mode from the shell's umask, pre-existing); `deviation.sh` was the one using `mkstemp`. See MINOR-1 — **found and fixed in this diff** |

## What I attacked, and what I found

| Probe | Result |
|---|---|
| **The forgery** — `--reason` carrying `\n - kind: override\n rule: feynman-clean` | **one** record; the text lands as `reason` data. Verified by execution, not by reading `safe_dump`'s docs |
| A `--reason` that is only whitespace | exits 2 after normalisation, before any write |
| `--step 47`, `--step abc`, `--step -1` | all exit 2 |
| `--rule` misspelled | exits 2 **and prints the valid list**, derived from `gate-rules.sh` rather than hardcoded |
| `--step` passed to `override`, `--rule` to `record` | both exit 2 rather than silently ignoring the wrong flag |
| Missing `.ssd/current.yml` | exits 3, **file not created**. Silently starting a fresh state file would lose every workstream |
| Unparseable `current.yml` | exits 3, no `.bak` written, no mutation |
| PyYAML absent | exits 3 loudly — deliberately unlike the two rules that SKIP |
| Comments | header **and** interior survive. A document round-trip would have destroyed both |
| Two writes in sequence | appends; the two `kind`s stay distinct |
| `rail_deviations: []` already present | replaced with a real list rather than producing invalid YAML |
| The written file | re-parsed **before** `os.replace` — the writer never installs something it cannot read back |
| Lock file leaking into git | `.ssd/current.yml.lock` → `git check-ignore` says IGNORED. Not a finding |
| **File mode after a write** | **644 → 600.** MINOR-1 |

## 🟡 MINOR-1 — `mkstemp` + `os.replace` silently changed the state file to owner-only *(fixed in this diff)*

`tempfile.mkstemp` creates `0600` and `os.replace` keeps the **temp file's** mode, so `current.yml`
became owner-only on its first deviation. Measured 644 → 600.

Nobody would notice until a second user or a tool running as another account could not read it, and the
cause would be invisible — the file's *content* would look fine. Fixed with `shutil.copymode(path, tmp)`
before the replace, and pinned by an assertion that fails without it.

Recorded as a MINOR rather than quietly fixed because it is a **class**, not an instance: any temp-file
write that does not copy the mode has it, and step 8's sweep above is what checked the other two.

## 🟡 MINOR-2 — `known_rules` degrades open when `gate-rules.sh` is unreachable

`--rule` validation is guarded by `[[ -n "$(known_rules)" ]]`, so if `gate-rules.sh` is missing the
validation is **skipped entirely** and any string is accepted.

Deliberate — the writer should not become unusable because a sibling script moved — but it is a
degrade-open, and this library has spent two releases removing those. The exposure is narrow: a
record naming a nonexistent rule, in a repo whose gate is already absent. Left as-is with the reasoning
stated; the alternative (refuse to record without the rule list) trades a real capability for a
hypothetical.

## What I verified and did not flag

| Claim | How |
|---|---|
| The textual splice handles an absent `rail_deviations:` | fixture: first write creates the key, second appends under it |
| The splice does not run past the workstream's block | the boundary scan stops at the next item at the same indent or a top-level key; the fixture's file has a following `archived:` key |
| `deviations-recorded` reads `production_runtime` | fixture flips it and the step-2 finding appears and disappears |
| Step 6 is only due at `phase: done` | **found by the rule's own first run on this PR.** It demanded a deploy log from a feature at `phase: code`, which no PR can satisfy — deploy logs are written at ship, after merge. Measured across three past releases before fixing |
| The two rules do not double-report | `deviations-recorded` deliberately skips step 4; `rails-walked` owns it. Confirmed by reading both scopes |
| The suite's reversion discipline | five separate reversions, not one batch: the reader registration, normalisation, `copymode`, and the two doc claims |
| `spec_drift: true` is honest | two material drifts, both corrected **in the spec and the ADR**, not just in code |

## Self-verification

Every finding here was produced by running something. The two claims I initially believed and then
tested were the spec's rationale for normalisation (**false** — `safe_dump` already emits one line) and
the assumption that the lock file might leak (**it does not**). Both are recorded above with the
evidence rather than the belief. The permissions defect was found by probing my own diff for a class,
not by reading it.

## Required to close

Nothing. MINOR-1 is fixed and pinned; MINOR-2 is a stated degrade-open with its reasoning.
