---
skill: architect
version: 1.2.0
produced_at: 2026-06-10T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: ssd-commit-split iteration B — optional pre-commit hook + docs polish
consumed_by: [coder, code-reviewer]
deliverables:
  component_diagram: inherited
  data_model: inherited
  api_contract: refined            # new --staged flag on gate-rules.sh
  integration_contract: refined    # git hook integration
  adrs: []                          # ADR-0008 covers iter B
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: inherited
quality_gate_pass: true
---

# Architect Spec — Iteration B (ssd-commit-split)

## Delta over iter A's architect

Iter A's architect (`../../01-architect.md`) specified iter B as "optional pre-commit hook +
docs polish." This doc resolves the three open questions surfaced in the brief and adds one
small `gate-rules.sh` change that iter A's spec didn't account for.

## Open questions resolved

### Q1: stage-diff vs commit-diff in `gate-rules.sh`

**Decision: add a `--staged` flag to `gate-rules.sh`. The pre-commit hook uses
`bash methodology/gate-rules.sh --staged --rules no-leaky-state`.**

**The issue.** Iter A's `gate-rules.sh` uses `git diff --name-only "$BASE"...HEAD` — a
commit-to-commit diff. For a pre-commit hook the commits don't exist yet; the hook needs to
check the **staged** files via `git diff --cached --name-only`. Iter A's spec assumed the
hook could use `gate-rules.sh --rules no-leaky-state` as-is, but that doesn't actually work
in the pre-commit context.

**Implementation.** Introduce a `MODE` variable (default `branch`, alternative `staged`).
The `diff_files()` helper checks `MODE` and selects the right git command. The `--staged`
flag sets `MODE=staged`. Affected SKIP detail messages change to "no staged files" in
staged mode. Other rules (`wip-commits`, `adr-delta`, `frontmatter-valid`) function
correctly in either mode — they all read `diff_files()` through the same helper. `tests-pass`
and `feature-flag-present` are mode-agnostic.

**Rationale for keeping it in `gate-rules.sh` (vs duplicating logic in the hook).** The
deny-list, the `gitignore_mode` opt-out check, the `gitignored_state[]` override, and the
glob matcher are all in `gate-rules.sh`. Duplicating any of them in the hook risks drift —
the iter A code review (MINOR-1) demonstrated how subtle the glob matcher is to get right.
Single source of truth wins.

**Rejected alternative: `--paths <list>` flag for explicit path input.** More general (could
support CI use cases that want to gate arbitrary path sets) but more complex and not needed
yet. Defer.

### Q2: `ssd-init` prompt placement

**Decision: new Step 5.5 — "Offer pre-commit hook install (v1.7.0+)."**

Step 5 (the gitignore migration from iter A) and the hook install are related but distinct
optionals. Inline in Step 5 would conflate them; a new Step 5.5 keeps the responsibilities
clean and makes the step easy to skip.

**Profile-aware default for the prompt:**

- `developer_profile: expert` — offer the install with explicit yes/no/skip choice.
- `developer_profile: standard` — silently skip (don't offer; user can install later by
  reading `methodology/hooks/README.md`).
- `developer_profile: novice` — silently skip (same reasoning).

**The prompt offers but never installs.** The orchestrator at most prints the install
command for the user to run themselves:

```
ln -s ../../methodology/hooks/pre-commit-no-leaky-state.sh .git/hooks/pre-commit
```

`ssd-init` does NOT execute the symlink itself. Git hooks are a per-user / per-checkout
trust boundary; the user runs the symlink command consciously.

### Q3: Iter C scope (post-user-commit b6fc739)

**Decision: declare the epic complete at v1.19.0 (this PR). No separate iter C ship.**

