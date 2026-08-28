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
#       ERROR <id>        :: apply ran but convention still absent — inspect manually
#
# The recorded-version bump advances only across the *contiguous* run of adopted entries (ascending
# by introduced_in) and STOPS at the first outstanding entry — including any guided one. That keeps
# guided practices re-surfacing (introduced_in still > recorded) until the project adopts them
# (ADR-0013 R3), without iter C's separate guided-adoption tracking. Mechanical entries above an
# outstanding guided entry are still applied; they simply don't advance the recorded version yet.
#
# This is the engine behind `/ssd upgrade` (orchestrator command). As of v1.23.0 it owns ALL four
# mechanical migrations including the v1→v2 `current.yml` split (extracted from ssd-init; ADR-0013).
# The v1→v2 apply is the conservative-safe form — back up + fresh v2 skeleton + original preserved in
# current.notes.yml `legacy_v1_import:` — so R1 (corruption) stays airtight without a field-classifying
# heuristic. ssd-init delegates v1→v2 and the selective .gitignore rewrite to this one engine.
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
ADOPT=""
MANIFEST_SEP=$'\x1f'   # read_manifest record delimiter — see the note in read_manifest's awk
ELECT=""            # id named by --elect; runs one elective migration and exits (never the sweep)
CONFIRM=0           # --confirm; without it, --elect is a pure dry-run that mutates nothing          # id of a guided migration the user asserts they've adopted (iter C)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --apply) APPLY=1; shift ;;
    --adopt) ADOPT="${2:-}"; shift 2 ;;
    --elect)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "--elect requires a migration id (e.g. --elect private-mode)" >&2; exit 2
      fi
      ELECT="$2"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    -h|--help) sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "migrate: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Default --to to the installed skills' VERSION (script ships at methodology/migrate.sh → ../VERSION).
if [[ -z "$TO" && -f "$SCRIPT_DIR/../VERSION" ]]; then
  TO="$(tr -d '[:space:]' < "$SCRIPT_DIR/../VERSION")"
fi
# `--confirm` only qualifies `--elect`. Accepting it silently elsewhere would let a user type
# "--apply --confirm", read it as "yes, really apply", and get no signal that it did nothing
# (round-1 SUGGESTION-1).
if [[ $CONFIRM -eq 1 && -z "$ELECT" ]]; then
  echo "migrate: --confirm only applies to --elect <id>. Did you mean: --elect private-mode --confirm?" >&2
  exit 2
fi
# --adopt and --elect both act on ONE named id and exit; neither walks the version window, so
# neither needs a recorded version.
if [[ -z "$FROM" && -z "$ADOPT" && -z "$ELECT" ]]; then
  echo "migrate: --from <recorded-version> is required (the project's recorded ssd.version)." >&2
  exit 2
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "migrate: manifest not found at $MANIFEST" >&2
  exit 3
fi

# Is guided id $1 recorded as adopted in project.yml.ssd.adopted_guided? (iter C — decouples guided
# re-surfacing from the version gate. detect: null guided entries can't be auto-probed, so adoption
# is an explicit user assertion recorded in project.yml.) Matches the inline-flow `adopted_guided: [a, b]`
# or the block-list form. Conservative substring-in-list match on the id token.
is_adopted() {
  local id="$1" pj="$ROOT/.ssd/project.yml"
  [[ -f "$pj" ]] || return 1
  # Pull the adopted_guided value (inline `[a, b]` or following `- item` lines) and look for the id.
  awk -v id="$id" '
    /^[[:space:]]*adopted_guided:[[:space:]]*\[/ {            # inline list form
      line=$0; gsub(/.*\[|\].*/, "", line); gsub(/[",[:space:]]+/, " ", line)
      n=split(line, a, " "); for (i=1;i<=n;i++) if (a[i]==id) { found=1 }
      next
    }
    /^[[:space:]]*adopted_guided:[[:space:]]*$/ { inblock=1; next }   # block list form
    inblock && /^[[:space:]]*-[[:space:]]*/ { v=$0; gsub(/^[[:space:]]*-[[:space:]]*|["[:space:]]+$/, "", v); if (v==id) found=1; next }
    inblock && /^[[:space:]]*[^[:space:]-]/ { inblock=0 }     # a sibling key ends the block
    END { exit (found ? 0 : 1) }
  ' "$pj"
}

# Return 0 if $1 > $2 (semver-ish X.Y.Z, numeric per component). Equal → 1 (not greater).
ver_gt() {
  [[ "$1" == "$2" ]] && return 1
  local top
  top="$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [[ "$top" == "$1" ]]
}

# Per-id idempotency probe (the dispatch table the architect spec calls for). Return 0 if the
# convention is ALREADY present in the project at $ROOT. Unknown id → 1 (treat as absent → PENDING).
# True iff the project has opted into private mode (ADR-0017). Read from project.yml, the single
# authoritative source; two migration entries below are N/A under it.
is_private_mode() {
  grep -qE '^[[:space:]]*gitignore_mode:[[:space:]]*private([[:space:]]|#|$)' \
    "$ROOT/.ssd/project.yml" 2>/dev/null
}

# NOTE: elective ids are deliberately absent here too — see the note on apply_dispatch. An elective
# entry's detect probe lives with its elect handler (detect_private_mode), not in this table, because
# nothing in the default sweep should be asking whether an elective convention is "present".
detect() {
  case "$1" in
    # Probes require the YAML *key* form (`^[[:space:]]*<key>:`), so a comment ("# key: …", which
    # begins with `#`) or a prose mention does NOT false-positive. (Code-review MINOR-1.)
    current-yml-v2)         grep -qE '^schema_version:[[:space:]]*2([[:space:]]|$)' "$ROOT/.ssd/current.yml" 2>/dev/null ;;
    dev-profile-keys)       grep -qE '^[[:space:]]*developer_profile:' "$ROOT/.ssd/project.yml" 2>/dev/null ;;
    parallel-features-keys) grep -qE '^[[:space:]]*branch_pattern:'    "$ROOT/.ssd/project.yml" 2>/dev/null ;;
    selective-gitignore)    grep -qE '^[[:space:]]*gitignore_mode:'    "$ROOT/.ssd/project.yml" 2>/dev/null ;;
    # ADR-0015 gate readiness. A *commented* placeholder (`# test_command:`) is intentionally NOT a
    # match — it does not define the input, so the convention stays PENDING until a real key exists.
    gate-inputs-present)    grep -qE '^[[:space:]]*test_command:' "$ROOT/.ssd/project.yml" 2>/dev/null \
                            || grep -qE '^[[:space:]]*test_command:' "$ROOT/.ssd/gate.yml" 2>/dev/null ;;
    # Private mode (ADR-0017) has no committed .ssd/gate.yml and no `!` negations at all, so this
    # convention does not exist in that destination world. Report it satisfied rather than letting
    # the project show PERMANENT, unfixable drift — and, worse, letting `--apply` re-add the
    # `!.ssd/gate.yml` negation, which would actively break privacy. Same shape as an obsoleted_in
    # entry, but conditioned on project mode rather than on library version.
    committed-gate-yml)     is_private_mode && return 0
                            [[ -f "$ROOT/.ssd/gate.yml" ]] && grep -qF '!.ssd/gate.yml' "$ROOT/.gitignore" 2>/dev/null ;;
    # The allow-list below `.ssd/*` is inert without a DEEP deny: `.ssd/*` matches depth-1 children
    # only, so once features/ and milestones/ are re-included every file beneath them is committable
    # regardless of the `!` lines. The `.ssd/features/**` deny line is the sentinel for the fixed form.
    # Also N/A under private mode: the deep-deny hardening exists to make SELECTIVE mode's
    # allow-list load-bearing. Private mode has no allow-list to harden (ADR-0017).
    strict-selective-gitignore) is_private_mode && return 0
                            grep -qxF '.ssd/features/**' "$ROOT/.gitignore" 2>/dev/null ;;
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

