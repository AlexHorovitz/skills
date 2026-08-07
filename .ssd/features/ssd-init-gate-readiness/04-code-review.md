---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-07T00:00:00Z
produced_by: claude-opus-4-8
project: InsanelyGreat's SSD Skills Library
scope: add-ssd-init-gate-readiness (Iter A; main...HEAD)
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 0
  minor: 0
  question: 0
  suggestion: 1
  nit: 2
gate_pass: true
remediation_mode: false
round: 2
closed_from_previous_round: [MAJOR-1, MINOR-1]
---

# Code Review — ssd-init-gate-readiness Iter A

Review of the `main...HEAD` diff on `add-ssd-init-gate-readiness` (commit `5e9e907` + round-2 fix).
Single-cycle feature, so round 2 is inlined here per code-reviewer § "Multi-Round Gates". Scope: the
`gate-rules.sh` fallback, the `migrate.sh` detect/apply, the `ssd-init` Step 6.5 prose, the manifest
entries, and the version/changelog bookkeeping.

**Gate result: PASS** (blocker 0, major 0 after round 2). One MAJOR was found in round 1 and closed in
round 2; details below.

## Round 1 findings

### 🟠 MAJOR-1 — pytest misdetection writes a false-red `test_command` (CLOSED in round 2)
`methodology/migrate.sh` · `apply_gate_inputs_present`

The detection ladder tested a bare `tests/` directory for the pytest branch **before** `go.mod` /
`Cargo.toml`:

```sh
elif [[ -f "$ROOT/pyproject.toml" || -f "$ROOT/pytest.ini" || -d "$ROOT/tests" ]]; then cmd="pytest"
elif [[ -f "$ROOT/go.mod" ]];     then cmd="go test ./..."
elif [[ -f "$ROOT/Cargo.toml" ]]; then cmd="cargo test"
```

**Failure trace:** a Rust project keeps integration tests in `tests/` beside `Cargo.toml`. With no
`Makefile` `test:` target and no `package.json`, `[[ -d "$ROOT/tests" ]]` matches first → `cmd=pytest`
→ `.ssd/gate.yml` gets `test_command: pytest` → the next `/ssd gate` runs `pytest` in a Rust repo →
non-zero exit → **false red**. This reintroduces exactly the misleading-gate-signal ADR-0015 exists to
eliminate, on the `/ssd upgrade --apply` retrofit path (non-interactive, no prompt to catch it). Go and
JS projects with a `tests/` dir hit the same branch. The `ssd-init` prose correctly qualified this as
"tests/ + a pytest **dependency**"; the bash dropped the qualifier.

**Fix (round 2):** the pytest branch now requires a real Python marker
(`pyproject.toml` / `pytest.ini` / `setup.py`); the bare `tests/` trigger is removed. Verified in a
scratch repo: a `Cargo.toml` + `tests/` project now resolves to `cargo test`; a `pyproject.toml`
project still resolves to `pytest`.

### 🟡 MINOR-1 — misleading `gate_input()` comment (CLOSED in round 2)
`methodology/gate-rules.sh` · `gate_input`

The docstring referenced an `origin` "second output line via a caller-set var" mechanism that was never
implemented — a vestige of an earlier design that would mislead the next reader. **Fix (round 2):**
trimmed to describe only the behaviour that exists (first non-empty of project.yml → gate.yml).

## Accepted as-is (documented, not blocking)

### 💡 SUGGESTION-1 — `package.json` test detection is a broad grep
`apply_gate_inputs_present` matches `"test"[[:space:]]*:` anywhere in `package.json`, not specifically
`scripts.test`. A stray `"test"` key elsewhere could false-positive to `npm test`. Accepted for a
best-effort, dependency-free migration (no `jq` guaranteed on the retrofit path); `npm test` is also the
overwhelmingly likely correct answer when any `"test"` key is present. Left as a documented heuristic.

### 📝 NIT-1 — a commented placeholder can linger above a later real key
If `apply_gate_inputs_present` writes `# test_command: <cmd>` (nothing detected) and a test framework is
added later, a subsequent apply appends a real `test_command:` line while leaving the stale comment
above it. Cosmetic; the real key wins in `gate_input`. Not worth extra bash.

### 📝 NIT-2 — project.yml→gate.yml carry-over copies inline comments verbatim
`apply_committed_gate_yml`'s carry loop copies a `key: value  # comment` line from `project.yml` into
`gate.yml` including any trailing inline comment. `gate-rules.sh`'s reader strips inline comments on
read, so this is cosmetic only.

## Checks performed
- Read every changed hunk in `gate-rules.sh` and `migrate.sh`; traced the fallback and both apply paths.
- Confirmed `no-leaky-state`'s baseline denylist does **not** include `.ssd/gate.yml`, so a committed
  `gate.yml` (a selective-gitignore exception) is not falsely flagged as leaked state.
- Verified migration ordering (`gate-inputs-present` before `committed-gate-yml`) is safe in both orders
  and idempotent (re-apply leaves line counts at 1).
- Re-ran the diff-independent gate rules after the fix: `frontmatter-valid`, `skill-version-sync`,
  `migration-manifest-current` all PASS.

## Verdict
Gate **passes** after the round-2 fix. Iter A is shippable. Iters B–D (library-root resolution + hook
fix, Step 9 gate-readiness reporting, CI validator vendoring) remain out of scope.
