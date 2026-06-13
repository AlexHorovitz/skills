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

# Fixture 16: migrate.sh --apply — current-yml-v2 (v1→v2 split) DEFERs to ssd-init, never half-applies (R1).
test_fixture_migrate_apply_defer() {
  echo "fixture: migrate-apply-defer"
  local tdir out
  tdir=$(fixture_setup "migrate-defer")
  cd "$tdir" || exit 2
  mkdir -p .ssd
  printf 'active:\n  - slug: legacy\n' > .ssd/current.yml          # v1 (no schema_version)
  printf 'ssd:\n  version: "1.3.0"\n' > .ssd/project.yml
  out=$(bash "$MIGRATE_SCRIPT" --from 1.3.0 --to 1.22.0 --manifest "$MANIFEST" --apply 2>&1)
  _assert "migrate-apply-defer" "current-yml-v2 DEFERs to ssd-init" \
    "$([[ "$out" == *"DEFER current-yml-v2"* ]] && echo 0 || echo 1)"
  _assert "migrate-apply-defer" "current.yml left untouched (still v1, no schema_version)" \
    "$(! grep -qE '^schema_version:' .ssd/current.yml && echo 0 || echo 1)"
  _assert "migrate-apply-defer" "version NOT advanced past the deferred entry (stays 1.3.0)" \
    "$(grep -qE '^[[:space:]]*version:[[:space:]]*"?1\.3\.0' .ssd/project.yml && echo 0 || echo 1)"
  fixture_teardown "$tdir"
}

# ---------- run ------------------------------------------------------------

echo "SSD parity-test harness — gate-rules.sh structural conformance"
echo "================================================================"
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
test_fixture_migrate_apply_old
test_fixture_migrate_apply_defer
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