apply_current_yml_v2() {          # ADR-0002 — v1→v2 split (extraction from ssd-init, v1.23.0).
  # Conservative-safe mechanical form (ADR-0013 extraction decision): the original v1 file may carry
  # arbitrary undocumented keys; a bash heuristic that field-classifies machine-vs-notes is exactly the
  # R1 corruption hazard. Instead: back up the original verbatim (.bak), write a fresh valid v2 skeleton,
  # and preserve the ENTIRE original under current.notes.yml `legacy_v1_import:` for human reconciliation.
  # Zero data loss (original lives in .bak AND in notes); detect (schema_version: 2) passes afterwards.
  # The user re-populates active[] from the preserved import. ssd-init delegates v1→v2 to this same path.
  local cy="$ROOT/.ssd/current.yml" notes="$ROOT/.ssd/current.notes.yml"
  [[ -f "$cy" ]] || return 1
  grep -qE '^schema_version:' "$cy" && return 0      # already has a schema_version line — nothing to do
  [[ -f "$cy.bak" ]] && return 1                      # refuse to clobber an existing backup (ssd-init rule 1)
  cp "$cy" "$cy.bak"
  # Preserve the full original under a legacy_v1_import block in the notes sidecar (create or append).
  {
    printf '\n# legacy_v1_import — original v1 current.yml preserved by /ssd upgrade --apply (ADR-0002/0013).\n'
    printf '# Reconcile active workstreams from here into current.yml.active[], then delete this block.\n'
    printf 'legacy_v1_import: |\n'
    sed 's/^/  /' "$cy.bak"
  } >> "$notes"
  # Fresh, valid v2 skeleton.
  cat > "$cy" <<'EOF'
# .ssd/current.yml — machine-managed SSD workstreams.
# Migrated v1→v2 by /ssd upgrade --apply (ADR-0002). The pre-migration file is at current.yml.bak;
# its full contents are preserved under current.notes.yml `legacy_v1_import:` for reconciliation.
schema_version: 2

active: []

archived: []
EOF
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
  # Guard (review MINOR-1): bail BEFORE any mutation if the canonical pattern file is missing (broken
  # install). Otherwise `cat` would no-op and the marker key would still get set → a silent-incomplete
  # APPLIED (recorded selective, no pattern) — the MAJOR-3/4 class of bug. Fail loud → ERROR instead.
  [[ -f "$SCRIPT_DIR/selective.gitignore" ]] || return 1
  # Idempotency on .gitignore content (dogfood finding MAJOR-3): detect() only probes the project.yml
  # marker key, but a project can already carry the selective pattern with the key absent (e.g. the
  # pattern was hand-added, or written by an older ssd-init that predated the key). Re-appending would
  # duplicate the whole block. Use the same sentinel ssd-init uses (`!.ssd/features/**/01-architect.md`)
  # to skip the .gitignore rewrite when the pattern is already present — then only the marker key is set.
  # Order matters (review MINOR-1): rewrite .gitignore FIRST, then set the marker key LAST. detect()
  # confirms on the marker key, so marker-last means a crash mid-apply leaves the project still
  # *detectably* un-migrated (re-run finishes the job) rather than recorded-selective-but-blanket.
  if ! grep -qF '!.ssd/features/**/01-architect.md' "$gi" 2>/dev/null; then
    backup_gi
    if [[ -f "$gi" ]]; then
      grep -vxE '[[:space:]]*\.ssd/[[:space:]]*' "$gi" > "$gi.tmp" && mv "$gi.tmp" "$gi"
    fi
    # Single source (ADR-0013 extraction, v1.23.0): the pattern lives in methodology/selective.gitignore.
    # ssd-init/SKILL.md Step 5 points to the same file instead of duplicating it (closes review SUGGESTION-1).
    printf '\n' >> "$gi"
    cat "$SCRIPT_DIR/selective.gitignore" >> "$gi"
  fi
  # Marker key LAST — see ordering note above. Comment on its OWN line, NOT inline after the value
  # (dogfood MAJOR-4): gate-rules.sh's no-leaky-state value parser does not strip a trailing `# …`,
  # so an inline comment makes it read the mode as `selective   # …` → "unknown gitignore_mode" →
  # the safety rule silently degrades to SKIP. Every other key in project.yml keeps comments on
  # their own line; match that.
  backup_pj
  insert_under_ssd "$pj" <<'EOF'
  # gitignore_mode added by /ssd upgrade --apply (ADR-0008).
  gitignore_mode: selective
EOF
}

