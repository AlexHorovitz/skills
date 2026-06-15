#!/usr/bin/env bash
# methodology/issue-sync.sh — SSD ↔ GitHub issue state mirror (ADR-0014).
#
# One-way mirror: local .ssd/ workstream state is the source of truth and DRIVES GitHub issues
# (create / update / re-label). The orchestrator calls this on phase advance when
# `.ssd/project.yml` integrations.github.issue_tracking is on. The mirror is BEST-EFFORT: any
# failure (gh absent, unauthenticated, offline) exits non-zero and the caller warns + continues —
# a sync failure never blocks SSD work. Local state is unaffected.
#
# The convention (ADR-0014):
#   ADR        → epic issue     label `ssd:epic`,    title `[ADR-NNNN] <title>`
#   workstream → feature issue  label `ssd:feature` + exactly one `ssd:phase/<phase>`, linked to epic
#
# Idempotent by construction: every "ensure-*" subcommand LISTs existing issues and matches an exact
# title prefix locally (robust against GitHub search tokenization of hyphens/brackets) before
# creating. Re-running a phase converges to one issue.
#
# Subcommands (ADR-0014):
#   preflight                              gh present + authed + repo resolvable? exit 3 if not.
#   ensure-epic    <ADR-NNNN> <title>      find-or-create the epic; echo its number.
#   ensure-feature <slug> <phase> <epic#>  find-or-create the feature issue linked to <epic#>; echo number.
#                                          For an iterated workstream, the caller passes the iteration-
#                                          qualified slug (e.g. github-issue-tracking#b) so a new
#                                          iteration gets a new issue instead of re-opening the closed
#                                          prior one (iter-B D3).
#   set-phase      <issue#> <phase>        swap the ssd:phase/* label; refresh the body Phase token.
#   close-feature  <issue#> [--confirm]    close the feature issue on `done`; gated behind auto_close.
#   close-epic     <epic#>  [--confirm]    close the epic iff all ssd:feature children are closed AND
#                                          the close gate (auto_close/--confirm) is satisfied (iter B).
#
# Closing (iter B, ADR-0014 Q2) is the only outward-destructive action and is double-gated:
#   * the auto_close toggle (.ssd/project.yml integrations.github.auto_close, default false) OR an
#     explicit --confirm from the orchestrator (the "user said yes once" signal) must be present;
#   * close-epic additionally refuses while any child ssd:feature issue is still OPEN.
# The "no further iteration planned" half of the epic guard lives in the ORCHESTRATOR (it reads
# .ssd/current.yml); this script only answers "are all GitHub children closed?" (iter-B D1 split).
#
# Matches the style of methodology/gate-rules.sh and methodology/migrate.sh: pure bash (3.2-compatible,
# no associative arrays), set -uo pipefail, exit-code driven, optional --json.
#
# Usage:
#   bash methodology/issue-sync.sh preflight [--json]
#   bash methodology/issue-sync.sh ensure-epic ADR-0014 "GitHub issue state tracking" [--json]
#   bash methodology/issue-sync.sh ensure-feature github-issue-tracking design 27 [--json]
#   bash methodology/issue-sync.sh set-phase 28 code [--json]
#   bash methodology/issue-sync.sh close-feature 28 [--confirm] [--json]
#   bash methodology/issue-sync.sh close-epic 27 [--confirm] [--json]
#
# Exit: 0 ok (incl. skipped/idempotent no-op); 2 bad args; 3 gh unavailable/error (caller no-ops);
#       10 close needs confirmation (auto_close off and no --confirm — caller prompts then re-runs).
#
# License: see /LICENSE.

set -uo pipefail

PHASE_LABEL_COLOR="0e8a16"   # matches the pre-existing ssd:phase/design label
EPIC_LABEL_COLOR="5319e7"
FEATURE_LABEL_COLOR="1d76db"

JSON=0
CONFIRM=0          # set by --confirm; the orchestrator's per-call "user approved this close" signal.
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    -h|--help) sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "issue-sync: unknown flag '$1'" >&2; exit 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_YML="$PROJECT_ROOT/.ssd/project.yml"

# Crude single-scalar YAML reader (consistent with gate-rules.sh yaml_get): first `key:` at any
# indentation, inline ` # comment` stripped, surrounding quotes removed. Used only to read the
# auto_close toggle, which is unique in project.yml. Empty if absent.
yaml_scalar() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || { echo ""; return; }
  awk -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ "^[[:space:]]*"k":" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, "")
      gsub(/^["'\'']|["'\'']$/, "")
      print; exit
    }
  ' "$file"
}