Background: between iter A merging (PR #7) and iter B starting, the user manually committed
the 16 historical `.ssd/features/{parallel-features, ssd-skill-upgrades}/**/*.md` artifacts
in commit `b6fc739 added features stuff`. That commit satisfies the iter C scope from iter
A's architect spec verbatim ("stage all previously-untracked .ssd/features/* artifacts").

**Rolling iter C's residual scope into iter B:**

- The README update (mentioning the repo tracks its own SSD artifacts) — small, no
  dependency on iter B's other work. Add to iter B.
- A short retro section in the v1.19.0 changelog acknowledging the manual backfill commit.
- Close the epic in `current.yml.archived[]` at v1.19.0 ship.

If real residual work emerges (e.g., the README update raises new questions, or the dogfood
revealed a bug in the gitignore pattern that needs a follow-up patch), it ships as a
post-epic patch release, not as iter C.

## Implementation breakdown

### 1. `methodology/hooks/pre-commit-no-leaky-state.sh` (NEW)

A plain bash script designed for symlink install. Structure:

```bash
#!/usr/bin/env bash
# pre-commit-no-leaky-state.sh — block staged files that match the SSD selective-commit
# deny-list. See docs/decisions/ADR-0008-ssd-commit-split.md.
#
# Install: from your project root,
#   ln -s ../../methodology/hooks/pre-commit-no-leaky-state.sh .git/hooks/pre-commit
# See methodology/hooks/README.md for install, uninstall, and coexistence with existing
# pre-commit hooks.

set -uo pipefail

# Resolve the repo root + script location. The symlink-from-.git/hooks pattern means $0
# resolves to the .git/hooks/pre-commit path; we need to chase the symlink to find the
# real script location (and from there, the methodology/ dir and the project root).

# Find the project root via git (works from any hook context).
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "pre-commit-no-leaky-state: not in a git repo" >&2
  exit 1
fi

GATE_RULES="$PROJECT_ROOT/methodology/gate-rules.sh"
if [[ ! -f "$GATE_RULES" ]]; then
  echo "pre-commit-no-leaky-state: methodology/gate-rules.sh not found at $GATE_RULES" >&2
  echo "  (the hook expects the SSD skills library installed in the repo)" >&2
  exit 1
fi

# Run only the no-leaky-state rule, in staged mode.
bash "$GATE_RULES" --staged --rules no-leaky-state
exit $?
```

**Behavior:**
- Locates `methodology/gate-rules.sh` via `git rev-parse --show-toplevel`.
- Invokes it with `--staged --rules no-leaky-state` (the two flags iter B adds /
  preserves).
- Exit code passes through. Hook exits 0 on PASS/SKIP, non-zero on FAIL.
- Output: the standard `PASS|FAIL|SKIP no-leaky-state :: <detail>` line, which `git commit`
  prints when the hook fails.

**No interactive prompts in the hook.** Pre-commit hooks must be non-interactive (they run
in the commit pipeline). The hook either passes silently (clean diff) or fails with a clear
message (forbidden file staged); the user fixes and retries.

### 2. `methodology/hooks/README.md` (NEW)

Sections:
- **What this hook does.** One paragraph; cross-references ADR-0008 and the
  `no-leaky-state` gate rule.
- **Install (the symlink convention).**
  ```bash
  cd <repo-root>
  ln -s ../../methodology/hooks/pre-commit-no-leaky-state.sh .git/hooks/pre-commit
  chmod +x methodology/hooks/pre-commit-no-leaky-state.sh   # one-time, if needed
  ```
  Verify: `ls -la .git/hooks/pre-commit` shows the symlink.
- **Verify it works.** Force-add a fake `.ssd/current.yml` and try to commit; the hook
  fires. Then unstage.
- **Uninstall.** `rm .git/hooks/pre-commit` (only if the symlink IS the no-leaky-state
  hook).
- **Coexistence with existing pre-commit hooks.** If `.git/hooks/pre-commit` already exists
  (e.g., a project-wide formatter hook), add a one-line invocation at the top of the
  existing hook:
  ```bash
  bash "$(git rev-parse --show-toplevel)/methodology/gate-rules.sh" --staged --rules no-leaky-state || exit $?
  ```
  Document this pattern.
- **Why a plain symlink, not husky / pre-commit.com.** Reference ADR-0008 § "Alternatives
  Rejected" — plain bash, no framework dependency, matches `gate-rules.sh` precedent.
- **CI integration.** Brief note that the same `gate-rules.sh --rules no-leaky-state`
  invocation (without `--staged`) is the recommended CI backstop.

### 3. `methodology/gate-rules.sh` — `--staged` flag

Add to the existing arg parser:

```bash
MODE="branch"   # branch | staged

while [[ $# -gt 0 ]]; do
  case "$1" in
    ...existing cases...
    --staged) MODE="staged"; shift ;;
    ...
  esac
done
```

Modify `diff_files()`:

```bash
diff_files() {
  is_git_repo || { echo ""; return; }
  if [[ "$MODE" == "staged" ]]; then
    git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null
  else
    git -C "$PROJECT_ROOT" diff --name-only "$BASE"...HEAD 2>/dev/null
  fi
}
```

Modify the SKIP detail in `rule_no_leaky_state` and `rule_adr_delta` (the two rules that
explicitly say "no diff vs $BASE" in their SKIP message) to read "no staged files" in
staged mode. Keep `rule_wip_commits` and `rule_frontmatter_valid` running their existing
logic — wip-commits doesn't fire pre-commit (no commit log to grep yet) so it SKIPs cleanly
in staged mode; frontmatter-valid validates files which works fine on staged content (the
files exist on disk).

Update the script header usage block to document `--staged`.

### 4. `ssd-init/SKILL.md` — new Step 5.5

After Step 5 (Update `.gitignore`) and before Step 6 (Detect Project Shape), insert:

```markdown
### Step 5.5 — Offer pre-commit hook install (v1.7.0+, optional)

Available for projects on `gitignore_mode: selective` (the v1.18.0+ default; see Step 5)
and `developer_profile: expert`. The hook catches `no-leaky-state` violations *before*
the commit lands, complementing the `/ssd gate` enforcement that runs at PR time.

**Profile-aware behavior:**

- **expert:** offer the install with explicit yes/no/skip prompt.
- **standard:** silently skip the offer (user can install later via
  `methodology/hooks/README.md`).
- **novice:** silently skip the offer.

**The offer prints the install command for the user to run themselves:**

    ln -s ../../methodology/hooks/pre-commit-no-leaky-state.sh .git/hooks/pre-commit

`ssd-init` does NOT execute the symlink. Git hooks are a per-user / per-checkout trust
boundary; the user installs consciously.

If the project already has a `.git/hooks/pre-commit` hook, `ssd-init` warns and prints the
coexistence pattern from `methodology/hooks/README.md` instead of suggesting the symlink.

See [ADR-0008](../docs/decisions/ADR-0008-ssd-commit-split.md) for the rationale and
`methodology/hooks/README.md` for the full install / uninstall / coexistence docs.
```

Bump `ssd-init/SKILL.md` version banner 1.7.0 → 1.8.0. Add a changelog entry.

### 5. README.md — mention the dogfood

One-paragraph addition near the top (after the badges, before the methodology section):

> **Dogfood.** As of v1.19.0 (per [ADR-0008](docs/decisions/ADR-0008-ssd-commit-split.md))
> this repo tracks its own SSD artifacts under `.ssd/features/` — briefs, architect specs,
> coder-status reports, and code-reviews for every feature shipped in v1.5.0+. Read the
> history of how the methodology was built using the methodology itself.

### 6. CHANGELOG.md — v1.19.0 entry

Standard format, matching the v1.18.0 style. Sections:

- Iteration B scope (hook + README + ssd-init Step 5.5)
- `gate-rules.sh` `--staged` flag — small but important; document the contract
- Acknowledgment of commit `b6fc739` (user-driven dogfood between iter A and iter B)
- Epic complete declaration at v1.19.0

### 7. VERSION — 1.18.0 → 1.19.0

## Risk assessment (iter B specific)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `--staged` flag introduces subtle bugs in other rules that read `diff_files()` | M | M | Code review verifies each rule's behavior in staged mode. `wip-commits` SKIPs (no commit log); `frontmatter-valid` validates files on disk (works regardless of mode); `tests-pass`/`feature-flag-present` don't call `diff_files()` directly. |
| User installs the hook in a project without SSD library installed | L | L | Hook checks for `methodology/gate-rules.sh` existence and exits non-zero with a clear error. Won't silently allow forbidden commits. |
| Hook fires on a clean diff and produces noisy output | L | L | The hook script doesn't echo on PASS — only the gate-rules.sh PASS line. For solo developers wanting silent-on-pass, document `2>/dev/null` redirection or suggest a stricter `--quiet` flag (deferred). |
| Existing pre-commit hook conflicts with the symlink install | M | M | README documents the coexistence pattern; ssd-init prompt detects existing hook and prints the coexistence path instead of the symlink path. |
| Hook performance: `git ls-files <glob>` per pattern is slow on huge repos | L | L | Same risk as the gate rule itself; mitigated by the small baseline deny-list size. Document. |

## Files in Scope (binding)

| File | Change |
|---|---|
| `methodology/hooks/pre-commit-no-leaky-state.sh` | NEW |
| `methodology/hooks/README.md` | NEW |
| `methodology/gate-rules.sh` | EDIT — `--staged` flag + `diff_files()` mode branching + SKIP detail update |
| `ssd-init/SKILL.md` | EDIT — new Step 5.5 + version bump to 1.8.0 + changelog |
| `README.md` | EDIT — dogfood paragraph |
| `CHANGELOG.md` | EDIT — v1.19.0 entry |
| `VERSION` | EDIT — 1.18.0 → 1.19.0 |
| `.ssd/features/ssd-commit-split/iterations/b/{brief, 01-architect, coder-status}.md` | NEW |
| `.ssd/features/ssd-commit-split/iterations/b/code-review/round-1.md` | NEW |

## Quality Gate

| Item | Status |
|---|---|
| Platform | ✓ markdown skills library + bash hook |
| ADRs | ✓ inherited (ADR-0008); no new ADRs |
| Data model | ✓ inherited |
| API contract | ✓ `--staged` flag spec'd; hook script spec'd; ssd-init Step 5.5 spec'd |
| Integration contract | ✓ hook → gate-rules.sh shell-out; git pre-commit lifecycle |
| Auth | N/A |
| Async | N/A |
| Feature flag | N/A — opt-in via symlink + profile gate |
| CI/CD | N/A this repo; recommended pattern documented in hooks/README.md |
| Risk assessment | ✓ |
| Scale baseline | inherited |
| Walking Skeleton deployable | ✓ iter B ships as v1.19.0 with hook as opt-in |

## Handoff to coder

Implement per § "Implementation breakdown" above. Files in order:

1. `methodology/gate-rules.sh` — add `--staged` flag and `MODE` branching first (the hook
   depends on this).
2. `methodology/hooks/pre-commit-no-leaky-state.sh` (NEW).
3. `methodology/hooks/README.md` (NEW).
4. `ssd-init/SKILL.md` — new Step 5.5 + version bump.
5. `README.md` — dogfood paragraph.
6. `CHANGELOG.md` v1.19.0 entry + `VERSION` bump.
7. `coder-status.md`.

After coder phase: code review (round 1), close any findings, commit, push, PR, merge,
tag v1.19.0, archive ssd-commit-split workstream.