# Create .ssd/gate.yml with its header if absent (ADR-0015). No-op when it already exists.
ensure_gate_yml_header() {
  local gate="$1"
  [[ -f "$gate" ]] && return 0
  cat > "$gate" <<'EOF'
# .ssd/gate.yml — committed gate inputs (ADR-0015). Portable across clones and CI runners.
# Machine-specific state stays in .ssd/project.yml (gitignored). gate-rules.sh reads project.yml
# first (local override), then this file (the committed floor).
EOF
}

apply_gate_inputs_present() {     # ADR-0015 — detect the test command; write it to committed gate.yml.
  local gate="$ROOT/.ssd/gate.yml" pj="$ROOT/.ssd/project.yml"
  # Idempotent: a real (non-comment) test_command in either file means the convention is present.
  grep -qE '^[[:space:]]*test_command:' "$pj" 2>/dev/null && return 0
  grep -qE '^[[:space:]]*test_command:' "$gate" 2>/dev/null && return 0
  # Detect most-specific-first: a project's own declared entry point wins over a language default.
  # The pytest branch requires a real Python marker (pyproject.toml / pytest.ini / setup.py) — NOT a
  # bare tests/ dir, which Rust (integration tests in tests/ beside Cargo.toml), Go, and JS projects
  # also have. Honoring the ADR-0015 "tests/ + a pytest dependency" qualifier; a bare tests/ dir would
  # misdetect a Rust repo as pytest and write a false-red test_command (round-1 review MAJOR-1).
  local cmd=""
  if   [[ -f "$ROOT/Makefile" ]]     && grep -qE '^test:'          "$ROOT/Makefile";     then cmd="make test"
  elif [[ -f "$ROOT/package.json" ]] && grep -qE '"test"[[:space:]]*:' "$ROOT/package.json"; then cmd="npm test"
  elif [[ -f "$ROOT/pyproject.toml" || -f "$ROOT/pytest.ini" || -f "$ROOT/setup.py" ]];    then cmd="pytest"
  elif [[ -f "$ROOT/go.mod" ]];      then cmd="go test ./..."
  elif [[ -f "$ROOT/Cargo.toml" ]];  then cmd="cargo test"
  elif [[ -f "$ROOT/Package.swift" ]]; then cmd="swift test"
  fi
  # Private mode (ADR-0017) has no committed .ssd/gate.yml, so the input goes into project.yml — the
  # same destination `ssd-init` uses under private mode. Writing to gate.yml here instead would leave
  # the two writers disagreeing about where a private project's gate config lives, and would create a
  # gate.yml the ADR says does not exist in this mode.
  if is_private_mode; then
    # Guard matching both sibling appliers (apply_selective_gitignore, apply_committed_gate_yml):
    # insert_under_ssd's awk only inserts after a line matching /^ssd:/, so with no `ssd:` block the
    # insert silently no-ops and this function would still return 0. The caller's
    # `apply_dispatch && detect` then reports a vague ERROR instead of an actionable failure.
    # (Review round-1 MINOR-2.)
    grep -qE '^ssd:' "$pj" || return 1
    if [[ -n "$cmd" ]]; then
      backup_pj
      insert_under_ssd "$pj" <<EOF
  # test_command added by /ssd upgrade --apply (ADR-0015; private mode → project.yml, ADR-0017).
  test_command: $cmd
EOF
    else
      grep -qE '^[[:space:]]*#[[:space:]]*test_command:' "$pj" 2>/dev/null || {
        backup_pj
        insert_under_ssd "$pj" <<'EOF'
  # test_command: <cmd>   # no test framework detected; set once tests exist (ADR-0015)
EOF
      }
      # NOOP, not success: a COMMENTED placeholder deliberately does not satisfy detect() (it does
      # not define the input), so returning 0 here would make the caller report ERROR. See the
      # apply_dispatch return-code contract.
      APPLY_NOTE="no test framework detected; commented placeholder written to .ssd/project.yml (private mode) — set test_command by hand once tests exist"
      return 8
    fi
    return 0
  fi
  ensure_gate_yml_header "$gate"
  if [[ -n "$cmd" ]]; then
    printf 'test_command: %s\n' "$cmd" >> "$gate"
  else
    # No framework detected → commented placeholder (degrades to a gate SKIP, no regression). Guarded
    # so a re-run does not stack duplicate placeholder lines.
    grep -qE '^#[[:space:]]*test_command:' "$gate" 2>/dev/null \
      || printf '# test_command: <cmd>   # no test framework detected; set once tests exist (ADR-0015)\n' >> "$gate"
    # NOOP, not success — same reasoning as the private-mode branch above. Returning 0 made
    # `/ssd upgrade --apply` exit 3 (engine error) on every project without a test framework.
    APPLY_NOTE="no test framework detected; commented placeholder written to .ssd/gate.yml — set test_command by hand once tests exist"
    return 8
  fi
}

