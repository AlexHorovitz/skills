#!/usr/bin/env bash
# scripts/parity-test.sh — structural-conformance test harness for the SSD skills library.
#
# Validates gate-rules.sh against a battery of synthetic git fixtures. Each fixture is a tiny
# repo with a known diff; the harness asserts the script emits the expected status (PASS/FAIL/SKIP)
# for each rule.
#
# What this harness IS:
#   - A fast (<5s) regression check that gate-rules.sh hasn't drifted.
#   - A documentation-by-example of what each rule actually checks.
#
# What this harness IS NOT:
#   - A two-surface parity test (conversational vs command). The plan envisioned that test, but
#     both surfaces are LLM-driven behaviors not directly invocable from bash. Deferred until SSD
#     has executable surface drivers.
#   - A frontmatter schema validator for `.ssd/features/<slug>/*.md` artifacts. Useful but
#     out of scope for v1.0.0 of this harness.
#
# Usage:
#   bash scripts/parity-test.sh             # run all fixtures
#   bash scripts/parity-test.sh -v          # verbose (show each rule's actual output)
#
# Exit code: 0 if every fixture matches its expected output. Non-zero on first mismatch.
#
# License: see /LICENSE.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE_SCRIPT="$REPO_ROOT/methodology/gate-rules.sh"
VALIDATOR="$REPO_ROOT/methodology/frontmatter-validate.py"
SCHEMAS_DIR="$REPO_ROOT/methodology/schemas"
MIGRATE_SCRIPT="$REPO_ROOT/methodology/migrate.sh"
MANIFEST="$REPO_ROOT/methodology/migrations.yml"
ISSUE_SYNC_SCRIPT="$REPO_ROOT/methodology/issue-sync.sh"
STORE_SCRIPT="$REPO_ROOT/methodology/store.sh"
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -x "$GATE_SCRIPT" ]]; then
  echo "FAIL: gate-rules.sh not found or not executable at $GATE_SCRIPT" >&2
  exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

# ---------- helpers ---------------------------------------------------------

# Build a fresh fixture repo. Args:
#   1: fixture name (label only; for output)
# Returns the tmp dir path on stdout. The CALLER must `cd` to it — fixture_setup runs in a
# command-substitution subshell, so any cd here would not propagate to the caller. (Earlier
# versions of this harness assumed it would, with disastrous consequences for the parent repo.)
fixture_setup() {
  local name="$1"
  local tdir
  tdir=$(mktemp -d "/tmp/ssd-parity-${name}.XXXXXX")
  (
    cd "$tdir" || exit 2
    git init -q -b main
    git config user.email "parity@test.local"
    git config user.name "parity-test"
    # Disable GPG signing for fixture commits — test artifacts in /tmp don't
    # need (and can't always do) signing; the user's global config may set
    # commit.gpgsign=true. Local-only override; doesn't affect anything outside
    # this tmp dir.
    git config commit.gpgsign false
    git config tag.gpgsign false
  )
  echo "$tdir"
}

fixture_teardown() {
  local tdir="$1"
  cd "$REPO_ROOT" || true
  rm -rf "$tdir"
}

