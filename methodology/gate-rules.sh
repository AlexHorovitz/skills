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
GATE_YML="$PROJECT_ROOT/.ssd/gate.yml"        # ADR-0015: committed, portable gate inputs

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

gate_input() {
  # ADR-0015 fallback chain for gate inputs (test_command, feature_flag_marker). Reads
  # .ssd/project.yml FIRST so a developer can override locally, then the committed .ssd/gate.yml
  # so the configuration travels to every clone and CI runner (fixes P2: gate config that could
  # not leave one workstation). Returns the first non-empty value, or "" if neither file defines
  # the key.
  local key="$1" val
  val=$(yaml_get "$PROJECT_YML" "$key")
  [[ -n "$val" ]] && { echo "$val"; return; }
  yaml_get "$GATE_YML" "$key"
}

# ----- gitignore-mode helpers (ADR-0017) -------------------------------------
# The project's commit posture. Exactly three values are recognized; anything else is a
# configuration error, NOT a silent default (see rule_no_leaky_state).
gitignore_mode() {
  local mode
  mode=$(yaml_get "$PROJECT_YML" "gitignore_mode")
  [[ -z "$mode" ]] && mode="selective"   # default for v1.18.0+
  echo "$mode"
}

# Which scope a rule that reads SSD ARTIFACTS should use.
#
# Under private mode (ADR-0017) no SSD artifact is ever tracked, so it can never appear in
# `git diff <base>...HEAD`. A rule that diff-scopes its artifact lookup is therefore
# structurally unable to fire — and for `adr-delta` it is worse than that: it FAILs demanding a
# committed ADR delta that private mode forbids, while `no-leaky-state` FAILs if one is
# force-added. Both branches FAIL and the gate becomes unpassable on any change over the
# adr-delta threshold. See ADR-0017 § "The gate must not go quiet".
#
# Worktree scope is strictly weaker than diff scope (an mtime is touchable in a way a commit is
# not); every caller must say so in its detail string. The alternative is a gate that either
# deadlocks or attests to nothing.
artifact_scope() {
  [[ "$(gitignore_mode)" == "private" ]] && echo "worktree" || echo "diff"
}

# $BASE's commit time as epoch seconds, minus one second of slack. Empty if unresolvable.
#
# The slack is not cosmetic: filesystem mtimes are second-granular, so an artifact written in the
# SAME second as the base commit would not count as "newer" and the rule would report a false FAIL.
# Erring one second toward PASS is the right direction — a false FAIL on adr-delta is an unpassable
# gate, which is the entire failure this fallback exists to avoid.
base_commit_epoch() {
  is_git_repo || { echo ""; return; }
  local epoch
  epoch=$(git -C "$PROJECT_ROOT" log -1 --format=%ct "$BASE" 2>/dev/null) || { echo ""; return; }
  [[ -z "$epoch" ]] && { echo ""; return; }
  echo "$((epoch - 1))"
}