apply_committed_gate_yml() {      # ADR-0015 — create gate.yml + the !.ssd/gate.yml gitignore exception.
  local gate="$ROOT/.ssd/gate.yml" pj="$ROOT/.ssd/project.yml" gi="$ROOT/.gitignore"
  # PRECONDITION → NOOP (8), not failure (Q2). detect() requires BOTH gate.yml and the
  # `!.ssd/gate.yml` negation; with no .gitignore there is nothing to add the negation to, so this
  # used to create gate.yml, return success, fail detect, and surface as ERROR + exit 3. Guard FIRST
  # so it does not even create gate.yml — a half-applied convention is worse than an honest NOOP.
  if [[ ! -f "$gi" ]]; then
    APPLY_NOTE="no .gitignore exists, so the !.ssd/gate.yml exception cannot be added — run the selective-gitignore migration first (a full-window --apply does this automatically)"
    return 8
  fi
  ensure_gate_yml_header "$gate"
  # Carry any gate inputs already set (uncommented) in project.yml into gate.yml if not already there.
  local k
  for k in test_command feature_flag_marker; do
    if grep -qE "^[[:space:]]*$k:" "$pj" 2>/dev/null && ! grep -qE "^[[:space:]]*$k:" "$gate" 2>/dev/null; then
      grep -E "^[[:space:]]*$k:" "$pj" | head -1 | sed 's/^[[:space:]]*//' >> "$gate"
    fi
  done
  # Add the gitignore exception if the selective block lacks it. Anchor it right after `.ssd/*`.
  if [[ -f "$gi" ]] && ! grep -qF '!.ssd/gate.yml' "$gi"; then
    backup_gi
    awk '{ print } /^\.ssd\/\*[[:space:]]*$/ && !done { print "!.ssd/gate.yml"; done=1 }' "$gi" > "$gi.tmp" && mv "$gi.tmp" "$gi"
    grep -qF '!.ssd/gate.yml' "$gi" || printf '!.ssd/gate.yml\n' >> "$gi"   # fallback if no .ssd/* anchor
  fi
}

apply_strict_selective_gitignore() {   # Feynman audit C12/C14 — make the allow-list load-bearing.
  local gi="$ROOT/.gitignore"
  # PRECONDITIONS → NOOP (8), not failure (Q2). These two states mean "cannot apply", not "tried and
  # failed", and returning 1 made the engine report `ERROR :: apply ran but convention still absent`
  # and exit 3 — telling a user their upgrade engine is broken when the project simply is not ready.
  # Same misleading-signal class as QUESTION-1; v2.8.0 already added the NOOP vocabulary for it.
  if [[ ! -f "$gi" ]]; then
    APPLY_NOTE="no .gitignore exists, so there is no selective block to harden — run the selective-gitignore migration first (a full-window --apply does this automatically)"
    return 8
  fi
  # Only upgrade a project that already carries the selective block; a project without it is the
  # `selective-gitignore` migration's job, and that one appends the canonical (already-strict) file.
  if ! grep -qF '!.ssd/features/**/01-architect.md' "$gi"; then
    APPLY_NOTE=".gitignore does not carry the selective block — run the selective-gitignore migration first (a full-window --apply does this automatically)"
    return 8
  fi
  grep -qxF '.ssd/features/**' "$gi" && return 0            # idempotent — already strict
  backup_gi
  # Pass A: the deep deny + directory re-includes, immediately after the `!.ssd/milestones/` line so
  # they precede every file negation (last matching pattern wins).
  awk '
    { print }
    /^![[:space:]]*\.ssd\/milestones\/$/ && !done {
      print ".ssd/features/**"
      print ".ssd/milestones/**"
      print "!.ssd/features/**/"
      print "!.ssd/milestones/**/"
      done = 1
    }
  ' "$gi" > "$gi.tmp" && mv "$gi.tmp" "$gi"
  # Pass B: negations for artifact paths skills already declare but the allow-list never listed —
  # they were only ever committable because the list was inert (code-reviewer/SKILL.md § Interface
  # milestone output; feynman/SKILL.md § Interface).
  if ! grep -qF '!.ssd/milestones/**/review-*.md' "$gi"; then
    awk '
      { print }
      /^![[:space:]]*\.ssd\/milestones\/\*\*\/verification\.md$/ && !done {
        print "!.ssd/milestones/**/review-*.md"
        print "!.ssd/milestones/**/feynman.md"
        done = 1
      }
    ' "$gi" > "$gi.tmp" && mv "$gi.tmp" "$gi"
    # Fallback when the block predates verification.md.
    grep -qF '!.ssd/milestones/**/review-*.md' "$gi" \
      || printf '!.ssd/milestones/**/review-*.md\n!.ssd/milestones/**/feynman.md\n' >> "$gi"
  fi
}

# Explanation for a NOOP/DEFER outcome, set by an apply fn and consumed by the report loop. The loop
# CLEARS it at the top of every iteration — a stale note attached to the wrong migration id would be
# worse than no note at all.
APPLY_NOTE=""

