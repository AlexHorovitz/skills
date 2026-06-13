---
skill: code-reviewer
version: 1.6.0
produced_at: 2026-06-13T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: branch add-ssd-upgrade vs main (ssd-upgrade iter A — read-only drift report)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 1
  question: 1
  suggestion: 0
  nit: 1
gate_pass: true
remediation_mode: false
round: 2
closed_from_previous_round: [MINOR-1]
---

# Code Review — ssd-upgrade iter A (`/ssd upgrade` read-only)

Feature work, round 1. Reviewed against [01-architect.md](01-architect.md) + [ADR-0013](../../../docs/decisions/ADR-0013-project-upgrade-migration-manifest.md).
Diff: 8 files, +705/-5. The substance is `methodology/migrate.sh` (126 lines bash+awk) + the manifest.

## Phase 2 — design/approach
Matches ADR-0013: manifest = metadata, executable probes = per-`id` dispatch in `migrate.sh`,
dry-run/detect-only. The iteration cut (read-only first) is the right Walking-Skeleton slice — it
delivers the drift report with **no write path**, so the corruption risk (ADR-0013 R1) cannot fire.

## Phase 3 — detailed review (verified by tracing + running)

**(2) Genuinely read-only?** ✅ Confirmed by scan: no `>`/`>>`/`sed -i`/`git` mutation/`tee`/`mv`/`rm`
in `migrate.sh` (the only matches are doc-comments and the read-only `git rev-parse --show-toplevel`).
`--apply` exits 2 before any action. R1 cannot fire in iter A.
**(1) `ver_gt`** — equal short-circuits to "not greater" (`[[ $1 == $2 ]] && return 1`); the
`sort -t. -k1,1n -k2,2n -k3,3n | tail -1` correctly orders real semver (verified `1.18.0 > 1.4.0`,
which a string sort gets wrong). Correct for 3-component versions (see QUESTION-1).
**(1) awk parser** — `val()` strips `^[^:]*:[[:space:]]*` (the *key's* first colon only), so values
containing `: ` are preserved; quote-stripping correct. Robust for the controlled manifest format.
**(1) JSON** — `python3 json.load` parses the output (zero-entry and multi-entry); separator logic
(`emitted` flag) produces valid arrays. ✓
**(1) `set -uo pipefail`** — no `set -e` (matches `gate-rules.sh`), so `detect`'s expected nonzero
exit doesn't abort; `${2:-}` guards arg reads; process-substitution loop is safe. ✓
**(3) manifest↔dispatch** — all 4 project-scoped *mechanical* ids (`current-yml-v2`,
`dev-profile-keys`, `parallel-features-keys`, `selective-gitignore`) have `detect()` cases; the
`guided` id (`decision-record-doctrine`) is handled before `detect` and needs none; unknown id →
`return 1` (PENDING, safe default). ✓
**(4) ssd/SKILL.md** — `/ssd upgrade` in the Invocation list + § doc; overlap table is **8 rows**
matching the updated "8 known overlap pairs" intro; `ssd-init`↔`/ssd upgrade` row is accurate
(state-disjoint). Banner 1.20.0→1.21.0 (ssd uses a placeholder frontmatter example → `skill-version-sync`
SKIPs it, so no sync break). ✓
**(5) known-good signal** — `migrate.sh --from 1.3.0` against this repo reports `PENDING
selective-gitignore` (real: `project.yml` never recorded `gitignore_mode`). Accurate detection. ✓
**Verified:** parity 20/20 (incl. the 2 new migrate fixtures); `gate-rules --base main` all PASS/SKIP.

## Findings

- 🟡 **MINOR-1 — detect probes are unanchored greps** *(closed inline, round 2)*. `grep -q
  'developer_profile'` (etc.) matches the token *anywhere* — including a comment or prose mention —
  so a project that merely *mentions* a key in a comment could be reported `SKIP-present` when the
  key isn't actually set. Low harm in read-only iter A (a mildly wrong report), but **iter-B
  `--apply` gates the migration on `detect`** — a false-positive there would silently skip a needed
  migration. Hardened now: probes require the YAML *key* form (`^[[:space:]]*<key>:`), which excludes
  comments (`# key:` starts with `#`). De-risks iter B and improves iter-A accuracy.
- 💭 **QUESTION-1 — `ver_gt` assumes 3-component `X.Y.Z`.** A 2-component (`1.20`) or pre-release
  (`2.0.0-rc1`) version would compare loosely (empty/garbage 3rd field → numeric 0). Confirmed
  acceptable: SSD library versions and `introduced_in` are always `X.Y.Z` (the `VERSION` file and
  every manifest entry). Documented in the `ver_gt` comment. No change; flagged so a future
  pre-release scheme revisits it.
- 📝 **NIT-1 — awk parser is indent-sensitive** to the 2/4-space form this repo authors in
  `migrations.yml`. Same controlled-format caveat `gate-rules.sh`'s `yaml_get` carries, and it's
  documented in the function comment. Acceptable for a repo-authored manifest.

## Round 2 (inline) — closure
- ✅ **MINOR-1 closed.** `detect()` probes changed from bare-token greps to anchored YAML-key form
  (`grep -qE '^[[:space:]]*<key>:'`; `current-yml-v2` → `^schema_version:[[:space:]]*2([[:space:]]|$)`).
  Comments/prose no longer false-positive. Re-verified: parity 20/20 still PASS; this repo still
  correctly reports `PENDING selective-gitignore`; the synthetic old-project fixture still PENDINGs
  the absent keys.

## Gate decision
**PASS** — `blocker == 0 AND major == 0`. MINOR-1 closed inline; QUESTION-1 answered-by-design;
NIT-1 is a documented controlled-format caveat. Ship as **v1.21.0**.
