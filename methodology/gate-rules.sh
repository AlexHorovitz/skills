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
#   bash methodology/gate-rules.sh --rules no-leaky-state[,other-rule]
#                                                 # run only the named rules
#                                                 # (used by the v1.18.0+ pre-commit hook —
#                                                 # see ADR-0008 and methodology/hooks/)
#   bash methodology/gate-rules.sh --staged       # diff staged-vs-HEAD instead of branch-vs-base
#                                                 # (v1.19.0+; used by the pre-commit hook)
#
# License: see /LICENSE.

set -uo pipefail   # NOTE: not -e — we want to run all rules even if one fails.

# BASE defaults to "main" by design — see docs/decisions/ADR-0007-parallel-features.md § "Q1".
# When called from the /ssd orchestrator on behalf of a parallel-features workstream, the
# orchestrator passes `--base <ref>` explicitly (typically origin/main or the workstream's
# recorded base). The script itself remains standalone and CI-friendly; it intentionally does
# NOT auto-derive the base from .ssd/current.yml so it can be invoked as a plain bash script
# without orchestrator context. Future iter-D `/ssd workstream` commands may introduce a
# `base:` field on the workstream entry; this script would still need an explicit `--base`
# from the caller. Keep the standalone contract.
BASE="main"
JSON=0
RULES_FILTER=""   # comma-separated list of rule names; empty = run all
MODE="branch"     # branch (default, diff vs $BASE...HEAD) | staged (diff vs --cached)
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
    --rules)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "--rules requires a value (comma-separated rule names)" >&2; exit 2
      fi
      RULES_FILTER="$2"; shift 2 ;;
    --staged) MODE="staged"; shift ;;
    -h|--help)
      sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Decide whether a rule should run given any --rules filter. Empty filter = run all.
should_run() {
  local rule="$1"
  [[ -z "$RULES_FILTER" ]] && return 0
  case ",$RULES_FILTER," in
    *",$rule,"*) return 0 ;;
    *) return 1 ;;
  esac
}

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
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")          # strip "key: "
      # Inline-comment handling (ssd-upgrade iter-B MAJOR-4): a trailing ` # …` is a YAML comment, not
      # part of the value. For an unquoted scalar, strip it; for a quoted scalar, take the value through
      # the closing quote (so a `#` inside quotes is preserved and a comment after it is dropped).
      if ($0 ~ /^["'\'']/) {
        q = substr($0, 1, 1); rest = substr($0, 2); idx = index(rest, q)
        print (idx > 0 ? substr(rest, 1, idx - 1) : rest)
      } else {
        sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, "")
        print
      }
      exit
    }
  ' "$file"
}

# Read a YAML list value into stdout, one item per line. Handles the simple two-space
# indented form ssd-init writes:
#
#   ssd:
#     gitignored_state:
#       - .env.local
#       - secrets/**
#
# Returns empty if the key isn't present or has no items. Quotes around items are stripped.
yaml_get_list() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return
  awk -v k="$key" '
    BEGIN { in_list = 0; list_indent = -1 }
    /^[[:space:]]*#/ { next }
    {
      if (in_list) {
        match($0, /^[[:space:]]*/)
        cur_indent = RLENGTH
        if (match($0, /^[[:space:]]*-[[:space:]]+/)) {
          item = $0
          sub(/^[[:space:]]*-[[:space:]]+/, "", item)
          gsub(/^["'\'']|["'\'']$/, "", item)
          print item
          next
        }
        # Non-list line at indent <= list_indent ends the list.
        if (length($0) > cur_indent && cur_indent <= list_indent) {
          in_list = 0
        } else {
          next
        }
      }
      if (match($0, "^[[:space:]]*"k":[[:space:]]*$")) {
        match($0, /^[[:space:]]*/)
        list_indent = RLENGTH
        in_list = 1
      }
    }
  ' "$file"
}