# A file's mtime in epoch seconds. Empty if it cannot be determined.
#
# BSD (`stat -f %m`) and GNU (`stat -c %Y`) take incompatible flags, so both are tried. Two
# non-obvious constraints, each learned from a real failure:
#
#   1. GNU FORM FIRST. On BSD, `stat -c` is an illegal option: it fails with EMPTY stdout, so falling
#      through is clean. The reverse is not true — on GNU, `-f` means --file-system, so
#      `stat -f %m FILE` parses as two operands (a file named `%m`, which fails, and FILE, which
#      prints a FILESYSTEM STATUS BLOCK to stdout). Exit status is non-zero, so `||` would fall
#      through, but the garbage is already on stdout. BSD-first therefore corrupts the value on every
#      Linux host — including CI runners. (Review round-1 MAJOR-1.)
#   2. VALIDATE THE OUTPUT. Ordering alone still trusts whatever lands on stdout. Requiring a bare
#      integer means no `stat` variant on any platform can have its output mistaken for a timestamp;
#      anything else returns empty, which callers must treat as "unknown", never as "old".
#
# Deliberately does NOT use `find -newermt`: BSD find cannot parse the `@epoch` form at all ("Can't
# parse date/time"), which turned this probe into a permanent FAIL on stock macOS — trading the
# deadlock this fallback fixes for a different unpassable gate. Both bugs are the same shape: a
# mechanism asserted from knowledge, true on one platform only.
file_mtime() {
  local v
  v=$(stat -c %Y "$1" 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; return; }
  v=$(stat -f %m "$1" 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && { echo "$v"; return; }
  echo ""
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
  #
  # `core.quotepath=false` IS LOAD-BEARING, not hygiene (Feynman audit post-v2.11.0, D1). By default
  # git C-QUOTES any path containing non-ASCII bytes — it wraps the path in double quotes and
  # octal-escapes the bytes, so `.ssd/archive/café.md` arrives as `".ssd/archive/caf\303\251.md"`.
  # Every downstream path comparison then misses, and SIX of the twelve rules read this function:
  # no-leaky-state, rails-walked, frontmatter-valid, feature-flag-present, adr-delta, feynman-clean.
  # Verified by control test: an ascii policy-ignored file FAILed no-leaky-state and an accented one
  # in the same directory PASSed while genuinely tracked — the privacy boundary going quiet on a leak.
  # Present since v1.5.0 (ee3b897), 27 releases, and the identical class had already been found and
  # fixed in migrate.sh's `ls-files -z` in this same epic. The sweep stopped at one file.
  #
  # Why not `-z`: it also survives a path containing a literal NEWLINE, which quotepath=false does not
  # — but it changes this function's contract from newline- to NUL-delimited and forces all six
  # consumers to move together. A newline in a path under .ssd/ is pathological; an accent is a
  # Tuesday in a French codebase. That residual gap is a known, narrower one and is recorded here
  # rather than left for the next reader to rediscover.
  is_git_repo || { echo ""; return; }
  if [[ "$MODE" == "staged" ]]; then
    git -C "$PROJECT_ROOT" -c core.quotepath=false diff --cached --name-only 2>/dev/null
  else
    git -C "$PROJECT_ROOT" -c core.quotepath=false diff --name-only "$BASE"...HEAD 2>/dev/null
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
  cmd=$(gate_input "test_command")
  if [[ -z "$cmd" ]]; then
    emit "SKIP" "tests-pass" "no test_command in .ssd/project.yml or .ssd/gate.yml"
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
  marker=$(gate_input "feature_flag_marker")
  if [[ -z "$marker" ]]; then
    emit "SKIP" "feature-flag-present" "no feature_flag_marker in .ssd/project.yml or .ssd/gate.yml"
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
  # Private mode (ADR-0017): docs/decisions/ is gitignored, so an ADR can never appear in the diff.
  # Diff-scoping here would FAIL demanding a committed ADR delta that the mode forbids, while
  # no-leaky-state FAILs if one is force-added — both branches FAIL and the gate is unpassable on
  # any change over the threshold. Fall back to a worktree probe: an ADR touched more recently than
  # the base commit. Deliberately weaker than a diff (an mtime is touchable) and the detail says so.
  if [[ "$(artifact_scope)" == "worktree" ]]; then
    local adr_dir="$PROJECT_ROOT/docs/decisions" base_epoch rcount=0 unreadable=0
    if [[ ! -d "$adr_dir" ]]; then
      emit "FAIL" "adr-delta" "$arch_lines architectural lines changed but docs/decisions/ does not exist (private mode, worktree scope)"
      return
    fi
    base_epoch=$(base_commit_epoch)
    if [[ -z "$base_epoch" ]]; then
      # No reference point for "recently touched", so report the limitation rather than inventing a
      # verdict in either direction. A SKIP here is honest; a PASS would attest to nothing.
      emit "SKIP" "adr-delta" "private mode — cannot resolve base '$BASE' commit time; worktree ADR probe has no reference point"
      return
    fi
    # Plain glob + stat rather than `find -newermt` (see file_mtime for why). docs/decisions/ is
    # flat by convention (architect/SKILL.md § ADR), so a glob covers it.
    local adr_file mt
    for adr_file in "$adr_dir"/ADR-*.md; do
      [[ -f "$adr_file" ]] || continue          # an unmatched glob stays literal
      mt=$(file_mtime "$adr_file")
      if [[ -z "$mt" ]]; then
        unreadable=$((unreadable + 1))
        continue
      fi
      [[ "$mt" -ge "$base_epoch" ]] && rcount=$((rcount + 1))
    done
    if [[ $rcount -gt 0 ]]; then
      emit "PASS" "adr-delta" "$rcount ADR file(s) modified since base for $arch_lines architectural lines (private mode: worktree mtime probe, weaker than a diff)"
    elif [[ $unreadable -gt 0 ]]; then
      emit "SKIP" "adr-delta" "private mode — $unreadable ADR file(s) present but mtime unreadable; cannot verify (worktree scope)"
    else
      emit "FAIL" "adr-delta" "$arch_lines architectural lines changed but no ADR under docs/decisions/ modified since base '$BASE' (private mode, worktree scope)"
    fi
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
    # Report validated AND unvalidated. The validator already emits a SKIP line per artifact with no
    # matching schema; discarding that count made "N artifact(s) validated" read as full coverage when
    # briefs / deploy notes / skeptic reports have no schema at all (Feynman audit 2026-08-19, C4).
    local count skipped detail
    count=$(echo "$out" | grep -c '^PASS ' || true)
    skipped=$(echo "$out" | grep -c '^SKIP ' || true)
    if [[ "$count" -gt 0 ]]; then
      detail="$count artifact(s) validated against schemas"
      [[ "$skipped" -gt 0 ]] && detail="$detail; $skipped unvalidated (no matching schema)"
      emit "PASS" "frontmatter-valid" "$detail"
    elif [[ "$skipped" -gt 0 ]]; then
      # NOT "no SSD artifacts in scope" (Feynman audit 2026-09-01, C7). This branch fires when the
      # change set contains artifacts the validator SAW and had no schema for. Reporting absence there
      # is a false statement, and it stood for four releases because the previous fix to this block
      # (Feynman audit 2026-08-19, C4) corrected the `count > 0` path and left this one asserting
      # something untrue. A SKIP still means "nothing was checked" — it now says WHY.
      emit "SKIP" "frontmatter-valid" "$skipped artifact(s) in scope, none with a matching schema"
    else
      emit "SKIP" "frontmatter-valid" "no SSD artifacts in scope"
    fi
  else
    local fail_lines
    fail_lines=$(echo "$out" | grep '^FAIL ' | head -3 | tr '\n' '|')
    emit "FAIL" "frontmatter-valid" "validator exit $exit_code :: $fail_lines"
  fi
}

# Read one scalar from a file's YAML frontmatter block ONLY — between the leading `---` and the next
# `---`. Deliberately narrower than yaml_get: a feynman report's prose and grade tables legitimately
# contain lines that yaml_get would match in the body (a claim quoted as `contradicted: ...`), and a
# gate rule that can be steered by report prose is not a gate rule. Returns "" if the file has no
# frontmatter or the key is absent.
frontmatter_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || { echo ""; return; }
  awk -v k="$key" '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
    /^---[[:space:]]*$/ { exit }
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ "^[[:space:]]*"k":[[:space:]]*" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print; exit
    }
  ' "$file"
}

