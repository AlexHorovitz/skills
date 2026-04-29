#!/usr/bin/env bash
# methodology/gate-rules.sh — executable SSD gate rules.
#
# Invoked by `/ssd gate` and `/ssd ship`. Runs each rule and emits one line of
# stdout per rule in the form:
#
#   PASS|FAIL|SKIP <rule-name> :: <detail>
#
# Exit code: 0 if every applicable rule is PASS or SKIP. Non-zero on any FAIL.
#
# Reads project metadata from .ssd/project.yml when available; rules whose
# preconditions aren't met SKIP rather than FAIL.
#
# See docs/decisions/ADR-0005-gate-execution-model.md for the design rationale.
#
# Usage:
#   bash methodology/gate-rules.sh                # check current branch vs main
#   bash methodology/gate-rules.sh --base develop # check vs a different base
#   bash methodology/gate-rules.sh --json         # emit JSON instead of text
#
# License: see /LICENSE.

set -uo pipefail   # NOTE: not -e — we want to run all rules even if one fails.

BASE="main"
JSON=0
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_YML="$PROJECT_ROOT/.ssd/project.yml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "--base requires a value (got '${2:-<empty>}')" >&2; exit 2
      fi
      BASE="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help)
      sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ----- result accumulators ---------------------------------------------------
RESULTS=()      # lines like "PASS rule-name :: detail"
FAIL_COUNT=0

emit() {
  # emit STATUS RULE DETAIL
  local status="$1" rule="$2" detail="$3"
  RESULTS+=("$status $rule :: $detail")
  [[ "$status" == "FAIL" ]] && FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ----- helpers ---------------------------------------------------------------
yaml_get() {
  # Crude YAML reader. Looks for `key:` at top level or `  key:` nested under
  # a parent. Returns first match's scalar value with surrounding whitespace
  # and quotes stripped. Comment lines (leading `#`, with or without
  # indentation) are skipped — `# test_command: pytest` is documentation,
  # not a value. Returns empty string if not found or YAML missing.
  local file="$1" key="$2"
  [[ -f "$file" ]] || { echo ""; return; }
  awk -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ "^[[:space:]]*"k":" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")
      gsub(/^["'\'']|["'\'']$/, "")
      print
      exit
    }
  ' "$file"
}

# Read a newline-separated string into a bash array (caller passes array name).
# Works on bash 3.2 (no readarray/mapfile required).
read_lines_into_array() {
  local _arr_name="$1"
  local _line
  eval "$_arr_name=()"
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    eval "$_arr_name+=(\"\$_line\")"
  done
}

is_git_repo() {
  git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1
}

diff_files() {
  # Files changed in HEAD vs BASE. Empty if not a git repo.
  is_git_repo || { echo ""; return; }
  git -C "$PROJECT_ROOT" diff --name-only "$BASE"...HEAD 2>/dev/null
}

# ----- rule: wip-commits -----------------------------------------------------
rule_wip_commits() {
  if ! is_git_repo; then
    emit "SKIP" "wip-commits" "not a git repo"
    return
  fi
  local matches
  matches=$(git -C "$PROJECT_ROOT" log "$BASE..HEAD" \
    --grep='WIP\|checkpoint\|TODO.*tomorrow\|FIXME.*later' -i \
    --oneline 2>/dev/null || true)
  if [[ -z "$matches" ]]; then
    emit "PASS" "wip-commits" "no WIP/checkpoint commits between $BASE and HEAD"
  else
    local count
    count=$(echo "$matches" | wc -l | tr -d ' ')
    emit "FAIL" "wip-commits" "$count commit(s) match WIP/checkpoint patterns: $(echo "$matches" | head -3 | tr '\n' '|')"
  fi
}

# ----- rule: tests-pass ------------------------------------------------------
rule_tests_pass() {
  local cmd
  cmd=$(yaml_get "$PROJECT_YML" "test_command")
  if [[ -z "$cmd" ]]; then
    emit "SKIP" "tests-pass" "no test_command in $PROJECT_YML"
    return
  fi
  local out exit_code
  out=$(cd "$PROJECT_ROOT" && eval "$cmd" 2>&1)
  exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    emit "PASS" "tests-pass" "\`$cmd\` exit 0"
  else
    local tail
    tail=$(echo "$out" | tail -3 | tr '\n' '|')
    emit "FAIL" "tests-pass" "\`$cmd\` exit $exit_code :: $tail"
  fi
}

# ----- rule: feature-flag-present --------------------------------------------
rule_feature_flag_present() {
  local marker
  marker=$(yaml_get "$PROJECT_YML" "feature_flag_marker")
  if [[ -z "$marker" ]]; then
    emit "SKIP" "feature-flag-present" "no feature_flag_marker in $PROJECT_YML"
    return
  fi
  local files
  files=$(diff_files)
  if [[ -z "$files" ]]; then
    emit "SKIP" "feature-flag-present" "no diff vs $BASE"
    return
  fi
  # Skip the rule for documentation-only / infra-only diffs.
  local non_doc
  non_doc=$(echo "$files" | grep -Ev '\.(md|txt|yml|yaml|toml|json)$|^LICENSE$|^docs/|^\.github/' || true)
  if [[ -z "$non_doc" ]]; then
    emit "SKIP" "feature-flag-present" "diff is documentation/config only"
    return
  fi
  # Pass non-doc filenames through stdin to git diff (NUL-safe via pathspec
  # file). Then grep ADDED lines (^+ but not ^+++) for the marker. We check
  # the patch, not the file contents — a file with a pre-existing flag marker
  # must not get the new code a free pass.
  local non_doc_array
  read_lines_into_array non_doc_array <<< "$non_doc"
  local diff_added
  diff_added=$(git -C "$PROJECT_ROOT" diff "$BASE...HEAD" -- "${non_doc_array[@]}" 2>/dev/null \
    | grep -E "^\+[^+]" || true)
  if [[ -z "$diff_added" ]]; then
    emit "SKIP" "feature-flag-present" "no added code lines in non-doc files"
    return
  fi
  if echo "$diff_added" | grep -qE "$marker"; then
    emit "PASS" "feature-flag-present" "marker \`$marker\` present in added code lines"
  else
    emit "FAIL" "feature-flag-present" "marker \`$marker\` not present in added code lines"
  fi
}