# Match a path against a gitignore-style pattern. Supports `**` (anything including
# slashes), `*` (anything but slash), trailing `/` (directory prefix), and `?` (single
# non-slash char). Returns 0 on match, 1 on no match.
matches_deny_pattern() {
  local path="$1" pattern="$2"
  # Trailing slash = directory prefix: any path that starts with pattern matches.
  if [[ "$pattern" == */ ]]; then
    [[ "$path" == "$pattern"* ]] && return 0
    return 1
  fi
  # No globs = exact match.
  if [[ "$pattern" != *'*'* && "$pattern" != *'?'* ]]; then
    [[ "$path" == "$pattern" ]] && return 0
    return 1
  fi
  # Convert glob to anchored bash regex. Escape regex metacharacters that are literal in
  # gitignore semantics (per code-review MINOR-1 on iter A — needed for user-supplied
  # gitignored_state[] patterns that may contain +, (, ), |, ^, $, \). Curly braces
  # intentionally NOT escaped: bash parameter expansion has brace-parsing ambiguity with
  # `${var//\}/...}` syntax, AND bash regex treats { } as literal outside {n,m} quantifier
  # context, so leaving them un-escaped is safe for the patterns we care about. If a project
  # ever needs explicit {n,m} matching semantics, they can use [ ] char classes instead.
  local regex="$pattern"
  regex="${regex//\\/\\\\}"   # escape backslash first
  regex="${regex//./\\.}"
  regex="${regex//+/\\+}"
  regex="${regex//(/\\(}"
  regex="${regex//)/\\)}"
  regex="${regex//|/\\|}"
  regex="${regex//\^/\\^}"
  regex="${regex//\$/\\\$}"
  # Now the glob → regex conversion. Order matters: ** before * (so the ** glob isn't
  # consumed by the single-* substitution). Brackets [abc] left intact — gitignore char
  # classes happen to be valid bash regex char classes too, so they work as-is.
  regex="${regex//\*\*/§§}"   # placeholder for **
  regex="${regex//\*/[^/]*}"  # single-* → non-slash
  regex="${regex//§§/.*}"     # ** → any (including slash)
  regex="${regex//\?/[^/]}"
  [[ "$path" =~ ^${regex}$ ]]
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
  # Files changed in HEAD vs BASE (default mode), or staged vs HEAD (--staged mode).
  # Empty if not a git repo.
  is_git_repo || { echo ""; return; }
  if [[ "$MODE" == "staged" ]]; then
    git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null
  else
    git -C "$PROJECT_ROOT" diff --name-only "$BASE"...HEAD 2>/dev/null
  fi
}

# Human-readable label for the current diff scope. Used in SKIP detail messages.
diff_scope_label() {
  if [[ "$MODE" == "staged" ]]; then
    echo "staged files"
  else
    echo "vs $BASE"
  fi
}

