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
ADOPT=""          # id of a guided migration the user asserts they've adopted (iter C)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --apply) APPLY=1; shift ;;
    --adopt) ADOPT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "migrate: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Default --to to the installed skills' VERSION (script ships at methodology/migrate.sh → ../VERSION).
if [[ -z "$TO" && -f "$SCRIPT_DIR/../VERSION" ]]; then
  TO="$(tr -d '[:space:]' < "$SCRIPT_DIR/../VERSION")"
fi
if [[ -z "$FROM" && -z "$ADOPT" ]]; then
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
  [[ -f "$gi" ]] || return 1
  # Only upgrade a project that already carries the selective block; a project without it is the
  # `selective-gitignore` migration's job, and that one appends the canonical (already-strict) file.
  grep -qF '!.ssd/features/**/01-architect.md' "$gi" || return 1
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
  awk '
    function val(line){ sub(/^[^:]*:[[:space:]]*/, "", line); gsub(/^"|"$/, "", line); return line }
    /^  - id:/             { if (id != "") print id"\t"iv"\t"ap"\t"kd"\t"ad"\t"ti"\t"ob; id=val($0); iv=ap=kd=ad=ti=ob="" ; next }
    /^    introduced_in:/  { iv=val($0); next }
    /^    obsoleted_in:/   { ob=val($0); next }
    /^    applies_to:/     { ap=val($0); next }
    /^    kind:/           { kd=val($0); next }
    /^    adr:/            { ad=val($0); next }
    /^    title:/          { ti=val($0); next }
    END                    { if (id != "") print id"\t"iv"\t"ap"\t"kd"\t"ad"\t"ti"\t"ob }
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
  while IFS=$'\t' read -r id iv ap kd ad ti ob; do
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

emitted=0
engine_error=0
advancing=1            # while 1, the recorded version may advance across adopted entries
cand_version="$FROM"   # highest contiguous adopted introduced_in (>= FROM)
applied_log=""         # accumulated init-log body
[[ $JSON -eq 1 ]] && printf '{\n  "from": "%s", "to": "%s", "apply": %s,\n  "migrations": [\n' "$FROM" "$TO" "$([[ $APPLY -eq 1 ]] && echo true || echo false)"

while IFS=$'\t' read -r id iv ap kd ad ti ob; do
  [[ -z "$id" ]] && continue
  [[ "$ap" != "project" ]] && continue            # skip library-scoped entries
  ver_gt "$iv" "$FROM" || continue                # only conventions newer than recorded
  if [[ -n "$TO" ]] && ver_gt "$iv" "$TO"; then continue; fi   # and no newer than target
  # An obsoleted convention is not offered when upgrading to a target at/after its removal — the
  # convention no longer exists in the destination world, so it must never be (re-)applied. A staged
  # upgrade to a pre-removal --to still sees it. (ssd-2.0-cuts iter C; ADR-0012/0013 obsoleted_in.)
  if [[ -n "$ob" && -n "$TO" ]] && ! ver_gt "$ob" "$TO"; then continue; fi

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