# True iff integrations.github.auto_close is truthy in project.yml.
auto_close_enabled() {
  local v; v="$(yaml_scalar "$PROJECT_YML" auto_close)"
  [[ "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

# Gate a close: proceed iff --confirm was passed OR auto_close is enabled. Emits the needs-confirm
# status and exits 10 otherwise (the orchestrator catches 10, prompts, and re-runs with --confirm).
close_gate_or_exit10() {
  local action="$1" issue="$2" detail="$3"
  if [[ $CONFIRM -eq 1 ]] || auto_close_enabled; then return 0; fi
  emit "$action" "$issue" needs-confirm "$detail"
  exit 10
}

[[ ${#ARGS[@]} -ge 1 ]] || { echo "issue-sync: a subcommand is required (preflight|ensure-epic|ensure-feature|set-phase|close-feature|close-epic)" >&2; exit 2; }
SUBCMD="${ARGS[0]}"

# Emit the status line. STDOUT is reserved as the single MACHINE channel (MAJOR-1 fix, round 2):
#   --json  → the status object goes to stdout (the orchestrator jq's it; `issue` carries the number).
#   text    → the human "OK …" line goes to STDERR, leaving stdout to carry ONLY the returned number
#             (the ensure-* functions `echo "$num"` to stdout in text mode; see below).
# This keeps `num="$(issue-sync.sh ensure-epic …)"` clean and `… --json | jq` valid in both modes.
emit() {
  local action="$1" issue="$2" state="$3" detail="$4"
  if [[ $JSON -eq 1 ]]; then
    printf '{"action":"%s","issue":%s,"state":"%s","detail":"%s"}\n' \
      "$action" "${issue:-null}" "$state" "$detail"
  else
    printf 'OK %s :: issue=%s state=%s %s\n' "$action" "${issue:-–}" "$state" "$detail" >&2
  fi
}

# gh present + authenticated + a repo resolvable from cwd. Any miss → exit 3 (caller no-ops).
do_preflight() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "issue-sync: gh not found on PATH — sync skipped (best-effort)." >&2; exit 3
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "issue-sync: gh not authenticated — sync skipped (best-effort)." >&2; exit 3
  fi
  if ! gh repo view --json nameWithOwner >/dev/null 2>&1; then
    echo "issue-sync: no GitHub repo resolvable from cwd — sync skipped (best-effort)." >&2; exit 3
  fi
  emit preflight "" ok "gh ready"
}

# Ensure a label exists (idempotent; --force updates color without erroring if present).
ensure_label() {
  local name="$1" color="$2"
  gh label create "$name" --color "$color" --force >/dev/null 2>&1 || true
}

# Echo the number of the first OPEN-OR-CLOSED issue carrying <label> whose title begins with <prefix>,
# or nothing. Local exact-prefix match — does not depend on GitHub search tokenization.
#
# Return code (MINOR-1 fix, round 2): 0 = lookup succeeded (stdout = number, or empty if no match);
# 2 = the `gh issue list` call itself FAILED (network/rate-limit). Callers MUST treat rc 2 as
# "unknown", NOT as "absent" — creating on a failed lookup is exactly how duplicates appear (the
# top risk in the architect's risk table). The `--limit` is raised to 1000 so SSD-labeled issues
# (only epics/features carry these labels) don't fall off the list at realistic scale; server-side
# `--search … in:title` confirmation is the iter-B hardening if a project ever exceeds that.
find_issue_by_prefix() {
  local label="$1" prefix="$2" out rc
  out="$(gh issue list --label "$label" --state all --limit 1000 --json number,title \
          --jq ".[] | select(.title | startswith(\"$prefix\")) | .number" 2>/dev/null)"
  rc=$?
  [[ $rc -ne 0 ]] && return 2
  printf '%s\n' "$out" | head -n1
}

do_ensure_epic() {
  local adr="$1" title="$2"
  [[ -n "$adr" && -n "$title" ]] || { echo "ensure-epic: <ADR-NNNN> <title> required" >&2; exit 2; }
  ensure_label "ssd:epic" "$EPIC_LABEL_COLOR"
  local prefix="[$adr]"
  local num rc; num="$(find_issue_by_prefix "ssd:epic" "$prefix")"; rc=$?
  if [[ $rc -eq 2 ]]; then
    echo "ensure-epic: could not list issues (gh error) — skipping to avoid a duplicate." >&2; exit 3
  fi
  if [[ -n "$num" ]]; then
    emit ensure-epic "$num" exists "$adr"
    if [[ $JSON -eq 0 ]]; then echo "$num"; fi
    return 0
  fi
  local body="**ADR:** $adr
_Epic issue — tracks the workstreams implementing $adr (ADR-0014 convention)._

<!-- ssd:epic for $adr -->"
  # REVIEW: `gh issue create --json number` requires gh >= 2.37 (Aug 2023). The `||` fallback parses
  # the trailing issue number from the URL gh prints on older versions. Confirm the minimum gh
  # version SSD wants to support and whether the fallback can be dropped.
  num="$(gh issue create --title "$prefix $title" --label "ssd:epic" --body "$body" \
          --json number --jq .number 2>/dev/null)" \
    || num="$(gh issue create --title "$prefix $title" --label "ssd:epic" --body "$body" 2>/dev/null | grep -oE '[0-9]+$' | tail -n1)"
  [[ -n "$num" ]] || { echo "ensure-epic: create failed for $adr" >&2; exit 3; }
  emit ensure-epic "$num" created "$adr"
  if [[ $JSON -eq 0 ]]; then echo "$num"; fi
}

# The machine-managed body block. Everything outside the ssd:begin/ssd:end markers is human-owned
# and preserved on re-sync.
feature_body_block() {
  local slug="$1" phase="$2" epic="$3"
  printf '<!-- ssd:begin -->\n**Workstream:** %s · **Phase:** %s · **Epic:** #%s\n_Synced from .ssd/current.yml — do not edit inside this block._\n<!-- ssd:end -->\n' \
    "$slug" "$phase" "$epic"
}

do_ensure_feature() {
  local slug="$1" phase="$2" epic="$3"
  [[ -n "$slug" && -n "$phase" && -n "$epic" ]] || { echo "ensure-feature: <slug> <phase> <epic#> required" >&2; exit 2; }
  ensure_label "ssd:feature" "$FEATURE_LABEL_COLOR"
  ensure_label "ssd:phase/$phase" "$PHASE_LABEL_COLOR"
  local prefix="$slug:"
  local num rc; num="$(find_issue_by_prefix "ssd:feature" "$prefix")"; rc=$?
  if [[ $rc -eq 2 ]]; then
    echo "ensure-feature: could not list issues (gh error) — skipping to avoid a duplicate." >&2; exit 3
  fi
  if [[ -n "$num" ]]; then
    emit ensure-feature "$num" exists "epic=#$epic"
    if [[ $JSON -eq 0 ]]; then echo "$num"; fi
    return 0
  fi
  local body; body="$(feature_body_block "$slug" "$phase" "$epic")
**Epic:** #$epic"
  num="$(gh issue create --title "$prefix SSD workstream" \
          --label "ssd:feature" --label "ssd:phase/$phase" --body "$body" \
          --json number --jq .number 2>/dev/null)" \
    || num="$(gh issue create --title "$prefix SSD workstream" \
                --label "ssd:feature" --label "ssd:phase/$phase" --body "$body" 2>/dev/null | grep -oE '[0-9]+$' | tail -n1)"
  [[ -n "$num" ]] || { echo "ensure-feature: create failed for $slug" >&2; exit 3; }
  emit ensure-feature "$num" created "epic=#$epic"
  if [[ $JSON -eq 0 ]]; then echo "$num"; fi
}

do_set_phase() {
  local issue="$1" phase="$2"
  [[ -n "$issue" && -n "$phase" ]] || { echo "set-phase: <issue#> <phase> required" >&2; exit 2; }
  ensure_label "ssd:phase/$phase" "$PHASE_LABEL_COLOR"

  # Remove any ssd:phase/* label that isn't the target (convergent — one phase label at a time).
  local cur
  cur="$(gh issue view "$issue" --json labels --jq '.labels[].name' 2>/dev/null | grep '^ssd:phase/' || true)"
  local l
  for l in $cur; do
    [[ "$l" == "ssd:phase/$phase" ]] && continue
    gh issue edit "$issue" --remove-label "$l" >/dev/null 2>&1 || true
  done
  gh issue edit "$issue" --add-label "ssd:phase/$phase" >/dev/null 2>&1 \
    || { echo "set-phase: failed to label issue #$issue" >&2; exit 3; }

  # Best-effort: refresh the **Phase:** token inside the ssd:begin/ssd:end block if present.
  local body
  body="$(gh issue view "$issue" --json body --jq .body 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q '<!-- ssd:begin -->'; then
    local new
    # Only rewrite the Phase token; leave the rest of the block (and all human text) intact.
    # REVIEW: this sed is coupled to the exact `**Phase:** <token>` body format emitted by
    # feature_body_block(). If the block format changes, this substitution silently no-ops (label
    # still updates correctly). Acceptable for a best-effort mirror, but worth a fixture in iter B.
    new="$(printf '%s' "$body" | sed -E "s#(\\*\\*Phase:\\*\\* )[^ ·]+#\\1$phase#")"
    if [[ "$new" != "$body" ]]; then
      printf '%s' "$new" | gh issue edit "$issue" --body-file - >/dev/null 2>&1 || true
    fi
  fi
  emit set-phase "$issue" updated "ssd:phase/$phase"
}

# Read an issue's state ("OPEN"/"CLOSED"); exit 3 on a gh error (issue unreadable / offline).
issue_state() {
  local issue="$1" st
  st="$(gh issue view "$issue" --json state --jq .state 2>/dev/null)" || return 1
  printf '%s\n' "$st"
}

do_close_feature() {
  local issue="$1"
  [[ -n "$issue" ]] || { echo "close-feature: <issue#> required" >&2; exit 2; }
  local st; st="$(issue_state "$issue")" || { echo "close-feature: cannot read issue #$issue (gh error)" >&2; exit 3; }
  if [[ "$st" == "CLOSED" ]]; then
    emit close-feature "$issue" closed "already closed (idempotent)"
    return 0
  fi
  close_gate_or_exit10 close-feature "$issue" "auto_close off — confirm to close feature #$issue"
  gh issue close "$issue" >/dev/null 2>&1 || { echo "close-feature: close failed for #$issue" >&2; exit 3; }
  emit close-feature "$issue" closed "closed"
}

# Echo the numbers of OPEN ssd:feature issues whose body references "Epic: #<epic>" (word-boundary,
# so #27 never matches #270). Return 2 if the `gh issue list` itself fails (caller treats as unknown,
# NOT as "no open children" — closing an epic on a failed lookup is the dangerous false negative).
# MINOR-2 (iter B): child membership is THIS label query, not the epic task list.
find_open_children() {
  local epic="$1" raw rc
  raw="$(gh issue list --label ssd:feature --state open --limit 1000 \
          --json number,body --jq '.[] | "\(.number)\t\(.body | gsub("\n";" "))"' 2>/dev/null)"
  rc=$?
  [[ $rc -ne 0 ]] && return 2
  printf '%s\n' "$raw" | awk -F'\t' -v e="$epic" '
    $2 ~ ("Epic: #" e "([^0-9]|$)") { print $1 }'
}

do_close_epic() {
  local epic="$1"
  [[ -n "$epic" ]] || { echo "close-epic: <epic#> required" >&2; exit 2; }
  local st; st="$(issue_state "$epic")" || { echo "close-epic: cannot read epic #$epic (gh error)" >&2; exit 3; }
  if [[ "$st" == "CLOSED" ]]; then
    emit close-epic "$epic" closed "already closed (idempotent)"
    return 0
  fi
  local open_children rc
  open_children="$(find_open_children "$epic")"; rc=$?
  [[ $rc -eq 2 ]] && { echo "close-epic: could not list children (gh error) — skipping to avoid a premature close." >&2; exit 3; }
  if [[ -n "$open_children" ]]; then
    local n; n="$(printf '%s\n' "$open_children" | grep -c .)"
    emit close-epic "$epic" skipped "$n open child(ren): $(printf '%s' "$open_children" | tr '\n' ' ')"
    return 0
  fi
  close_gate_or_exit10 close-epic "$epic" "all children closed; auto_close off — confirm to close epic #$epic"
  gh issue close "$epic" >/dev/null 2>&1 || { echo "close-epic: close failed for #$epic" >&2; exit 3; }
  emit close-epic "$epic" closed "closed (all children closed)"
}

case "$SUBCMD" in
  preflight)      do_preflight ;;
  ensure-epic)    do_ensure_epic    "${ARGS[1]:-}" "${ARGS[2]:-}" ;;
  ensure-feature) do_ensure_feature "${ARGS[1]:-}" "${ARGS[2]:-}" "${ARGS[3]:-}" ;;
  set-phase)      do_set_phase      "${ARGS[1]:-}" "${ARGS[2]:-}" ;;
  close-feature)  do_close_feature  "${ARGS[1]:-}" ;;
  close-epic)     do_close_epic     "${ARGS[1]:-}" ;;
  *) echo "issue-sync: unknown subcommand '$SUBCMD'" >&2; exit 2 ;;
esac
