#!/usr/bin/env bash
# methodology/migrate.sh — SSD convention-migration engine (ADR-0013).
#
# Reads methodology/migrations.yml, selects project-scoped entries newer than the project's recorded
# version, and either REPORTS the drift (default, detect-only) or APPLIES the mechanical migrations
# (`--apply`, iter B). Pure bash + awk (bash 3.2-compatible — no associative arrays), matching
# gate-rules.sh.
#
#   DETECT (default): writes NOTHING. One line per selected migration:
#     PENDING <id>      :: <title> (introduced v<iv>, <adr>)   # mechanical, not yet present
#     SKIP-present <id> :: already adopted                     # mechanical, detect found it
#     GUIDED <id>       :: <title> (<adr>)                     # a practice; adopt by hand
#
#   APPLY (--apply, iter B): for each selected MECHANICAL entry whose `detect` probe reports ABSENT,
#     backs up each mutated file (`<file>.bak`), runs the per-id apply function, then RE-RUNS detect
#     to confirm. Non-destructive merges only (add keys / split / rewrite-with-backup; never delete).
#     On success it bumps `.ssd/project.yml.ssd.version` to the highest fully-adopted version and
#     appends a dated entry to `.ssd/init-log.md`. Statuses:
#       APPLIED <id>      :: <title> (applied; backup written)
#       SKIP-present <id> :: already adopted                   # idempotent — re-running is a no-op
#       GUIDED <id>       :: <title> (<adr>) — outstanding; adopt by hand   # re-surfaced every run (R3)
#       DEFER <id>        :: handled by /ssd-init (run it, then re-run --apply)
#       ERROR <id>        :: apply ran but convention still absent — inspect manually
#
# The recorded-version bump advances only across the *contiguous* run of adopted entries (ascending
# by introduced_in) and STOPS at the first outstanding entry — including any guided one. That keeps
# guided practices re-surfacing (introduced_in still > recorded) until the project adopts them
# (ADR-0013 R3), without iter C's separate guided-adoption tracking. Mechanical entries above an
# outstanding guided entry are still applied; they simply don't advance the recorded version yet.
#
# This is the engine behind `/ssd upgrade` (orchestrator command). The v1→v2 `current.yml` split is
# still owned by `ssd-init` (its prose is not yet extracted here — that behavior-preserving refactor
# is a tracked follow-up); `current-yml-v2` therefore reports DEFER rather than a half-implemented
# split, keeping R1 (corruption) airtight.
#
# Usage:
#   bash methodology/migrate.sh --from <recorded> [--to <version>] [--apply] [--manifest <path>] [--json]
#
# Exit: 0 normally; 2 on bad args; 3 on engine error (manifest unreadable, or an apply ERROR).
#
# License: see /LICENSE.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/migrations.yml"
# Inspect the project where the command runs (the consuming project), not the skills repo.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FROM=""
TO=""
JSON=0
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "migrate: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Default --to to the installed skills' VERSION (script ships at methodology/migrate.sh → ../VERSION).
if [[ -z "$TO" && -f "$SCRIPT_DIR/../VERSION" ]]; then
  TO="$(tr -d '[:space:]' < "$SCRIPT_DIR/../VERSION")"
fi
if [[ -z "$FROM" ]]; then
  echo "migrate: --from <recorded-version> is required (the project's recorded ssd.version)." >&2
  exit 2
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "migrate: manifest not found at $MANIFEST" >&2
  exit 3
fi

# Return 0 if $1 > $2 (semver-ish X.Y.Z, numeric per component). Equal → 1 (not greater).
ver_gt() {
  [[ "$1" == "$2" ]] && return 1
  local top
  top="$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [[ "$top" == "$1" ]]
}

