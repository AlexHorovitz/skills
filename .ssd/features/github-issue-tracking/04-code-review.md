---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-06-14T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: add-github-issue-tracking (iter A diff vs main)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 1
  minor: 2
  question: 0
  suggestion: 2
  nit: 1
gate_pass: false
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — github-issue-tracking (iter A), round 1

**Verdict: GATE FAIL** — 1 MAJOR (`blocker == 0 AND major == 0` is false). One quick fix-cycle, then
re-gate. The design is sound and the dogfood works; the MAJOR is a machine-contract defect, not a
design flaw.

Scope reviewed: `methodology/issue-sync.sh` (line-by-line), `ssd/chapters/{state,phases}.md` (prose
vs. implemented behavior), `ADR-0014`, `01-architect.md`, `03-coder-status.md`. All claims below were
traced against the code and, where noted, reproduced live.

---

## 🟠 MAJOR-1 — `--json` output is not valid JSON; plain stdout mixes the return value with status text
**File:** [methodology/issue-sync.sh:60-68](methodology/issue-sync.sh#L60-L68), echoes at
[:106](methodology/issue-sync.sh#L106), [:121](methodology/issue-sync.sh#L121),
[:153](methodology/issue-sync.sh#L153).

`do_ensure_epic` / `do_ensure_feature` call **both** `emit …` (status line on stdout) **and**
`echo "$num"` (the return value on stdout). Reproduced live:

- `ensure-epic … --json` → stdout is **two lines**: the JSON object **and** a bare `27`. The help
  text + architect contract advertise "`--json` emits `{action, issue, state}` … the orchestrator can
  jq" — a trailing bare integer breaks any object-shaped jq filter (`jq '.issue'` errors on the second
  value `Cannot index number`).
- Non-`--json` → `num="$(issue-sync.sh ensure-epic …)"` captures
  `"OK ensure-epic :: issue=27 … \n27"`, **not** `27`. The orchestrator prose at
  [phases.md](ssd/chapters/phases.md) literally says it "caches the **returned number**" — a
  deterministic wrapper (which iter B will add) gets garbage.

Why MAJOR and not MINOR: it's a demonstrable violation of the documented machine interface, and iter B
builds automated capture/`close-epic` logic directly on this return value. Cheap to fix now, silent
data-corruption risk if it ships.

**Fix (small):** send human/diagnostic output to **stderr**, keep stdout as the single machine
channel. Concretely: `emit` writes to `>&2` in text mode; in `--json` mode `emit` writes the object to
stdout and the bare `echo "$num"` is **suppressed** (the number is already in the object's `issue`
field). Then: text mode → stdout = just the number; `--json` → stdout = just the object. Update the
help/usage block to state the contract explicitly.

---

## 🟡 MINOR-1 — `find_issue_by_prefix` can falsely report "not found" → duplicate create
**File:** [methodology/issue-sync.sh:92-96](methodology/issue-sync.sh#L92-L96)

Two paths yield an empty result that the callers interpret as "doesn't exist, create it" — the exact
top-risk (duplicate issues) from the architect's risk table:

1. **`--limit 200` cap.** `ssd:feature` issues accumulate across the project's whole life (`--state
   all` includes closed/archived workstreams). The architect's own 10x baseline is ~30 active + many
   archived; over years this crosses 200 and older issues fall off the list → duplicate.
2. **Transient `gh issue list` failure** (rate-limit/network blip) → `$()` empty → treated as
   "not found" → create. `preflight` doesn't protect this individual call.

**Fix:** distinguish list-failure from genuinely-empty (check `gh` exit before deciding to create),
and either paginate (`--limit` is a cap, not a page) or match by exact title via `gh issue list
--search "<exact title> in:title"` as a second confirmation before creating. Low urgency at the
current 28-issue scale; flagging because it erodes the feature's core idempotency guarantee and the
mitigation the risk table claims ("verified by a parity fixture") doesn't exist until iter B.

## 🟡 MINOR-2 — `ensure-feature` links to the epic only by body mention, not the task-list entry the spec defines
**File:** [methodology/issue-sync.sh:144-145](methodology/issue-sync.sh#L144-L145)

The architect data model says a feature links to its epic via "a `Epic: #E` body line **+ task-list
entry on the epic**." The helper writes the body line (which does create a GitHub back-reference on
the epic) but never appends/maintains the epic's `- [ ] #F` task list — I did that by hand in the
dogfood bootstrap. Not wrong, but impl and spec disagree, and a reader will expect the epic checklist
to stay current. **Fix:** either append to the epic task list in `ensure-feature`, or amend ADR-0014 /
the architect data model to say "linkage is the body mention; epic child-tracking is by `ssd:feature`
label query, not the task list" (which is in fact what iter-B close-detection should use — so prefer
the doc amendment). `03-coder-status.md` noted a body-block simplification but not this linkage gap.

---

## 💡 SUGGESTION-1 — REVIEW marker #2 (set-phase sed) is also locale-fragile, not just format-coupled
**File:** [methodology/issue-sync.sh:181](methodology/issue-sync.sh#L181)

`sed -E "s#(\*\*Phase:\*\* )[^ ·]+#…#"` puts the multibyte `·` (U+00B7) inside a bracket expression;
in a C/POSIX locale that excludes its raw bytes (0xC2 0xB7), which happens to work here (verified live)
but is fragile. Since it's a best-effort cosmetic refresh (the label is canonical), it's not blocking —
but consider anchoring the rewrite to within the `ssd:begin/ssd:end` span and matching `[^ ]` only
(the token never contains a space), or regenerating the whole block from known fields in iter B. The
existing REVIEW marker adequately flags the coupling; this just adds the locale dimension.

## 💡 SUGGESTION-2 — REVIEW marker #1 (gh ≥ 2.37 `--json` fallback) is adequately handled; document the floor
**File:** [methodology/issue-sync.sh:113-118](methodology/issue-sync.sh#L113-L118)

The `--json number || URL-parse` fallback is a reasonable belt-and-suspenders and does not block. To
close the REVIEW marker: state SSD's minimum supported `gh` version once (README/preflight) and, if
it's ≥ 2.37, the fallback can be dropped to simplify; if older gh must be supported, keep it and add a
one-line comment that it's intentional.

---

## 📝 NIT-1 — `emit` does not JSON-escape `detail`/`state`
**File:** [methodology/issue-sync.sh:62-64](methodology/issue-sync.sh#L62-L64)

`printf '{"detail":"%s"}' "$detail"` would emit invalid JSON if a value contained `"` or `\`. All
current callers pass controlled tokens (ADR ids, `epic=#27`, label names) so it can't happen today;
worth a comment or a minimal escape if `detail` ever carries free text.

---

## Cross-checks
- **Prose vs. behavior:** [phases.md](ssd/chapters/phases.md) (preflight→exit-3 warn+continue;
  ensure-epic/ensure-feature/set-phase; create/update auto, close gated to iter B) and
  [state.md](ssd/chapters/state.md) (`epic:`/`issue:` optional, lazy-cached) both match the
  implementation. The only mismatch is MINOR-2 (task-list linkage).
- **bash 3.2 / `set -uo pipefail`:** clean. No associative arrays; `ARGS=()` indexed array + `${ARGS[1]:-}`
  guards are correct. `bash -n` passes.
- **Exit codes:** consistent with the header (`0` ok, `2` bad-args/iter-B-stub, `3` gh-unavailable).
  The `close-feature|close-epic` stub correctly exits 2 with an explanatory message.
- **Cross-workstream overlap check:** only `github-issue-tracking` is active in `current.yml` →
  single-workstream, check skipped (no OVERLAP findings).
- **Gate-rules.sh:** ran green earlier (fail_count 0; `adr-delta`/`no-leaky-state` SKIP on the
  uncommitted tree — they'll exercise at commit; ADR-0014 is present and `no-leaky-state` is satisfied
  because `current.yml`/`project.yml` are gitignored).

## What's genuinely good
- Idempotency-by-local-prefix-match (avoiding GitHub search tokenization) is the right call and the
  reasoning is documented at the call site.
- The best-effort/never-block degradation (preflight exit-3) is exactly right for a mirror, and the
  prose makes the orchestrator surface each action (rule-zero).
- `spec_drift: false` is accurate apart from MINOR-2; the iter-A/B split is honest and the deferred
  list is explicit, not silent.

## To clear the gate (round 2)
Fix **MAJOR-1** (stdout/stderr split + suppress bare echo in `--json`). MINOR-1/-2 may ship to iter B
with a tracked note, or be closed now since MINOR-1's fix is small — reviewer's preference is to close
MINOR-1 alongside MAJOR-1 since they share the same function neighborhood and both touch the
idempotency contract. Re-run `/ssd gate` for a round-2 review.