# Rewrite an indented `<key>:` line's scalar, in place, SCOPED to a named top-level block.
#
# Deliberately awk+mv rather than `sed -i`: BSD sed requires `-i ''` and GNU sed requires a bare `-i`,
# and that exact divergence produced two defects in iteration A.
#
# The `block` argument is not optional decoration (round-1 MINOR-1). bump_recorded_version carries a
# comment recording that a PRIOR REVIEW required it to be scoped to `ssd:` "so a nested version: under
# an earlier block in a consuming project's file can't be hit by mistake." An unscoped first-match
# helper reintroduces that class — and it matters most for `issue_tracking`, which lives under a LIST
# ITEM inside `integrations:`, where "the first match" is only correct because today's ssd-init template
# happens to give the key to just one entry. Add it to the jira entry, or reorder the list, and an
# unscoped rewrite silently edits the wrong integration.
#
# Args: file, top-level block name (e.g. `ssd` or `integrations`), key, value.
set_yaml_scalar() {
  local f="$1" block="$2" key="$3" val="$4"
  awk -v b="$block" -v k="$key" -v v="$val" '
    $0 ~ "^"b":" { inblock=1; print; next }
    /^[^[:space:]#]/ { inblock=0 }                       # any new top-level key ends the block
    inblock && !done && $0 ~ "^[[:space:]]+"k":" {
      match($0, /^[[:space:]]+/); indent = substr($0, 1, RLENGTH)
      print indent k ": " v; done=1; next
    }
    { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# ----- elective migrations (ADR-0013 addendum, ADR-0017 amendment) -----------
# The four SSD path roots a private project must not track. Kept in one place so the enumerator, the
# verifier, and the docs cannot disagree about scope.
SSD_TRACKED_ROOTS=(".ssd" "docs/decisions" "docs/runbooks" "docs/architecture")

# Every path git currently TRACKS under the SSD roots, **NUL-delimited**. Empty when there are none.
# `git ls-files` lists tracked files only (no --others), which is exactly the set `git rm --cached`
# would act on.
#
# `-z` IS LOAD-BEARING, not hygiene. Without it `git ls-files` C-QUOTES any path containing non-ASCII
# bytes — `"docs/decisions/ADR-0002-h\303\251llo.md"` — and that string then (a) cannot match the ADR
# naming pattern, so a real ADR is misreported as UNCONFIRMED, (b) fails `[[ -f ]]`, so the frontmatter
# probe silently cannot run, and (c) is rejected by `git rm --cached` as a pathspec. Because git
# validates ALL pathspecs before acting, ONE accented filename made the entire retrofit impossible.
# (Round-1 MAJOR-1, reproduced.) Callers must read with `read -r -d ''`.
tracked_ssd_paths() {
  git -C "$ROOT" ls-files -z -- "${SSD_TRACKED_ROOTS[@]}" 2>/dev/null | sort -z
}

# True iff a path can be POSITIVELY identified as SSD-produced. Three signals, in order of strength:
#
#   1. `.ssd/**`                  — unambiguous; SSD owns the whole tree.
#   2. `docs/decisions/ADR-*.md`  — the ADR naming convention (architect/SKILL.md § ADR).
#   3. SSD frontmatter            — a `skill:` key inside the leading `---` block, per
#                                   ssd/chapters/state.md § Structured Output Requirements.
#
# Signal 3 matters for runbooks and architecture docs, whose filenames are feature-named and therefore
# indistinguishable from any other doc. Without it, SSD's OWN runbooks got flagged as "not created by
# SSD" — and a warning that fires on the tool's own output trains the user to ignore it, which
# destroys exactly the signal this interlock exists to give.
#
# Anything not matched is reported as UNCONFIRMED, not as "not SSD's": this function cannot prove
# authorship, and the heading must not claim more than the probe supports.
is_ssd_owned_path() {
  local pth="$1"
  case "$pth" in
    .ssd/*)                   return 0 ;;
    docs/decisions/ADR-*.md)  return 0 ;;
  esac
  # Frontmatter probe: `skill:` within the first few lines of a leading `---` block.
  if [[ -f "$ROOT/$pth" ]] && head -1 "$ROOT/$pth" 2>/dev/null | grep -qx -- '---'; then
    awk 'NR>1 && /^---[[:space:]]*$/ {exit 1} NR>1 && /^skill:[[:space:]]*[^[:space:]]/ {found=1; exit 0} NR>12 {exit 1} END {exit found?0:1}' \
      "$ROOT/$pth" 2>/dev/null && return 0
  fi
  return 1
}

# Probe: is the project already on private mode? Both halves must hold — the recorded mode AND the
# pattern — so a half-applied project is correctly reported as NOT yet private and can be finished.
detect_private_mode() {
  grep -qE '^[[:space:]]*gitignore_mode:[[:space:]]*private([[:space:]]|#|$)' \
    "$ROOT/.ssd/project.yml" 2>/dev/null || return 1
  grep -qxF '# ssd:gitignore-mode=private' "$ROOT/.gitignore" 2>/dev/null || return 1
  return 0
}

# Non-destructive half: write the pattern + record the config. Mirrors apply_selective_gitignore's
# four hard-won ordering rules (bail-before-mutating, pattern first / marker key LAST, comments on
# their own line, sentinel-guarded append).
apply_private_mode_config() {
  local pj="$ROOT/.ssd/project.yml" gi="$ROOT/.gitignore"
  [[ -f "$pj" ]] || return 1
  grep -qE '^ssd:' "$pj" || return 1
  [[ -f "$SCRIPT_DIR/private.gitignore" ]] || return 1   # broken install → fail loud, never partial
  if ! grep -qxF '# ssd:gitignore-mode=private' "$gi" 2>/dev/null; then
    backup_gi
    printf '\n' >> "$gi"
    cat "$SCRIPT_DIR/private.gitignore" >> "$gi"
  fi
  backup_pj
  if grep -qE '^[[:space:]]*gitignore_mode:' "$pj"; then
    set_yaml_scalar "$pj" ssd gitignore_mode private
  else
    insert_under_ssd "$pj" <<'EOF'
  # gitignore_mode set by /ssd upgrade --apply private-mode (ADR-0017).
  gitignore_mode: private
EOF
  fi
  # Both are best-effort: absent keys are left absent rather than invented, because ssd-init owns the
  # template and a key this script did not find is one the project chose not to carry.
  grep -qE '^[[:space:]]*branch_pattern:' "$pj" && set_yaml_scalar "$pj" ssd branch_pattern '"{slug}"'
  # issue_tracking must be off — mirroring workstream state to a public tracker contradicts the mode
  # outright (issue-sync.sh preflight also refuses at runtime, since project.yml is hand-editable).
  grep -qE '^[[:space:]]*issue_tracking:' "$pj" && set_yaml_scalar "$pj" integrations issue_tracking off
  return 0
}

# THE ITEMIZED-CONSENT INTERLOCK (architect spec iter B §4.3).
#
# Dry-run BY DEFAULT: enumerate, print the COMPLETE list, warn about history, exit 10. `--confirm`
# acts. This inverts the engine's normal behavior deliberately — it is the only operation in this
# script that can remove anything from git. ADR-0013 iteration A shipped read-only "so the corruption
# risk of a bad migration cannot fire"; this operation is strictly more dangerous.
#
# Never itemize-and-proceed in one invocation: the list and the action are two separate runs, so the
# user has read the list before the second one exists.
elect_private_mode() {
  local owned=() review=() pth
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "migrate: --elect private-mode needs a git repository (nothing to untrack otherwise)." >&2
    return 2
  fi
  if detect_private_mode && [[ -z "$(tracked_ssd_paths | tr -d '\0')" ]]; then
    echo "ELECTED private-mode :: already private and no SSD path is tracked; nothing to do."
    return 0
  fi
  # One enumeration, held as an array. NUL-delimited so any filename survives (see tracked_ssd_paths).
  local all=()
  while IFS= read -r -d '' pth; do
    [[ -z "$pth" ]] && continue
    all+=("$pth")
    if is_ssd_owned_path "$pth"; then owned+=("$pth"); else review+=("$pth"); fi
  done < <(tracked_ssd_paths)

  echo "ELECT private-mode :: ${#owned[@]} SSD-owned + ${#review[@]} needing review would be untracked"
  echo
  if [[ ${#owned[@]} -gt 0 ]]; then
    echo "SSD-owned artifacts to be untracked (${#owned[@]}):"
    printf '  %s\n' "${owned[@]}"          # COMPLETE list — never truncated, never summarized
    echo
  fi
  if [[ ${#review[@]} -gt 0 ]]; then
    echo "!! UNCONFIRMED as SSD-produced — review before confirming (${#review[@]}):"
    printf '  !! %s\n' "${review[@]}"
    echo "   These live under the SSD docs roots but carry no SSD naming convention or frontmatter,"
    echo "   so this migration cannot tell whether SSD created them or your team did."
    echo "   Untracking a file your team owns is not what this migration is for."
    echo
  fi
  echo "HISTORY IS NOT REWRITTEN. \`git rm --cached\` stops FUTURE tracking only. Anything already"
  echo "committed and pushed stays in this repository's history and on every existing clone. Electing"
  echo "private mode makes future commits private; it does not make this project private retroactively."
  echo "Files are removed from the index, NOT from disk."
  echo
  if [[ $CONFIRM -ne 1 ]]; then
    echo "Nothing has been changed. Re-run with --confirm to apply:"
    echo "  /ssd upgrade --apply private-mode --confirm"
    return 10
  fi

  # PRE-FLIGHT THE DESTRUCTIVE STEP BEFORE MUTATING ANYTHING (round-1 MAJOR-2). The untrack is the only
  # thing here that can fail, and it used to run LAST — after the config writes — so any failure left a
  # half-migrated repo: `gitignore_mode: private` recorded while every artifact stayed tracked, a state
  # neither mode describes. That state is only *conditionally* visible, because the no-leaky-state rule
  # is diff-scoped and SKIPs when there is no diff. `git rm --dry-run` validates every pathspec and
  # touches nothing, so a problem now aborts with the repo untouched — which is what a user expects
  # from a failed migration. Deliberately independent of MAJOR-1's fix: this guards EVERY failure
  # cause, not just the quoting one.
  if [[ ${#all[@]} -gt 0 ]]; then
    git -C "$ROOT" rm --cached --dry-run --quiet -- "${all[@]}" >/dev/null 2>&1 || {
      echo "migrate: cannot untrack the enumerated paths (git rm --dry-run refused them)." >&2
      echo "         NOTHING has been changed. Inspect the paths listed above and retry." >&2
      return 3
    }
  fi
  apply_private_mode_config || {
    echo "migrate: could not write the private-mode configuration (project.yml missing an ssd: block, or methodology/private.gitignore absent)." >&2
    echo "         NOTHING has been changed." >&2
    return 3
  }
  if [[ ${#all[@]} -gt 0 ]]; then
    git -C "$ROOT" rm --cached --quiet -- "${all[@]}" || {
      echo "migrate: git rm --cached failed AFTER the dry-run passed; configuration was written but" >&2
      echo "         paths remain tracked. Inspect manually — this should not happen." >&2
      return 3
    }
  fi
  # Re-verify rather than assume (architect spec §4.3 step 6).
  local remaining=()
  while IFS= read -r -d '' pth; do [[ -n "$pth" ]] && remaining+=("$pth"); done < <(tracked_ssd_paths)
  if [[ ${#remaining[@]} -gt 0 ]]; then
    echo "migrate: paths still tracked after untracking — inspect manually:" >&2
    printf '  %s\n' "${remaining[@]}" >&2
    return 3
  fi
  echo "ELECTED private-mode :: ${#owned[@]} + ${#review[@]} path(s) untracked; files remain on disk."
  echo "Commit the result to make it durable. History is unchanged."
  return 0
}

elect_dispatch() {
  case "$1" in
    private-mode) elect_private_mode ;;
    *)            echo "migrate: no elect handler for '$1'." >&2; return 2 ;;
  esac
}

# Dispatch. Return codes:
#   0     apply ran — caller re-detects to confirm the convention is now present
#   8     NOOP — nothing to apply because a precondition is genuinely absent (e.g. the project has no
#         test framework, so there is no test_command to write). NOT an engine failure: the convention
#         stays PENDING and the recorded version correctly does not advance past it. Set APPLY_NOTE.
#   9     DEFER — the migration is delegated elsewhere (e.g. to ssd-init). Set APPLY_NOTE.
#   other ERROR — no apply path, or the mutation failed.
#
# Codes 8 and 9 exist so "cannot apply" is distinguishable from "tried and failed". Before this,
# every non-zero return collapsed into ERROR + `engine_error=1` + `exit 3`, so a project with no test
# framework made `/ssd upgrade --apply` report a broken engine (round-1 QUESTION-1). Code 9 was
# documented here but handled by NEITHER side — a dead contract that would have silently become an
# ERROR for the first apply fn to use it. Both are now live in the report loop.
# NOTE: elective ids are DELIBERATELY ABSENT from this dispatcher (and from detect()). They are
# reachable only through elect_dispatch. This is the SECOND, independent layer of the guarantee that a
# default sweep can never apply one: even if the `el == "true"` skip in the report loop were removed,
# `--apply private-mode` would find no handler here and could not untrack anything. Verified by
# reversion — removing the skip alone does not make the sweep destructive; removing BOTH does.
# Registering an elective id here would silently defeat that. Don't.
apply_dispatch() {
  case "$1" in
    current-yml-v2)         apply_current_yml_v2 ;;
    dev-profile-keys)       apply_dev_profile_keys ;;
    parallel-features-keys) apply_parallel_features_keys ;;
    selective-gitignore)    apply_selective_gitignore ;;
    gate-inputs-present)    apply_gate_inputs_present ;;
    committed-gate-yml)     apply_committed_gate_yml ;;
    strict-selective-gitignore) apply_strict_selective_gitignore ;;
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

# Extract one tab-separated record per manifest entry: id, introduced_in, applies_to, kind, adr, title,
# obsoleted_in (trailing; empty when the convention is still live). Parser assumes the 2-space-indented
# list form this repo authors in migrations.yml (same controlled-format caveat gate-rules.sh's yaml_get
# carries). NOTE: obsoleted_in is the LAST field — every `read -r ... ob` consumer must list it, or the
# 7th column folds into the 6th (title) var.
read_manifest() {
  awk -v SEP="$MANIFEST_SEP" '
    function val(line){ sub(/^[^:]*:[[:space:]]*/, "", line); gsub(/^"|"$/, "", line); return line }
    # US (\x1f), NOT tab. Tab is IFS *whitespace*, so bash collapses consecutive tabs into a single
    # delimiter and an EMPTY MIDDLE FIELD silently shifts everything after it. The 7-column form
    # survived only because the one optional field (obsoleted_in) was LAST, where a trailing empty
    # field is harmless. Appending `elective` after it made every entry without an obsoleted_in — i.e.
    # all of them — read `elective` into the `ob` slot. A non-whitespace IFS delimiter preserves empty
    # fields (verified empirically, not assumed).
    function rec(){ return id SEP iv SEP ap SEP kd SEP ad SEP ti SEP ob SEP el }
    /^  - id:/             { if (id != "") print rec(); id=val($0); iv=ap=kd=ad=ti=ob=el="" ; next }
    /^    introduced_in:/  { iv=val($0); next }
    /^    obsoleted_in:/   { ob=val($0); next }
    /^    applies_to:/     { ap=val($0); next }
    /^    kind:/           { kd=val($0); next }
    /^    elective:/       { el=val($0); next }
    /^    adr:/            { ad=val($0); next }
    /^    title:/          { ti=val($0); next }
    END                    { if (id != "") print rec() }
  ' "$MANIFEST"
}

# Record a guided practice as adopted in project.yml.ssd.adopted_guided (block-list form), .bak first.
# Returns 2 if adopted_guided pre-exists in INLINE form (review MINOR-1): appending a `- item` line
# under an inline `[...]` value would emit malformed YAML, so refuse and let the caller tell the user
# to add it by hand. The engine only ever writes the block form, so this only fires on a hand-authored
# inline list.
adopt_guided() {
  local id="$1" pj="$ROOT/.ssd/project.yml"
  [[ -f "$pj" ]] || return 1
  if grep -qE '^[[:space:]]*adopted_guided:[[:space:]]*\[' "$pj"; then
    return 2
  fi
  cp "$pj" "$pj.bak"
  if grep -qE '^[[:space:]]*adopted_guided:' "$pj"; then
    awk -v id="$id" '{ print } /^[[:space:]]*adopted_guided:[[:space:]]*$/ && !done { print "    - " id; done=1 }' \
      "$pj" > "$pj.tmp" && mv "$pj.tmp" "$pj"
  else
    insert_under_ssd "$pj" <<EOF
  # Guided practices the project asserts it follows (/ssd upgrade --adopt; ADR-0013 iter C).
  adopted_guided:
    - $id
EOF
  fi
}

# --adopt <id>: record a guided migration as adopted (iter C). Decouples guided re-surfacing from the
# version gate — once adopted, the entry is "satisfied" and the recorded version can advance past it.
if [[ -n "$ADOPT" ]]; then
  guided_ok=0
  while IFS="$MANIFEST_SEP" read -r id iv ap kd ad ti ob el; do
    [[ "$id" == "$ADOPT" && "$kd" == "guided" ]] && guided_ok=1
  done < <(read_manifest)
  if [[ $guided_ok -ne 1 ]]; then
    echo "migrate: --adopt '$ADOPT' is not a guided migration id in the manifest." >&2
    exit 2
  fi
  if is_adopted "$ADOPT"; then
    echo "ADOPTED $ADOPT :: already recorded in project.yml.ssd.adopted_guided"
    exit 0
  fi
  adopt_guided "$ADOPT"; ag_rc=$?
  if [[ $ag_rc -eq 2 ]]; then
    echo "migrate: project.yml.ssd.adopted_guided is an inline list ([...]); add '$ADOPT' to it by hand." >&2
    exit 2
  elif [[ $ag_rc -ne 0 ]]; then
    echo "migrate: failed to record adoption of '$ADOPT' (project.yml missing?)." >&2
    exit 3
  fi
  echo "ADOPTED $ADOPT :: recorded in project.yml.ssd.adopted_guided (backup: project.yml.bak)"
  exit 0
fi

# --elect <id>: run ONE elective migration and exit. Placed here — before the report loop, mirroring
# --adopt — so the elect path and the default sweep can never interleave.
if [[ -n "$ELECT" ]]; then
  el_found=0; el_kind=""; el_elective=""
  while IFS="$MANIFEST_SEP" read -r id iv ap kd ad ti ob el; do
    if [[ "$id" == "$ELECT" ]]; then el_found=1; el_kind="$kd"; el_elective="$el"; fi
  done < <(read_manifest)
  if [[ $el_found -ne 1 ]]; then
    echo "migrate: --elect '$ELECT' is not a migration id in the manifest." >&2; exit 2
  fi
  if [[ "$el_elective" != "true" ]]; then
    echo "migrate: --elect '$ELECT' is not an elective migration. Swept conventions are applied with --apply." >&2; exit 2
  fi
  if [[ "$el_kind" != "mechanical" ]]; then
    echo "migrate: --elect '$ELECT' is kind '$el_kind'; only mechanical entries have an apply path." >&2; exit 2
  fi
  elect_dispatch "$ELECT"; exit $?
fi

emitted=0
engine_error=0
advancing=1            # while 1, the recorded version may advance across adopted entries
cand_version="$FROM"   # highest contiguous adopted introduced_in (>= FROM)
applied_log=""         # accumulated init-log body
[[ $JSON -eq 1 ]] && printf '{\n  "from": "%s", "to": "%s", "apply": %s,\n  "migrations": [\n' "$FROM" "$TO" "$([[ $APPLY -eq 1 ]] && echo true || echo false)"

while IFS="$MANIFEST_SEP" read -r id iv ap kd ad ti ob el; do
  [[ -z "$id" ]] && continue
  [[ "$ap" != "project" ]] && continue            # skip library-scoped entries
  ver_gt "$iv" "$FROM" || continue                # only conventions newer than recorded
  if [[ -n "$TO" ]] && ver_gt "$iv" "$TO"; then continue; fi   # and no newer than target
  # An obsoleted convention is not offered when upgrading to a target at/after its removal — the
  # convention no longer exists in the destination world, so it must never be (re-)applied. A staged
  # upgrade to a pre-removal --to still sees it. (ssd-2.0-cuts iter C; ADR-0012/0013 obsoleted_in.)
  if [[ -n "$ob" && -n "$TO" ]] && ! ver_gt "$ob" "$TO"; then continue; fi
  # An ELECTIVE entry is not drift — it is a choice only some projects should make (ADR-0013
  # addendum). Skipping HERE, before the satisfied/advancing bookkeeping below, makes it inert in
  # every default behavior at once: the report emit, the JSON emit, recorded-version advancement, and
  # the init-log append ALL live further down this same loop. It is reachable only via --elect.
  #
  # The placement is the whole guarantee. Moved below `satisfied=0`, an unapplied elective entry
  # would pin the recorded version for every project that never wanted it.
  if [[ "$el" == "true" ]]; then continue; fi

  satisfied=0
  if [[ "$kd" == "guided" ]]; then
    if is_adopted "$id"; then
      status="GUIDED-ADOPTED"; detail="$ti ($ad) — adopted"; satisfied=1
    else
      status="GUIDED"; detail="$ti ($ad)"
      [[ $APPLY -eq 1 ]] && detail="$detail — outstanding; adopt with: /ssd upgrade --adopt $id"
    fi
  elif detect "$id"; then
    status="SKIP-present"; detail="already adopted"; satisfied=1
  elif [[ $APPLY -eq 1 ]]; then
    APPLY_NOTE=""                                   # never carry a note across ids
    apply_dispatch "$id"; ap_rc=$?
    if [[ $ap_rc -eq 8 ]]; then
      # Precondition absent — the convention cannot be applied here and that is not an error.
      # satisfied stays 0, so the recorded version stops below this entry and the next --apply
      # re-offers it once the precondition exists.
      status="NOOP"; detail="$ti — ${APPLY_NOTE:-precondition absent; nothing to apply}"
    elif [[ $ap_rc -eq 9 ]]; then
      status="DEFER"; detail="$ti — ${APPLY_NOTE:-delegated; run the named tool to complete}"
    elif [[ $ap_rc -eq 0 ]] && detect "$id"; then
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

# If the contiguous adopted run never broke (every selected entry through --to is adopted/applied),
# the project is fully current — record the target version, not just the highest manifest entry. This
# is what lets a fully-caught-up project record zero drift (iter C: matters once guided items can be
# adopted, so the recorded version is no longer permanently pinned below the newest guided entry).
if [[ $advancing -eq 1 && -n "$TO" ]] && ver_gt "$TO" "$cand_version"; then
  cand_version="$TO"
fi

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
