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
  local issues; issues=$'27|OPEN|ssd:epic|[ADR-0014] x\n28|OPEN|ssd:feature,ssd:phase/code|x: Epic: #27'
  local out; out=$(run_issue_sync "$issues" true close-epic 27)   # auto_close ON, yet must still skip
  _assert "close-epic-open-children" "open child → exit 0 (not an error)" \
    "$([[ "$out" == *"exit=0"* ]] && echo 0 || echo 1)"
  _assert "close-epic-open-children" "state=skipped (open child blocks close even with auto_close)" \
    "$([[ "$out" == *"state=skipped"* ]] && echo 0 || echo 1)"
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
