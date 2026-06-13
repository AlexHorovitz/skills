#!/usr/bin/env bash
# methodology/migrate.sh — SSD convention-migration engine (ADR-0013).
#
# ITER A: DETECT-ONLY. Reads methodology/migrations.yml, selects project-scoped entries newer than
# the project's recorded version, and reports each as PENDING / SKIP-present / GUIDED. It writes
# NOTHING. `--apply` is intentionally not implemented here (iter B); it exits 2 with a pointer.
#
# This is the engine behind `/ssd upgrade` (orchestrator command) and — from iter B — the shared
# migration path `ssd-init` also calls. Pure bash + awk (bash 3.2-compatible), matching gate-rules.sh.
#
# Usage:
#   bash methodology/migrate.sh --from <recorded-version> [--to <version>] [--manifest <path>] [--json]
#   bash methodology/migrate.sh --apply ...     # iter A: refuses (exit 2); apply lands in iter B
#
# Output (text): one line per selected migration —
#   PENDING <id> :: <title> (introduced v<introduced_in>, <adr>)     # mechanical, not yet present
#   SKIP-present <id> :: already adopted                              # mechanical, detect found it
#   GUIDED <id> :: <guidance-title> (<adr>)                           # a practice; adopt by hand
# Empty output = project is already current relative to --to.
#
# Exit: 0 normally; 2 on --apply (iter A) or bad args; 3 on engine error (manifest unreadable).
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --apply)
      echo "migrate: --apply is not implemented in iter A (detect-only). Mechanical apply lands in iter B per ADR-0013." >&2
      exit 2 ;;
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
[[ $JSON -eq 1 ]] && printf '{\n  "from": "%s", "to": "%s",\n  "migrations": [\n' "$FROM" "$TO"

while IFS=$'\t' read -r id iv ap kd ad ti; do
  [[ -z "$id" ]] && continue
  [[ "$ap" != "project" ]] && continue            # skip library-scoped entries
  ver_gt "$iv" "$FROM" || continue                # only conventions newer than recorded
  if [[ -n "$TO" ]] && ver_gt "$iv" "$TO"; then continue; fi   # and no newer than target

  if [[ "$kd" == "guided" ]]; then
    status="GUIDED"; detail="$ti ($ad)"
  elif detect "$id"; then
    status="SKIP-present"; detail="already adopted"
  else
    status="PENDING"; detail="$ti (introduced v$iv, $ad)"
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
exit 0