# Per-id idempotency probe (the dispatch table the architect spec calls for). Return 0 if the
# convention is ALREADY present in the project at $ROOT. Unknown id → 1 (treat as absent → PENDING).
detect() {
  case "$1" in
    # Probes require the YAML *key* form (`^[[:space:]]*<key>:`), so a comment ("# key: …", which
    # begins with `#`) or a prose mention does NOT false-positive. (Code-review MINOR-1.)
    current-yml-v2)         grep -qE '^schema_version:[[:space:]]*2([[:space:]]|$)' "$ROOT/.ssd/current.yml" 2>/dev/null ;;
    dev-profile-keys)       grep -qE '^[[:space:]]*developer_profile:' "$ROOT/.ssd/project.yml" 2>/dev/null ;;
    parallel-features-keys) grep -qE '^[[:space:]]*branch_pattern:'    "$ROOT/.ssd/project.yml" 2>/dev/null ;;
    selective-gitignore)    grep -qE '^[[:space:]]*gitignore_mode:'    "$ROOT/.ssd/project.yml" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# ----- apply machinery (iter B) -------------------------------------------------------------------
# Once-per-run backup guards so each mutated file's `.bak` captures the true pre-run original even
# when several apply steps touch the same file. (bash 3.2 — no associative arrays.)
PJ_BACKED=0
GI_BACKED=0
backup_pj() { [[ $PJ_BACKED -eq 1 ]] && return 0; [[ -f "$ROOT/.ssd/project.yml" ]] && cp "$ROOT/.ssd/project.yml" "$ROOT/.ssd/project.yml.bak"; PJ_BACKED=1; }
backup_gi() { [[ $GI_BACKED -eq 1 ]] && return 0; [[ -f "$ROOT/.gitignore" ]] && cp "$ROOT/.gitignore" "$ROOT/.gitignore.bak"; GI_BACKED=1; }

# Insert lines as the first children of the top-level `ssd:` block. Args: file, then payload on stdin.
# The payload is staged through a temp file and read line-by-line inside awk — `awk -v` rejects
# embedded newlines, so a multi-line payload must not be passed as a variable.
insert_under_ssd() {
  local f="$1" pf
  pf="$(mktemp "${TMPDIR:-/tmp}/ssd-ins.XXXXXX")"
  cat > "$pf"
  awk -v pf="$pf" '
    { print }
    /^ssd:/ && !done { while ((getline line < pf) > 0) print line; close(pf); done=1 }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  rm -f "$pf"
}

apply_dev_profile_keys() {        # ADR-0004 — top-level keys; append at EOF (non-destructive).
  local pj="$ROOT/.ssd/project.yml"
  [[ -f "$pj" ]] || return 1
  backup_pj
  cat >> "$pj" <<'EOF'

# Added by /ssd upgrade --apply (dev-profile-keys, ADR-0004).
developer_profile: standard
teaching_mode:
  enabled: true
  invocations_remaining: 5
EOF
}

apply_parallel_features_keys() {  # ADR-0007 — four ssd.* keys nested under ssd:.
  local pj="$ROOT/.ssd/project.yml"
  [[ -f "$pj" ]] || return 1
  grep -qE '^ssd:' "$pj" || return 1
  backup_pj
  insert_under_ssd "$pj" <<'EOF'
  # Added by /ssd upgrade --apply (parallel-features-keys, ADR-0007).
  branch_pattern: "add-{slug}"
  worktree_root: "../"
  worktree_name_pattern: "{repo}-{slug}"
  switch_note_default: prompt
EOF
}