# ----- rule: adr-delta -------------------------------------------------------
rule_adr_delta() {
  local files
  files=$(diff_files)
  if [[ -z "$files" ]]; then
    emit "SKIP" "adr-delta" "no diff vs $BASE"
    return
  fi
  # Heuristic: changes to source code (not tests, migrations, docs, config)
  # above the threshold expect a new or modified ADR.
  local arch_files
  arch_files=$(echo "$files" | grep -Ev '\.(md|txt|yml|yaml|json|lock)$|^LICENSE$|^docs/|tests?/|migrations?/|^\.github/|/test_|_test\.' || true)
  local arch_lines=0
  if [[ -n "$arch_files" ]] && is_git_repo; then
    local arch_files_array
    read_lines_into_array arch_files_array <<< "$arch_files"
    arch_lines=$(git -C "$PROJECT_ROOT" diff --numstat "$BASE...HEAD" -- "${arch_files_array[@]}" 2>/dev/null \
      | awk '{a+=$1; b+=$2} END {print a+b+0}')
  fi
  local threshold=200
  if [[ $arch_lines -lt $threshold ]]; then
    emit "SKIP" "adr-delta" "architectural diff $arch_lines lines below threshold $threshold"
    return
  fi
  local adr_changes
  adr_changes=$(echo "$files" | grep -E '^docs/decisions/ADR-' || true)
  if [[ -n "$adr_changes" ]]; then
    local count
    count=$(echo "$adr_changes" | wc -l | tr -d ' ')
    emit "PASS" "adr-delta" "$count ADR file(s) changed for $arch_lines architectural lines"
  else
    emit "FAIL" "adr-delta" "$arch_lines architectural lines changed but no ADR delta in docs/decisions/"
  fi
}

# ----- rule: frontmatter-valid -----------------------------------------------
rule_frontmatter_valid() {
  local validator="$PROJECT_ROOT/methodology/frontmatter-validate.py"
  if [[ ! -f "$validator" ]]; then
    emit "SKIP" "frontmatter-valid" "validator not found at methodology/frontmatter-validate.py"
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    emit "SKIP" "frontmatter-valid" "python3 not on PATH"
    return
  fi
  # Verify PyYAML is importable. The validator itself prints a FAIL line and
  # exit 2 if PyYAML is missing; we pre-check so the rule SKIPs cleanly
  # rather than appearing to FAIL on a missing dependency.
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    emit "SKIP" "frontmatter-valid" "PyYAML not installed (pip3 install pyyaml)"
    return
  fi
  # Determine which artifact files to validate. If we have a diff vs BASE,
  # restrict to changed .ssd/features/*.md and .ssd/milestones/*.md files.
  # Otherwise (no diff) the validator walks .ssd/features/ and .ssd/milestones/
  # by default.
  local files out exit_code
  files=$(diff_files | grep -E '^\.ssd/(features|milestones)/.*\.md$' || true)
  if [[ -n "$files" ]]; then
    local files_array
    read_lines_into_array files_array <<< "$files"
    out=$(python3 "$validator" "${files_array[@]}" 2>&1)
    exit_code=$?
  else
    out=$(python3 "$validator" 2>&1)
    exit_code=$?
  fi
  if [[ $exit_code -eq 0 ]]; then
    local count
    count=$(echo "$out" | grep -c '^PASS ' || true)
    if [[ "$count" -gt 0 ]]; then
      emit "PASS" "frontmatter-valid" "$count artifact(s) validated against schemas"
    else
      emit "SKIP" "frontmatter-valid" "no SSD artifacts in scope"
    fi
  else
    local fail_lines
    fail_lines=$(echo "$out" | grep '^FAIL ' | head -3 | tr '\n' '|')
    emit "FAIL" "frontmatter-valid" "validator exit $exit_code :: $fail_lines"
  fi
}

# ----- run all rules ---------------------------------------------------------
rule_wip_commits
rule_tests_pass
rule_feature_flag_present
rule_adr_delta
rule_frontmatter_valid

# ----- emit results ----------------------------------------------------------
if [[ $JSON -eq 1 ]]; then
  echo "{"
  echo "  \"base\": \"$BASE\","
  echo "  \"fail_count\": $FAIL_COUNT,"
  echo "  \"results\": ["
  json_idx=0
  json_last=$((${#RESULTS[@]} - 1))
  for line in "${RESULTS[@]}"; do
    json_status=$(echo "$line" | awk '{print $1}')
    json_rule=$(echo "$line" | awk '{print $2}')
    json_detail=$(echo "$line" | sed 's/^[^:]*:: //' | sed 's/"/\\"/g')
    if [[ $json_idx -eq $json_last ]]; then
      echo "    {\"status\": \"$json_status\", \"rule\": \"$json_rule\", \"detail\": \"$json_detail\"}"
    else
      echo "    {\"status\": \"$json_status\", \"rule\": \"$json_rule\", \"detail\": \"$json_detail\"},"
    fi
    json_idx=$((json_idx + 1))
  done
  echo "  ]"
  echo "}"
else
  for line in "${RESULTS[@]}"; do
    echo "$line"
  done
fi

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