# Assert that running gate-rules.sh in cwd produces the expected status for a given rule.
# Args: fixture-name rule-name expected-status (PASS|FAIL|SKIP) [base-ref=main]
assert_rule() {
  local fixture="$1" rule="$2" expected="$3" base="${4:-main}"
  local out actual
  out=$(bash "$GATE_SCRIPT" --base "$base" 2>&1)
  actual=$(echo "$out" | awk -v r="$rule" '$2 == r { print $1; exit }')
  if [[ "$actual" == "$expected" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    [[ $VERBOSE -eq 1 ]] && echo "  ✓ $fixture / $rule → $expected"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("$fixture / $rule: expected $expected, got '${actual:-<missing>}'")
    [[ $VERBOSE -eq 1 ]] && {
      echo "  ✗ $fixture / $rule: expected $expected, got '${actual:-<missing>}'"
      echo "    --- gate output ---"
      echo "$out" | sed 's/^/    /'
    }
  fi
}

# ---------- fixtures --------------------------------------------------------

# Fixture 1: clean diff with feature flag and ADR — all rules PASS or SKIP appropriately.
test_fixture_clean_flagged() {
  echo "fixture: clean-flagged-with-adr"
  local tdir
  tdir=$(fixture_setup "clean-flagged")
  cd "$tdir" || exit 2
  mkdir -p .ssd docs/decisions
  cat > .ssd/project.yml <<EOF
feature_flag_marker: flag_enabled\(
EOF
  echo "def base(): pass" > app.py
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  cat >> app.py <<'EOF'

def new_thing():
    if flag_enabled("new"):
        return "ok"
EOF
  # Add 250-line architectural change to trigger adr-delta — requires an ADR.
  yes "x" | head -250 > big_arch.py
  cat > docs/decisions/ADR-9999-test.md <<'EOF'
# ADR-9999: Test ADR
## Status
Accepted
EOF
  git add -A && git commit -qm "add flagged feature + arch change with ADR"

  assert_rule "clean-flagged" "wip-commits" "PASS"
  assert_rule "clean-flagged" "feature-flag-present" "PASS"
  assert_rule "clean-flagged" "adr-delta" "PASS"
  assert_rule "clean-flagged" "tests-pass" "SKIP"  # no test_command in project.yml

  fixture_teardown "$tdir"
}

# Fixture 2: WIP commit on the branch — wip-commits FAILs.
test_fixture_wip_commit() {
  echo "fixture: wip-commit-fails"
  local tdir
  tdir=$(fixture_setup "wip-commit")
  cd "$tdir" || exit 2
  echo "x" > a.txt
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  echo "y" > a.txt
  git add -A && git commit -qm "WIP: not done yet"

  assert_rule "wip-commit" "wip-commits" "FAIL"

  fixture_teardown "$tdir"
}

# Fixture 3: code change without flag in a repo with a flag marker configured — feature-flag-present FAILs.
test_fixture_missing_flag() {
  echo "fixture: missing-flag-fails"
  local tdir
  tdir=$(fixture_setup "missing-flag")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  cat > .ssd/project.yml <<EOF
feature_flag_marker: flag_enabled\(
EOF
  echo "def base(): pass" > app.py
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  echo "def unflagged(): return 1" >> app.py
  git add -A && git commit -qm "add unflagged code"

  assert_rule "missing-flag" "feature-flag-present" "FAIL"

  fixture_teardown "$tdir"
}

# Fixture 4: doc-only diff in a flag-aware repo — feature-flag-present SKIPs.
test_fixture_docs_only_skips_flag() {
  echo "fixture: docs-only-skips-flag"
  local tdir
  tdir=$(fixture_setup "docs-only")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  cat > .ssd/project.yml <<EOF
feature_flag_marker: flag_enabled\(
EOF
  echo "# README" > README.md
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  echo "more docs" >> README.md
  git add -A && git commit -qm "doc only"

  assert_rule "docs-only" "feature-flag-present" "SKIP"

  fixture_teardown "$tdir"
}

# Fixture 5: large architectural change without ADR — adr-delta FAILs.
test_fixture_missing_adr() {
  echo "fixture: missing-adr-fails"
  local tdir
  tdir=$(fixture_setup "missing-adr")
  cd "$tdir" || exit 2
  echo "def x(): pass" > app.py
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  yes "x" | head -300 > big.py
  git add -A && git commit -qm "300-line change without ADR"

  assert_rule "missing-adr" "adr-delta" "FAIL"

  fixture_teardown "$tdir"
}

# Fixture 6: yaml_get rejects commented keys (regression for round-2 fix MINOR-1).
test_fixture_yaml_comment_skip() {
  echo "fixture: yaml-comment-skip"
  local tdir
  tdir=$(fixture_setup "yaml-comment")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  cat > .ssd/project.yml <<'EOF'
# test_command: rm -rf /
# This is a documentation example, not a real value.
EOF
  echo "x" > a.txt
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  echo "y" > a.txt
  git add -A && git commit -qm "change"

  # If yaml_get incorrectly grabs the commented `test_command`, the rule would attempt to run
  # `rm -rf /` (eval'd). Our guard skips comments, so the rule should SKIP cleanly.
  assert_rule "yaml-comment" "tests-pass" "SKIP"

  fixture_teardown "$tdir"
}

# Fixture 7: spaced filename in changed paths — both rules complete cleanly (regression for MAJOR-2).
test_fixture_spaced_path() {
  echo "fixture: spaced-path"
  local tdir
  tdir=$(fixture_setup "spaced-path")
  cd "$tdir" || exit 2
  mkdir -p .ssd "src dir"
  cat > .ssd/project.yml <<EOF
feature_flag_marker: flag_enabled\(
EOF
  echo "def x(): pass" > "src dir/mod.py"
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  cat >> "src dir/mod.py" <<'EOF'

def new():
    if flag_enabled("new"):
        return 1
EOF
  git add -A && git commit -qm "add flagged code in spaced dir"

  assert_rule "spaced-path" "feature-flag-present" "PASS"

  fixture_teardown "$tdir"
}

# Fixture 8: valid frontmatter on an architect artifact — frontmatter-valid PASSes.
# Skips if PyYAML isn't installed (matches the gate rule's own SKIP condition).
test_fixture_frontmatter_valid() {
  echo "fixture: frontmatter-valid"
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "  ⊘ skipped: PyYAML not installed"
    return
  fi
  local tdir
  tdir=$(fixture_setup "frontmatter-valid")
  cd "$tdir" || exit 2
  # Symlink the validator + schemas into the fixture so the gate rule can find them.
  mkdir -p methodology
  ln -s "$VALIDATOR" methodology/frontmatter-validate.py
  ln -s "$SCHEMAS_DIR" methodology/schemas
  mkdir -p .ssd/features/test-feature
  cat > .ssd/features/test-feature/01-architect.md <<'EOF'
---
skill: architect
version: 1.2.0
produced_at: 2026-04-29T12:00:00Z
produced_by: claude-test
project: test-project
scope: test-feature
consumed_by: [coder, systems-designer]
deliverables:
  component_diagram: true
  data_model: true
  api_contract: true
  integration_contract: not_applicable
  adrs: [ADR-0001]
  risk_assessment: true
  feature_flag: not_applicable
  scale_baseline: true
quality_gate_pass: true
---
# Test architect output
EOF
  echo "x" > a.txt
  git add -A && git commit -qm "initial with valid architect"
  git checkout -qb feat
  echo "y" > a.txt
  git add -A && git commit -qm "trigger a diff"

  assert_rule "frontmatter-valid" "frontmatter-valid" "PASS"

  fixture_teardown "$tdir"
}

# Fixture 9: invalid frontmatter (missing required field) — frontmatter-valid FAILs.
test_fixture_frontmatter_invalid() {
  echo "fixture: frontmatter-invalid"
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "  ⊘ skipped: PyYAML not installed"
    return
  fi
  local tdir
  tdir=$(fixture_setup "frontmatter-invalid")
  cd "$tdir" || exit 2
  mkdir -p methodology
  ln -s "$VALIDATOR" methodology/frontmatter-validate.py
  ln -s "$SCHEMAS_DIR" methodology/schemas
  mkdir -p .ssd/features/test-feature
  # Missing `produced_at`, `consumed_by`, `deliverables`, `quality_gate_pass`.
  cat > .ssd/features/test-feature/01-architect.md <<'EOF'
---
skill: architect
version: 1.2.0
produced_by: claude-test
project: test-project
scope: test-feature
---
# Test architect output (intentionally missing fields)
EOF
  echo "x" > a.txt
  git add -A && git commit -qm "initial with invalid architect"
  git checkout -qb feat
  echo "y" > a.txt
  git add -A && git commit -qm "trigger a diff"

  assert_rule "frontmatter-invalid" "frontmatter-valid" "FAIL"

  fixture_teardown "$tdir"
}

# Fixture 10: skill-version-sync PASS — a SKILL.md whose frontmatter-example
# version matches its **Version:** banner (refactor R4, post-v1.19 milestone).
test_fixture_skill_version_match() {
  echo "fixture: skill-version-match"
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "  ⊘ skipped: PyYAML not installed"
    return
  fi
  local tdir
  tdir=$(fixture_setup "skill-version-match")
  cd "$tdir" || exit 2
  mkdir -p methodology
  ln -s "$VALIDATOR" methodology/frontmatter-validate.py
  ln -s "$SCHEMAS_DIR" methodology/schemas
  mkdir -p fakeskill
  cat > fakeskill/SKILL.md <<'EOF'
# Fake Skill

**Version:** 1.4.0

Required output frontmatter:

```yaml
---
skill: fakeskill
version: 1.4.0
produced_at: <ISO-8601>
---
```
EOF
  echo "x" > a.txt
  git add -A && git commit -qm "initial with matching skill version"

  assert_rule "skill-version-match" "skill-version-sync" "PASS"

  fixture_teardown "$tdir"
}

# Fixture 11: skill-version-sync FAIL — example version drifts from the banner.
# This is the test-first fixture for R4: it demonstrates the FAIL the new check
# is built to catch.
test_fixture_skill_version_drift() {
  echo "fixture: skill-version-drift"
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "  ⊘ skipped: PyYAML not installed"
    return
  fi
  local tdir
  tdir=$(fixture_setup "skill-version-drift")
  cd "$tdir" || exit 2
  mkdir -p methodology
  ln -s "$VALIDATOR" methodology/frontmatter-validate.py
  ln -s "$SCHEMAS_DIR" methodology/schemas
  mkdir -p fakeskill
  cat > fakeskill/SKILL.md <<'EOF'
# Fake Skill

**Version:** 1.4.0

Required output frontmatter:

```yaml
---
skill: fakeskill
version: 1.0.0
produced_at: <ISO-8601>
---
```
EOF
  echo "x" > a.txt
  git add -A && git commit -qm "initial with drifted skill version"

  assert_rule "skill-version-drift" "skill-version-sync" "FAIL"

  fixture_teardown "$tdir"
}

# Fixture 12: --base arg validation (regression for MINOR-2).
test_fixture_base_arg_validation() {
  echo "fixture: base-arg-validation"
  local out exit_code
  # Missing value → exit 2
  out=$(bash "$GATE_SCRIPT" --base 2>&1); exit_code=$?
  if [[ $exit_code -eq 2 && "$out" == *"requires a value"* ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    [[ $VERBOSE -eq 1 ]] && echo "  ✓ --base (no value) → exit 2"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("base-arg-validation: --base no value: expected exit 2 'requires a value', got exit $exit_code: $out")
  fi
  # Adjacent flag → exit 2
  out=$(bash "$GATE_SCRIPT" --base --json 2>&1); exit_code=$?
  if [[ $exit_code -eq 2 && "$out" == *"requires a value"* ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    [[ $VERBOSE -eq 1 ]] && echo "  ✓ --base --json → exit 2"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("base-arg-validation: --base --json: expected exit 2 'requires a value', got exit $exit_code: $out")
  fi
}

# Small inline assertion for non-gate-rules scripts (migrate.sh). Args: label condition-desc bool(0/1).
_assert() {
  local label="$1" desc="$2" ok="$3"
  # A verdict that is not an integer is a BROKEN assertion, never a passing one. bash arithmetic
  # coerces both "" and "banana" to 0, so `[[ "$ok" -eq 0 ]]` scored a command substitution that
  # produced NOTHING — a typo'd path, an errored pipeline, a grep against a missing file — as a PASS,
  # silently and green (Feynman audit 2026-09-01, H1). Every one of the 211 call sites is currently
  # guarded by an `echo 0`/`echo 1` fallback, so this changes no result today; it makes the guard
  # structural instead of conventional, which is the difference between "sound" and "sound so far".
  if [[ ! "$ok" =~ ^[0-9]+$ ]]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("$label: $desc [BROKEN ASSERTION — verdict '$ok' is not an integer]")
    return
  fi
  if [[ "$ok" -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1)); [[ $VERBOSE -eq 1 ]] && echo "  ✓ $label / $desc"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILURES+=("$label: $desc")
  fi
}

# Fixture 13: migrate.sh detect — an OLD project sees the expected PENDING/GUIDED drift (ssd-upgrade iter A).
test_fixture_migrate_detect_old() {
  echo "fixture: migrate-detect-old"
  local tdir out
  tdir=$(fixture_setup "migrate-old")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'schema_version: 2\nactive: []\n' > .ssd/current.yml          # current-yml-v2 present
  printf 'ssd:\n  version: "1.3.0"\n' > .ssd/project.yml               # no profile/branch/gitignore keys
  out=$(bash "$MIGRATE_SCRIPT" --from 1.3.0 --to 1.20.1 --manifest "$MANIFEST" 2>&1)
  _assert "migrate-detect-old" "current-yml-v2 already present → SKIP" \
    "$([[ "$out" == *"SKIP-present current-yml-v2"* ]] && echo 0 || echo 1)"
  _assert "migrate-detect-old" "selective-gitignore absent → PENDING" \
    "$([[ "$out" == *"PENDING selective-gitignore"* ]] && echo 0 || echo 1)"
  _assert "migrate-detect-old" "decision-record-doctrine → GUIDED" \
    "$([[ "$out" == *"GUIDED decision-record-doctrine"* ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Fixture 14: migrate.sh detect — a CURRENT project sees no pending migrations.
test_fixture_migrate_detect_current() {
  echo "fixture: migrate-detect-current"
  local tdir out
  tdir=$(fixture_setup "migrate-current")
  cd "$tdir" || exit 2
  # recorded == target → nothing newer than recorded is selected, regardless of file contents.
  out=$(bash "$MIGRATE_SCRIPT" --from 1.20.1 --to 1.20.1 --manifest "$MANIFEST" 2>&1)
  _assert "migrate-detect-current" "no migrations newer than recorded → empty report" \
    "$([[ -z "$out" ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Fixture 15: migrate.sh --apply — a drifted project adopts the mechanical conventions safely.
test_fixture_migrate_apply_old() {
  echo "fixture: migrate-apply-old"
  local tdir out out2
  tdir=$(fixture_setup "migrate-apply")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'schema_version: 2\nactive: []\n' > .ssd/current.yml
  printf 'ssd:\n  version: "1.9.0"\n  artifact_root: .ssd/\n' > .ssd/project.yml   # missing dev/parallel/gitignore keys
  printf '.ssd/\nnode_modules/\n' > .gitignore
  out=$(bash "$MIGRATE_SCRIPT" --from 1.9.0 --to 1.22.0 --manifest "$MANIFEST" --apply 2>&1)

  _assert "migrate-apply-old" "dev-profile-keys APPLIED" \
    "$([[ "$out" == *"APPLIED dev-profile-keys"* ]] && echo 0 || echo 1)"
  _assert "migrate-apply-old" "parallel-features-keys APPLIED" \
    "$([[ "$out" == *"APPLIED parallel-features-keys"* ]] && echo 0 || echo 1)"
  _assert "migrate-apply-old" "selective-gitignore APPLIED" \
    "$([[ "$out" == *"APPLIED selective-gitignore"* ]] && echo 0 || echo 1)"
  _assert "migrate-apply-old" "guided item re-surfaced (not auto-applied)" \
    "$([[ "$out" == *"GUIDED decision-record-doctrine"* ]] && echo 0 || echo 1)"
  # Conventions are now actually present in the files.
  _assert "migrate-apply-old" "developer_profile key written to project.yml" \
    "$(grep -qE '^[[:space:]]*developer_profile:' .ssd/project.yml && echo 0 || echo 1)"
  _assert "migrate-apply-old" "branch_pattern key written to project.yml" \
    "$(grep -qE '^[[:space:]]*branch_pattern:' .ssd/project.yml && echo 0 || echo 1)"
  _assert "migrate-apply-old" "gitignore_mode key written to project.yml" \
    "$(grep -qE '^[[:space:]]*gitignore_mode:' .ssd/project.yml && echo 0 || echo 1)"
  # Dogfood MAJOR-4: the value must be comment-free so gate-rules.sh's no-leaky-state parser reads it.
  _assert "migrate-apply-old" "gitignore_mode value has no inline comment (gate-parseable)" \
    "$(grep -qE '^[[:space:]]*gitignore_mode:[[:space:]]*selective[[:space:]]*$' .ssd/project.yml && echo 0 || echo 1)"
  _assert "migrate-apply-old" "selective .gitignore pattern written" \
    "$(grep -qF '!.ssd/features/**/01-architect.md' .gitignore && echo 0 || echo 1)"
  # R1 mitigation: a .bak per mutated file.
  _assert "migrate-apply-old" "project.yml.bak written" \
    "$([[ -f .ssd/project.yml.bak ]] && echo 0 || echo 1)"
  _assert "migrate-apply-old" ".gitignore.bak written" \
    "$([[ -f .gitignore.bak ]] && echo 0 || echo 1)"
  # Version bumps to the highest contiguous adopted version (1.18.0), capped below the guided 1.20.1.
  _assert "migrate-apply-old" "recorded version bumped to 1.18.0 (capped below guided)" \
    "$(grep -qE '^[[:space:]]*version:[[:space:]]*1\.18\.0' .ssd/project.yml && echo 0 || echo 1)"
  _assert "migrate-apply-old" "init-log appended" \
    "$([[ -f .ssd/init-log.md ]] && grep -qF '/ssd upgrade --apply' .ssd/init-log.md && echo 0 || echo 1)"

  # Idempotency: re-run from the freshly recorded version → no mechanical work, guided still surfaces.
  out2=$(bash "$MIGRATE_SCRIPT" --from 1.18.0 --to 1.22.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "migrate-apply-old" "re-run applies nothing mechanical (idempotent)" \
    "$([[ "$out2" != *APPLIED* ]] && echo 0 || echo 1)"
  _assert "migrate-apply-old" "re-run still re-surfaces guided item (R3)" \
    "$([[ "$out2" == *"GUIDED decision-record-doctrine"* ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Fixture 16: migrate.sh --apply — current-yml-v2 (v1→v2 split) extracted into the engine (v1.23.0).
# Conservative-safe form: .bak + fresh v2 skeleton + original preserved verbatim in current.notes.yml.
test_fixture_migrate_apply_v1_to_v2() {
  echo "fixture: migrate-apply-v1-to-v2"
  local tdir out
  tdir=$(fixture_setup "migrate-v1v2")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'active:\n  - slug: legacy\n    custom_user_note: "keep me"\n' > .ssd/current.yml   # v1, undocumented key
  printf 'ssd:\n  version: "1.3.0"\n' > .ssd/project.yml
  out=$(bash "$MIGRATE_SCRIPT" --from 1.3.0 --to 1.23.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "migrate-apply-v1-to-v2" "current-yml-v2 APPLIED (no longer DEFER)" \
    "$([[ "$out" == *"APPLIED current-yml-v2"* ]] && echo 0 || echo 1)"
  _assert "migrate-apply-v1-to-v2" "current.yml is now v2 (schema_version: 2)" \
    "$(grep -qE '^schema_version:[[:space:]]*2' .ssd/current.yml && echo 0 || echo 1)"
  _assert "migrate-apply-v1-to-v2" "original backed up to current.yml.bak" \
    "$([[ -f .ssd/current.yml.bak ]] && echo 0 || echo 1)"
  _assert "migrate-apply-v1-to-v2" "original (incl undocumented key) preserved in notes legacy_v1_import" \
    "$(grep -q 'legacy_v1_import' .ssd/current.notes.yml && grep -q 'custom_user_note' .ssd/current.notes.yml && echo 0 || echo 1)"
  _assert "migrate-apply-v1-to-v2" "no data loss — custom key NOT silently dropped" \
    "$(grep -q 'keep me' .ssd/current.notes.yml && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Fixture 17: migrate.sh --apply — selective .gitignore already present but marker key absent.
# Dogfood finding (MAJOR-3): the .gitignore rewrite must NOT duplicate an already-present pattern.
test_fixture_migrate_apply_gitignore_idempotent() {
  echo "fixture: migrate-apply-gitignore-idempotent"
  local tdir
  tdir=$(fixture_setup "migrate-gi-idem")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'schema_version: 2\nactive: []\n' > .ssd/current.yml
  printf 'ssd:\n  version: "1.16.0"\n' > .ssd/project.yml                       # gitignore_mode absent
  printf '.ssd/*\n!.ssd/features/**/01-architect.md\n' > .gitignore             # pattern ALREADY present
  bash "$MIGRATE_SCRIPT" --from 1.16.0 --to 1.22.0 --manifest "$MANIFEST" --apply >/dev/null 2>&1
  _assert "migrate-apply-gitignore-idempotent" "selective pattern NOT duplicated (sentinel appears once)" \
    "$([[ "$(grep -c '01-architect.md' .gitignore)" -eq 1 ]] && echo 0 || echo 1)"
  _assert "migrate-apply-gitignore-idempotent" "marker key still set in project.yml" \
    "$(grep -qE '^[[:space:]]*gitignore_mode:' .ssd/project.yml && echo 0 || echo 1)"
  _assert "migrate-apply-gitignore-idempotent" ".gitignore left untouched (no .bak written)" \
    "$([[ ! -f .gitignore.bak ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Fixture 28: strict-selective-gitignore — the allow-list must actually BLOCK. Before this migration
# `.ssd/*` matched depth-1 only, so every file under features/ and milestones/ was committable no
# matter what the `!` lines said (Feynman audit 2026-08-19, C12/C14). Negative assertions are the
# point here: a stray secrets.env must be ignored, and the declared artifact paths must not be.
test_fixture_strict_selective_gitignore() {
  echo "fixture: strict-selective-gitignore"
  local tdir
  tdir=$(fixture_setup "strict-gi")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'ssd:\n  version: "2.5.0"\n  gitignore_mode: selective\n' > .ssd/project.yml
  # The PRE-migration (inert) block, verbatim in shape: depth-1 deny + per-file allow-list.
  cat > .gitignore <<'GIEOF'
.ssd/*
!.ssd/gate.yml
!.ssd/features/
!.ssd/milestones/
!.ssd/features/**/
!.ssd/features/**/00-brief.md
!.ssd/features/**/01-architect.md
!.ssd/features/**/iterations/**/coder-status.md
!.ssd/milestones/**/
!.ssd/milestones/**/skeptic-before.md
!.ssd/milestones/**/verification.md
GIEOF
  # Precondition: the hole is real before we migrate.
  _assert "strict-selective-gitignore" "PRE: stray file is committable (the bug)" \
    "$(git check-ignore -q .ssd/features/foo/secrets.env && echo 1 || echo 0)"

  bash "$MIGRATE_SCRIPT" --from 2.5.0 --manifest "$MANIFEST" --apply >/dev/null 2>&1

  _assert "strict-selective-gitignore" "POST: stray secrets.env is BLOCKED" \
    "$(git check-ignore -q .ssd/features/foo/secrets.env && echo 0 || echo 1)"
  _assert "strict-selective-gitignore" "POST: stray file under milestones/ is BLOCKED" \
    "$(git check-ignore -q .ssd/milestones/m/anything.txt && echo 0 || echo 1)"
  _assert "strict-selective-gitignore" "POST: 00-brief.md still committable" \
    "$(git check-ignore -q .ssd/features/foo/00-brief.md && echo 1 || echo 0)"
  _assert "strict-selective-gitignore" "POST: nested iterations coder-status.md still committable" \
    "$(git check-ignore -q .ssd/features/foo/iterations/a/coder-status.md && echo 1 || echo 0)"
  _assert "strict-selective-gitignore" "POST: code-reviewer milestone review-*.md committable (C14)" \
    "$(git check-ignore -q .ssd/milestones/m/review-r1.md && echo 1 || echo 0)"
  _assert "strict-selective-gitignore" "POST: gate.yml still committable" \
    "$(git check-ignore -q .ssd/gate.yml && echo 1 || echo 0)"
  # Idempotency: re-running must not stack a second deny line.
  bash "$MIGRATE_SCRIPT" --from 2.5.0 --manifest "$MANIFEST" --apply >/dev/null 2>&1
  _assert "strict-selective-gitignore" "idempotent (deep-deny line appears exactly once)" \
    "$([[ "$(grep -cxF '.ssd/features/**' .gitignore)" -eq 1 ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Fixture 18: migrate.sh --adopt — guided adoption decouples re-surfacing from the version gate (iter C).
test_fixture_migrate_guided_adoption() {
  echo "fixture: migrate-guided-adoption"
  local tdir out_before out_after
  tdir=$(fixture_setup "migrate-adopt")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'schema_version: 2\nactive: []\n' > .ssd/current.yml
  printf 'ssd:\n  version: "1.18.0"\n  branch_pattern: "add-{slug}"\n  gitignore_mode: selective\ndeveloper_profile: expert\n' > .ssd/project.yml
  printf '.ssd/*\n!.ssd/features/**/01-architect.md\n' > .gitignore
  # Before adoption: guided outstanding, version capped below it.
  out_before=$(bash "$MIGRATE_SCRIPT" --from 1.18.0 --to 1.23.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "migrate-guided-adoption" "guided outstanding before adoption" \
    "$([[ "$out_before" == *"GUIDED decision-record-doctrine"* ]] && echo 0 || echo 1)"
  _assert "migrate-guided-adoption" "version capped at 1.18.0 before adoption" \
    "$(grep -qE '^[[:space:]]*version:[[:space:]]*"?1\.18\.0' .ssd/project.yml && echo 0 || echo 1)"
  # Adopt the guided practice.
  bash "$MIGRATE_SCRIPT" --adopt decision-record-doctrine --manifest "$MANIFEST" >/dev/null 2>&1
  _assert "migrate-guided-adoption" "adopted_guided recorded in project.yml" \
    "$(grep -qE '^[[:space:]]*adopted_guided:' .ssd/project.yml && echo 0 || echo 1)"
  # After adoption: GUIDED-ADOPTED + version advances to the target (zero drift).
  out_after=$(bash "$MIGRATE_SCRIPT" --from 1.18.0 --to 1.23.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "migrate-guided-adoption" "guided now reports GUIDED-ADOPTED" \
    "$([[ "$out_after" == *"GUIDED-ADOPTED decision-record-doctrine"* ]] && echo 0 || echo 1)"
  _assert "migrate-guided-adoption" "version advances to target 1.23.0 after adoption" \
    "$(grep -qE '^[[:space:]]*version:[[:space:]]*1\.23\.0' .ssd/project.yml && echo 0 || echo 1)"
  _assert "migrate-guided-adoption" "--adopt of a non-guided id is rejected (exit 2)" \
    "$(bash "$MIGRATE_SCRIPT" --adopt selective-gitignore --manifest "$MANIFEST" >/dev/null 2>&1; [[ $? -eq 2 ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Fixture 21: migrate.sh obsoleted_in — a convention retired in 2.0 is not offered to a 2.x-target
# upgrade (and is never re-applied), but a staged upgrade to a pre-removal target still sees it.
# Regression guard for ssd-2.0-cuts iter C (the bug: /ssd upgrade re-adding developer_profile, the
# key SSD 2.0 removed). ADR-0012/0013 obsoleted_in.
test_fixture_migrate_obsoleted_in() {
  echo "fixture: migrate-obsoleted-in"
  local tdir out_2x out_staged
  tdir=$(fixture_setup "migrate-obsoleted")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'schema_version: 2\nactive: []\n' > .ssd/current.yml
  printf 'ssd:\n  version: "1.5.0"\n' > .ssd/project.yml            # old project, NO developer_profile key
  printf '.ssd/\n' > .gitignore

  # Upgrading TO a 2.x target: the retired convention is NOT offered...
  out_2x=$(bash "$MIGRATE_SCRIPT" --from 1.5.0 --to 2.2.0 --manifest "$MANIFEST" 2>&1)
  _assert "migrate-obsoleted-in" "dev-profile-keys NOT offered when target >= obsoleted_in (2.2.0)" \
    "$([[ "$out_2x" != *"dev-profile-keys"* ]] && echo 0 || echo 1)"
  # ...and the new 2.0.0 guided deprecation entries ARE surfaced (R3 re-surfacing).
  _assert "migrate-obsoleted-in" "profile-concept-removed surfaced as GUIDED" \
    "$([[ "$out_2x" == *"GUIDED profile-concept-removed"* ]] && echo 0 || echo 1)"
  _assert "migrate-obsoleted-in" "single-surface-doctrine surfaced as GUIDED" \
    "$([[ "$out_2x" == *"GUIDED single-surface-doctrine"* ]] && echo 0 || echo 1)"

  # Staged upgrade to a PRE-removal target: the convention still applies (that target still had it).
  out_staged=$(bash "$MIGRATE_SCRIPT" --from 1.5.0 --to 1.25.0 --manifest "$MANIFEST" 2>&1)
  _assert "migrate-obsoleted-in" "dev-profile-keys STILL offered when target < obsoleted_in (1.25.0)" \
    "$([[ "$out_staged" == *"dev-profile-keys"* ]] && echo 0 || echo 1)"
  _assert "migrate-obsoleted-in" "2.0.0 guided entries NOT offered below their introduced_in (1.25.0)" \
    "$([[ "$out_staged" != *"profile-concept-removed"* ]] && echo 0 || echo 1)"

  # The bug iter C prevents: --apply to a 2.x target must NOT re-write the removed developer_profile key.
  bash "$MIGRATE_SCRIPT" --from 1.5.0 --to 2.2.0 --manifest "$MANIFEST" --apply >/dev/null 2>&1
  _assert "migrate-obsoleted-in" "developer_profile NOT re-added by --apply to 2.x (R2 regression)" \
    "$(grep -qE '^[[:space:]]*developer_profile:' .ssd/project.yml && echo 1 || echo 0)"
  fixture_teardown "$tdir"
}

# Fixture 19: gate-rules migration-manifest-current (ADR-0013 R2) — valid PASS, broken manifest FAIL.
test_fixture_manifest_current() {
  echo "fixture: migration-manifest-current"
  local tdir
  tdir=$(fixture_setup "manifest-current")
  cd "$tdir" || exit 2
  mkdir -p methodology
  printf '1.5.0\n' > VERSION
  # Valid manifest → PASS.
  printf 'migrations:\n  - id: a\n    introduced_in: "1.4.0"\n  - id: b\n    introduced_in: "1.5.0"\n' > methodology/migrations.yml
  assert_rule "manifest-current(valid)" "migration-manifest-current" "PASS"
  # Duplicate id → FAIL.
  printf 'migrations:\n  - id: a\n    introduced_in: "1.4.0"\n  - id: a\n    introduced_in: "1.5.0"\n' > methodology/migrations.yml
  assert_rule "manifest-current(dup)" "migration-manifest-current" "FAIL"
  # introduced_in newer than VERSION → FAIL.
  printf 'migrations:\n  - id: a\n    introduced_in: "9.9.9"\n' > methodology/migrations.yml
  assert_rule "manifest-current(future)" "migration-manifest-current" "FAIL"
  fixture_teardown "$tdir"
}

# Fixture 20: gate-rules yaml_get strips an inline comment on a scalar value (iter-B MAJOR-4 parser half).
test_fixture_yaml_get_inline_comment() {
  echo "fixture: yaml-get-inline-comment"
  local tdir
  tdir=$(fixture_setup "yaml-inline")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  # gitignore_mode carries an inline comment; selective pattern present so no-leaky-state runs its body.
  printf 'ssd:\n  gitignore_mode: selective   # inline comment must be stripped\n' > .ssd/project.yml
  printf '.ssd/*\n!.ssd/features/**/01-architect.md\n' > .gitignore
  printf 'placeholder\n' > a.txt
  git add a.txt .gitignore && git commit -qm base
  printf 'change\n' >> a.txt && git add a.txt && git commit -qm change
  # If yaml_get failed to strip the comment, no-leaky-state would SKIP with "unknown gitignore_mode".
  local out
  out=$(bash "$GATE_SCRIPT" --base main --rules no-leaky-state 2>&1)
  _assert "yaml-get-inline-comment" "gitignore_mode parsed as 'selective' (comment stripped, not 'unknown')" \
    "$([[ "$out" != *"unknown gitignore_mode"* ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# ---------- issue-sync.sh (mock-gh unit coverage, iter B) -------------------
#
# First real test coverage for methodology/issue-sync.sh. We can't hit live GitHub in CI, so we put a
# stub `gh` on PATH that answers only the handful of invocations close-feature/close-epic + the
# issue-sync-current gate rule make. The stub is driven by a fixture file ($MOCK_GH_ISSUES) with one
# `num|state|labels-csv|body` line per issue. This documents the exact gh contract issue-sync.sh
# depends on — if a real `gh` ever changes that contract, the stub (and these asserts) must follow.

# Write the mock `gh` into <dir>/bin/gh (executable) and echo that bin dir. Caller prepends to PATH.
setup_mock_gh() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
# Mock gh for issue-sync.sh tests. State source: $MOCK_GH_ISSUES (num|state|labels|body per line).
set -uo pipefail
F="${MOCK_GH_ISSUES:-/dev/null}"
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "repo view")   echo '{"nameWithOwner":"mock/repo"}'; exit 0 ;;
  "label create") exit 0 ;;
esac
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  num="${3:-}"; line="$(grep "^${num}|" "$F" | head -1)"
  [[ -n "$line" ]] || exit 1
  IFS='|' read -r n state labels body <<<"$line"
  if printf '%s ' "$@" | grep -q 'state,labels'; then        # gate rule: "STATE\tphase-labels"
    phl="$(printf '%s' "$labels" | tr ',' '\n' | grep '^ssd:phase/' | paste -sd, - 2>/dev/null)"
    printf '%s\t%s\n' "$state" "$phl"
  elif printf '%s ' "$@" | grep -q 'body'; then               # set-phase body read (unused here)
    printf '%s\n' "$body"
  else
    printf '%s\n' "$state"                                     # --json state --jq .state
  fi
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then       # open ssd:feature issues → "num\tbody"
  while IFS='|' read -r n state labels body; do
    [[ "$state" == "OPEN" ]] || continue
    printf '%s' "$labels" | tr ',' '\n' | grep -qx 'ssd:feature' || continue
    printf '%s\t%s\n' "$n" "$body"
  done < "$F"
  exit 0
fi
[[ "${1:-}" == "issue" && "${2:-}" == "close" ]] && exit 0
exit 0
MOCK
  chmod +x "$dir/bin/gh"
  echo "$dir/bin"
}

# Run issue-sync.sh in a mock-gh sandbox. Args: <issues-file-content> <auto_close-bool> <subcmd...>.
# Echoes "exit=<code>" on the last line plus any stderr/stdout, for the caller to grep.
run_issue_sync() {
  local issues="$1" auto_close="$2"; shift 2
  local tdir; tdir=$(mktemp -d "/tmp/ssd-issuesync.XXXXXX")
  local bindir; bindir=$(setup_mock_gh "$tdir")
  mkdir -p "$tdir/.ssd"
  printf 'integrations:\n  - type: github\n    issue_tracking: on\n    auto_close: %s\n' "$auto_close" > "$tdir/.ssd/project.yml"
  printf '%s\n' "$issues" > "$tdir/issues.txt"
  local out code
  out=$(cd "$tdir" && MOCK_GH_ISSUES="$tdir/issues.txt" PATH="$bindir:$PATH" \
        bash "$ISSUE_SYNC_SCRIPT" "$@" 2>&1); code=$?
  rm -rf "$tdir"
  printf '%s\nexit=%s\n' "$out" "$code"
}

# Fixture 21: close-feature is idempotent — an already-CLOSED issue → exit 0, state=closed.
test_fixture_close_feature_idempotent() {
  echo "fixture: close-feature-idempotent"
  local out; out=$(run_issue_sync "28|CLOSED|ssd:feature,ssd:phase/done|x: Epic: #27" false close-feature 28)
  _assert "close-feature-idempotent" "already-closed → exit 0" \
    "$([[ "$out" == *"exit=0"* ]] && echo 0 || echo 1)"
  _assert "close-feature-idempotent" "reports state=closed (idempotent)" \
    "$([[ "$out" == *"state=closed"* ]] && echo 0 || echo 1)"
}

# Fixture 22: close-feature on an OPEN issue with auto_close off and no --confirm → exit 10 needs-confirm.
test_fixture_close_feature_needs_confirm() {
  echo "fixture: close-feature-needs-confirm"
  local out; out=$(run_issue_sync "28|OPEN|ssd:feature,ssd:phase/done|x: Epic: #27" false close-feature 28)
  _assert "close-feature-needs-confirm" "auto_close off, no --confirm → exit 10" \
    "$([[ "$out" == *"exit=10"* ]] && echo 0 || echo 1)"
  _assert "close-feature-needs-confirm" "state=needs-confirm" \
    "$([[ "$out" == *"needs-confirm"* ]] && echo 0 || echo 1)"
}

# Fixture 23: close-feature --confirm overrides the gate → closes (exit 0, state=closed).
test_fixture_close_feature_confirm() {
  echo "fixture: close-feature-confirm"
  local out; out=$(run_issue_sync "28|OPEN|ssd:feature,ssd:phase/done|x: Epic: #27" false close-feature 28 --confirm)
  _assert "close-feature-confirm" "--confirm → exit 0 (closes)" \
    "$([[ "$out" == *"exit=0"* && "$out" == *"state=closed"* ]] && echo 0 || echo 1)"
}

# Fixture 24: close-epic refuses while a child ssd:feature issue is still OPEN → exit 0, state=skipped.
test_fixture_close_epic_open_children() {
  echo "fixture: close-epic-open-children"
  # The child body MUST be the format ensure_feature actually writes — `**Epic:** #N`, with markdown
  # emphasis. The original fixture used a hand-written `x: Epic: #27` (plain), a shape the writer never
  # produces, so it passed while the real guard was inert: find_open_children matched nothing for ANY
  # epic and do_close_epic concluded "all children closed" with children open. That is the guard
  # ADR-0014's D1 split exists to provide, silently failing OPEN.
  #
  # Third instance of one mechanism in this workstream: a fixture that fabricates input the system does
  # not generate (cf. the flat current.yml, and the ASCII-only filenames).
  local issues; issues=$'27|OPEN|ssd:epic|[ADR-0014] x\n28|OPEN|ssd:feature,ssd:phase/code|<!-- ssd:begin --> **Workstream:** x · **Phase:** code · **Epic:** #27 <!-- ssd:end -->'
  local out; out=$(run_issue_sync "$issues" true close-epic 27)   # auto_close ON, yet must still skip
  _assert "close-epic-open-children" "open child → exit 0 (not an error)" \
    "$([[ "$out" == *"exit=0"* ]] && echo 0 || echo 1)"
  _assert "close-epic-open-children" "state=skipped (open child blocks close even with auto_close)" \
    "$([[ "$out" == *"state=skipped"* ]] && echo 0 || echo 1)"
  _assert "close-epic-open-children" "the open child is named in the detail" \
    "$([[ "$out" == *"28"* ]] && echo 0 || echo 1)"

  # MIRROR ASSERTION — the real defence. The body WRITER and the child READER live in the same file and
  # drifted apart; assert they still agree, so a future formatting change to the body cannot silently
  # disable the guard again.
  local writer reader
  writer=$(grep -c 'Epic:\*\* #%s' "$ISSUE_SYNC_SCRIPT" || true)
  reader=$(awk '/^find_open_children\(\)/,/^}/' "$ISSUE_SYNC_SCRIPT" | grep -c 'gsub(/\[\*_\]/' || true)
  _assert "close-epic-open-children" "writer emits markdown-emphasised Epic ref" \
    "$([[ "$writer" -ge 1 ]] && echo 0 || echo 1)"
  _assert "close-epic-open-children" "reader normalises emphasis before matching (writer/reader agree)" \
    "$([[ "$reader" -ge 1 ]] && echo 0 || echo 1)"
}

# Fixture 25: close-epic with all children closed + auto_close on → closes (exit 0, state=closed).
# Also guards the #27-vs-#270 word boundary: #270 is an open child of a DIFFERENT epic and must not count.
test_fixture_close_epic_all_closed() {
  echo "fixture: close-epic-all-closed"
  local issues; issues=$'27|OPEN|ssd:epic|[ADR-0014] x\n28|CLOSED|ssd:feature,ssd:phase/done|x: Epic: #27\n270|OPEN|ssd:feature,ssd:phase/code|y: Epic: #270'
  local out; out=$(run_issue_sync "$issues" true close-epic 27)
  _assert "close-epic-all-closed" "all children closed + auto_close → exit 0 closes" \
    "$([[ "$out" == *"exit=0"* && "$out" == *"state=closed"* ]] && echo 0 || echo 1)"
  _assert "close-epic-all-closed" "#270 (different epic) not miscounted as #27 child" \
    "$([[ "$out" != *"state=skipped"* ]] && echo 0 || echo 1)"
}

# Fixture 26: issue-sync-current gate rule SKIPs cleanly when gh is absent (CI without gh stays green).
test_fixture_strict_selective_gitignore
test_fixture_issue_sync_current_skip_no_gh() {
  echo "fixture: issue-sync-current-skip-no-gh"
  local tdir; tdir=$(fixture_setup "issuesync-nogh")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'integrations:\n  - type: github\n    issue_tracking: on\n' > .ssd/project.yml
  printf 'active:\n  - slug: x\n    phase: code\n    issue: 28\n' > .ssd/current.yml
  printf 'base\n' > a.txt; git add a.txt .ssd && git commit -qm base
  # Empty PATH (only coreutils via absolute calls inside the script) → `command -v gh` fails → SKIP.
  local out; out=$(PATH="/usr/bin:/bin" bash "$GATE_SCRIPT" --base main --rules issue-sync-current 2>&1)
  _assert "issue-sync-current-skip-no-gh" "no gh on PATH → SKIP (not FAIL)" \
    "$([[ "$out" == SKIP* ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# ---------- run ------------------------------------------------------------

echo "SSD parity-test harness — gate-rules.sh structural conformance"
echo "================================================================"
# Fixture: feynman-clean (ADR-0016). Four behaviors, one of them negative: a report whose BODY
# contains lines that look like frontmatter counters must NOT be able to talk the rule out of a FAIL.
test_fixture_feynman_clean() {
  echo "fixture: feynman-clean"
  local tdir
  tdir=$(fixture_setup "feynman-clean")
  cd "$tdir" || exit 2
  mkdir -p .ssd/milestones/m1
  echo "base" > app.py
  git add -A && git commit -qm "initial"
  git checkout -qb feat

  # (a) no feynman report in the diff → SKIP. /feynman is not mandatory.
  echo "change" >> app.py
  git add -A && git commit -qm "change with no audit"
  assert_rule "feynman-clean" "feynman-clean" "SKIP"

  # (b) clean report (0 contradicted, 0 theater) → PASS
  cat > .ssd/milestones/m1/feynman.md <<'EOF'
---
skill: feynman
version: 1.1.0
claim_counts:
  verified: 6
  unverified: 1
  contradicted: 0
  theater: 0
posture: calibrated
gate_pass: true
not_examined:
  - production telemetry
---
# Feynman Audit
Body prose.
EOF
  git add -A && git commit -qm "add clean audit"
  assert_rule "feynman-clean" "feynman-clean" "PASS"

  # (c) contradicted claims → FAIL, and the gate exits non-zero
  cat > .ssd/milestones/m1/feynman.md <<'EOF'
---
skill: feynman
version: 1.1.0
claim_counts:
  contradicted: 2
  theater: 1
posture: self-deceiving
gate_pass: false
not_examined:
  - production telemetry
---
# Feynman Audit
Body prose.
EOF
  git add -A && git commit -qm "audit finds contradicted claims"
  assert_rule "feynman-clean" "feynman-clean" "FAIL"
  if bash "$GATE_SCRIPT" --base main >/dev/null 2>&1; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("feynman-clean / exit-code: expected non-zero on FAIL, got 0")
  else
    PASS_COUNT=$((PASS_COUNT + 1))
    [[ $VERBOSE -eq 1 ]] && echo "  ✓ feynman-clean / exit-code → non-zero"
  fi

  # (d) NEGATIVE: body prose that mimics clean counters must not override the frontmatter verdict.
  cat > .ssd/milestones/m1/feynman.md <<'EOF'
---
skill: feynman
version: 1.1.0
claim_counts:
  contradicted: 3
  theater: 2
posture: self-deceiving
gate_pass: false
not_examined:
  - production telemetry
---
# Feynman Audit
The two lines below are prose in the report body, not frontmatter:
contradicted: 0
theater: 0
EOF
  git add -A && git commit -qm "audit with adversarial body prose"
  assert_rule "feynman-clean" "feynman-clean" "FAIL"

  # (e) report present but claim_counts unreadable → SKIP, never a silent PASS
  cat > .ssd/milestones/m1/feynman.md <<'EOF'
---
skill: feynman
posture: unknown
---
No counters in this report.
EOF
  git add -A && git commit -qm "audit with unreadable counters"
  assert_rule "feynman-clean" "feynman-clean" "SKIP"

  fixture_teardown "$tdir"
}

# ---------- artifact store (ADR-0018) --------------------------------------

# Round-1 MAJOR-1 regression. The store location must be read with keys that are UNIQUE in
# project.yml. `root` is not: ssd-init has written `project.root` (the PROJECT's own path) since
# v1.0.0, and both readers here match the first `<key>:` at ANY indentation. Result: the DRIFT check
# advertised by store-link-sane and ADR-0018 was structurally unreachable (rdir empty ⇒ guard skipped),
# and filling in the documented config turned it into a FALSE FAIL — the rule would compare the link
# target against <project-root>/<dir>.
test_fixture_store_keys_dont_collide() {
  echo "fixture: store-keys-dont-collide"
  # 1. STRUCTURAL: neither reader may look up the bare `root` / `dir` keys.
  _assert "store-keys-dont-collide" "store.sh does not read a bare 'root' key" \
    "$(grep -qE 'yaml_scalar "\$PROJECT_YML" root([^_]|$)' "$STORE_SCRIPT" && echo 1 || echo 0)"
  _assert "store-keys-dont-collide" "store.sh does not read a bare 'dir' key" \
    "$(grep -qE 'yaml_scalar "\$PROJECT_YML" dir([^_]|$)' "$STORE_SCRIPT" && echo 1 || echo 0)"
  _assert "store-keys-dont-collide" "gate-rules.sh does not read a bare 'root'/'dir' key" \
    "$(grep -qE 'yaml_get "\$PROJECT_YML" "(root|dir)"' "$GATE_SCRIPT" && echo 1 || echo 0)"

  # 2. BEHAVIOURAL: with the documented config filled in, a HEALTHY link must PASS — the false-FAIL
  #    this defect produces. Uses a project.yml that carries `project.root`, exactly as ssd-init writes.
  local tdir out; tdir=$(fixture_setup "store-keys")
  cd "$tdir" || exit 2
  mkdir -p store/proj/features proj
  echo x > store/proj/features/brief.md
  mkdir -p proj && cd proj || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
  echo base > a.txt && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1
  ln -s "$tdir/store/proj" .ssd
  printf '.ssd\n' > .gitignore
  # project.root is the PROJECT path (as ssd-init writes it); the store keys point elsewhere.
  cat > "$tdir/store/proj/project.yml" <<EOF
project:
  name: demo
  root: $tdir/proj
ssd:
  gitignore_mode: private
  store_root: $tdir/store
  store_dir: proj
EOF
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-keys-dont-collide" "healthy link with store config filled in -> PASS" \
    "$(echo "$out" | grep -qE '^PASS store-link-sane' && echo 0 || echo 1)"
  _assert "store-keys-dont-collide" "does NOT report bogus DRIFT against the project root" \
    "$(echo "$out" | grep -q 'DRIFT' && echo 1 || echo 0)"

  # 3. And real drift MUST still be caught — a fix that just deleted the check would be worse.
  printf 'project:\n  root: %s\nssd:\n  gitignore_mode: private\n  store_root: /somewhere/else\n  store_dir: proj\n' "$tdir/proj" > "$tdir/store/proj/project.yml"
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-keys-dont-collide" "genuine drift IS caught (check kept its teeth)" \
    "$(echo "$out" | grep -q 'DRIFT' && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}


# REGRESSION GUARD, added because the suite did not have one and a change nearly shipped without it.
# Adding a bare `.ssd` line to selective.gitignore excludes the DIRECTORY, and gitignore cannot
# re-include a file whose parent directory is excluded — so every `!.ssd/features/**/…` negation goes
# inert and a selective project commits NOTHING under .ssd/. 205 assertions passed while that was true.
# This asserts the CORE PROMISE of selective mode directly.
test_fixture_selective_artifacts_still_committable() {
  echo "fixture: selective-artifacts-still-committable"
  local tdir; tdir=$(fixture_setup "sel-commit")
  cd "$tdir" || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
  mkdir -p .ssd/features/f1/iterations/b/code-review .ssd/milestones/m1
  cat "$REPO_ROOT/methodology/selective.gitignore" > .gitignore
  echo x > .ssd/features/f1/00-brief.md
  echo x > .ssd/features/f1/01-architect.md
  echo x > .ssd/features/f1/iterations/b/brief.md
  echo x > .ssd/features/f1/iterations/b/code-review/round-1.md
  echo x > .ssd/milestones/m1/verification.md
  echo x > .ssd/current.yml          # machine state — must STAY ignored
  echo x > .ssd/project.yml          # machine state — must STAY ignored

  local f
  for f in .ssd/features/f1/00-brief.md .ssd/features/f1/01-architect.md \
           .ssd/features/f1/iterations/b/brief.md \
           .ssd/features/f1/iterations/b/code-review/round-1.md \
           .ssd/milestones/m1/verification.md; do
    _assert "selective-artifacts-still-committable" "durable artifact is committable: ${f#.ssd/}" \
      "$(git check-ignore -q "$f" && echo 1 || echo 0)"
  done
  for f in .ssd/current.yml .ssd/project.yml; do
    _assert "selective-artifacts-still-committable" "machine state stays ignored: ${f#.ssd/}" \
      "$(git check-ignore -q "$f" && echo 0 || echo 1)"
  done
  # And the observable end-to-end promise: git actually stages them.
  git add -A >/dev/null 2>&1
  _assert "selective-artifacts-still-committable" "git stages the durable artifacts" \
    "$([[ "$(git diff --cached --name-only | grep -c '^\.ssd/')" -ge 5 ]] && echo 0 || echo 1)"
  _assert "selective-artifacts-still-committable" "selective.gitignore carries NO bare .ssd line" \
    "$(grep -qxF '.ssd' "$REPO_ROOT/methodology/selective.gitignore" && echo 1 || echo 0)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}


# ACCEPTANCE TEST. A symlinked `.ssd` must be ignored by BOTH canonical pattern files. It is not, and
# that is the whole safety story: a trailing-slash gitignore pattern matches DIRECTORIES ONLY, and to
# git a symlink is a file — so `.ssd/` cannot match a symlink named `.ssd`. Left unfixed, enabling the
# store would commit the absolute store path (the user's home directory) into the very repository they
# are keeping private. Uses the REAL pattern files, not a hand-written approximation.
test_fixture_store_symlink_is_ignored() {
  echo "fixture: store-symlink-is-ignored"
  # PRIVATE ONLY. selective.gitignore must NOT carry a bare `.ssd` — see
  # selective-artifacts-still-committable for why, and ADR-0018 for the reason the store requires
  # private (git cannot track files through a directory symlink at all).
  # PATTERN-FILE MODES ONLY, and `private` is the only one that has a pattern file: `blanket` needs
  # no allow-list so no blanket.gitignore exists, and `selective` must never carry a bare `.ssd`.
  # This was a one-iteration `for pat in private` loop until shellcheck (SC2043) flagged it — the
  # first lint this library ever ran (Feynman audit 2026-09-01, C10). Blanket-mode linking is covered
  # separately by store-link-blanket-mode.
  local pat=private
  {
    local tdir; tdir=$(fixture_setup "store-ign-$pat")
    cd "$tdir" || exit 2
    mkdir -p realstore/proj
    echo x > realstore/proj/project.yml
    mkdir -p proj && cd proj || exit 2
    git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
    ln -s "$tdir/realstore/proj" .ssd
    cat "$REPO_ROOT/methodology/$pat.gitignore" > .gitignore
    _assert "store-symlink-is-ignored" "$pat.gitignore ignores a symlinked .ssd" \
      "$(git check-ignore -q .ssd && echo 0 || echo 1)"
    # And the consequence if it is not: `git add -A` must not stage it.
    git add -A >/dev/null 2>&1
    _assert "store-symlink-is-ignored" "$pat: git add -A does not stage the symlink" \
      "$(git diff --cached --name-only | grep -qx '.ssd' && echo 1 || echo 0)"
    cd "$REPO_ROOT" || exit 2
    fixture_teardown "$tdir"
  }
}

# The gate's SECOND layer was equally blind: no-leaky-state's deny-list uses the same `.ssd/` prefix
# form, and matches_deny_pattern ".ssd" ".ssd/" is a NON-match. Tests the real function.
test_fixture_deny_list_catches_symlink() {
  echo "fixture: deny-list-catches-symlink"
  local probe; probe=$(mktemp "${TMPDIR:-/tmp}/mdp.XXXXXX")
  awk '/^matches_deny_pattern\(\)/,/^}/' "$GATE_SCRIPT" > "$probe"
  cat >> "$probe" <<'EOS'
matches_deny_pattern ".ssd" ".ssd" && echo EXACT_MATCH
matches_deny_pattern ".ssd/features/f/00-brief.md" ".ssd/" && echo PREFIX_STILL_WORKS
EOS
  local out; out=$(bash "$probe" 2>&1); rm -f "$probe"
  _assert "deny-list-catches-symlink" "an exact .ssd pattern matches the bare symlink path" \
    "$(echo "$out" | grep -q EXACT_MATCH && echo 0 || echo 1)"
  _assert "deny-list-catches-symlink" "the .ssd/ prefix form still matches paths beneath it" \
    "$(echo "$out" | grep -q PREFIX_STILL_WORKS && echo 0 || echo 1)"
  # BOTH baselines in gate-rules.sh must carry the exact entry.
  local sel priv
  sel=$(awk '/local baseline=\(/,/\)/' "$GATE_SCRIPT" | grep -c '"\.ssd"' || true)
  priv=$(awk '/local private_baseline=\(/,/\)/' "$GATE_SCRIPT" | grep -c '"\.ssd"' || true)
  _assert "deny-list-catches-symlink" "selective baseline carries an exact .ssd entry" \
    "$([[ "$sel" -ge 1 ]] && echo 0 || echo 1)"
  _assert "deny-list-catches-symlink" "private baseline carries an exact .ssd entry" \
    "$([[ "$priv" -ge 1 ]] && echo 0 || echo 1)"
}

# `store.sh link` MOVES a directory — the second destructive operation in the library. Dry-run by
# default (exit 10), nothing touched, no symlink created.
test_fixture_store_link_dry_run() {
  echo "fixture: store-link-dry-run"
  local tdir out rc
  tdir=$(fixture_setup "store-dry")
  cd "$tdir" || exit 2
  mkdir -p proj/.ssd/features/f1 store
  echo "# brief" > proj/.ssd/features/f1/00-brief.md
  printf 'ssd:\n  gitignore_mode: private\n' > proj/.ssd/project.yml
  cd proj || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
  echo code > app.py && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1

  out=$(bash "$STORE_SCRIPT" link "$tdir/store" 2>&1); rc=$?
  _assert "store-link-dry-run" "dry-run exits 10 (needs-confirm)" \
    "$([[ $rc -eq 10 ]] && echo 0 || echo 1)"
  _assert "store-link-dry-run" ".ssd is STILL a real directory (nothing moved)" \
    "$([[ -d .ssd && ! -L .ssd ]] && echo 0 || echo 1)"
  _assert "store-link-dry-run" "the artifact is still in place" \
    "$([[ -f .ssd/features/f1/00-brief.md ]] && echo 0 || echo 1)"
  _assert "store-link-dry-run" "the store destination was NOT populated" \
    "$([[ -z "$(ls -A "$tdir/store" 2>/dev/null)" ]] && echo 0 || echo 1)"
  _assert "store-link-dry-run" "it enumerates what would move" \
    "$(echo "$out" | grep -qF 'features/f1/00-brief.md' && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# `link --confirm` end to end, INCLUDING the two bugs the live dogfood found that no fixture had:
#   (a) `init` pre-creates <root>/<dir>, and `mv src dest` with dest an EXISTING directory moves src
#       INSIDE it — producing <dest>/.ssd/… instead of <dest>/…. The clobber guard only fired on a
#       NON-empty destination, so the happy path walked straight into it.
#   (b) verifying that the link RESOLVES is not enough: a misplaced move leaves a link to a real
#       directory whose content is one level too deep, which looks healthy until a file is opened.
test_fixture_store_link_confirm() {
  echo "fixture: store-link-confirm"
  local tdir; tdir=$(fixture_setup "store-confirm")
  cd "$tdir" || exit 2
  mkdir -p proj/.ssd/features/f1/iterations/b store
  printf 'ssd:\n  gitignore_mode: private\n' > proj/.ssd/project.yml
  echo x > proj/.ssd/features/f1/00-brief.md
  echo x > proj/.ssd/features/f1/iterations/b/brief.md
  cd proj || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
  cat "$REPO_ROOT/methodology/private.gitignore" > .gitignore
  echo code > app.py && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1

  # init FIRST, so the destination already exists — this is the trap.
  bash "$STORE_SCRIPT" init "$tdir/store" >/dev/null 2>&1
  bash "$STORE_SCRIPT" link "$tdir/store" --confirm >/dev/null 2>&1
  local rc=$?

  _assert "store-link-confirm" "link --confirm succeeds even though init pre-created the destination" \
    "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  _assert "store-link-confirm" ".ssd is now a symlink" \
    "$([[ -L .ssd ]] && echo 0 || echo 1)"
  # (b): content reachable THROUGH the link, at the right depth — not nested under an extra .ssd/.
  _assert "store-link-confirm" "artifact readable through the link (not nested one level too deep)" \
    "$([[ -f .ssd/features/f1/00-brief.md ]] && echo 0 || echo 1)"
  _assert "store-link-confirm" "nested iteration artifact readable through the link" \
    "$([[ -f .ssd/features/f1/iterations/b/brief.md ]] && echo 0 || echo 1)"
  _assert "store-link-confirm" "project.yml readable through the link" \
    "$([[ -f .ssd/project.yml ]] && echo 0 || echo 1)"
  # (a) stated directly: no doubled .ssd inside the store.
  _assert "store-link-confirm" "store contains NO doubled .ssd directory" \
    "$([[ -d "$tdir/store/proj/.ssd" ]] && echo 1 || echo 0)"
  _assert "store-link-confirm" ".gitignore gained the bare .ssd line" \
    "$(grep -qxF '.ssd' .gitignore && echo 0 || echo 1)"
  _assert "store-link-confirm" "the symlink is ignored and not staged" \
    "$(git add -A >/dev/null 2>&1; git diff --cached --name-only | grep -qx '.ssd' && echo 1 || echo 0)"
  # Idempotent re-link.
  bash "$STORE_SCRIPT" link "$tdir/store" --confirm >/dev/null 2>&1
  _assert "store-link-confirm" "re-link is idempotent (exit 0, still one symlink)" \
    "$([[ $? -eq 0 && -L .ssd ]] && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# `link` must refuse on selective mode: git cannot track files through a directory symlink, so
# selective's whole purpose (committing .ssd/features/** to the project) becomes silently impossible.
test_fixture_store_link_refuses_selective() {
  echo "fixture: store-link-refuses-selective"
  local tdir out rc; tdir=$(fixture_setup "store-sel")
  cd "$tdir" || exit 2
  mkdir -p proj/.ssd store && printf 'ssd:\n  gitignore_mode: selective\n' > proj/.ssd/project.yml
  cd proj || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t
  out=$(bash "$STORE_SCRIPT" link "$tdir/store" --confirm 2>&1); rc=$?
  _assert "store-link-refuses-selective" "refuses on selective mode (exit 2)" \
    "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"
  _assert "store-link-refuses-selective" "explains that git cannot track through a symlink" \
    "$(echo "$out" | grep -q 'beyond\|cannot track' && echo 0 || echo 1)"
  _assert "store-link-refuses-selective" "nothing was linked" \
    "$([[ -L .ssd ]] && echo 1 || echo 0)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# store-link-sane: every failure mode is a FAIL, never a SKIP, and the healthy case PASSes.
test_fixture_store_link_sane_verdicts() {
  echo "fixture: store-link-sane-verdicts"
  local tdir; tdir=$(fixture_setup "store-sane")
  cd "$tdir" || exit 2
  mkdir -p store/proj/features && printf 'ssd:\n  gitignore_mode: private\n' > store/proj/project.yml
  echo x > store/proj/features/brief.md
  mkdir -p proj && cd proj || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
  echo base > a.txt && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1

  # NOTE on the capture-then-grep shape used throughout: `bash "$GATE_SCRIPT" … | grep -q …` does NOT
  # work under this harness's `set -o pipefail` — the gate exits 1 whenever a rule FAILs, and pipefail
  # propagates that, defeating the `&&` even when grep matched. Capture first, then grep the variable.
  local out

  # (1) plain directory -> SKIP
  mkdir -p .ssd && printf 'ssd:\n  gitignore_mode: private\n' > .ssd/project.yml
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-link-sane-verdicts" "plain .ssd directory -> SKIP" \
    "$(echo "$out" | grep -qE '^SKIP store-link-sane' && echo 0 || echo 1)"
  rm -rf .ssd

  # (2) symlink, NOT ignored -> FAIL
  ln -s "$tdir/store/proj" .ssd
  : > .gitignore
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-link-sane-verdicts" "unignored symlink -> FAIL (NOT-IGNORED)" \
    "$(echo "$out" | grep -q 'NOT-IGNORED' && echo 0 || echo 1)"

  # (3) ignored + target present -> PASS
  printf '.ssd\n' > .gitignore
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-link-sane-verdicts" "ignored symlink with live target -> PASS" \
    "$(echo "$out" | grep -qE '^PASS store-link-sane' && echo 0 || echo 1)"

  # (4) tracked symlink -> FAIL (the leak already happened)
  git add -f .ssd >/dev/null 2>&1 && git commit -qm leak >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-link-sane-verdicts" "tracked symlink -> FAIL (TRACKED)" \
    "$(echo "$out" | grep -q 'TRACKED' && echo 0 || echo 1)"
  git rm -q --cached .ssd >/dev/null 2>&1; git commit -qm unleak >/dev/null 2>&1

  # (5) dangling target -> FAIL
  mv "$tdir/store/proj" "$tdir/store/moved"
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-link-sane-verdicts" "dangling target -> FAIL (DANGLING)" \
    "$(echo "$out" | grep -q 'DANGLING' && echo 0 || echo 1)"
  mv "$tdir/store/moved" "$tdir/store/proj"

  # (6) misplaced content: link resolves, but project.yml is unreachable through it -> FAIL, and NOT
  #     with a bogus SELECTIVE-MODE reason (an unreadable project.yml makes the mode default to
  #     selective; the rule must report the real problem).
  mv "$tdir/store/proj/project.yml" "$tdir/store/proj/features/"
  out=$(bash "$GATE_SCRIPT" --base main --rules store-link-sane 2>&1)
  _assert "store-link-sane-verdicts" "misplaced content -> FAIL (MISPLACED-CONTENT)" \
    "$(echo "$out" | grep -q 'MISPLACED-CONTENT' && echo 0 || echo 1)"
  _assert "store-link-sane-verdicts" "misplaced content is NOT misreported as SELECTIVE-MODE" \
    "$(echo "$out" | grep -q 'SELECTIVE-MODE' && echo 1 || echo 0)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# The store's own .gitignore must be MINIMAL. Copying SSD's project-side ignores in would silently drop
# current.yml, project.yml, archive/ and *.bak — precisely the files whose history the store exists for.
test_fixture_store_gitignore_minimal() {
  echo "fixture: store-gitignore-minimal"
  local tdir; tdir=$(fixture_setup "store-ign-min")
  cd "$tdir" || exit 2
  bash "$STORE_SCRIPT" init "$tdir/store" >/dev/null 2>&1
  local gi="$tdir/store/.gitignore" pat
  _assert "store-gitignore-minimal" "init wrote a .gitignore" "$([[ -f "$gi" ]] && echo 0 || echo 1)"
  for pat in '.ssd/*' '.ssd/features/**' '.ssd/audits/' '*.bak'; do
    _assert "store-gitignore-minimal" "store does NOT ignore '$pat'" \
      "$(grep -qxF "$pat" "$gi" 2>/dev/null && echo 1 || echo 0)"
  done
  # And the store repo must actually be able to track machine state.
  mkdir -p "$tdir/store/proj" && echo x > "$tdir/store/proj/current.yml"
  _assert "store-gitignore-minimal" "current.yml is trackable in the store" \
    "$(git -C "$tdir/store" check-ignore -q proj/current.yml && echo 1 || echo 0)"
  # init is idempotent.
  local before; before=$(git -C "$tdir/store" rev-parse --git-dir)
  bash "$STORE_SCRIPT" init "$tdir/store" >/dev/null 2>&1
  _assert "store-gitignore-minimal" "init is idempotent (same repo, not reinitialised)" \
    "$([[ "$before" == "$(git -C "$tdir/store" rev-parse --git-dir)" ]] && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# commit is LOCAL ONLY and --auto is a silent no-op when nothing changed.
test_fixture_store_commit_local_only() {
  echo "fixture: store-commit-local-only"
  local tdir out; tdir=$(fixture_setup "store-commit")
  cd "$tdir" || exit 2
  mkdir -p proj/.ssd/features && printf 'ssd:\n  gitignore_mode: private\n' > proj/.ssd/project.yml
  echo x > proj/.ssd/features/brief.md
  cd proj || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
  cat "$REPO_ROOT/methodology/private.gitignore" > .gitignore
  echo c > app.py && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1
  bash "$STORE_SCRIPT" init "$tdir/store" >/dev/null 2>&1
  bash "$STORE_SCRIPT" link "$tdir/store" --confirm >/dev/null 2>&1

  out=$(bash "$STORE_SCRIPT" commit -m "code: demo" 2>&1)
  _assert "store-commit-local-only" "commit reports a sha" \
    "$(echo "$out" | grep -qE 'STORE commit :: [0-9a-f]{7}' && echo 0 || echo 1)"
  _assert "store-commit-local-only" "commit says it did NOT push" \
    "$(echo "$out" | grep -q 'not pushed' && echo 0 || echo 1)"
  _assert "store-commit-local-only" "the store repo has a commit containing the artifacts" \
    "$(git -C "$tdir/store" log --oneline 2>/dev/null | grep -q . && echo 0 || echo 1)"
  _assert "store-commit-local-only" "store.sh contains no push call inside commit" \
    "$(awk '/^do_commit\(\)/,/^}/' "$STORE_SCRIPT" | grep -qE 'git( -C [^ ]+)? push' && echo 1 || echo 0)"
  # --auto with nothing to commit: exit 0, no new commit, no output noise.
  local n1 n2; n1=$(git -C "$tdir/store" rev-list --count HEAD)
  out=$(bash "$STORE_SCRIPT" commit --auto -m x 2>&1); local rc=$?
  n2=$(git -C "$tdir/store" rev-list --count HEAD)
  _assert "store-commit-local-only" "--auto with no changes exits 0" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  _assert "store-commit-local-only" "--auto with no changes creates no commit" "$([[ "$n1" == "$n2" ]] && echo 0 || echo 1)"
  _assert "store-commit-local-only" "--auto with no changes is silent" "$([[ -z "$out" ]] && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# ---------- recorded-defect fixes ------------------------------------------

# parse_active_workstreams fragmented ANY workstream carrying a nested list. `rail_deviations`,
# `adrs_authored` and `touches` are all documented v2 schema LIST fields, and the parser treated every
# `- ` line as a new workstream boundary — so one workstream became ~18 records, the record holding
# `issue:` had an empty slug, the rule's `[[ -n $slug ]]` guard skipped it, and issue-sync-current
# emitted "gh lookups all failed" having made ZERO gh calls. It could never PASS for a real workstream
# and had almost certainly never passed since shipping in v2.4.0.
#
# The fixture that let this through built a FLAT current.yml (slug/phase/issue, nothing nested) — a
# shape no real workstream has. This one is built from the realistic schema, which is the whole point.
test_fixture_parse_active_workstreams_nested_lists() {
  echo "fixture: parse-active-workstreams-nested-lists"
  local tdir out
  tdir=$(fixture_setup "parse-nested")
  cd "$tdir" || exit 2
  mkdir -p .ssd methodology
  printf 'integrations:\n  - type: github\n    issue_tracking: on\n' > .ssd/project.yml
  # A REALISTIC active entry: nested rail_deviations, adrs_authored and touches, with issue: LAST —
  # exactly the ordering that made the binding unreachable.
  cat > .ssd/current.yml <<'EOF'
schema_version: 2

active:
  - slug: demo-feature
    phase: code
    iteration: null
    started: 2026-08-28T00:00:00Z
    rail_deviations:
      - step: systems-designer
        reason: "no runtime"
        ts: 2026-08-28T00:00:00Z
    blockers: []
    adrs_authored:
      - ADR-0099 (something)
      - ADR-0098 (something else)
    branch: add-demo-feature
    worktree: null
    touches:
      - methodology/a.sh
      - methodology/b.sh
      - scripts/c.sh
    epic: 100
    issue: 101

archived: []
EOF
  echo base > a.txt && git add -A && git commit -qm base

  # gh MUST be available for the bug to manifest — with gh absent the rule SKIPs at the gh check
  # before the loop ever runs, so the buggy and fixed code look identical. Mock gh, and give issue 101
  # a label that MATCHES the local phase, so a correctly-parsed workstream PASSES.
  local bindir; bindir=$(setup_mock_gh "$tdir")
  printf '101|OPEN|ssd:feature,ssd:phase/code|body\n' > "$tdir/issues.txt"
  local out
  out=$(MOCK_GH_ISSUES="$tdir/issues.txt" PATH="$bindir:$PATH" \
        bash "$GATE_SCRIPT" --base main --rules issue-sync-current 2>&1)

  _assert "parse-active-workstreams-nested-lists" "the issue binding survives the nested lists → rule PASSES" \
    "$(echo "$out" | grep -qE '^PASS issue-sync-current' && echo 0 || echo 1)"
  _assert "parse-active-workstreams-nested-lists" "does NOT claim 'gh lookups all failed'" \
    "$(echo "$out" | grep -q 'gh lookups all failed' && echo 1 || echo 0)"
  _assert "parse-active-workstreams-nested-lists" "reports exactly ONE binding, not a fragmented count" \
    "$(echo "$out" | grep -qE '1 issue binding\(s\)' && echo 0 || echo 1)"

  # And real drift must still be detected — a fix that made the rule always PASS would be worse.
  printf '101|OPEN|ssd:feature,ssd:phase/deploy|body\n' > "$tdir/issues.txt"
  out=$(MOCK_GH_ISSUES="$tdir/issues.txt" PATH="$bindir:$PATH" \
        bash "$GATE_SCRIPT" --base main --rules issue-sync-current 2>&1)
  _assert "parse-active-workstreams-nested-lists" "label/phase drift still FAILs (rule kept its teeth)" \
    "$(echo "$out" | grep -qE '^FAIL issue-sync-current' && echo 0 || echo 1)"
  _assert "parse-active-workstreams-nested-lists" "drift message names the slug (not an empty string)" \
    "$(echo "$out" | grep -q 'demo-feature' && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Q2 (recorded at iteration A's ship). `committed-gate-yml` and `strict-selective-gitignore` reported
#   ERROR :: apply ran but convention still absent — inspect manually     (engine exit 3)
# when their precondition was genuinely absent — a project with NO .gitignore at all, so there is no
# file to append the `!.ssd/gate.yml` negation to and no selective block to harden. That is the same
# misleading-signal class as QUESTION-1: "cannot apply" reported as "tried and failed", telling a user
# their upgrade engine is broken when the project state is simply not ready.
#
# v2.8.0 already introduced the vocabulary for this (NOOP, return 8). These two just never used it.
test_fixture_apply_noop_on_absent_precondition() {
  echo "fixture: apply-noop-on-absent-precondition"
  local tdir out rc
  tdir=$(fixture_setup "noop-precond")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  # Recorded at 2.4.0 with the marker key present but NO .gitignore — so selective-gitignore
  # (introduced 1.18.0) is outside the window and never establishes the pattern.
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  printf 'test:\n\t@echo ok\n' > Makefile
  echo base > a.txt && git add -A && git commit -qm base

  out=$(bash "$MIGRATE_SCRIPT" --from 2.4.0 --to 2.9.0 --manifest "$MANIFEST" --apply 2>&1); rc=$?

  _assert "apply-noop-on-absent-precondition" "committed-gate-yml reports NOOP, not ERROR" \
    "$(echo "$out" | grep -qE '^NOOP committed-gate-yml' && echo 0 || echo 1)"
  _assert "apply-noop-on-absent-precondition" "strict-selective-gitignore reports NOOP, not ERROR" \
    "$(echo "$out" | grep -qE '^NOOP strict-selective-gitignore' && echo 0 || echo 1)"
  _assert "apply-noop-on-absent-precondition" "no ERROR line anywhere in the report" \
    "$(echo "$out" | grep -qE '^ERROR ' && echo 1 || echo 0)"
  _assert "apply-noop-on-absent-precondition" "--apply exits 0 (not 3 = engine error)" \
    "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  # The NOOP must name the missing precondition specifically — a generic "precondition absent" would
  # not tell the user what to do next.
  _assert "apply-noop-on-absent-precondition" "NOOP detail names the missing .gitignore precondition" \
    "$(echo "$out" | grep -qE 'NOOP (committed-gate-yml|strict-selective-gitignore).*\.gitignore' && echo 0 || echo 1)"

  # CONTROL: with the selective pattern present, both must still APPLY. A "fix" that made them
  # unconditionally NOOP would be worse than the bug.
  cat "$REPO_ROOT/methodology/selective.gitignore" > .gitignore
  out=$(bash "$MIGRATE_SCRIPT" --from 2.4.0 --to 2.9.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "apply-noop-on-absent-precondition" "control: with the pattern present, committed-gate-yml APPLIES" \
    "$(echo "$out" | grep -qE '^(APPLIED|SKIP-present) committed-gate-yml' && echo 0 || echo 1)"
  _assert "apply-noop-on-absent-precondition" "control: strict-selective-gitignore APPLIES" \
    "$(echo "$out" | grep -qE '^(APPLIED|SKIP-present) strict-selective-gitignore' && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# The fragmentation fix must not narrow the field tolerance the previous parser had. A file using
# non-canonical field indent (fields deeper than boundary+2) must still yield its binding — an
# `ind == bnd + 2` field rule was tried first and silently lost phase/issue on such a file.
test_fixture_parse_active_workstreams_indent_tolerance() {
  echo "fixture: parse-active-workstreams-indent-tolerance"
  local tdir out bindir
  tdir=$(fixture_setup "parse-indent")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'integrations:
  - type: github
    issue_tracking: on
' > .ssd/project.yml
  # Fields at boundary+4, plus a nested list — non-canonical but valid YAML.
  cat > .ssd/current.yml <<'EOF'
schema_version: 2

active:
  - slug: odd-indent
      phase: code
      touches:
        - a.sh
      issue: 77

archived: []
EOF
  echo base > a.txt && git add -A && git commit -qm base
  bindir=$(setup_mock_gh "$tdir")
  printf '77|OPEN|ssd:feature,ssd:phase/code|body
' > "$tdir/issues.txt"
  out=$(MOCK_GH_ISSUES="$tdir/issues.txt" PATH="$bindir:$PATH" \
        bash "$GATE_SCRIPT" --base main --rules issue-sync-current 2>&1)
  _assert "parse-active-workstreams-indent-tolerance" "non-canonical field indent still yields the binding" \
    "$(echo "$out" | grep -qE '^PASS issue-sync-current' && echo 0 || echo 1)"
  _assert "parse-active-workstreams-indent-tolerance" "not degraded to 'no active workstream has an issue binding'" \
    "$(echo "$out" | grep -q 'no active workstream has an issue binding' && echo 1 || echo 0)"
  fixture_teardown "$tdir"
}

# ---------- private mode (ADR-0017) ----------------------------------------

# ---- iteration B: the elective retrofit (ADR-0013 addendum, ADR-0017 amendment) ----

# An elective entry is NOT drift. It must be invisible to the default sweep: absent from the report,
# and never a participant in recorded-version advancement (a swept-but-unapplied entry PINS the
# recorded version below itself, so a leaked elective entry would freeze every project's version and
# report permanent unclosable drift).
test_fixture_elective_inert_in_default_sweep() {
  echo "fixture: elective-inert-in-default-sweep"
  local tdir out
  tdir=$(fixture_setup "elective-inert")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'ssd:\n  gitignore_mode: selective\n  version: 2.8.0\n' > .ssd/project.yml
  cat "$REPO_ROOT/methodology/selective.gitignore" > .gitignore
  printf 'test:\n\t@echo ok\n' > Makefile

  # (1) plain report over a window that INCLUDES 2.9.0 must not mention it
  out=$(bash "$MIGRATE_SCRIPT" --from 2.8.0 --to 2.9.0 --manifest "$MANIFEST" 2>&1)
  _assert "elective-inert-in-default-sweep" "plain report never lists private-mode" \
    "$(echo "$out" | grep -q 'private-mode' && echo 1 || echo 0)"

  # (2) --apply must not apply it, and must not ERROR on it
  out=$(bash "$MIGRATE_SCRIPT" --from 2.8.0 --to 2.9.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "elective-inert-in-default-sweep" "--apply never mentions private-mode" \
    "$(echo "$out" | grep -q 'private-mode' && echo 1 || echo 0)"

  # (3) and it must not pin the recorded version: with every OTHER convention satisfied, the bump
  #     must reach the target. A swept private-mode would stop it at 2.8.0.
  _assert "elective-inert-in-default-sweep" "recorded version advances to the target (not pinned)" \
    "$(grep -qE '^[[:space:]]*version:[[:space:]]*2\.9\.0' .ssd/project.yml 2>/dev/null && echo 0 || echo 1)"

  fixture_teardown "$tdir"
}

# `read_manifest` gained an 8th column (`elective`) appended after `obsoleted_in`. There are exactly
# two consumers and both must list it; a missed one silently shifts every field.
test_fixture_read_manifest_eight_columns() {
  echo "fixture: read-manifest-eight-columns"
  local total on_sep
  total=$(grep -c 'read -r id iv ap kd ad ti ob el' "$MIGRATE_SCRIPT" || true)
  on_sep=$(grep -c 'IFS="$MANIFEST_SEP" read -r id iv ap kd ad ti ob el' "$MIGRATE_SCRIPT" || true)
  _assert "read-manifest-eight-columns" "at least one read_manifest consumer exists" \
    "$([[ "$total" -ge 1 ]] && echo 0 || echo 1)"
  # EVERY consumer must be on the shared delimiter — a consumer left on tab reads shifted fields.
  _assert "read-manifest-eight-columns" "every consumer uses \$MANIFEST_SEP (none left on tab)" \
    "$([[ "$total" -eq "$on_sep" ]] && echo 0 || echo 1)"
  _assert "read-manifest-eight-columns" "no consumer remains on the 7-column read" \
    "$(grep -qE 'read -r id iv ap kd ad ti ob;' "$MIGRATE_SCRIPT" && echo 1 || echo 0)"
  _assert "read-manifest-eight-columns" "read_manifest emits an elective field" \
    "$(awk '/^read_manifest\(\)/,/^}/' "$MIGRATE_SCRIPT" | grep -q 'elective' && echo 0 || echo 1)"
}

# THE BUG THIS ITERATION ALMOST SHIPPED. `read_manifest` records must survive an EMPTY MIDDLE FIELD.
# Tab is IFS *whitespace*, so bash collapses consecutive tabs and every field after an empty one
# shifts left. The 7-column form was safe only because its one optional field (obsoleted_in) was
# LAST. Appending `elective` after it made every entry lacking an obsoleted_in — i.e. all of them —
# read `elective` into the `ob` slot, so `--elect` rejected its own manifest entry as "not elective".
#
# Tests the OBSERVABLE SYMPTOM, not the delimiter choice or the internals: private-mode has
# `elective: true` and no `obsoleted_in`, so if fields shift, --elect cannot see its own entry.
test_fixture_read_manifest_empty_middle_field() {
  echo "fixture: read-manifest-empty-middle-field"
  local tdir out
  tdir=$(fixture_setup "empty-field")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  echo base > a.txt && git add -A && git commit -qm base

  out=$(bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" 2>&1)
  # The exact symptom of a shifted field:
  _assert "read-manifest-empty-middle-field" "--elect does NOT reject private-mode as non-elective" \
    "$(echo "$out" | grep -q 'is not an elective migration' && echo 1 || echo 0)"
  _assert "read-manifest-empty-middle-field" "--elect does NOT misread the kind" \
    "$(echo "$out" | grep -q "only mechanical entries have an apply path" && echo 1 || echo 0)"
  _assert "read-manifest-empty-middle-field" "--elect reaches the interlock" \
    "$(echo "$out" | grep -q 'HISTORY IS NOT REWRITTEN' && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

test_fixture_elect_lists_every_tracked_file() {
  echo "fixture: elect-lists-every-tracked-file"
  local tdir out rc
  tdir=$(fixture_setup "elect-list")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features/f1 docs/decisions docs/runbooks docs/architecture
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  echo "# brief"   > .ssd/features/f1/00-brief.md
  echo "# ADR-1"   > docs/decisions/ADR-0001-a.md
  echo "# ADR-2"   > docs/decisions/ADR-0002-b.md
  echo "# runbook" > docs/runbooks/deploy.md
  echo "# arch"    > docs/architecture/overview.md
  echo "code"      > app.py
  git add -A && git commit -qm "project with committed SSD artifacts"

  out=$(bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" 2>&1); rc=$?
  local f
  for f in .ssd/features/f1/00-brief.md docs/decisions/ADR-0001-a.md docs/decisions/ADR-0002-b.md \
           docs/runbooks/deploy.md docs/architecture/overview.md; do
    _assert "elect-lists-every-tracked-file" "lists $f" \
      "$(echo "$out" | grep -qF "$f" && echo 0 || echo 1)"
  done
  _assert "elect-lists-every-tracked-file" "does NOT list unrelated tracked code (app.py)" \
    "$(echo "$out" | grep -qF 'app.py' && echo 1 || echo 0)"
  _assert "elect-lists-every-tracked-file" "exits 10 (needs-confirm)" \
    "$([[ $rc -eq 10 ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Dry-run means dry. A user who runs the command to SEE what it would do must not come back to a
# modified repo — not the pattern, not the config, not the git index.
# THE ACCEPTANCE TEST FOR ITERATION B. A default sweep must NEVER untrack anything. If `--apply`
# on an ordinary project can remove SSD artifacts from the index, the feature is worse than not
# shipping: a team repo would be converted to a privacy posture nobody asked for by a routine upgrade.
test_fixture_elective_not_applied_by_sweep() {
  echo "fixture: elective-not-applied-by-sweep"
  local tdir before after
  tdir=$(fixture_setup "sweep-safe")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features/f1 docs/decisions
  printf 'ssd:\n  gitignore_mode: selective\n  version: 2.8.0\n' > .ssd/project.yml
  echo "# brief" > .ssd/features/f1/00-brief.md
  echo "# ADR"   > docs/decisions/ADR-0001-a.md
  echo code      > app.py
  printf 'test:\n\t@echo ok\n' > Makefile
  git add -A && git commit -qm "team repo with committed SSD artifacts"
  before=$(git ls-files | sort | git hash-object --stdin)

  # The most dangerous invocation: a full-window --apply on a project that never asked for privacy.
  bash "$MIGRATE_SCRIPT" --from 2.0.0 --to 2.9.0 --manifest "$MANIFEST" --apply >/dev/null 2>&1
  after=$(git ls-files | sort | git hash-object --stdin)

  _assert "elective-not-applied-by-sweep" "--apply untracks NOTHING (index identical)" \
    "$([[ "$before" == "$after" ]] && echo 0 || echo 1)"
  _assert "elective-not-applied-by-sweep" "SSD artifacts still tracked after the sweep" \
    "$(git ls-files --error-unmatch .ssd/features/f1/00-brief.md docs/decisions/ADR-0001-a.md >/dev/null 2>&1 && echo 0 || echo 1)"
  _assert "elective-not-applied-by-sweep" "the sweep did NOT switch the project to private mode" \
    "$(grep -qE '^[[:space:]]*gitignore_mode:[[:space:]]*private' .ssd/project.yml && echo 1 || echo 0)"
  _assert "elective-not-applied-by-sweep" "the sweep did NOT append the private pattern" \
    "$(grep -qxF '# ssd:gitignore-mode=private' .gitignore 2>/dev/null && echo 1 || echo 0)"
  # SECOND LAYER, pinned so it cannot be quietly removed: elective ids must stay out of the swept
  # dispatchers entirely. Reversion showed removing the report-loop skip ALONE does not make the
  # sweep destructive — it is only destructive if this layer goes too. Both must hold.
  _assert "elective-not-applied-by-sweep" "private-mode is absent from apply_dispatch (swept path)" \
    "$(awk '/^apply_dispatch\(\)/,/^}/' "$MIGRATE_SCRIPT" | grep -qE '^\s+private-mode\)' && echo 1 || echo 0)"
  _assert "elective-not-applied-by-sweep" "private-mode is absent from detect() (swept path)" \
    "$(awk '/^detect\(\) \{/,/^}/' "$MIGRATE_SCRIPT" | grep -qE '^\s+private-mode\)' && echo 1 || echo 0)"
  fixture_teardown "$tdir"
}

# The interlock must distinguish files SSD demonstrably produced from files it cannot vouch for.
# Over-flagging is not "safe": a warning that fires on SSD's own runbooks trains the user to ignore
# it, which destroys the signal the interlock exists to give.
# Round-1 MAJOR-1 / MINOR-2 regression. `git ls-files` C-QUOTES any path with non-ASCII bytes:
#   "docs/decisions/ADR-0002-h\303\251llo.md"
# The quoted string cannot match the ADR pattern (so it misclassifies), `[[ -f ]]` is false for it (so
# the frontmatter probe cannot run), and `git rm --cached` rejects it as a pathspec — and git validates
# ALL pathspecs before acting, so ONE accented filename made the whole retrofit impossible.
#
# Every new fixture in this iteration used ASCII names, which is exactly how a total-failure bug got
# through a red-first, reversion-verified test pass. Red-first on the cases you thought of is not
# coverage.
test_fixture_elect_handles_unusual_filenames() {
  echo "fixture: elect-handles-unusual-filenames"
  local tdir out rc
  tdir=$(fixture_setup "elect-odd-names")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features docs/decisions
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  echo x > "docs/decisions/ADR-0001-with space.md"      # spaces: unquoted by git, must keep working
  echo y > "docs/decisions/ADR-0002-héllo.md"           # non-ASCII: git C-quotes this one
  echo z > ".ssd/features/quote'name.md"                # apostrophe
  git add -A && git commit -qm "artifacts with unusual names"

  out=$(bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" 2>&1)
  _assert "elect-handles-unusual-filenames" "no C-quoted/escaped path appears in the output" \
    "$(echo "$out" | grep -qE '\\\\[0-9]{3}|^\s*!?!?\s*"' && echo 1 || echo 0)"
  # Check the SSD-owned section POSITIVELY contains the real (unescaped) name. Grepping the UNCONFIRMED
  # section for the real name would pass vacuously, because a C-quoted path renders as h\303\251llo.
  _assert "elect-handles-unusual-filenames" "the non-ASCII ADR is listed under SSD-owned by its real name" \
    "$(echo "$out" | sed -n '/SSD-owned/,/UNCONFIRMED\|HISTORY/p' | grep -qF 'ADR-0002-héllo.md' && echo 0 || echo 1)"

  # The whole point: --confirm must actually complete.
  bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" --confirm >/dev/null 2>&1; rc=$?
  _assert "elect-handles-unusual-filenames" "--confirm succeeds (exit 0) despite unusual names" \
    "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  _assert "elect-handles-unusual-filenames" "every SSD path is untracked, including the non-ASCII one" \
    "$(git ls-files -- .ssd docs/decisions | grep -q . && echo 1 || echo 0)"
  _assert "elect-handles-unusual-filenames" "files remain on disk" \
    "$([[ -f "docs/decisions/ADR-0002-héllo.md" && -f ".ssd/features/quote'name.md" ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Round-1 MAJOR-2 regression: a failed election must leave the repo UNTOUCHED, never half-migrated
# (config recorded private while every artifact stays tracked — a state neither mode describes, and one
# the diff-scoped no-leaky-state rule notices only when there happens to be a diff).
#
# Two assertions of different kinds, and the reason is worth stating: once MAJOR-1's `-z` fix landed,
# the only failure this fixture could previously trigger (a C-quoted pathspec) stopped failing. Every
# remaining runtime failure — a path vanishing between enumeration and rm — needs injection the harness
# cannot do. So this pins (1) the one reachable failure path behaviorally, and (2) the ORDERING
# invariant structurally, which is what MAJOR-2 is actually about.
test_fixture_elect_no_partial_state_on_failure() {
  echo "fixture: elect-no-partial-state-on-failure"
  local tdir gi_before pj_before body dry_line cfg_line
  tdir=$(fixture_setup "elect-atomic")
  cd "$tdir" || exit 2
  mkdir -p .ssd docs/decisions
  # No `ssd:` block → apply_private_mode_config refuses. Reachable, and it must change nothing.
  printf 'notssd:\n  x: 1\n' > .ssd/project.yml
  cat "$REPO_ROOT/methodology/selective.gitignore" > .gitignore
  echo "# ADR" > docs/decisions/ADR-0001-a.md
  git add -A && git commit -qm base
  gi_before=$(git hash-object .gitignore)
  pj_before=$(git hash-object .ssd/project.yml)

  bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" --confirm >/dev/null 2>&1

  _assert "elect-no-partial-state-on-failure" "a failed election leaves .gitignore untouched" \
    "$([[ "$gi_before" == "$(git hash-object .gitignore)" ]] && echo 0 || echo 1)"
  _assert "elect-no-partial-state-on-failure" "a failed election leaves project.yml untouched" \
    "$([[ "$pj_before" == "$(git hash-object .ssd/project.yml)" ]] && echo 0 || echo 1)"
  _assert "elect-no-partial-state-on-failure" "the ADR is still tracked (no partial untracking)" \
    "$(git ls-files --error-unmatch docs/decisions/ADR-0001-a.md >/dev/null 2>&1 && echo 0 || echo 1)"

  # ORDERING: the destructive step must be VALIDATED before anything is written. If
  # apply_private_mode_config runs first, any rm failure yields the half-migrated state.
  body=$(awk '/^elect_private_mode\(\)/,/^}/' "$MIGRATE_SCRIPT")
  dry_line=$(echo "$body" | grep -n 'rm --cached --dry-run' | head -1 | cut -d: -f1)
  cfg_line=$(echo "$body" | grep -n 'apply_private_mode_config' | head -1 | cut -d: -f1)
  _assert "elect-no-partial-state-on-failure" "a --dry-run pre-flight exists" \
    "$([[ -n "$dry_line" ]] && echo 0 || echo 1)"
  _assert "elect-no-partial-state-on-failure" "the dry-run pre-flight precedes the config write" \
    "$([[ -n "$dry_line" && -n "$cfg_line" && "$dry_line" -lt "$cfg_line" ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

test_fixture_elect_classifies_docs() {
  echo "fixture: elect-classifies-docs"
  local tdir out
  tdir=$(fixture_setup "elect-classify")
  cd "$tdir" || exit 2
  mkdir -p .ssd docs/decisions docs/runbooks docs/architecture
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  echo "# ADR" > docs/decisions/ADR-0001-a.md
  printf -- '---\nskill: systems-designer\nversion: 1.5.0\n---\n# runbook\n' > docs/runbooks/deploy.md
  echo "our own doc, not SSD's" > docs/architecture/team-owned.md
  git add -A && git commit -qm base

  out=$(bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" 2>&1)
  _assert "elect-classifies-docs" "an ADR is recognized as SSD-produced" \
    "$(echo "$out" | grep -A20 'SSD-owned' | grep -q 'ADR-0001-a.md' && echo 0 || echo 1)"
  _assert "elect-classifies-docs" "a runbook with SSD frontmatter is recognized (not flagged)" \
    "$(echo "$out" | grep -q '!! docs/runbooks/deploy.md' && echo 1 || echo 0)"
  _assert "elect-classifies-docs" "a team-owned doc IS flagged for review" \
    "$(echo "$out" | grep -q '!! docs/architecture/team-owned.md' && echo 0 || echo 1)"
  _assert "elect-classifies-docs" "the flag heading claims only UNCONFIRMED, not authorship" \
    "$(echo "$out" | grep -q 'UNCONFIRMED as SSD-produced' && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# The history limitation must appear in BOTH runs. A user who only ever sees the confirmed run must
# still be told, and a user who only dry-runs must be told too.
test_fixture_elect_history_warning_both_runs() {
  echo "fixture: elect-history-warning-both-runs"
  local tdir dry conf
  tdir=$(fixture_setup "elect-warn")
  cd "$tdir" || exit 2
  mkdir -p .ssd docs/decisions
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  echo "# ADR" > docs/decisions/ADR-0001-a.md
  git add -A && git commit -qm base
  dry=$(bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" 2>&1)
  conf=$(bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" --confirm 2>&1)
  _assert "elect-history-warning-both-runs" "dry-run warns that history is not rewritten" \
    "$(echo "$dry" | grep -q 'HISTORY IS NOT REWRITTEN' && echo 0 || echo 1)"
  _assert "elect-history-warning-both-runs" "confirmed run warns too" \
    "$(echo "$conf" | grep -q 'HISTORY IS NOT REWRITTEN' && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# --confirm untracks, leaves files ON DISK, records the mode, and is idempotent on re-run.
test_fixture_elect_confirm_untracks() {
  echo "fixture: elect-confirm-untracks"
  local tdir rc out
  tdir=$(fixture_setup "elect-confirm")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features/f1 docs/decisions
  # `decoy:` comes FIRST and carries a same-named key — an unscoped first-match helper would edit it
  # and leave ssd.gitignore_mode untouched.
  printf 'decoy:\n  gitignore_mode: decoy\nssd:\n  gitignore_mode: selective\n  branch_pattern: "add-{slug}"\nintegrations:\n  - type: github\n    issue_tracking: on\n' > .ssd/project.yml
  echo "# brief" > .ssd/features/f1/00-brief.md
  echo "# ADR"   > docs/decisions/ADR-0001-a.md
  echo code      > app.py
  git add -A && git commit -qm base

  bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" --confirm >/dev/null 2>&1
  _assert "elect-confirm-untracks" "SSD paths untracked" \
    "$(git ls-files -- .ssd docs/decisions | grep -q . && echo 1 || echo 0)"
  _assert "elect-confirm-untracks" "unrelated code still tracked" \
    "$(git ls-files --error-unmatch app.py >/dev/null 2>&1 && echo 0 || echo 1)"
  _assert "elect-confirm-untracks" "files remain ON DISK (untracked, not deleted)" \
    "$([[ -f docs/decisions/ADR-0001-a.md && -f .ssd/features/f1/00-brief.md ]] && echo 0 || echo 1)"
  _assert "elect-confirm-untracks" "gitignore_mode recorded private" \
    "$(grep -qE '^[[:space:]]*gitignore_mode:[[:space:]]*private' .ssd/project.yml && echo 0 || echo 1)"
  # Round-1 MINOR-1: set_yaml_scalar is block-scoped. A decoy `gitignore_mode` under an EARLIER
  # top-level block must be left alone, and `issue_tracking` must be found under `integrations:` even
  # though it lives in a list item rather than directly under a top-level key.
  _assert "elect-confirm-untracks" "a decoy key under an earlier block is NOT rewritten" \
    "$(grep -qE '^[[:space:]]+gitignore_mode:[[:space:]]*decoy' .ssd/project.yml && echo 0 || echo 1)"
  _assert "elect-confirm-untracks" "issue_tracking rewritten inside integrations (list-item scope)" \
    "$(grep -qE '^[[:space:]]+issue_tracking:[[:space:]]*off' .ssd/project.yml && echo 0 || echo 1)"
  _assert "elect-confirm-untracks" "branch_pattern rewritten to {slug}" \
    "$(grep -qE '^[[:space:]]*branch_pattern:[[:space:]]*"\{slug\}"' .ssd/project.yml && echo 0 || echo 1)"
  _assert "elect-confirm-untracks" "private pattern appended with sentinel" \
    "$(grep -qxF '# ssd:gitignore-mode=private' .gitignore && echo 0 || echo 1)"
  # Idempotent second run.
  out=$(bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" --confirm 2>&1); rc=$?
  _assert "elect-confirm-untracks" "re-run is a clean no-op (exit 0)" \
    "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  _assert "elect-confirm-untracks" "re-run says nothing to do" \
    "$(echo "$out" | grep -q 'nothing to do' && echo 0 || echo 1)"
  _assert "elect-confirm-untracks" "re-run did not duplicate the pattern block" \
    "$([[ "$(grep -cxF '# ssd:gitignore-mode=private' .gitignore)" -eq 1 ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Validation: three distinct refusals, each exit 2.
test_fixture_elect_validation() {
  echo "fixture: elect-validation"
  local tdir out rc
  tdir=$(fixture_setup "elect-valid")
  cd "$tdir" || exit 2
  mkdir -p .ssd && printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  echo base > a.txt && git add -A && git commit -qm base

  out=$(bash "$MIGRATE_SCRIPT" --elect no-such-id --manifest "$MANIFEST" 2>&1); rc=$?
  _assert "elect-validation" "unknown id → exit 2" "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"
  _assert "elect-validation" "unknown id message names the manifest" \
    "$(echo "$out" | grep -q 'not a migration id in the manifest' && echo 0 || echo 1)"

  out=$(bash "$MIGRATE_SCRIPT" --elect selective-gitignore --manifest "$MANIFEST" 2>&1); rc=$?
  _assert "elect-validation" "swept (non-elective) id → exit 2" "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"
  _assert "elect-validation" "swept id message points at --apply" \
    "$(echo "$out" | grep -q 'applied with --apply' && echo 0 || echo 1)"

  out=$(bash "$MIGRATE_SCRIPT" --elect decision-record-doctrine --manifest "$MANIFEST" 2>&1); rc=$?
  _assert "elect-validation" "guided id → exit 2" "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"

  out=$(bash "$MIGRATE_SCRIPT" --elect --manifest "$MANIFEST" 2>&1); rc=$?
  _assert "elect-validation" "--elect with no value → exit 2" "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

test_fixture_elect_dry_run_mutates_nothing() {
  echo "fixture: elect-dry-run-mutates-nothing"
  local tdir before_gi before_pj before_idx
  tdir=$(fixture_setup "elect-dry")
  cd "$tdir" || exit 2
  mkdir -p .ssd docs/decisions
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  cat "$REPO_ROOT/methodology/selective.gitignore" > .gitignore
  echo "# ADR" > docs/decisions/ADR-0001-a.md
  git add -A && git commit -qm base

  before_gi=$(git hash-object .gitignore)
  before_pj=$(git hash-object .ssd/project.yml)
  before_idx=$(git ls-files | sort | git hash-object --stdin)

  bash "$MIGRATE_SCRIPT" --elect private-mode --manifest "$MANIFEST" >/dev/null 2>&1

  _assert "elect-dry-run-mutates-nothing" ".gitignore unchanged" \
    "$([[ "$before_gi" == "$(git hash-object .gitignore)" ]] && echo 0 || echo 1)"
  _assert "elect-dry-run-mutates-nothing" "project.yml unchanged" \
    "$([[ "$before_pj" == "$(git hash-object .ssd/project.yml)" ]] && echo 0 || echo 1)"
  _assert "elect-dry-run-mutates-nothing" "git index unchanged (nothing untracked)" \
    "$([[ "$before_idx" == "$(git ls-files | sort | git hash-object --stdin)" ]] && echo 0 || echo 1)"
  _assert "elect-dry-run-mutates-nothing" "no .bak files written" \
    "$([[ -z "$(find . -name '*.bak' 2>/dev/null)" ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Round-1 QUESTION-1 regression. A COMMENTED test_command placeholder deliberately does not satisfy
# detect() (it does not define the input), so an apply that writes one must NOT report success. It
# used to return 0, which made the caller emit `ERROR :: apply ran but convention still absent`,
# set engine_error=1, and exit 3 — so `/ssd upgrade --apply` reported a BROKEN ENGINE on every
# project that simply has no test framework yet. It must be NOOP with exit 0.
test_fixture_apply_noop_not_error() {
  echo "fixture: apply-noop-not-error"
  local tdir out rc
  tdir=$(fixture_setup "apply-noop")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'ssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  # Realistic 2.4.0-era project: selective block present, no test framework of any kind.
  cat "$REPO_ROOT/methodology/selective.gitignore" > .gitignore

  out=$(bash "$MIGRATE_SCRIPT" --from 2.4.0 --to 2.8.0 --manifest "$MANIFEST" --apply 2>&1); rc=$?
  _assert "apply-noop-not-error" "gate-inputs-present reports NOOP, not ERROR" \
    "$(echo "$out" | grep -qE '^NOOP gate-inputs-present' && echo 0 || echo 1)"
  _assert "apply-noop-not-error" "no ERROR line anywhere in the report" \
    "$(echo "$out" | grep -qE '^ERROR ' && echo 1 || echo 0)"
  _assert "apply-noop-not-error" "--apply exits 0 (not 3 = engine error)" \
    "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  # The NOOP must be actionable: say what is missing and what to do about it.
  _assert "apply-noop-not-error" "NOOP detail names the missing precondition and the fix" \
    "$(echo "$out" | grep -qE 'no test framework detected.*set test_command' && echo 0 || echo 1)"
  # And it must stay PENDING-equivalent: the recorded version must NOT advance past an unapplied
  # convention, or the next --apply would never re-offer it.
  _assert "apply-noop-not-error" "recorded version does not advance past the NOOP entry" \
    "$(grep -qE '^[[:space:]]*version:[[:space:]]*2\.(5|6|7|8)' .ssd/project.yml 2>/dev/null && echo 1 || echo 0)"

  # Control: WITH a test framework the same run must APPLY and write a real key.
  printf 'test:\n\t@echo ok\n' > Makefile
  out=$(bash "$MIGRATE_SCRIPT" --from 2.4.0 --to 2.8.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "apply-noop-not-error" "control: with a Makefile test target it APPLIES" \
    "$(echo "$out" | grep -qE '^APPLIED gate-inputs-present' && echo 0 || echo 1)"

  fixture_teardown "$tdir"
}

# Round-1 MAJOR-1 regression. `file_mtime` must try the GNU form FIRST and validate the result is a
# bare integer. BSD-first corrupts the value on every Linux host: on GNU, `-f` is --file-system, so
# `stat -f %m FILE` prints a filesystem status block to STDOUT before failing, and that garbage is
# then compared against an epoch. Structural assertion by necessity — the failure manifests only on
# the other platform, so behavior alone cannot pin it from one OS.
test_fixture_file_mtime_portability() {
  echo "fixture: file-mtime-portability"
  # Scope the ordering check to the FUNCTION BODY. Grepping the whole file matches the explanatory
  # comment above file_mtime, which names both forms — the assertion then passes for the wrong reason
  # (verified: it stayed green against the reverted BSD-first code). A test that cannot fail is worse
  # than no test.
  local body gnu bsd
  body=$(awk '/^file_mtime\(\)/,/^}/' "$GATE_SCRIPT")
  gnu=$(echo "$body" | grep -n 'stat -c %Y' | head -1 | cut -d: -f1)
  bsd=$(echo "$body" | grep -n 'stat -f %m' | head -1 | cut -d: -f1)
  _assert "file-mtime-portability" "GNU form (stat -c %Y) is attempted before BSD (stat -f %m)" \
    "$([[ -n "$gnu" && -n "$bsd" && "$gnu" -lt "$bsd" ]] && echo 0 || echo 1)"
  _assert "file-mtime-portability" "file_mtime validates its output is a bare integer" \
    "$(awk '/^file_mtime\(\)/,/^}/' "$GATE_SCRIPT" | grep -qF '^[0-9]+$' && echo 0 || echo 1)"
  # And the probe must actually work on THIS platform, whichever it is.
  local tdir mt
  tdir=$(fixture_setup "file-mtime")
  cd "$tdir" || exit 2
  echo x > f
  mt=$(bash -c 'v=$(stat -c %Y f 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; exit; }
                v=$(stat -f %m f 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; exit; }')
  _assert "file-mtime-portability" "the probe returns a bare integer on this host" \
    "$([[ "$mt" =~ ^[0-9]+$ ]] && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Round-1 MAJOR-2 regression. The private branch used to `return` before reading
# project.yml.ssd.gitignored_state, silently unenforcing a project's own patterns in the one mode
# where no-leaky-state is the primary safety layer.
test_fixture_private_honors_gitignored_state() {
  echo "fixture: private-honors-gitignored-state"
  local tdir
  tdir=$(fixture_setup "private-extra")
  cd "$tdir" || exit 2
  mkdir -p .ssd secrets
  cat > .ssd/project.yml <<'EOF'
ssd:
  gitignore_mode: private
  gitignored_state:
    - secrets/**
EOF
  echo "base" > app.py
  git add -A app.py && git commit -qm "initial"
  git checkout -qb feat

  # (a) control — a code-only change is clean
  echo "change" >> app.py
  git add -A app.py && git commit -qm "code only"
  assert_rule "private-honors-gitignored-state" "no-leaky-state" "PASS"

  # (b) a project-declared pattern in the diff must FAIL, exactly as under selective mode
  echo "hunter2" > secrets/key.txt
  git add -f secrets/key.txt && git commit -qm "leak a project-declared secret"
  assert_rule "private-honors-gitignored-state" "no-leaky-state" "FAIL"

  fixture_teardown "$tdir"
}

# Round-1 MINOR-1 regression. Worktree scope must recognize the SAME artifact set as diff scope: the
# mode changes where the rule looks, not what counts as a report. `feynman-*.md` belongs to
# docs/audits/ only; a draft or superseded report under .ssd/ must not FAIL the gate.
test_fixture_feynman_private_scope_mirrors_diff() {
  echo "fixture: feynman-private-scope-mirrors-diff"
  local tdir
  tdir=$(fixture_setup "feynman-scope")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features/f1
  printf 'ssd:\n  gitignore_mode: private\n' > .ssd/project.yml
  echo "base" > app.py
  git add -A app.py && git commit -qm "initial"
  git checkout -qb feat
  echo "change" >> app.py
  git add -A app.py && git commit -qm "code only"

  # A superseded/draft report under .ssd/ is NOT a report — diff scope would never match it either.
  cat > .ssd/features/f1/feynman-draft.md <<'EOF'
---
skill: feynman
claim_counts:
  contradicted: 9
  theater: 9
gate_pass: false
---
Draft, superseded.
EOF
  assert_rule "feynman-private-scope-mirrors-diff" "feynman-clean" "SKIP"

  # The canonical filename IS a report, and still FAILs on contradicted claims.
  cat > .ssd/features/f1/feynman.md <<'EOF'
---
skill: feynman
claim_counts:
  contradicted: 1
  theater: 0
gate_pass: false
---
Real report.
EOF
  assert_rule "feynman-private-scope-mirrors-diff" "feynman-clean" "FAIL"

  fixture_teardown "$tdir"
}

# The canonical pattern file itself. Private mode's whole promise is "no `!` negation anywhere";
# a stray negation would re-expose an artifact class silently.
test_fixture_private_gitignore_sentinel() {
  echo "fixture: private-gitignore-sentinel"
  local pf="$REPO_ROOT/methodology/private.gitignore"
  _assert "private-gitignore-sentinel" "methodology/private.gitignore exists" \
    "$([[ -f "$pf" ]] && echo 0 || echo 1)"
  _assert "private-gitignore-sentinel" "carries the # ssd:gitignore-mode=private sentinel" \
    "$(grep -qxF '# ssd:gitignore-mode=private' "$pf" 2>/dev/null && echo 0 || echo 1)"
  # No negation of ANY kind — in particular no !.ssd/gate.yml (ADR-0015 inputs cannot be committed).
  _assert "private-gitignore-sentinel" "contains NO '!' negation line" \
    "$(grep -qE '^[[:space:]]*!' "$pf" 2>/dev/null && echo 1 || echo 0)"
  for pat in '.ssd/' 'docs/decisions/' 'docs/runbooks/' 'docs/architecture/'; do
    _assert "private-gitignore-sentinel" "ignores $pat" \
      "$(grep -qxF "$pat" "$pf" 2>/dev/null && echo 0 || echo 1)"
  done
}

# The deny-list in gate-rules.sh and the pattern file are the same set in two syntaxes. ADR-0008
# § "Future Compatibility" warns a forgotten side is a silent leak; under private mode that leak is
# a privacy failure. This is the only mechanical defense against the two drifting apart.
#
# SET EQUALITY, not a spot-check (round-1 SUGGESTION-1). The earlier version asserted that four
# KNOWN patterns appeared in both files, which could not detect the failure it existed to prevent:
# adding a fifth pattern to one file only left it green, because the fixture never learned about the
# fifth. Comparing the full sets means any divergence — an addition, a removal, or a typo on either
# side — fails by construction, with no fixture edit required.
test_fixture_private_deny_list_mirrors_pattern() {
  echo "fixture: deny-list-mirrors-pattern-file"
  local pf="$REPO_ROOT/methodology/private.gitignore"
  _assert "deny-list-mirrors-pattern-file" "methodology/private.gitignore exists" \
    "$([[ -f "$pf" ]] && echo 0 || echo 1)"
  [[ -f "$pf" ]] || return

  # Pattern file: every non-comment, non-blank line, trailing whitespace trimmed.
  local from_file from_code
  from_file=$(grep -vE '^[[:space:]]*(#|$)' "$pf" | sed 's/[[:space:]]*$//' | sort -u)

  # gate-rules.sh: the quoted tokens of the private_baseline array. The awk range tolerates the array
  # being reflowed across lines, so a future `git diff`-driven reformat cannot quietly break the test.
  from_code=$(awk '/private_baseline=\(/,/\)/' "$GATE_SCRIPT" \
              | grep -o '"[^"]*"' | tr -d '"' | sort -u)

  _assert "deny-list-mirrors-pattern-file" "both sides are non-empty (extraction actually worked)" \
    "$([[ -n "$from_file" && -n "$from_code" ]] && echo 0 || echo 1)"
  _assert "deny-list-mirrors-pattern-file" "private.gitignore and gate-rules private_baseline are the SAME SET" \
    "$([[ "$from_file" == "$from_code" ]] && echo 0 || echo 1)"
  if [[ $VERBOSE -eq 1 && "$from_file" != "$from_code" ]]; then
    echo "    --- only in private.gitignore ---"; comm -23 <(echo "$from_file") <(echo "$from_code") | sed 's/^/    /'
    echo "    --- only in private_baseline ---"; comm -13 <(echo "$from_file") <(echo "$from_code") | sed 's/^/    /'
  fi
}

# Under private mode no-leaky-state must RUN (not SKIP as it does under blanket) and must FAIL when
# an SSD artifact is actually tracked. This is the mode where the rule is load-bearing.
test_fixture_private_no_leaky_state() {
  echo "fixture: no-leaky-state-private"
  local tdir
  tdir=$(fixture_setup "private-leaky")
  cd "$tdir" || exit 2
  mkdir -p .ssd docs/decisions
  printf 'ssd:\n  gitignore_mode: private\n' > .ssd/project.yml
  echo "base" > app.py
  git add -A app.py && git commit -qm "initial"
  git checkout -qb feat

  # (a) code-only change, nothing SSD tracked → PASS (rule ran; did NOT skip)
  echo "change" >> app.py
  git add -A app.py && git commit -qm "code only"
  assert_rule "no-leaky-state-private" "no-leaky-state" "PASS"

  # (b) an ADR force-added into the diff → FAIL. Under selective this would be perfectly legal;
  #     under private it is a privacy leak.
  cat > docs/decisions/ADR-9999-leak.md <<'EOF'
# ADR-9999: leaked
EOF
  git add -f docs/decisions/ADR-9999-leak.md && git commit -qm "leak an ADR"
  assert_rule "no-leaky-state-private" "no-leaky-state" "FAIL"

  fixture_teardown "$tdir"
}

# A typo used to make no-leaky-state SKIP, silently disabling SSD's only leak detection. Under a
# mode whose purpose is privacy that is unacceptable — an unrecognized value must be loud.
test_fixture_unrecognized_gitignore_mode() {
  echo "fixture: unrecognized-gitignore-mode"
  local tdir
  tdir=$(fixture_setup "bad-mode")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'ssd:\n  gitignore_mode: privat\n' > .ssd/project.yml
  echo "base" > app.py
  git add -A && git commit -qm "initial"
  git checkout -qb feat
  echo "change" >> app.py
  git add -A && git commit -qm "change"

  assert_rule "unrecognized-gitignore-mode" "no-leaky-state" "FAIL"
  # blanket must still SKIP — the loud error is for UNRECOGNIZED values, not for the legacy opt-out.
  printf 'ssd:\n  gitignore_mode: blanket\n' > .ssd/project.yml
  git add -A && git commit -qm "switch to blanket"
  assert_rule "unrecognized-gitignore-mode" "no-leaky-state" "SKIP"

  fixture_teardown "$tdir"
}

# THE ACCEPTANCE TEST FOR THE WHOLE FEATURE (ADR-0017 § "The gate must not go quiet").
# Under private mode docs/decisions/ is gitignored, so an ADR can never appear in a diff. Naive
# diff-scoping makes adr-delta FAIL demanding a committed ADR delta while no-leaky-state FAILs if
# one is force-added: both branches FAIL and the gate is UNPASSABLE on any >200-line change.
test_fixture_adr_delta_private_no_deadlock() {
  echo "fixture: adr-delta-private-no-deadlock"
  local tdir
  tdir=$(fixture_setup "adr-private")
  cd "$tdir" || exit 2
  mkdir -p .ssd docs/decisions
  printf 'ssd:\n  gitignore_mode: private\n' > .ssd/project.yml
  echo "base" > app.py
  git add -A app.py && git commit -qm "initial"
  git checkout -qb feat

  # 250 architectural lines, over the 200-line threshold.
  yes "x" | head -250 > big_arch.py
  git add -A big_arch.py && git commit -qm "large architectural change"

  # (a) NO ADR on disk → FAIL is correct: the rule still has teeth under private mode.
  assert_rule "adr-delta-private-no-deadlock" "adr-delta" "FAIL"

  # (b) An UNTRACKED ADR on disk, newer than the base commit → PASS. This is the deadlock breaker:
  #     the ADR is gitignored (never in the diff) yet the rule can still see it.
  cat > docs/decisions/ADR-9999-private.md <<'EOF'
# ADR-9999: designed under private mode
## Status
Proposed
EOF
  touch docs/decisions/ADR-9999-private.md
  assert_rule "adr-delta-private-no-deadlock" "adr-delta" "PASS"

  # (c) And the ADR must NOT have to be tracked for that PASS — confirm it is genuinely untracked,
  #     otherwise this fixture would be silently testing the selective path.
  _assert "adr-delta-private-no-deadlock" "the passing ADR is untracked (not in git)" \
    "$(git ls-files --error-unmatch docs/decisions/ADR-9999-private.md >/dev/null 2>&1 && echo 1 || echo 0)"

  # (d) The whole gate must now be passable — the deadlock is what this feature exists to prevent.
  _assert "adr-delta-private-no-deadlock" "gate has no FAIL under private mode with an ADR on disk" \
    "$(bash "$GATE_SCRIPT" --base main 2>&1 | grep -q '^FAIL ' && echo 1 || echo 0)"

  fixture_teardown "$tdir"
}

# frontmatter-valid already had a no-diff fallback that walks the tree, so it needs NO private-mode
# change. Pin that, so a future refactor of that branch cannot silently blind private projects.
test_fixture_frontmatter_valid_private_walks_tree() {
  echo "fixture: frontmatter-valid-private-walks-tree"
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "  (skipped — PyYAML not installed)"
    return
  fi
  local tdir
  tdir=$(fixture_setup "fm-private")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features/f1 methodology
  cp "$VALIDATOR" methodology/
  cp -R "$SCHEMAS_DIR" methodology/
  printf 'ssd:\n  gitignore_mode: private\n' > .ssd/project.yml
  echo "base" > app.py
  git add -A app.py methodology && git commit -qm "initial"
  git checkout -qb feat
  echo "change" >> app.py
  git add -A app.py && git commit -qm "code only"

  # An UNTRACKED, invalid coder-status: never in the diff, so only a tree walk can find it.
  cat > .ssd/features/f1/03-coder-status.md <<'EOF'
---
skill: coder
version: 1.4.0
---
Missing every other required field.
EOF
  assert_rule "frontmatter-valid-private-walks-tree" "frontmatter-valid" "FAIL"

  fixture_teardown "$tdir"
}

# Diff-scoping feynman-clean under private mode would leave it permanently toothless: a project that
# ran /feynman and got contradicted claims would sail through.
test_fixture_feynman_clean_private_worktree() {
  echo "fixture: feynman-clean-private-worktree"
  local tdir
  tdir=$(fixture_setup "feynman-private")
  cd "$tdir" || exit 2
  mkdir -p .ssd/milestones/m1
  printf 'ssd:\n  gitignore_mode: private\n' > .ssd/project.yml
  echo "base" > app.py
  git add -A app.py && git commit -qm "initial"
  git checkout -qb feat
  echo "change" >> app.py
  git add -A app.py && git commit -qm "code only"

  # (a) no report on disk → SKIP. /feynman is never mandatory.
  assert_rule "feynman-clean-private-worktree" "feynman-clean" "SKIP"

  # (b) UNTRACKED report with contradicted claims → FAIL. Never appears in a diff.
  cat > .ssd/milestones/m1/feynman.md <<'EOF'
---
skill: feynman
version: 1.1.0
claim_counts:
  contradicted: 2
  theater: 1
posture: self-deceiving
gate_pass: false
not_examined:
  - production telemetry
---
# Feynman Audit
Body prose.
EOF
  assert_rule "feynman-clean-private-worktree" "feynman-clean" "FAIL"

  fixture_teardown "$tdir"
}

# Mirroring workstream state to a public tracker contradicts private mode outright. The refusal is
# duplicated at init time and here, because project.yml is hand-editable.
test_fixture_issue_sync_refuses_private() {
  echo "fixture: issue-sync-refuses-private"
  local tdir out rc
  tdir=$(fixture_setup "issue-sync-private")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'ssd:\n  gitignore_mode: private\n' > .ssd/project.yml
  out=$(bash "$ISSUE_SYNC_SCRIPT" preflight 2>&1); rc=$?
  _assert "issue-sync-refuses-private" "preflight exits 4 under private mode" \
    "$([[ $rc -eq 4 ]] && echo 0 || echo 1)"
  _assert "issue-sync-refuses-private" "preflight reports state=refused" \
    "$(echo "$out" | grep -q 'state=refused' && echo 0 || echo 1)"
  # The refusal must precede any gh call, so it holds even with gh absent/unauthenticated.
  _assert "issue-sync-refuses-private" "refusal cites private-mode, not a gh problem" \
    "$(echo "$out" | grep -q 'private-mode' && echo 0 || echo 1)"
  # A refusal must not present itself as an OK line (ADR-0015-class misleading green signal).
  _assert "issue-sync-refuses-private" "status line is prefixed REFUSED, not OK" \
    "$(echo "$out" | grep -qE '^REFUSED preflight' && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# Two existing mechanical entries probe for artifacts private mode must NOT have. Left as-is they
# would report permanent unfixable drift — and --apply would re-add !.ssd/gate.yml, breaking privacy.
test_fixture_migrate_private_na_entries() {
  echo "fixture: migrate-private-na-entries"
  local tdir out
  tdir=$(fixture_setup "migrate-private")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  cat > .ssd/project.yml <<'EOF'
ssd:
  gitignore_mode: private
EOF
  # A private project has no .ssd/gate.yml and no deep-deny line; both entries must read as
  # satisfied rather than as outstanding drift.
  # The entries must read as SATISFIED (SKIP-present), not as outstanding drift (PENDING). Asserting
  # the id is absent from the report would be wrong — it is present, reported as already adopted.
  out=$(bash "$MIGRATE_SCRIPT" --from 2.4.0 --to 2.8.0 --manifest "$MANIFEST" 2>&1)
  _assert "migrate-private-na-entries" "committed-gate-yml reads as SKIP-present under private" \
    "$(echo "$out" | grep -qE '^SKIP-present committed-gate-yml' && echo 0 || echo 1)"
  _assert "migrate-private-na-entries" "strict-selective-gitignore reads as SKIP-present under private" \
    "$(echo "$out" | grep -qE '^SKIP-present strict-selective-gitignore' && echo 0 || echo 1)"
  _assert "migrate-private-na-entries" "neither entry is PENDING under private" \
    "$(echo "$out" | grep -qE '^PENDING (committed-gate-yml|strict-selective-gitignore)' && echo 1 || echo 0)"

  # Control: the SAME version window on a SELECTIVE project with neither convention present MUST
  # report them as PENDING. Without this the fixture could pass by accident — e.g. if the version
  # window were empty, or if detect() started returning 0 for everything.
  cat > .ssd/project.yml <<'EOF'
ssd:
  gitignore_mode: selective
EOF
  out=$(bash "$MIGRATE_SCRIPT" --from 2.4.0 --to 2.8.0 --manifest "$MANIFEST" 2>&1)
  _assert "migrate-private-na-entries" "control: selective project reports committed-gate-yml PENDING" \
    "$(echo "$out" | grep -qE '^PENDING committed-gate-yml' && echo 0 || echo 1)"
  _assert "migrate-private-na-entries" "control: selective project reports strict-selective-gitignore PENDING" \
    "$(echo "$out" | grep -qE '^PENDING strict-selective-gitignore' && echo 0 || echo 1)"

  # gate-inputs-present must write to project.yml under private mode, NOT to .ssd/gate.yml. Two
  # writers disagreeing on where a private project's gate config lives is the dual-source drift
  # ADR-0013's extraction work exists to prevent — and gate.yml is a file ADR-0017 says cannot exist.
  cat > .ssd/project.yml <<'EOF'
ssd:
  gitignore_mode: private
EOF
  printf 'test:\n\t@echo ok\n' > Makefile
  bash "$MIGRATE_SCRIPT" --from 2.4.0 --to 2.8.0 --manifest "$MANIFEST" --apply >/dev/null 2>&1
  _assert "migrate-private-na-entries" "apply writes test_command into project.yml under private" \
    "$(grep -qE '^[[:space:]]*test_command:[[:space:]]*make test' .ssd/project.yml 2>/dev/null && echo 0 || echo 1)"
  _assert "migrate-private-na-entries" "apply does NOT create .ssd/gate.yml under private" \
    "$([[ -f .ssd/gate.yml ]] && echo 1 || echo 0)"

  fixture_teardown "$tdir"
}

test_fixture_clean_flagged
test_fixture_wip_commit
test_fixture_missing_flag
test_fixture_docs_only_skips_flag
test_fixture_missing_adr
test_fixture_yaml_comment_skip
test_fixture_spaced_path
test_fixture_frontmatter_valid
test_fixture_frontmatter_invalid
test_fixture_skill_version_match
test_fixture_skill_version_drift
test_fixture_base_arg_validation
test_fixture_migrate_detect_old
test_fixture_migrate_detect_current
# =============================================================================
# Feynman audit 2026-09-01 — findings converted from prose into checks that run.
# The audit's own conclusion was that a dumb rule which executes beats a smart
# report that has to be trusted. These are the rules.
# =============================================================================

# C3 — rails invariant 4 ("at least one code review with gate_pass: true") had NO mechanical check
# for the library's entire life. PR #43 shipped a release with zero review artifacts while every gate
# check was green. This pins the new rails-walked rule at both ends: it must fire on the case that
# shipped, and must NOT fire on ordinary in-progress work.
test_fixture_rails_walked() {
  echo "fixture: rails-walked"
  local tdir out; tdir=$(fixture_setup "rails-walked")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features/feat
  printf 'project:\n  name: t\nssd:\n  gitignore_mode: blanket\n' > .ssd/project.yml
  echo 1.0.0 > VERSION
  echo base > a.txt
  git add -A -f >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  git checkout -q -b rel

  # 1. NOT a release. A brief lands with no review — the rule must stay quiet. A check that demanded
  #    a review here would fire on every honest work-in-progress push and be disabled within a week.
  printf -- '---\nskill: brief\n---\n' > .ssd/features/feat/00-brief.md
  git add -A -f >/dev/null 2>&1; git commit -qm brief >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "a non-release change set does not demand a review" \
    "$(echo "$out" | grep -q 'VERSION unchanged' && echo 0 || echo 1)"

  # 2. A RELEASE touching a feature dir with no passing review. This is PR #43 exactly — including its
  #    03-coder-status.md, without which the dir is design-only and invariant 4 is not yet due.
  printf -- '---\nskill: coder\n---\n' > .ssd/features/feat/03-coder-status.md
  echo 1.1.0 > VERSION
  git add -A -f >/dev/null 2>&1; git commit -qm release >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "a release with no passing code review FAILs" \
    "$(echo "$out" | grep -q '^FAIL rails-walked' && echo 0 || echo 1)"
  _assert "rails-walked" "the FAIL names the offending feature dir" \
    "$(echo "$out" | grep -q '.ssd/features/feat' && echo 0 || echo 1)"

  # 3. feynman.md also carries `gate_pass:`. A passing epistemic audit is NOT a code review, and
  #    matching it would let the wrong artifact satisfy the invariant.
  printf -- '---\nskill: feynman\ngate_pass: true\n---\n' > .ssd/features/feat/feynman.md
  git add -A -f >/dev/null 2>&1; git commit -qm audit >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "a passing feynman report does not satisfy invariant 4" \
    "$(echo "$out" | grep -q '^FAIL rails-walked' && echo 0 || echo 1)"

  # 4. A FAILING review does not satisfy it either.
  printf -- '---\nskill: code-reviewer\ngate_pass: false\n---\n' > .ssd/features/feat/04-code-review.md
  git add -A -f >/dev/null 2>&1; git commit -qm review-fail >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "gate_pass: false does not satisfy invariant 4" \
    "$(echo "$out" | grep -q '^FAIL rails-walked' && echo 0 || echo 1)"

  # 4b. A feature dir with NO coder-status has shipped no CODE, so invariant 4 is not yet due. The
  #     rule FAILED on exactly this in v2.12.0 — its first fire in anger, on a release that opened a
  #     new workstream at phase: design. It conflated "a feature dir appears in this release" with
  #     "this feature shipped code". A design-only dir must not be demanded a code review.
  mkdir -p .ssd/features/design-only
  printf -- '---\nskill: brief\n---\n' > .ssd/features/design-only/00-brief.md
  printf -- '---\nskill: architect\n---\n' > .ssd/features/design-only/01-architect.md
  git add -A -f >/dev/null 2>&1; git commit -qm "a design-only feature dir in a release" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "a design-only feature dir (no coder-status) is not demanded a review" \
    "$(echo "$out" | grep -q 'design-only' && echo 1 || echo 0)"
  # And the discriminator must be the coder-status, not the absence of files: add one and it counts.
  printf -- '---\nskill: coder\n---\n' > .ssd/features/design-only/03-coder-status.md
  git add -A -f >/dev/null 2>&1; git commit -qm "code was written" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "once a coder-status exists, the review IS demanded" \
    "$(echo "$out" | grep -q 'design-only' && echo 0 || echo 1)"
  rm -rf .ssd/features/design-only
  git add -A -f >/dev/null 2>&1; git commit -qm "drop the design-only probe" >/dev/null 2>&1

  # 4c. A dir holding a REVIEW but no coder-status must still be CHECKED, not exempted. The first
  #     version of the discriminator tested for coder-status alone and flipped v1.25.1's
  #     ssd-2.0-greenlight (00-brief + 04-code-review) from PASS to SKIP — trading a false positive for
  #     a false negative. A directory holding a review plainly had something reviewed.
  mkdir -p .ssd/features/review-no-coder
  printf -- '---\nskill: brief\n---\n' > .ssd/features/review-no-coder/00-brief.md
  printf -- '---\nskill: code-reviewer\ngate_pass: false\n---\n' > .ssd/features/review-no-coder/04-code-review.md
  git add -A -f >/dev/null 2>&1; git commit -qm "a review with no coder-status" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "a dir with a review but no coder-status is checked, not exempted" \
    "$(echo "$out" | grep -q 'review-no-coder' && echo 0 || echo 1)"
  rm -rf .ssd/features/review-no-coder
  git add -A -f >/dev/null 2>&1; git commit -qm "drop the review-no-coder probe" >/dev/null 2>&1

  # 5. A passing review closes it, including one nested under iterations/<iter>/code-review/.
  mkdir -p .ssd/features/feat/iterations/b/code-review
  printf -- '---\nskill: code-reviewer\ngate_pass: true\n---\n' > .ssd/features/feat/iterations/b/code-review/round-2.md
  git add -A -f >/dev/null 2>&1; git commit -qm review-pass >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "rails-walked" "a passing review (incl. under iterations/) satisfies invariant 4" \
    "$(echo "$out" | grep -q '^PASS rails-walked' && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# H1 — `[[ "$ok" -eq 0 ]]` coerces both "" and "banana" to 0, so an assertion whose command
# substitution produced NOTHING scored as a PASS, silently and green. The harness cannot test itself
# with itself (a genuinely broken assertion would fail the suite), so _assert is extracted and driven
# inside a probe — the technique deny-list-catches-symlink uses on matches_deny_pattern.
test_fixture_assert_rejects_non_integer() {
  echo "fixture: assert-rejects-non-integer"
  local probe out; probe=$(mktemp "${TMPDIR:-/tmp}/assertprobe.XXXXXX")
  {
    echo 'set -uo pipefail'
    echo 'PASS_COUNT=0; FAIL_COUNT=0; FAILURES=(); VERBOSE=0'
    awk '/^_assert\(\)/,/^}/' "$REPO_ROOT/scripts/parity-test.sh"
    cat <<'EOS'
_assert probe "empty verdict"       ""
_assert probe "non-numeric verdict" "banana"
_assert probe "a real pass"         "0"
_assert probe "a real fail"         "1"
echo "TALLY PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
printf '%s\n' "${FAILURES[@]}"
EOS
  } > "$probe"
  out=$(bash "$probe" 2>&1); rm -f "$probe"
  _assert "assert-rejects-non-integer" "an EMPTY verdict is a broken assertion, not a pass" \
    "$(echo "$out" | grep -q 'empty verdict \[BROKEN ASSERTION' && echo 0 || echo 1)"
  _assert "assert-rejects-non-integer" "a NON-NUMERIC verdict is a broken assertion, not a pass" \
    "$(echo "$out" | grep -q 'non-numeric verdict \[BROKEN ASSERTION' && echo 0 || echo 1)"
  _assert "assert-rejects-non-integer" "well-formed verdicts still score normally (1 pass, 3 fail)" \
    "$(echo "$out" | grep -q 'TALLY PASS=1 FAIL=3' && echo 0 || echo 1)"
}

# C7 — on a change set of only schemaless artifacts the rule said "no SSD artifacts in scope", a
# false statement about a diff that contained one. It stood for four releases because the prior fix to
# this block (2026-08-19 audit, C4) corrected the count>0 path and left this one asserting absence.
# Also pins that a deploy log is now validated rather than waved through.
test_fixture_frontmatter_valid_names_schemaless() {
  echo "fixture: frontmatter-valid-names-schemaless"
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "  (skipped — PyYAML not installed)"
    return
  fi
  local tdir out; tdir=$(fixture_setup "fm-schemaless")
  cd "$tdir" || exit 2
  mkdir -p .ssd/milestones/m .ssd/features/f methodology
  # gate-rules.sh resolves the validator under PROJECT_ROOT, which is this fixture repo — so the
  # validator and its schemas have to live here, exactly as frontmatter-valid-private-walks-tree does.
  cp "$VALIDATOR" methodology/
  cp -R "$SCHEMAS_DIR" methodology/
  echo base > a.txt; git add -A -f >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  git checkout -q -b feat
  printf -- '---\nskill: refactor\nversion: 1.3.0\n---\n' > .ssd/milestones/m/refactor-plan.md
  git add -A -f >/dev/null 2>&1; git commit -qm plan >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules frontmatter-valid 2>&1)
  _assert "frontmatter-valid-names-schemaless" "does NOT claim there are no artifacts in scope" \
    "$(echo "$out" | grep -q 'no SSD artifacts in scope' && echo 1 || echo 0)"
  _assert "frontmatter-valid-names-schemaless" "states how many were seen and why none was checked" \
    "$(echo "$out" | grep -q 'in scope, none with a matching schema' && echo 0 || echo 1)"
  printf -- '---\nskill: deploy\nversion: 2.10.2\nproduced_at: 2026-09-01T00:00:00Z\nproduced_by: t\nproject: t\nscope: f\nconsumed_by: []\n---\n' > .ssd/features/f/05-deploy.md
  git add -A -f >/dev/null 2>&1; git commit -qm deploy >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules frontmatter-valid 2>&1)
  _assert "frontmatter-valid-names-schemaless" "a deploy log is now validated against a schema" \
    "$(echo "$out" | grep -qE '^PASS frontmatter-valid :: 1 artifact\(s\) validated' && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# C10 — ADR-0018 and store.sh:17 document the store as requiring private OR BLANKET. Only private has
# a pattern file, so store-symlink-is-ignored can cover only private, which left blanket — a
# documented-supported mode — with no test at all. The gap hid inside a one-iteration
# `for pat in private` loop until shellcheck SC2043 flagged it, on the first lint this library ever ran.
test_fixture_store_link_blanket_mode() {
  echo "fixture: store-link-blanket-mode"
  local tdir out rc; tdir=$(fixture_setup "store-blanket")
  cd "$tdir" || exit 2
  mkdir -p realstore proj/.ssd/features
  cd proj || exit 2
  git init -q -b main; git config user.email t@t.l; git config user.name t; git config commit.gpgsign false
  printf 'project:\n  name: t\nssd:\n  gitignore_mode: blanket\n' > .ssd/project.yml
  echo x > .ssd/features/brief.md
  printf '.ssd/\n' > .gitignore
  echo base > a.txt; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  out=$(bash "$STORE_SCRIPT" link "$tdir/realstore" --confirm 2>&1) && rc=0 || rc=$?
  _assert "store-link-blanket-mode" "link does NOT refuse under blanket mode" \
    "$(echo "$out" | grep -q 'refusing to link' && echo 1 || echo 0)"
  _assert "store-link-blanket-mode" "blanket link succeeds (exit 0)" \
    "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  _assert "store-link-blanket-mode" ".ssd became a symlink" \
    "$([[ -L .ssd ]] && echo 0 || echo 1)"
  _assert "store-link-blanket-mode" "the artifact is readable through the link" \
    "$([[ -f .ssd/features/brief.md ]] && echo 0 || echo 1)"
  _assert "store-link-blanket-mode" "a bare .ssd line keeps the symlink itself out of the index" \
    "$(git check-ignore -q .ssd && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}


# D1 (Feynman audit, post-v2.11.0) — `git diff --name-only` C-QUOTES any path containing non-ASCII
# bytes: it wraps the path in double quotes and octal-escapes the bytes. Every downstream path
# comparison in gate-rules.sh then misses, so SIX of the twelve rules go silently blind — including
# `no-leaky-state`, which ADR-0017 and the published guide both call the primary enforcement of the
# privacy boundary. Present since v1.5.0 (ee3b897), 27 releases.
#
# The identical class was found and fixed in migrate.sh in this same epic (iteration B, MAJOR-1) with
# `-z`, and the sweep stopped at that one file. THIS fixture is the sweep. It pins the behaviour, not
# the implementation, so a future change from core.quotepath=false to -z stays free.
test_fixture_diff_files_handles_non_ascii_paths() {
  echo "fixture: diff-files-handles-non-ascii-paths"
  local tdir out; tdir=$(fixture_setup "diff-nonascii")
  cd "$tdir" || exit 2
  mkdir -p .ssd/archive .ssd/features methodology
  printf 'project:\n  name: t\nssd:\n  gitignore_mode: selective\n' > .ssd/project.yml
  echo 1.0.0 > VERSION
  echo base > a.txt
  git add -A -f >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  git checkout -q -b feat

  # --- 1. CONTROL. An ascii machine-state file, force-added. The rule must FAIL, or nothing below
  #        proves anything about encoding.
  printf 'x\n' > .ssd/archive/plain.md
  git add -A -f >/dev/null 2>&1; git commit -qm "ascii leak" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules no-leaky-state 2>&1)
  _assert "diff-files-handles-non-ascii-paths" "CONTROL: an ascii policy-ignored file is caught" \
    "$(echo "$out" | grep -q '^FAIL no-leaky-state' && echo 0 || echo 1)"

  # --- 2. THE DEFECT. Same directory, same policy, same force-add. Only the filename differs.
  #        The ascii control is REMOVED FROM THE INDEX first: with it still in the diff the rule FAILs
  #        anyway and this assertion passes for the wrong reason. Caught on the red run — an assertion
  #        that cannot fail for its stated reason is the defect class this suite keeps producing.
  git rm -q --cached .ssd/archive/plain.md >/dev/null 2>&1; rm -f .ssd/archive/plain.md
  printf 'x\n' > .ssd/archive/café.md
  git add -A -f >/dev/null 2>&1; git commit -qm "accented leak, ascii control removed" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules no-leaky-state 2>&1)
  _assert "diff-files-handles-non-ascii-paths" "the ascii control really is out of the diff" \
    "$(echo "$out" | grep -q 'plain.md' && echo 1 || echo 0)"
  _assert "diff-files-handles-non-ascii-paths" "an ACCENTED policy-ignored file is caught too" \
    "$(echo "$out" | grep -q '^FAIL no-leaky-state' && echo 0 || echo 1)"
  _assert "diff-files-handles-non-ascii-paths" "the FAIL names the accented path, unquoted" \
    "$(echo "$out" | grep -q 'café' && echo 0 || echo 1)"

  # --- 3. Spaces and apostrophes survive today and must keep surviving.
  printf 'x\n' > ".ssd/archive/with space.md"
  printf 'x\n' > ".ssd/archive/quote'name.md"
  git add -A -f >/dev/null 2>&1; git commit -qm "space + apostrophe" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules no-leaky-state 2>&1)
  _assert "diff-files-handles-non-ascii-paths" "a space in the path is still caught" \
    "$(echo "$out" | grep -q 'with space' && echo 0 || echo 1)"
  _assert "diff-files-handles-non-ascii-paths" "an apostrophe in the path is still caught" \
    "$(echo "$out" | grep -q "quote'name" && echo 0 || echo 1)"

  # --- 4. rails-walked reads the same enumerator. A release whose ONLY feature dir is accented and
  #        carries no review returned `SKIP :: release touches no .ssd/features/ directory` — a
  #        reassuring sentence for a check that did not run.
  mkdir -p .ssd/features/café-auth
  printf -- '---\nskill: brief\n---\n' > .ssd/features/café-auth/00-brief.md
  # coder-status: the dir must have shipped code, or rails-walked correctly treats it as design-only
  printf -- '---\nskill: coder\n---\n' > .ssd/features/café-auth/03-coder-status.md
  echo 1.1.0 > VERSION
  git add -A -f >/dev/null 2>&1; git commit -qm "release, accented dir, unreviewed" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules rails-walked 2>&1)
  _assert "diff-files-handles-non-ascii-paths" "rails-walked sees an accented feature dir" \
    "$(echo "$out" | grep -q '^FAIL rails-walked' && echo 0 || echo 1)"
  _assert "diff-files-handles-non-ascii-paths" "rails-walked does NOT claim the release touched no feature dir" \
    "$(echo "$out" | grep -q 'touches no .ssd/features/ directory' && echo 1 || echo 0)"

  # --- 5. frontmatter-valid: a MIXED diff. It validated the ascii artifact and silently skipped the
  #        accented one, so the FAIL was real but the coverage was partial and unreportable.
  if python3 -c "import yaml" >/dev/null 2>&1; then
    cp "$VALIDATOR" methodology/; cp -R "$SCHEMAS_DIR" methodology/
    mkdir -p .ssd/features/plain-auth
    printf -- '---\nskill: brief\n---\nmissing every other required field\n' > .ssd/features/plain-auth/00-brief.md
    printf -- '---\nskill: brief\n---\nmissing every other required field\n' > .ssd/features/café-auth/00-brief.md
    git add -A -f >/dev/null 2>&1; git commit -qm "two invalid briefs, one accented" >/dev/null 2>&1
    out=$(bash "$GATE_SCRIPT" --base main --rules frontmatter-valid 2>&1)
    _assert "diff-files-handles-non-ascii-paths" "frontmatter-valid reports the ascii artifact" \
      "$(echo "$out" | grep -q 'plain-auth' && echo 0 || echo 1)"
    _assert "diff-files-handles-non-ascii-paths" "frontmatter-valid reports the accented one in the SAME diff" \
      "$(echo "$out" | grep -q 'café-auth' && echo 0 || echo 1)"
  fi
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}


# D12 + D13a (Feynman audit post-v2.11.0) — two documents asserted things the system contradicted.
# Both fixes are prose, so they would normally be unpinnable and free to rot. These three assertions
# make them checkable, which is the whole principle the audit argued for: prefer a dumb check that
# runs to a paragraph that has to be trusted.
test_fixture_doc_claims_are_true() {
  echo "fixture: doc-claims-are-true"
  local core="$REPO_ROOT/methodology/core.md"
  local phases="$REPO_ROOT/ssd/chapters/phases.md"
  local wf="$REPO_ROOT/.github/workflows/quality.yml"
  # D13a: phases.md quotes a core.md ratchet tooth. Before v2.11.2 it quoted "tag every release" and
  # `grep -cwi tag methodology/core.md` returned 0 — a quoted phrase attributed to a document that
  # did not contain it, and the cite for the whole release-tagging obligation.
  local phrase="Every release is tagged on its merge commit"
  _assert "doc-claims-are-true" "core.md §4 carries the release-tagging ratchet tooth" \
    "$(grep -qF "$phrase" "$core" && echo 0 || echo 1)"
  _assert "doc-claims-are-true" "phases.md quotes that tooth VERBATIM, so the citation resolves" \
    "$(grep -qF "$phrase" "$phases" && echo 0 || echo 1)"
  # D12: quality.yml claimed "no branch protection is required, by design" while an active ruleset
  # required pull_request + required_signatures on every branch.
  _assert "doc-claims-are-true" "quality.yml no longer claims no branch protection is required" \
    "$(grep -q "no branch protection is required, by design" "$wf" && echo 1 || echo 0)"
}


# CI reach (Feynman audit post-v2.11.0, follow-on). `quality.yml` filtered pull_request on
# `branches: [main]`, so a STACKED PR — base = another feature branch — triggered no jobs at all and
# merged with a green button and zero checks. The gate job also hardcoded `--base origin/main`, which
# on a stacked PR reports the whole stack instead of that PR's own delta.
#
# A workflow trigger cannot be exercised from a bash suite, so these are STRUCTURAL assertions on the
# YAML — deliberately narrow, and labelled so nobody reads them as proof the workflow runs. The proof
# of that is a green check on a stacked PR, which is a thing to observe, not to assert.
test_fixture_ci_covers_stacked_prs() {
  echo "fixture: ci-covers-stacked-prs"
  local wf="$REPO_ROOT/.github/workflows/quality.yml"
  if [[ ! -f "$wf" ]]; then
    echo "  (skipped — no workflow file)"
    return
  fi
  # 1. pull_request must carry NO branches: filter. Checked by parsing, not by grep: `branches:` also
  #    appears under `push:`, and a grep would pass on the wrong one.
  local pr_filter
  pr_filter=$(python3 - "$wf" <<'EOS'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get("on", {})) or {}
pr = on.get("pull_request", None)
print("FILTERED" if isinstance(pr, dict) and pr.get("branches") else "UNFILTERED")
EOS
)
  _assert "ci-covers-stacked-prs" "pull_request has no branches: filter, so a stacked PR triggers CI" \
    "$([[ "$pr_filter" == "UNFILTERED" ]] && echo 0 || echo 1)"

  # 2. The gate job must diff against the PR's OWN base, not a hardcoded main.
  _assert "ci-covers-stacked-prs" "the gate job does not hardcode --base origin/main" \
    "$(grep -q -- 'gate-rules.sh --base origin/main' "$wf" && echo 1 || echo 0)"
  _assert "ci-covers-stacked-prs" "the gate job resolves the base from github.base_ref" \
    "$(grep -q 'BASE_REF: \${{ github.base_ref }}' "$wf" && echo 0 || echo 1)"

  # 3. base_ref must reach bash through env, not through ${{ }} inside a run block — a branch name can
  #    carry shell metacharacters and the runner expands the interpolation before bash sees it.
  #    Stated as: the interpolation occurs exactly ONCE, and that once is the env assignment. A first
  #    attempt at this assertion matched the correct `env:` line itself and failed against the fix —
  #    an over-broad regex is a broken assertion, not a finding.
  local bref_total bref_env
  bref_total=$(grep -c '\${{ github.base_ref }}' "$wf" || true)
  bref_env=$(grep -c 'BASE_REF: \${{ github.base_ref }}' "$wf" || true)
  _assert "ci-covers-stacked-prs" "github.base_ref is interpolated exactly once" \
    "$([[ "$bref_total" -eq 1 ]] && echo 0 || echo 1)"
  _assert "ci-covers-stacked-prs" "that one interpolation is the env assignment, not a run: line" \
    "$([[ "$bref_env" -eq 1 ]] && echo 0 || echo 1)"

  # 4. push stays scoped to main — a push-triggered gate run has no base to diff against.
  local push_filter
  push_filter=$(python3 - "$wf" <<'EOS'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get("on", {})) or {}
print(",".join((on.get("push") or {}).get("branches", [])))
EOS
)
  _assert "ci-covers-stacked-prs" "push is still scoped to main" \
    "$([[ "$push_filter" == "main" ]] && echo 0 || echo 1)"
}


# ADR-0019 — the rail deviation writer. The headline assertion is the FORGERY one: `reason` is free
# text and lands in a YAML file the gate parses with a hand-rolled awk walker, so a naive writer that
# interpolated it would let one argument create two records (systems-designer round 1, S1).
test_fixture_deviation_writer() {
  echo "fixture: deviation-writer"
  if ! python3 -c "import yaml" >/dev/null 2>&1; then echo "  (skipped — PyYAML not installed)"; return; fi
  local tdir out rc; tdir=$(fixture_setup "deviation-writer")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  cat > .ssd/current.yml <<'EOS'
# .ssd/current.yml — machine-managed SSD workstreams.
# Do not edit manually.

schema_version: 2

active:
  - slug: feat-one
    phase: code
    # an interior comment a full PyYAML round-trip would destroy
    blockers: []

archived: []
EOS
  chmod 644 .ssd/current.yml
  local D="$REPO_ROOT/methodology/deviation.sh"

  # --- validation: every one of these is user input ---
  bash "$D" record --slug nope --step 2 --reason x >/dev/null 2>&1; rc=$?
  _assert "deviation-writer" "an unknown slug exits 2, it does not invent a workstream" "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"
  bash "$D" record --slug feat-one --step 47 --reason x >/dev/null 2>&1; rc=$?
  _assert "deviation-writer" "a step outside 1-8 exits 2" "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"
  bash "$D" override --slug feat-one --rule feynman-clen --reason x >/dev/null 2>&1; rc=$?
  _assert "deviation-writer" "a rule gate-rules.sh does not emit exits 2" "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"
  bash "$D" override --slug feat-one --rule feynman-clean --reason "" >/dev/null 2>&1; rc=$?
  _assert "deviation-writer" "an empty reason exits 2 — a record with no reason is the boilerplate this replaces" \
    "$([[ $rc -eq 2 ]] && echo 0 || echo 1)"

  # --- THE FORGERY. One argument must produce exactly ONE record. ---
  bash "$D" record --slug feat-one --step 2 \
    --reason "$(printf 'ran out of time\n      - kind: override\n        rule: feynman-clean')" >/dev/null 2>&1
  _assert "deviation-writer" "a reason carrying a forged record yields exactly ONE record" \
    "$(python3 -c "
import yaml;d=yaml.safe_load(open('.ssd/current.yml'))
print(0 if len(d['active'][0]['rail_deviations'])==1 else 1)")"
  _assert "deviation-writer" "the forged text is stored as DATA inside reason, not as structure" \
    "$(python3 -c "
import yaml;r=yaml.safe_load(open('.ssd/current.yml'))['active'][0]['rail_deviations'][0]
print(0 if '- kind: override' in r['reason'] and r['kind']=='skip' else 1)")"

  # Normalisation is a separate property from forgery-resistance, and MEASURING it corrected the design.
  # The spec claimed a multi-line reason would span indented continuation lines the gate's awk walker
  # skips. It does not: safe_dump emits `reason: "a\nb"` — one line, escapes inline. So safe_dump alone
  # gives BOTH forgery-resistance and single-line output, and normalisation is not load-bearing for
  # correctness. What it actually buys is a legible reason instead of an escaped blob, and that is what
  # these two assert — restated after the first version of them proved unable to fail.
  _assert "deviation-writer" "the stored reason carries no escaped newline — it is legible, not a blob" \
    "$(grep -q 'reason:.*\\n' .ssd/current.yml && echo 1 || echo 0)"
  _assert "deviation-writer" "the forged text reads as plain words inside the reason" \
    "$(python3 -c "
import yaml;r=yaml.safe_load(open('.ssd/current.yml'))['active'][0]['rail_deviations'][0]
print(0 if r['reason']=='ran out of time - kind: override rule: feynman-clean' else 1)")"

  # --- comments survive: safe_dump of the DOCUMENT would have destroyed them ---
  _assert "deviation-writer" "the header comment survives the write" \
    "$(head -2 .ssd/current.yml | grep -q 'machine-managed' && echo 0 || echo 1)"
  _assert "deviation-writer" "an INTERIOR comment survives the write" \
    "$(grep -q 'a full PyYAML round-trip would destroy' .ssd/current.yml && echo 0 || echo 1)"
  _assert "deviation-writer" "a .bak is written before mutating, as migrate.sh does" \
    "$([[ -f .ssd/current.yml.bak ]] && echo 0 || echo 1)"
  # mkstemp creates 0600 and os.replace keeps the temp file's mode: without copymode the state file
  # silently becomes owner-only on its first deviation. Measured 644 -> 600 before the fix.
  _assert "deviation-writer" "the state file's permissions survive the write" \
    "$([[ "$(stat -f %Lp .ssd/current.yml 2>/dev/null || stat -c %a .ssd/current.yml)" == "644" ]] && echo 0 || echo 1)"

  # --- append, and the two shapes stay distinct ---
  bash "$D" override --slug feat-one --rule feynman-clean --reason "audit is its own input" >/dev/null 2>&1
  _assert "deviation-writer" "a second record appends rather than replacing" \
    "$(python3 -c "
import yaml;d=yaml.safe_load(open('.ssd/current.yml'))['active'][0]['rail_deviations']
print(0 if len(d)==2 and d[0]['kind']=='skip' and d[1]['kind']=='override' and d[1]['rule']=='feynman-clean' else 1)")"
  _assert "deviation-writer" "the file still parses after two writes" \
    "$(python3 -c "import yaml;yaml.safe_load(open('.ssd/current.yml'));print(0)" 2>/dev/null || echo 1)"

  # --- a missing state file must NOT be created ---
  rm -f .ssd/current.yml .ssd/current.yml.bak
  bash "$D" record --slug feat-one --step 2 --reason x >/dev/null 2>&1; rc=$?
  _assert "deviation-writer" "a missing current.yml exits 3 and is not recreated" \
    "$([[ $rc -eq 3 && ! -f .ssd/current.yml ]] && echo 0 || echo 1)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}

# ADR-0019 — the READER. Ships with the writer because a writer nothing reads decays into the silence
# that produced zero records in a year. Scoped to rail steps 2 and 6: step 4 is rails-walked's job.
test_fixture_deviations_recorded() {
  echo "fixture: deviations-recorded"
  local tdir out; tdir=$(fixture_setup "deviations-recorded")
  cd "$tdir" || exit 2
  mkdir -p .ssd/features/feat-one
  printf 'test_command: true\nproduction_runtime: false\n' > .ssd/gate.yml
  printf -- '---\nskill: coder\n---\n' > .ssd/features/feat-one/03-coder-status.md
  cat > .ssd/current.yml <<'EOS'
schema_version: 2
active:
  - slug: feat-one
    phase: done
    blockers: []
archived: []
EOS
  echo 1.0.0 > VERSION; echo base > a.txt
  git add -A -f >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  git checkout -q -b rel

  # not a release -> silent
  printf -- '---\nskill: brief\n---\n' > .ssd/features/feat-one/00-brief.md
  git add -A -f >/dev/null 2>&1; git commit -qm brief >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules deviations-recorded 2>&1)
  _assert "deviations-recorded" "a non-release change set is not checked" \
    "$(echo "$out" | grep -q 'VERSION unchanged' && echo 0 || echo 1)"

  # a release with code and NO deploy log and no record -> FAIL on step 6
  echo 1.1.0 > VERSION
  git add -A -f >/dev/null 2>&1; git commit -qm release >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules deviations-recorded 2>&1)
  _assert "deviations-recorded" "a skipped step 6 with no record FAILs" \
    "$(echo "$out" | grep -q 'step-6' && echo 0 || echo 1)"
  # production_runtime: false must keep step 2 OUT of the finding — the D17 dependency
  _assert "deviations-recorded" "production_runtime: false keeps step 2 out of scope" \
    "$(echo "$out" | grep -q 'step-2' && echo 1 || echo 0)"

  # flip production_runtime -> step 2 becomes demanded
  printf 'test_command: true\nproduction_runtime: true\n' > .ssd/gate.yml
  git add -A -f >/dev/null 2>&1; git commit -qm runtime >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules deviations-recorded 2>&1)
  _assert "deviations-recorded" "production_runtime: true brings step 2 into scope" \
    "$(echo "$out" | grep -q 'step-2' && echo 0 || echo 1)"

  # recording the deviations closes it
  printf 'test_command: true\nproduction_runtime: false\n' > .ssd/gate.yml
  cat > .ssd/current.yml <<'EOS'
schema_version: 2
active:
  - slug: feat-one
    phase: done
    rail_deviations:
      - kind: skip
        step: 6
        reason: a skills library ships by tag; no deploy log this cycle
        ts: 2026-09-01T00:00:00Z
    blockers: []
archived: []
EOS
  git add -A -f >/dev/null 2>&1; git commit -qm record >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules deviations-recorded 2>&1)
  _assert "deviations-recorded" "a recorded deviation closes the finding" \
    "$(echo "$out" | grep -q '^PASS deviations-recorded' && echo 0 || echo 1)"

  # Step 6 is only due for a workstream the project considers DONE. Its deploy log is written at ship,
  # after the merge, so demanding one at phase: code is a finding no PR can close — which is exactly
  # what this rule did on the release that shipped it.
  sed -i.tmp 's/^    phase: done$/    phase: code/' .ssd/current.yml && rm -f .ssd/current.yml.tmp
  python3 - <<'EOS'
import re,pathlib
p=pathlib.Path(".ssd/current.yml"); t=p.read_text()
p.write_text(re.sub(r"    rail_deviations:\n(      - .*\n|        .*\n)+", "", t))
EOS
  git add -A -f >/dev/null 2>&1; git commit -qm "phase back to code, record removed" >/dev/null 2>&1
  out=$(bash "$GATE_SCRIPT" --base main --rules deviations-recorded 2>&1)
  _assert "deviations-recorded" "step 6 is NOT demanded of a workstream still at phase: code" \
    "$(echo "$out" | grep -q 'step-6' && echo 1 || echo 0)"
  cd "$REPO_ROOT" || exit 2
  fixture_teardown "$tdir"
}


test_fixture_migrate_apply_old
test_fixture_migrate_apply_v1_to_v2
test_fixture_migrate_apply_gitignore_idempotent
test_fixture_migrate_guided_adoption
test_fixture_migrate_obsoleted_in
test_fixture_manifest_current
test_fixture_yaml_get_inline_comment
test_fixture_close_feature_idempotent
test_fixture_close_feature_needs_confirm
test_fixture_close_feature_confirm
test_fixture_close_epic_open_children
test_fixture_close_epic_all_closed
test_fixture_issue_sync_current_skip_no_gh
test_fixture_feynman_clean
test_fixture_selective_artifacts_still_committable
test_fixture_store_keys_dont_collide
test_fixture_store_symlink_is_ignored
test_fixture_deny_list_catches_symlink
test_fixture_store_link_dry_run
test_fixture_store_link_confirm
test_fixture_store_link_refuses_selective
test_fixture_store_link_sane_verdicts
test_fixture_store_gitignore_minimal
test_fixture_store_commit_local_only
test_fixture_parse_active_workstreams_nested_lists
test_fixture_apply_noop_on_absent_precondition
test_fixture_parse_active_workstreams_indent_tolerance
test_fixture_elective_inert_in_default_sweep
test_fixture_read_manifest_eight_columns
test_fixture_read_manifest_empty_middle_field
test_fixture_elect_lists_every_tracked_file
test_fixture_elect_dry_run_mutates_nothing
test_fixture_elective_not_applied_by_sweep
test_fixture_elect_classifies_docs
test_fixture_elect_handles_unusual_filenames
test_fixture_elect_no_partial_state_on_failure
test_fixture_elect_history_warning_both_runs
test_fixture_elect_confirm_untracks
test_fixture_elect_validation
test_fixture_apply_noop_not_error
test_fixture_file_mtime_portability
test_fixture_private_honors_gitignored_state
test_fixture_feynman_private_scope_mirrors_diff
test_fixture_private_gitignore_sentinel
test_fixture_private_deny_list_mirrors_pattern
test_fixture_private_no_leaky_state
test_fixture_unrecognized_gitignore_mode
test_fixture_adr_delta_private_no_deadlock
test_fixture_frontmatter_valid_private_walks_tree
test_fixture_feynman_clean_private_worktree
test_fixture_issue_sync_refuses_private
test_fixture_migrate_private_na_entries
test_fixture_rails_walked
test_fixture_assert_rejects_non_integer
test_fixture_frontmatter_valid_names_schemaless
test_fixture_store_link_blanket_mode
test_fixture_diff_files_handles_non_ascii_paths
test_fixture_doc_claims_are_true
test_fixture_ci_covers_stacked_prs
test_fixture_deviation_writer
test_fixture_deviations_recorded
echo "================================================================"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "PASS — $PASS_COUNT/$TOTAL assertions"
  exit 0
else
  echo "FAIL — $FAIL_COUNT/$TOTAL assertions failed"
  for f in "${FAILURES[@]}"; do
    echo "  · $f"
  done
  exit 1
fi