# ----- rule: wip-commits -----------------------------------------------------
rule_wip_commits() {
  if ! is_git_repo; then
    emit "SKIP" "wip-commits" "not a git repo"
    return
  fi
  # In --staged mode the commit isn't yet created, so there's nothing to grep for WIP/
  # checkpoint messages. SKIP cleanly — the rule runs in branch mode after the commit lands,
  # catching WIP / checkpoint commits at gate time. The pre-commit hook handles state
  # leakage (no-leaky-state), not commit-message discipline.
  if [[ "$MODE" == "staged" ]]; then
    emit "SKIP" "wip-commits" "staged mode (no commits to grep yet)"
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
    emit "SKIP" "feature-flag-present" "no diff ($(diff_scope_label))"
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
    emit "SKIP" "adr-delta" "no diff ($(diff_scope_label))"
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

# ----- rule: no-leaky-state --------------------------------------------------
# Catches gitignored-by-policy files smuggled into the diff (force-add via `git add -f`,
# `.gitignore` edited to remove protections, new artifact types not yet in `.gitignore`).
# Doctrine cite: ADR-0008 § "Decision" — layered defenses around the selective-commit split.
rule_no_leaky_state() {
  is_git_repo || { emit "SKIP" "no-leaky-state" "not a git repo"; return; }
  local mode
  mode=$(yaml_get "$PROJECT_YML" "gitignore_mode")
  [[ -z "$mode" ]] && mode="selective"   # default for v1.18.0+
  if [[ "$mode" == "blanket" ]]; then
    emit "SKIP" "no-leaky-state" "project on blanket gitignore mode (project.yml.ssd.gitignore_mode)"
    return
  fi
  if [[ "$mode" != "selective" ]]; then
    emit "SKIP" "no-leaky-state" "unknown gitignore_mode: '$mode' (expected selective|blanket)"
    return
  fi
  local files
  files=$(diff_files)
  if [[ -z "$files" ]]; then
    emit "SKIP" "no-leaky-state" "no diff ($(diff_scope_label))"
    return
  fi
  # Baseline deny-list, hard-coded per ADR-0008 § "Decision". Projects extend (not shrink)
  # via project.yml.ssd.gitignored_state.
  local baseline=(
    ".ssd/current.yml"
    ".ssd/current.notes.yml"
    ".ssd/init-log.md"
    ".ssd/project.yml"
    ".ssd/archive/"
    ".ssd/audits/"
    ".ssd/features/**/iterations/**/deferred.yml"
    ".ssd/features/**/current.yml.bak"
    ".ssd/milestones/**/sha-before"
    ".ssd/milestones/**/metrics-before.yml"
  )
  # Read project-supplied additional patterns.
  local additional=()
  local _line
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    additional+=("$_line")
  done < <(yaml_get_list "$PROJECT_YML" "gitignored_state")
  local forbidden=()
  local f pattern
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    for pattern in "${baseline[@]}" ${additional[@]+"${additional[@]}"}; do
      if matches_deny_pattern "$f" "$pattern"; then
        forbidden+=("$f")
        break
      fi
    done
  done <<< "$files"
  if [[ ${#forbidden[@]} -eq 0 ]]; then
    emit "PASS" "no-leaky-state" "no gitignored-by-policy files in diff"
  else
    local count=${#forbidden[@]}
    local sample
    sample=$(printf '%s|' "${forbidden[@]:0:3}")
    emit "FAIL" "no-leaky-state" "$count file(s) gitignored by policy but tracked: ${sample}"
  fi
}

# ----- rule: skill-version-sync ----------------------------------------------
# Asserts every <project-root>/*/SKILL.md's required-frontmatter example version
# matches that file's **Version:** banner. Closes the version-drift-in-examples
# finding (refactor R4, post-v1.19 milestone) by enforcing self-consistency
# mechanically. SKIPs cleanly for downstream projects that have no in-repo
# SKILL.md example blocks, so it's a no-op outside the skills library itself.
# Doctrine cite: core.md §2 (docs as a first-class deliverable; keep examples honest).
rule_skill_version_sync() {
  local validator="$PROJECT_ROOT/methodology/frontmatter-validate.py"
  if [[ ! -f "$validator" ]]; then
    emit "SKIP" "skill-version-sync" "validator not found at methodology/frontmatter-validate.py"
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    emit "SKIP" "skill-version-sync" "python3 not on PATH"
    return
  fi
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    emit "SKIP" "skill-version-sync" "PyYAML not installed (pip3 install pyyaml)"
    return
  fi
  local out exit_code
  out=$(python3 "$validator" --check-skill-examples "$PROJECT_ROOT" 2>&1)
  exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    local count
    count=$(echo "$out" | grep -c '^PASS ' || true)
    if [[ "$count" -gt 0 ]]; then
      emit "PASS" "skill-version-sync" "$count skill example(s) match banner"
    else
      emit "SKIP" "skill-version-sync" "no SKILL.md example blocks to check"
    fi
  else
    local fail_lines
    fail_lines=$(echo "$out" | grep '^FAIL ' | head -3 | tr '\n' '|')
    emit "FAIL" "skill-version-sync" "$fail_lines"
  fi
}

# ----- rule: migration-manifest-current --------------------------------------
# Closes ADR-0013 R2 (manifest drift) at the structural level. Only meaningful in the SSD skills
# library repo itself (a consuming project has no methodology/migrations.yml — it ships with the
# installed skills), so it SKIPs cleanly elsewhere. Validates the manifest is healthy: required
# fields per entry, unique ids, ascending introduced_in (append-only), and no introduced_in newer
# than the repo's VERSION. The "did a convention change but no entry was added" judgment remains a
# documented human release obligation (ADR-0013) — a script can't read intent — but these structural
# checks catch the authoring mistakes that silently rot the manifest.
rule_migration_manifest_current() {
  local manifest="$PROJECT_ROOT/methodology/migrations.yml"
  local version_file="$PROJECT_ROOT/VERSION"
  if [[ ! -f "$manifest" ]]; then
    emit "SKIP" "migration-manifest-current" "no methodology/migrations.yml (not the skills-library repo)"
    return
  fi
  local version=""
  [[ -f "$version_file" ]] && version="$(tr -d '[:space:]' < "$version_file")"
  # awk validates structure; prints "OK" or "FAIL: <reason>".
  local result
  result=$(awk -v ver="$version" '
    function vle(a, b,   x, y, i) {   # return 1 if a <= b (numeric per dotted component)
      split(a, x, "."); split(b, y, ".")
      for (i = 1; i <= 3; i++) { if ((x[i]+0) < (y[i]+0)) return 1; if ((x[i]+0) > (y[i]+0)) return 0 }
      return 1
    }
    /^  - id:/            { n++; id=$3
                            if (id == "") { print "FAIL: entry "n" has empty id"; failed=1; exit }
                            ids[id]++; if (ids[id] > 1) { print "FAIL: duplicate id " id; failed=1; exit } ; next }
    /^    introduced_in:/ { iv=$2; gsub(/"/,"",iv)
                            if (prev_iv != "" && !vle(prev_iv, iv)) { print "FAIL: introduced_in not ascending at " id " (" prev_iv " then " iv ")"; failed=1; exit }
                            if (ver != "" && !vle(iv, ver)) { print "FAIL: " id " introduced_in " iv " is newer than VERSION " ver; failed=1; exit }
                            prev_iv=iv; next }
    END { if (!failed) { if (n == 0) print "FAIL: manifest has no entries"; else print "OK " n } }
  ' "$manifest")
  if [[ "$result" == FAIL:* ]]; then
    emit "FAIL" "migration-manifest-current" "${result#FAIL: }"
  elif [[ "$result" == OK* ]]; then
    emit "PASS" "migration-manifest-current" "manifest valid (${result#OK } entries; ids unique, ascending, ≤ VERSION ${version:-?})"
  else
    emit "SKIP" "migration-manifest-current" "manifest unreadable"
  fi
}

# Extract active workstreams from .ssd/current.yml as `slug|phase|issue` lines (one per active[]
# entry). Crude YAML list walker (no PyYAML dependency, consistent with yaml_get): tracks the
# top-level `active:` section, starts a record at each `  - ` item, and captures slug/phase/issue.
# `issue:` may be `null`, empty, or a number; callers filter to numeric bindings.
parse_active_workstreams() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    function flush() { if (have) printf "%s|%s|%s\n", slug, phase, issue; have=0; slug=""; phase=""; issue="" }
    /^[^[:space:]#]/ { flush(); section = ($0 ~ /^active:/) ? "active" : "other"; next }
    section != "active" { next }
    /^[[:space:]]*-[[:space:]]/ {
      flush(); have=1
      if ($0 ~ /slug:/) { s=$0; sub(/.*slug:[[:space:]]*/,"",s); sub(/[[:space:]]*#.*/,"",s); slug=s }
      next
    }
    /^[[:space:]]+slug:/  { s=$0; sub(/.*slug:[[:space:]]*/,"",s);  sub(/[[:space:]]*#.*/,"",s); slug=s;  next }
    /^[[:space:]]+phase:/ { s=$0; sub(/.*phase:[[:space:]]*/,"",s); sub(/[[:space:]]*#.*/,"",s); phase=s; next }
    /^[[:space:]]+issue:/ { s=$0; sub(/.*issue:[[:space:]]*/,"",s); sub(/[[:space:]]*#.*/,"",s); issue=s; next }
    END { flush() }
  ' "$file"
}

# issue-sync-current (ADR-0014 Q3): when GitHub issue tracking is on, verify each active workstream's
# cached `issue:` is still OPEN and its single ssd:phase/* label matches current.yml's phase. The
# issue is a one-way MIRROR, so this rule is informational and SKIP-by-default — it SKIPs whenever
# tracking is off, gh is unavailable, or no workstream has an issue binding (i.e. every project except
# an opted-in one). It FAILs only on a hard inconsistency. Models on rule_migration_manifest_current.
rule_issue_sync_current() {
  local current="$PROJECT_ROOT/.ssd/current.yml"
  local tracking; tracking="$(yaml_get "$PROJECT_YML" "issue_tracking")"
  case "$tracking" in
    on|true|yes) ;;
    *) emit "SKIP" "issue-sync-current" "issue_tracking not on (mirror dormant)"; return ;;
  esac
  [[ -f "$current" ]] || { emit "SKIP" "issue-sync-current" "no .ssd/current.yml"; return; }
  # Collect workstreams with a numeric issue binding FIRST — before touching the network. A repo that
  # opted in but hasn't synced any issue yet (every issue: null) then SKIPs with zero gh calls (MINOR-1).
  local bindings; bindings="$(parse_active_workstreams "$current" | awk -F'|' '$3 ~ /^[0-9]+$/')"
  if [[ -z "$bindings" ]]; then
    emit "SKIP" "issue-sync-current" "no active workstream has an issue binding"; return
  fi
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1 || ! gh repo view >/dev/null 2>&1; then
    emit "SKIP" "issue-sync-current" "gh unavailable/unauthenticated — mirror not checkable"; return
  fi
  local checked=0 problems="" slug phase issue
  while IFS='|' read -r slug phase issue; do
    [[ -n "$slug" ]] || continue
    local out state labels
    out="$(gh issue view "$issue" --json state,labels \
            --jq '.state + "\t" + ([.labels[].name | select(startswith("ssd:phase/"))] | join(","))' 2>/dev/null)" \
      || continue                                  # flaky per-issue lookup → don't FAIL on it
    checked=$((checked + 1))
    state="${out%%$'\t'*}"; labels="${out#*$'\t'}"
    if [[ "$state" == "CLOSED" ]]; then
      problems+=" #$issue($slug:closed-while-active)"
    elif [[ "$labels" != "ssd:phase/$phase" ]]; then
      problems+=" #$issue($slug:label='${labels:-none}'≠phase/$phase)"
    fi
  done < <(printf '%s\n' "$bindings")
  if [[ "$checked" -eq 0 ]]; then
    emit "SKIP" "issue-sync-current" "issue binding(s) present but gh lookups all failed — mirror not checkable"
  elif [[ -n "$problems" ]]; then
    emit "FAIL" "issue-sync-current" "mirror drift:${problems}"
  else
    emit "PASS" "issue-sync-current" "$checked issue binding(s) open and phase-label in sync"
  fi
}

# ----- run all rules ---------------------------------------------------------
should_run wip-commits        && rule_wip_commits
should_run tests-pass         && rule_tests_pass
should_run feature-flag-present && rule_feature_flag_present
should_run adr-delta          && rule_adr_delta
should_run frontmatter-valid  && rule_frontmatter_valid
should_run no-leaky-state     && rule_no_leaky_state
should_run skill-version-sync && rule_skill_version_sync
should_run migration-manifest-current && rule_migration_manifest_current
should_run issue-sync-current && rule_issue_sync_current

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