apply_selective_gitignore() {     # ADR-0008 — gitignore_mode key + selective .gitignore pattern.
  local pj="$ROOT/.ssd/project.yml" gi="$ROOT/.gitignore"
  [[ -f "$pj" ]] || return 1
  grep -qE '^ssd:' "$pj" || return 1
  # Order matters (review MINOR-1): rewrite .gitignore FIRST, then set the marker key LAST. detect()
  # confirms on the marker key, so marker-last means a crash mid-apply leaves the project still
  # *detectably* un-migrated (re-run finishes the job) rather than recorded-selective-but-blanket.
  backup_gi
  if [[ -f "$gi" ]]; then
    grep -vxE '[[:space:]]*\.ssd/[[:space:]]*' "$gi" > "$gi.tmp" && mv "$gi.tmp" "$gi"
  fi
  cat >> "$gi" <<'EOF'

# SSD working directory — selective commit (ADR-0008, v1.18.0+). Added by /ssd upgrade --apply.
# Block everything under .ssd/ by default, then allow the durable artifact tree.
.ssd/*
!.ssd/features/
!.ssd/milestones/
!.ssd/features/**/
!.ssd/features/**/00-brief.md
!.ssd/features/**/01-architect.md
!.ssd/features/**/02-systems-designer.md
!.ssd/features/**/03-coder-status.md
!.ssd/features/**/04-code-review*.md
!.ssd/features/**/05-deploy.md
!.ssd/features/**/iterations/**/brief.md
!.ssd/features/**/iterations/**/coder-status.md
!.ssd/features/**/iterations/**/code-review/round-*.md
!.ssd/features/**/iterations/**/deploy.md
.ssd/features/**/iterations/**/deferred.yml
.ssd/features/**/current.yml.bak
!.ssd/milestones/**/
!.ssd/milestones/**/skeptic-before.md
!.ssd/milestones/**/skeptic-after.md
!.ssd/milestones/**/refactor-plan.md
!.ssd/milestones/**/refactor-prs.md
!.ssd/milestones/**/verification.md
.ssd/milestones/**/sha-before
.ssd/milestones/**/metrics-before.yml
.ssd/audits/
EOF
  # Marker key LAST — see ordering note above.
  backup_pj
  insert_under_ssd "$pj" <<'EOF'
  gitignore_mode: selective   # added by /ssd upgrade --apply (ADR-0008)
EOF
}

# Dispatch. Return 0 = apply ran (caller re-detects to confirm); 9 = DEFER (delegated to ssd-init);
# other = ERROR (no apply path / mutation failed).
apply_dispatch() {
  case "$1" in
    dev-profile-keys)       apply_dev_profile_keys ;;
    parallel-features-keys) apply_parallel_features_keys ;;
    selective-gitignore)    apply_selective_gitignore ;;
    current-yml-v2)         return 9 ;;   # v1→v2 split owned by ssd-init (extraction is a follow-up)
    *)                      return 1 ;;   # unknown mechanical id
  esac
}