# ----- rule: no-leaky-state --------------------------------------------------
# Catches gitignored-by-policy files smuggled into the diff (force-add via `git add -f`,
# `.gitignore` edited to remove protections, new artifact types not yet in `.gitignore`).
# Doctrine cite: ADR-0008 § "Decision" — layered defenses around the selective-commit split.
rule_no_leaky_state() {
  is_git_repo || { emit "SKIP" "no-leaky-state" "not a git repo"; return; }
  local mode
  mode=$(gitignore_mode)
  if [[ "$mode" == "blanket" ]]; then
    emit "SKIP" "no-leaky-state" "project on blanket gitignore mode (project.yml.ssd.gitignore_mode)"
    return
  fi
  # An unrecognized value is a FAIL, not a SKIP (ADR-0017). Previously any unknown string —
  # including a typo like `privat` — silently disabled SSD's only leak-detection rule. Under a mode
  # whose entire purpose is privacy, a typo that turns protection off without saying so is
  # unacceptable. FAIL is the loud channel in the PASS|FAIL|SKIP contract; no 4th status is invented.
  if [[ "$mode" != "selective" && "$mode" != "private" ]]; then
    emit "FAIL" "no-leaky-state" "unrecognized gitignore_mode: '$mode' (expected selective|blanket|private) — fix project.yml.ssd.gitignore_mode; leak detection is NOT running"
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
  # Project-supplied additional patterns, read ONCE and unioned into whichever deny-list applies.
  # Hoisted above the mode branch (review round-1 MAJOR-2): the private branch used to `return`
  # before reaching this read, so a private project's `gitignored_state` was silently unenforced —
  # in the one mode where this rule is the primary safety layer, and contradicting both
  # chapters/enforcement.md and the project.yml template's "additive only" promise. Assembling the
  # deny-list once for both modes removes the possibility of that drift recurring.
  local additional=()
  local _line
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    additional+=("$_line")
  done < <(yaml_get_list "$PROJECT_YML" "gitignored_state")

  # Private mode (ADR-0017) denies EVERYTHING SSD produces — this is the mode where the rule is
  # load-bearing rather than advisory. Under `blanket` the rule SKIPs because nothing needs
  # protecting; under `private` it is the primary enforcement of the privacy promise, so a leaked
  # artifact is a privacy failure rather than commit noise.
  #
  # This set MUST mirror methodology/private.gitignore. They are the same set in two syntaxes and a
  # forgotten side is a silent leak (ADR-0008 § "Future Compatibility"); parity fixture
  # `deny-list-mirrors-pattern-file` asserts they agree.
  if [[ "$mode" == "private" ]]; then
    # `.ssd` (exact) alongside `.ssd/` (prefix) — ADR-0018. matches_deny_pattern treats a trailing
    # slash as a DIRECTORY PREFIX, so `.ssd/` does not match the bare path `.ssd`, which is what a
    # symlinked artifact store appears as in a diff. Without the exact entry this rule is blind to a
    # committed store symlink — the one leak the store feature must never permit.
    local private_baseline=( ".ssd" ".ssd/" "docs/decisions/" "docs/runbooks/" "docs/architecture/" )
    local leaked=() pf pp
    while IFS= read -r pf; do
      [[ -z "$pf" ]] && continue
      for pp in "${private_baseline[@]}" ${additional[@]+"${additional[@]}"}; do
        if matches_deny_pattern "$pf" "$pp"; then
          leaked+=("$pf")
          break
        fi
      done
    done <<< "$files"
    if [[ ${#leaked[@]} -eq 0 ]]; then
      emit "PASS" "no-leaky-state" "private mode — no SSD artifact tracked in diff ($(diff_scope_label))"
    else
      local lcount=${#leaked[@]} lsample
      lsample=$(printf '%s|' "${leaked[@]:0:3}")
      emit "FAIL" "no-leaky-state" "private mode — $lcount SSD file(s) tracked but must not be: ${lsample}"
    fi
    return
  fi
  local baseline=(
    ".ssd"                     # exact: a symlinked artifact store (ADR-0018); `.ssd/` cannot match it
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
  # (project-supplied `additional` patterns were read above the mode branch — see MAJOR-2 note)
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

# ----- rule: store-link-sane -------------------------------------------------
# store-link-sane (ADR-0018): when `.ssd` is a symlink into a private artifact store, the link must be
# safe. Every failure mode here is a FAIL, never a SKIP, because each one is a silent leak or a
# silent data-loss path:
#
#   tracked        the leak has ALREADY happened — the absolute store path (the user's home directory)
#                  is committed in a repository they are keeping private.
#   not ignored    one `git add -A` from that leak. `.ssd/` cannot ignore a symlink: a trailing-slash
#                  pattern matches directories only, and to git a symlink is a file. A bare `.ssd` is
#                  required, which is why private.gitignore carries one.
#   dangling       SSD is writing into nothing, or into a fresh directory that looks like the store.
#   selective mode git CANNOT track files through a directory symlink, so selective mode's whole
#                  purpose (committing .ssd/features/** to the project) is silently impossible.
#   drift          project.yml records a store location that disagrees with the link. The LINK is
#                  authoritative — project.yml lives inside the store — so a mismatch means one of
#                  them is a lie.
#
# SKIPs cleanly for every project whose .ssd is an ordinary directory, which is the common case.
rule_store_link_sane() {
  local link="$PROJECT_ROOT/.ssd"
  if [[ ! -L "$link" ]]; then
    emit "SKIP" "store-link-sane" "no store link (.ssd is a project-local directory)"
    return
  fi
  is_git_repo || { emit "SKIP" "store-link-sane" "not a git repo"; return; }
  local target problems=""
  target="$(readlink "$link" 2>/dev/null)"
  [[ -n "$target" ]] || { emit "FAIL" "store-link-sane" ".ssd is a symlink but its target is unreadable"; return; }

  git -C "$PROJECT_ROOT" ls-files --error-unmatch .ssd >/dev/null 2>&1 \
    && problems+=" TRACKED(the store path is committed in this repo — remove it: git rm --cached .ssd)"
  git -C "$PROJECT_ROOT" check-ignore -q .ssd 2>/dev/null \
    || problems+=" NOT-IGNORED(add a bare '.ssd' line to .gitignore — '.ssd/' cannot match a symlink)"
  [[ -d "$target" ]] || problems+=" DANGLING(target does not exist: $target)"
  # A link that RESOLVES but whose content is misplaced (e.g. one level too deep after a bad move)
  # reads as healthy until something opens a file. project.yml is the file every consumer needs, so
  # its absence through the link is the cheapest true signal. Checked BEFORE reading the mode, because
  # an unreadable project.yml makes gitignore_mode default to `selective` and would otherwise be
  # reported as a bogus SELECTIVE-MODE failure.
  local mode="unknown"
  if [[ -d "$target" && ! -f "$link/project.yml" ]]; then
    problems+=" MISPLACED-CONTENT(.ssd/project.yml unreadable through the link — inspect $target)"
  else
    mode=$(gitignore_mode)
  fi
  [[ "$mode" == "selective" ]] \
    && problems+=" SELECTIVE-MODE(git cannot track through a symlink; switch to private or blanket)"

  local rroot rdir
  # store_root / store_dir, NOT bare root/dir: yaml_get matches the first `<key>:` at any indentation
  # and project.yml has carried `project.root` (the PROJECT path) since ssd-init v1.0.0. Reading a bare
  # `root` made this DRIFT check unreachable, and a false FAIL once configured. (Round-1 MAJOR-1.)
  rroot="$(yaml_get "$PROJECT_YML" "store_root")"; rdir="$(yaml_get "$PROJECT_YML" "store_dir")"
  if [[ -n "$rroot" && -n "$rdir" && "$target" != "$rroot/$rdir" ]]; then
    problems+=" DRIFT(project.yml says $rroot/$rdir)"
  fi

  if [[ -n "$problems" ]]; then
    emit "FAIL" "store-link-sane" "store link unsafe:${problems}"
  else
    local repo; repo="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || true)"
    emit "PASS" "store-link-sane" "store link ok: $target${repo:+ (repo $repo)}"
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
    # Same reasoning as frontmatter-valid: a skill with no example block is EXEMPT from the version
    # check, and the summary must say so. ssd/SKILL.md — the orchestrator — is one of them
    # (Feynman audit 2026-08-19, C5).
    local count skipped detail
    count=$(echo "$out" | grep -c '^PASS ' || true)
    skipped=$(echo "$out" | grep -c '^SKIP ' || true)
    if [[ "$count" -gt 0 ]]; then
      detail="$count skill example(s) match banner"
      [[ "$skipped" -gt 0 ]] && detail="$detail; $skipped exempt (no example block)"
      emit "PASS" "skill-version-sync" "$detail"
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
  # INDENT-AWARE. The previous version treated EVERY `- ` line as a new workstream boundary, but
  # `rail_deviations`, `adrs_authored` and `touches` are all documented v2 schema LIST fields — so a
  # single realistic workstream fragmented into ~18 records, the record carrying `issue:` ended up with
  # an empty slug, and rule_issue_sync_current's `[[ -n "$slug" ]]` guard skipped it. The rule then
  # reported "issue binding(s) present but gh lookups all failed" having made ZERO gh calls, and could
  # never PASS for any workstream with a nested list — i.e. essentially every real one, since v2.4.0.
  #
  # Fix: the FIRST list item under `active:` defines the workstream indent; only `- ` at that exact
  # indent starts a new workstream, and scalar fields are read only at the field indent (boundary + 2).
  # Deriving the indent instead of hardcoding two spaces keeps this working if the emitter's style ever
  # changes, and reading fields only at their own depth means a same-named key nested deeper (say a
  # future `phase:` inside a list item) cannot overwrite the workstream's own.
  awk '
    function flush() { if (have) printf "%s|%s|%s\n", slug, phase, issue; have=0; slug=""; phase=""; issue="" }
    function scalar(line, key) { sub(".*" key ":[[:space:]]*", "", line); sub(/[[:space:]]*#.*/, "", line); return line }
    /^[^[:space:]#]/ { flush(); section = ($0 ~ /^active:/) ? "active" : "other"; bnd_set=0; next }
    section != "active" { next }
    { match($0, /^[[:space:]]*/); ind = RLENGTH }
    /^[[:space:]]*-[[:space:]]/ {
      if (!bnd_set) { bnd = ind; bnd_set = 1 }
      if (ind != bnd) next                      # a nested list item, not a new workstream
      flush(); have=1
      if ($0 ~ /slug:/) slug = scalar($0, "slug")
      next
    }
    # Fields are accepted at ANY depth INSIDE the current workstream (ind > bnd), not only at bnd+2.
    # A stricter `ind == bnd + 2` was tried and REGRESSED tolerance the previous parser had: a file
    # using non-canonical field indent (fields at bnd+4 under a bnd list item) lost phase and issue,
    # which degrades the rule to "no binding" — honest, but a needless narrowing. The boundary rule
    # (ind == bnd) is what fixes the fragmentation; the field rule does not need to be strict too.
    # Safe against the documented schema: the only keys nested deeper inside a workstream are the
    # rail_deviations item fields (step/reason/ts) plus bare-string list items, none of which collide
    # with slug/phase/issue.
    !have || ind <= bnd { next }
    /^[[:space:]]+slug:/  { slug  = scalar($0, "slug");  next }
    /^[[:space:]]+phase:/ { phase = scalar($0, "phase"); next }
    /^[[:space:]]+issue:/ { issue = scalar($0, "issue"); next }
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

# ----- rule: feynman-clean ---------------------------------------------------
# feynman-clean (ADR-0016): when a `/feynman` epistemic audit report is part of this change set, its
# verdict gates. A `contradicted` or `theater` claim means the project's own account of itself failed
# against evidence the audit produced — shipping on that is shipping on a belief that has already
# been falsified, which is the one thing the gate exists to make loud.
#
# This is a FAILable rule. The override is NOT `/ssd ship --force` — that flag does not exist
# (Feynman audit 2026-09-01, C4); overriding means merging a red gate deliberately and writing the
# reason into the deploy log by hand. Structurally it FAILs exactly like
# `wip-commits`. It is NOT hard enforcement in the ADR-0012 Pillar 5 sense — that pillar rejects
# branch-protection walls and required merge checks, not loud gate signals.
#
# Diff-scoped by design, like `frontmatter-valid` and `no-leaky-state`: it reads feynman reports that
# appear in <base>..HEAD and SKIPs when none do. `/feynman` is deliberately NOT mandatory — running
# it every cycle is precisely the ritualization its own Phase 3 exists to catch — so "no report" is a
# SKIP, never a FAIL. Stated limitation: an audit committed on an earlier branch is not re-read here,
# so a PASS means "no failing audit in this change set", not "this project's beliefs are calibrated".
# ----- rails-walked ----------------------------------------------------------
# Rails invariant 4 ("at least one code review with `gate_pass: true`") had NO mechanical check for
# the library's entire life. PR #41 and PR #43 each shipped a release with ZERO review artifacts while
# every gate check was green and CI passed (Feynman audit 2026-09-01, C3 — "the single most likely
# self-deception: that the gate enforces the rails"). Eleven rules existed and not one of them was a
# rails invariant. This is the first.
#
# TRIGGER: the change set bumps VERSION — i.e. it claims to be a release. Deliberately NOT every
# commit: you commit a brief long before a review exists, and a rule that demanded one would fire on
# every honest work-in-progress push and be disabled within a week.
#
# SCOPE LIMITATION, stated rather than implied: the review may live anywhere under the feature
# directory, including `iterations/<iter>/code-review/`. The rule does NOT verify the review belongs
# to the iteration being shipped — that needs iteration resolution and is not built. A PASS here means
# "this feature has been reviewed at some point," not "this iteration was reviewed."
rule_rails_walked() {
  local files
  files=$(diff_files)
  if [[ -z "$files" ]]; then
    emit "SKIP" "rails-walked" "no diff (vs $BASE)"
    return
  fi
  if ! echo "$files" | grep -qx "VERSION"; then
    emit "SKIP" "rails-walked" "no release in this change set (VERSION unchanged) — invariant 4 is checked at release boundaries"
    return
  fi
  local dirs
  dirs=$(echo "$files" | sed -n 's#^\(\.ssd/features/[^/]*\)/.*#\1#p' | sort -u)
  if [[ -z "$dirs" ]]; then
    emit "SKIP" "rails-walked" "release touches no .ssd/features/ directory"
    return
  fi
  local missing=() checked=0 skipped_design=0 d rev found
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    [[ -d "$PROJECT_ROOT/$d" ]] || continue
    # "Not yet due" = the feature has NEITHER a coder-status NOR a review. Found by this rule's FIRST
    # FIRE IN ANGER, on v2.12.0 — a release that also opened a new workstream at `phase: design`. The
    # rule had conflated "a feature dir appears in this release" with "this feature shipped code", and
    # demanded a code review for a design that had no code to review.
    #
    # BOTH halves of the test are load-bearing, and the second was added after the first was measured:
    #   - coder-status only  ->  v1.25.1's ssd-2.0-greenlight (00-brief + 04-code-review, no
    #     coder-status) flipped PASS -> SKIP. A directory holding a REVIEW plainly had something
    #     reviewed; exempting it traded a false positive for a false negative.
    #   - either artifact present  ->  PR #43's ssd-store (00-brief + 01-architect + coder-status, no
    #     review) still FAILs, which is the case this rule exists for.
    #
    # A feature that ships code with no coder-status at all violates invariant 3 rather than 4, and
    # this rule does not check invariant 3. Stated so the gap is known, not discovered.
    if ! find "$PROJECT_ROOT/$d" -type f \( -name '*coder-status*.md' -o -name '*code-review*.md' -o -name 'round-*.md' \) 2>/dev/null | read -r _; then
      skipped_design=$((skipped_design + 1))
      continue
    fi
    checked=$((checked + 1))
    found=0
    # Only code-reviewer artifacts count. `gate_pass:` also appears in feynman.md frontmatter, and a
    # passing epistemic audit is not a code review — matching it would let the wrong artifact satisfy
    # the invariant.
    while IFS= read -r rev; do
      [[ -z "$rev" ]] && continue
      if grep -q "^gate_pass: true" "$rev" 2>/dev/null; then found=1; break; fi
    done < <(find "$PROJECT_ROOT/$d" -type f \( -name '*code-review*.md' -o -name 'round-*.md' \) 2>/dev/null)
    [[ $found -eq 1 ]] || missing+=("$d")
  done <<< "$dirs"
  if [[ ${#missing[@]} -gt 0 ]]; then
    emit "FAIL" "rails-walked" "release with no code review carrying gate_pass: true for: ${missing[*]} — rails invariant 4"
  elif [[ $checked -eq 0 ]]; then
    emit "SKIP" "rails-walked" "release touches $skipped_design feature dir(s), none with code to review yet"
  else
    local detail="$checked feature dir(s) in this release each carry a code review with gate_pass: true"
    [[ $skipped_design -gt 0 ]] && detail="$detail; $skipped_design design-only dir(s) not yet due"
    emit "PASS" "rails-walked" "$detail"
  fi
}

# Steps recorded in a workstream's rail_deviations. Crude walker, consistent with yaml_get and
# parse_active_workstreams — the gate deliberately carries no PyYAML dependency (ADR-0019 D3).
workstream_deviation_steps() {
  local want="$1" file="$PROJECT_ROOT/.ssd/current.yml"
  [[ -f "$file" ]] || return 0
  awk -v want="$want" '
    /^[[:space:]]*-[[:space:]]+slug:[[:space:]]*/ {
      s = $0; sub(/^[^:]*:[[:space:]]*/, "", s); gsub(/[";'"'"']/, "", s); gsub(/[[:space:]]+$/, "", s)
      inw = (s == want); indev = 0; next
    }
    !inw { next }
    /^[[:space:]]+rail_deviations:/ { indev = 1; next }
    indev && /^[[:space:]]+[a-z_]+:/ && !/step:|kind:|reason:|ts:|rule:/ { indev = 0 }
    indev && /step:[[:space:]]*[0-9]+/ { v = $0; sub(/^.*step:[[:space:]]*/, "", v); sub(/[^0-9].*$/, "", v); print v }
  ' "$file"
}

# ----- deviations-recorded --------------------------------------------------
# ADR-0019. The READER half of rail deviation records, and it ships with the writer on purpose: a
# writer nothing reads decays into the same silence that produced ZERO rail_deviations fields across
# 15 workstreams in a year.
#
# SCOPE, deliberately narrow so it does not duplicate rails-walked: this rule checks rail step 2
# (systems-designer) and step 6 (deploy log). Step 4 (code review) is rails-walked's job and checking it
# here would produce two FAILs for one cause. Steps 1/3 are covered by frontmatter conventions.
#
# Step 2 is IN SCOPE ONLY when `production_runtime` resolves true. Without that read this rule's first
# act on this repository would be to demand deviation records for 13 features that never needed them —
# manufacturing the 14th instance of the finding it exists to prevent (Feynman audit post-v2.11.0, D17).
rule_deviations_recorded() {
  local files
  files=$(diff_files)
  [[ -n "$files" ]] || { emit "SKIP" "deviations-recorded" "no diff (vs $BASE)"; return; }
  if ! echo "$files" | grep -qx "VERSION"; then
    emit "SKIP" "deviations-recorded" "no release in this change set (VERSION unchanged)"
    return
  fi
  local dirs
  dirs=$(echo "$files" | sed -n 's#^\(\.ssd/features/[^/]*\)/.*#\1#p' | sort -u)
  [[ -n "$dirs" ]] || { emit "SKIP" "deviations-recorded" "release touches no .ssd/features/ directory"; return; }

  local runtime; runtime="$(gate_input "production_runtime")"
  [[ -n "$runtime" ]] || runtime="true"   # absent => assume the project has users

  local missing=() checked=0 d slug recorded
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    [[ -d "$PROJECT_ROOT/$d" ]] || continue
    # Only a feature that shipped code can have skipped a step on the way there.
    find "$PROJECT_ROOT/$d" -type f -name '*coder-status*.md' 2>/dev/null | read -r _ || continue
    slug="${d##*/}"
    checked=$((checked + 1))
    recorded="$(workstream_deviation_steps "$slug")"
    if [[ "$runtime" != "false" ]] \
       && ! find "$PROJECT_ROOT/$d" -type f -name '*systems-designer*.md' 2>/dev/null | read -r _ \
       && ! echo "$recorded" | grep -qx "2"; then
      missing+=("$slug:step-2(systems-designer)")
    fi
    if ! find "$PROJECT_ROOT/$d" -type f -name '*deploy*.md' 2>/dev/null | read -r _ \
       && ! echo "$recorded" | grep -qx "6"; then
      missing+=("$slug:step-6(deploy-log)")
    fi
  done <<< "$dirs"

  if [[ ${#missing[@]} -gt 0 ]]; then
    emit "FAIL" "deviations-recorded" "rail step(s) skipped in a release with no rail_deviations record: ${missing[*]} — record one with methodology/deviation.sh"
  elif [[ $checked -eq 0 ]]; then
    emit "SKIP" "deviations-recorded" "release touches no feature dir with code to check"
  else
    emit "PASS" "deviations-recorded" "$checked feature dir(s): every in-scope rail step either walked or recorded (production_runtime=$runtime)"
  fi
}

rule_feynman_clean() {
  is_git_repo || { emit "SKIP" "feynman-clean" "not a git repo"; return; }
  local reports=() f
  local scope; scope=$(artifact_scope)
  if [[ "$scope" == "worktree" ]]; then
    # Private mode (ADR-0017): .ssd/ is gitignored, so a feynman report can never appear in the
    # diff and diff-scoping would make this rule permanently toothless — a project that ran
    # /feynman and got contradicted claims would sail through. Glob the worktree instead.
    # The artifact SET must match the diff-scoped case patterns below exactly — the mode changes
    # where the rule looks, never what counts as a report (review round-1 MINOR-1). So bare
    # `feynman.md` under .ssd/, and `feynman-*.md` ONLY under docs/audits/. Applying `feynman-*.md`
    # under .ssd/ too would make a draft or superseded report (feynman-old.md) FAIL the gate under
    # private mode while being ignored on a selective project.
    # Two `find` calls rather than one: -path/-prune portability across BSD and GNU is not worth the
    # cleverness, and only -name is used here (unlike -newermt — see file_mtime).
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      reports+=("${f#"$PROJECT_ROOT/"}")
    done < <( { find "$PROJECT_ROOT/.ssd/features" "$PROJECT_ROOT/.ssd/milestones" \
                    -name 'feynman.md' 2>/dev/null
                find "$PROJECT_ROOT/docs/audits" -name 'feynman-*.md' 2>/dev/null; } | sort)
    if [[ ${#reports[@]} -eq 0 ]]; then
      emit "SKIP" "feynman-clean" "no feynman report on disk (private mode, worktree scope)"; return
    fi
  else
    local files; files=$(diff_files)
    if [[ -z "$files" ]]; then
      emit "SKIP" "feynman-clean" "no diff ($(diff_scope_label))"; return
    fi
    # `*` in a bash case pattern crosses `/`, so these three patterns also cover reports nested under
    # iterations/ (verified, not assumed).
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      case "$f" in
        .ssd/features/*/feynman.md|.ssd/milestones/*/feynman.md|docs/audits/feynman-*.md)
          [[ -f "$PROJECT_ROOT/$f" ]] && reports+=("$f") ;;
      esac
    done <<< "$files"
    if [[ ${#reports[@]} -eq 0 ]]; then
      emit "SKIP" "feynman-clean" "no feynman report in scope ($(diff_scope_label))"; return
    fi
  fi
  local problems="" checked=0 unreadable=0 contradicted theater posture
  for f in "${reports[@]}"; do
    contradicted=$(frontmatter_get "$PROJECT_ROOT/$f" "contradicted")
    theater=$(frontmatter_get "$PROJECT_ROOT/$f" "theater")
    posture=$(frontmatter_get "$PROJECT_ROOT/$f" "posture")
    # A report whose counters can't be read cannot be judged. Count it and say so (v2.6.0 doctrine:
    # a rule reports what it did NOT check) rather than letting it pass silently.
    if [[ ! "$contradicted" =~ ^[0-9]+$ ]] || [[ ! "$theater" =~ ^[0-9]+$ ]]; then
      unreadable=$((unreadable + 1)); continue
    fi
    checked=$((checked + 1))
    if [[ "$contradicted" -gt 0 ]] || [[ "$theater" -gt 0 ]]; then
      problems+=" $f(${contradicted} contradicted, ${theater} theater${posture:+, posture=$posture})"
    fi
  done
  if [[ -n "$problems" ]]; then
    emit "FAIL" "feynman-clean" "audit verdict stands against this change set:${problems}"
  elif [[ "$checked" -eq 0 ]]; then
    emit "SKIP" "feynman-clean" "${unreadable} feynman report(s) in scope but claim_counts unreadable"
  else
    local detail="${checked} feynman report(s): 0 contradicted, 0 theater"
    [[ "$unreadable" -gt 0 ]] && detail="$detail; ${unreadable} unreadable (not judged)"
    emit "PASS" "feynman-clean" "$detail"
  fi
}

# ----- run all rules ---------------------------------------------------------
should_run wip-commits        && rule_wip_commits
should_run tests-pass         && rule_tests_pass
should_run feature-flag-present && rule_feature_flag_present
should_run adr-delta          && rule_adr_delta
should_run frontmatter-valid  && rule_frontmatter_valid
should_run no-leaky-state     && rule_no_leaky_state
should_run store-link-sane    && rule_store_link_sane
should_run skill-version-sync && rule_skill_version_sync
should_run migration-manifest-current && rule_migration_manifest_current
should_run rails-walked       && rule_rails_walked
should_run deviations-recorded && rule_deviations_recorded
should_run feynman-clean      && rule_feynman_clean
should_run issue-sync-current && rule_issue_sync_current

# ----- emit results ----------------------------------------------------------
# A gate that exits zero because most of its checks never ran is not a passing gate — it is an
# unrun one. Count the statuses so the summary states coverage instead of implying it
# (Feynman audit 2026-08-19, C9).
PASS_N=0; SKIP_N=0
for line in "${RESULTS[@]}"; do
  case "$line" in
    PASS*) PASS_N=$((PASS_N + 1)) ;;
    SKIP*) SKIP_N=$((SKIP_N + 1)) ;;
  esac
done

if [[ $JSON -eq 1 ]]; then
  echo "{"
  echo "  \"base\": \"$BASE\","
  echo "  \"fail_count\": $FAIL_COUNT,"
  echo "  \"pass_count\": $PASS_N,"
  echo "  \"skip_count\": $SKIP_N,"
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
  # Name the skips. A SKIP is a check that did NOT run, not a check that passed.
  printf 'GATE %d pass · %d skip · %d fail — a skip is a check that did not run\n' \
    "$PASS_N" "$SKIP_N" "$FAIL_COUNT"
fi

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