# Set `.ssd/project.yml.ssd.version`. Scoped to the `ssd:` block (review MINOR-2): only the indented
# `version:` BETWEEN `^ssd:` and the next top-level key is rewritten, so a nested `version:` under an
# earlier block in a consuming project's file can't be hit by mistake. Args: new-version.
bump_recorded_version() {
  local pj="$ROOT/.ssd/project.yml"
  [[ -f "$pj" ]] || return 0
  backup_pj
  awk -v nv="$1" '
    /^ssd:/ { inssd=1 }
    /^[^[:space:]#]/ && !/^ssd:/ { inssd=0 }                       # a new top-level key ends the block
    inssd && !bumped && /^[[:space:]]+version:/ { sub(/version:[[:space:]]*[^[:space:]#]+/, "version: " nv); bumped=1 }
    { print }
  ' "$pj" > "$pj.tmp" && mv "$pj.tmp" "$pj"
}

# Extract one tab-separated record per manifest entry: id, introduced_in, applies_to, kind, adr, title.
# Parser assumes the 2-space-indented list form this repo authors in migrations.yml (same controlled-
# format caveat gate-rules.sh's yaml_get carries).
read_manifest() {
  awk '
    function val(line){ sub(/^[^:]*:[[:space:]]*/, "", line); gsub(/^"|"$/, "", line); return line }
    /^  - id:/             { if (id != "") print id"\t"iv"\t"ap"\t"kd"\t"ad"\t"ti; id=val($0); iv=ap=kd=ad=ti="" ; next }
    /^    introduced_in:/  { iv=val($0); next }
    /^    applies_to:/     { ap=val($0); next }
    /^    kind:/           { kd=val($0); next }
    /^    adr:/            { ad=val($0); next }
    /^    title:/          { ti=val($0); next }
    END                    { if (id != "") print id"\t"iv"\t"ap"\t"kd"\t"ad"\t"ti }
  ' "$MANIFEST"
}

emitted=0
engine_error=0
advancing=1            # while 1, the recorded version may advance across adopted entries
cand_version="$FROM"   # highest contiguous adopted introduced_in (>= FROM)
applied_log=""         # accumulated init-log body
[[ $JSON -eq 1 ]] && printf '{\n  "from": "%s", "to": "%s", "apply": %s,\n  "migrations": [\n' "$FROM" "$TO" "$([[ $APPLY -eq 1 ]] && echo true || echo false)"

while IFS=$'\t' read -r id iv ap kd ad ti; do
  [[ -z "$id" ]] && continue
  [[ "$ap" != "project" ]] && continue            # skip library-scoped entries
  ver_gt "$iv" "$FROM" || continue                # only conventions newer than recorded
  if [[ -n "$TO" ]] && ver_gt "$iv" "$TO"; then continue; fi   # and no newer than target

  satisfied=0
  if [[ "$kd" == "guided" ]]; then
    status="GUIDED"; detail="$ti ($ad)"
    [[ $APPLY -eq 1 ]] && detail="$detail — outstanding; adopt by hand"
  elif detect "$id"; then
    status="SKIP-present"; detail="already adopted"; satisfied=1
  elif [[ $APPLY -eq 1 ]]; then
    apply_dispatch "$id"; rc=$?
    if [[ $rc -eq 9 ]]; then
      status="DEFER"; detail="v1→v2 current.yml split is performed by /ssd-init (run it, then re-run --apply)"
    elif [[ $rc -eq 0 ]] && detect "$id"; then
      status="APPLIED"; detail="$ti (applied; backup written)"; satisfied=1
      applied_log="${applied_log}- APPLIED ${id} (v${iv}, ${ad})"$'\n'
    else
      status="ERROR"; detail="apply ran but convention still absent — inspect manually"; engine_error=1
    fi
  else
    status="PENDING"; detail="$ti (introduced v$iv, $ad)"
  fi

  # Recorded-version advancement: walk the contiguous adopted run; stop at the first outstanding entry.
  if [[ $advancing -eq 1 && $satisfied -eq 1 ]]; then
    cand_version="$iv"
  elif [[ $satisfied -eq 0 ]]; then
    advancing=0
  fi

  if [[ $JSON -eq 1 ]]; then
    [[ $emitted -eq 1 ]] && printf ',\n'
    printf '    {"id": "%s", "status": "%s", "introduced_in": "%s", "kind": "%s", "adr": "%s"}' \
      "$id" "$status" "$iv" "$kd" "$ad"
  else
    printf '%s %s :: %s\n' "$status" "$id" "$detail"
  fi
  emitted=1
done < <(read_manifest)

[[ $JSON -eq 1 ]] && printf '\n  ]\n}\n'

# Post-apply: bump recorded version + append init-log, only if something actually advanced.
if [[ $APPLY -eq 1 ]] && ver_gt "$cand_version" "$FROM"; then
  bump_recorded_version "$cand_version"
  logf="$ROOT/.ssd/init-log.md"
  {
    printf '\n## /ssd upgrade --apply — %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo undated)"
    printf 'Recorded ssd.version %s → %s (target %s).\n\n' "$FROM" "$cand_version" "${TO:-$cand_version}"
    [[ -n "$applied_log" ]] && printf '%s' "$applied_log"
  } >> "$logf"
fi

[[ $engine_error -eq 1 ]] && exit 3
exit 0
