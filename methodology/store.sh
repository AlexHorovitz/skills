#!/usr/bin/env bash
# methodology/store.sh — the SSD artifact store (ADR-0018).
#
# Makes `<project>/.ssd` an absolute symlink into a per-project subdirectory of one private git repo,
# so the whole methodology record (briefs, specs, reviews, deploy logs, current.yml history) lives in
# version control OUTSIDE the project — which is exactly what `gitignore_mode: private` cannot give.
#
# WHY A SYMLINK. Every SSD consumer resolves PROJECT_ROOT once from the invocation cwd and then reads
# "$PROJECT_ROOT/.ssd/…", which the filesystem resolves through the link. Verified: no tool anywhere
# cd's into .ssd/, so none can accidentally resolve the STORE's git root instead of the project's. Zero
# consumer changes — that is what makes this mechanism cheap rather than invasive.
#
# THE SYMLINK IS THE SINGLE SOURCE OF TRUTH for where the store is. project.yml records it too, but
# project.yml LIVES INSIDE the store, so reading it already required following the link. `status` uses
# readlink; a project.yml that disagrees is drift to report, not a value to trust.
#
# REQUIRES gitignore_mode private (or blanket). NOT selective: git CANNOT track files through a
# directory symlink at all ("fatal: pathspec … is beyond a symbolic link"), so selective mode's entire
# purpose — committing .ssd/features/** into the project — becomes silently impossible. `link` refuses.
#
# Subcommands:
#   status                          report the link, its target, repo state, uncommitted count, drift.
#   init   <root>                   create/prepare the private repo at <root> (idempotent).
#   link   <root> [--dir <name>] [--confirm]
#                                   DRY-RUN BY DEFAULT (exit 10). With --confirm: move an existing
#                                   .ssd/ into <root>/<dir>/ and create the symlink.
#   commit [-m <msg>] [--auto]      commit this project's store subdir. LOCAL ONLY — never pushes.
#   push                            explicit, outward. Never called by commit or by any phase.
#
# Exit codes (matching issue-sync.sh / migrate.sh):
#   0 ok · 2 usage/validation · 3 failure · 10 needs-confirm
#
# License: see /LICENSE.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_YML="$ROOT/.ssd/project.yml"
CONFIRM=0
AUTO=0
MSG=""
DIR_OVERRIDE=""
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=1; shift ;;
    --auto)    AUTO=1; shift ;;
    --dir)
      [[ -n "${2:-}" && "${2:-}" != --* ]] || { echo "store: --dir requires a name" >&2; exit 2; }
      DIR_OVERRIDE="$2"; shift 2 ;;
    -m|--message)
      [[ -n "${2:-}" ]] || { echo "store: -m requires a message" >&2; exit 2; }
      MSG="$2"; shift 2 ;;
    -h|--help) sed -n '1,/^# License/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

[[ ${#ARGS[@]} -ge 1 ]] || { echo "store: a subcommand is required (status|init|link|commit|push)" >&2; exit 2; }
SUBCMD="${ARGS[0]}"

# Crude single-scalar YAML reader, consistent with the other helpers.
yaml_scalar() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || { echo ""; return; }
  awk -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ "^[[:space:]]*"k":" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, "")
      gsub(/^["'\'']|["'\'']$/, ""); print; exit
    }
  ' "$file"
}

project_name() { basename "$ROOT"; }
# NOTE the key names: store_root / store_dir / store_auto_commit, FLAT under `ssd:` and each unique in
# project.yml. NOT a nested `store:` block with `root:`/`dir:` — yaml_scalar matches the first `<key>:`
# at ANY indentation, and project.yml has carried `project.root` (the PROJECT's own path) since
# ssd-init v1.0.0. Reading a bare `root` returned that, which left store-link-sane's DRIFT check
# structurally unreachable and turned it into a false FAIL as soon as the config was filled in.
# `worktree_root` is the existing precedent for this flat naming. (Review round-1 MAJOR-1.)
store_dir_name() { [[ -n "$DIR_OVERRIDE" ]] && { echo "$DIR_OVERRIDE"; return; }; yaml_scalar "$PROJECT_YML" store_dir 2>/dev/null | grep . || project_name; }

# The link target, or empty when .ssd is not a symlink.
link_target() { [[ -L "$ROOT/.ssd" ]] && readlink "$ROOT/.ssd" || echo ""; }

# The git repo enclosing a path, or empty. Supports both supported layouts: the store root being one
# repo with per-project subdirs (the documented default), and a per-project store repo.
enclosing_repo() { [[ -d "$1" ]] && git -C "$1" rev-parse --show-toplevel 2>/dev/null || echo ""; }

gitignore_mode() { yaml_scalar "$PROJECT_YML" gitignore_mode | grep . || echo selective; }

# Ensure a bare `.ssd` line exists in the project's .gitignore. Bare, NOT `.ssd/`: a trailing-slash
# pattern matches directories only, and to git a symlink is a file — so `.ssd/` cannot ignore the link.
ensure_gitignore_bare_ssd() {
  local gi="$ROOT/.gitignore"
  grep -qxF '.ssd' "$gi" 2>/dev/null && return 0
  printf '\n# SSD artifact store (ADR-0018): the .ssd SYMLINK itself. A bare line, because `.ssd/`\n# matches directories only and cannot ignore a symlink.\n.ssd\n' >> "$gi"
}

do_status() {
  local tgt repo mode n drift="none"
  tgt="$(link_target)"
  mode="$(gitignore_mode)"
  if [[ -z "$tgt" ]]; then
    echo "STORE status :: linked=no  mode=$mode  (.ssd is a project-local directory)"
    return 0
  fi
  repo="$(enclosing_repo "$tgt")"
  local recorded_root recorded_dir
  recorded_root="$(yaml_scalar "$PROJECT_YML" store_root)"
  recorded_dir="$(yaml_scalar "$PROJECT_YML" store_dir)"
  if [[ -n "$recorded_root" && -n "$recorded_dir" && "$tgt" != "$recorded_root/$recorded_dir" ]]; then
    drift="project.yml says $recorded_root/$recorded_dir"
  fi
  if [[ ! -d "$tgt" ]]; then
    echo "STORE status :: linked=yes  target=$tgt  *** TARGET MISSING ***  mode=$mode"
    return 0
  fi
  if [[ -z "$repo" ]]; then
    echo "STORE status :: linked=yes  target=$tgt  repo=NONE (not a git repo — history is NOT being kept)  mode=$mode  drift=$drift"
    return 0
  fi
  n="$(git -C "$repo" status --porcelain -- "$tgt" 2>/dev/null | grep -c . || true)"
  echo "STORE status :: linked=yes  target=$tgt  repo=$repo  uncommitted=$n  mode=$mode  drift=$drift"
}

do_init() {
  local root="${ARGS[1]:-}"
  [[ -n "$root" ]] || { echo "store: init <root> required" >&2; exit 2; }
  mkdir -p "$root" || { echo "store: cannot create $root" >&2; exit 3; }
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$root" init -q || { echo "store: git init failed in $root" >&2; exit 3; }
    echo "STORE init :: initialised a git repo at $root"
  else
    echo "STORE init :: $root is already a git repo (left untouched)"
  fi
  # MINIMAL ignores. The store exists to preserve exactly what selective.gitignore excludes —
  # current.yml, project.yml, archive/, audits/ — so SSD's project-side patterns must NEVER be copied
  # here. `*.bak` is deliberately NOT ignored: migrate.sh writes backups before mutating, and in the
  # store their history is evidence.
  if [[ ! -f "$root/.gitignore" ]]; then
    printf '# SSD artifact store (ADR-0018). Deliberately MINIMAL: everything SSD produces is kept here,\n# including current.yml, project.yml, archive/ and *.bak. Do NOT copy SSD project-side ignores in.\n.DS_Store\n*.tmp\n' > "$root/.gitignore"
    echo "STORE init :: wrote a minimal .gitignore"
  fi
  if [[ ! -f "$root/README.md" ]]; then
    printf '# Private SSD artifact store\n\nThe SSD methodology record for one or more projects, kept OUTSIDE those projects (ADR-0018).\nOne subdirectory per project; each is the target of that project s `.ssd` symlink.\n\n**This repository is private by location, not by encryption.** Treat it accordingly.\n' > "$root/README.md"
    echo "STORE init :: wrote README.md"
  fi
  mkdir -p "$root/$(store_dir_name)"
  echo "STORE init :: store dir ready at $root/$(store_dir_name)"
}

do_link() {
  local root="${ARGS[1]:-}" dir dest tgt mode
  [[ -n "$root" ]] || { echo "store: link <root> required" >&2; exit 2; }
  dir="$(store_dir_name)"; dest="$root/$dir"
  mode="$(gitignore_mode)"

  # REQUIRES private or blanket. Git cannot track files through a directory symlink, so selective
  # mode's whole purpose (committing .ssd/features/** into the project) becomes silently impossible.
  if [[ "$mode" == "selective" ]]; then
    echo "store: refusing to link — gitignore_mode is 'selective'." >&2
    echo "       Git cannot track files through a directory symlink, so selective mode would commit" >&2
    echo "       NOTHING under .ssd/ once it is a link. Switch to private (or blanket) first:" >&2
    echo "         /ssd upgrade --apply private-mode --confirm" >&2
    exit 2
  fi

  tgt="$(link_target)"
  if [[ -n "$tgt" ]]; then
    if [[ "$tgt" == "$dest" ]]; then
      echo "STORE link :: already linked to $dest (idempotent; nothing to do)"
      ensure_gitignore_bare_ssd
      return 0
    fi
    echo "store: .ssd is already a symlink to $tgt (wanted $dest). Resolve by hand." >&2
    exit 2
  fi

  # Refuse to clobber: merging two artifact trees is not something a migration should guess at.
  if [[ -d "$ROOT/.ssd" && -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    echo "store: both .ssd/ and $dest are non-empty — refusing to merge two artifact trees." >&2
    exit 2
  fi

  local moving=()
  if [[ -d "$ROOT/.ssd" ]]; then
    while IFS= read -r f; do [[ -n "$f" ]] && moving+=("$f"); done \
      < <(cd "$ROOT/.ssd" && find . -type f 2>/dev/null | sed 's|^\./||' | sort)
  fi

  echo "STORE link :: $ROOT/.ssd  ->  $dest"
  echo
  if [[ ${#moving[@]} -gt 0 ]]; then
    echo "Would MOVE ${#moving[@]} file(s) out of the project into the store:"
    printf '  %s\n' "${moving[@]}"          # complete list — never truncated
    echo
  else
    echo "No existing .ssd/ content — the link will be created empty."
    echo
  fi
  echo "The store keeps the FULL history of these artifacts; the project keeps none of them."
  echo "The symlink itself is never committed to the project (a bare .ssd line is added to .gitignore)."
  echo
  if [[ $CONFIRM -ne 1 ]]; then
    echo "Nothing has been changed. Re-run with --confirm to apply:"
    echo "  /ssd store link $root --confirm"
    return 10
  fi

  mkdir -p "$root" || { echo "store: cannot create $root" >&2; return 3; }
  if [[ -d "$ROOT/.ssd" ]]; then
    mkdir -p "$(dirname "$dest")"
    # `mv src dest` where dest is an EXISTING directory moves src INSIDE it, producing
    # <dest>/.ssd/… instead of <dest>/…. `init` pre-creates <dest>, so this trap is on the happy
    # path. Remove the empty destination first so `mv` creates it with the right shape. A NON-empty
    # destination was already refused above, so rmdir can only succeed or leave us in the refused
    # state — it never destroys content.
    [[ -d "$dest" ]] && rmdir "$dest" 2>/dev/null
    if [[ -e "$dest" ]]; then
      echo "store: destination $dest exists and is not an empty directory — refusing to move." >&2
      return 3
    fi
    if mv "$ROOT/.ssd" "$dest" 2>/dev/null; then
      : # atomic within a filesystem
    else
      # Cross-device fallback: copy, then NEVER delete the original. Losing artifacts is worse than
      # leaving a duplicate the user can remove once they have verified the store.
      mkdir -p "$dest"
      cp -R "$ROOT/.ssd/." "$dest/" || { echo "store: copy to $dest failed; nothing changed." >&2; return 3; }
      echo "store: cross-device move — content COPIED to $dest." >&2
      echo "       The original $ROOT/.ssd was left in place ON PURPOSE. Verify the store, then remove it" >&2
      echo "       by hand and re-run 'store link $root --confirm' to create the symlink." >&2
      return 3
    fi
  else
    mkdir -p "$dest"
  fi

  ln -s "$dest" "$ROOT/.ssd" || { echo "store: symlink creation failed; content is at $dest." >&2; return 3; }
  # Verify through the link before reporting success. Checking that the link RESOLVES is not enough —
  # a misplaced move (see the mv note above) leaves a link to a real directory whose content is one
  # level too deep, which reads as "fine" until something tries to open a file. So verify a file that
  # was actually moved.
  [[ -d "$ROOT/.ssd" ]] || { echo "store: the new .ssd link is not readable — inspect $dest." >&2; return 3; }
  if [[ ${#moving[@]} -gt 0 && ! -f "$ROOT/.ssd/${moving[0]}" ]]; then
    echo "store: content is not reachable through the new link (expected .ssd/${moving[0]})." >&2
    echo "       The files are at $dest — inspect before re-running." >&2
    return 3
  fi
  ensure_gitignore_bare_ssd
  echo "STORE linked :: .ssd -> $dest  (${#moving[@]} file(s) moved; .gitignore updated)"
  echo "Commit the store to capture the history: /ssd store commit"
}

do_commit() {
  local tgt repo msg
  tgt="$(link_target)"
  if [[ -z "$tgt" ]]; then
    [[ $AUTO -eq 1 ]] && return 0
    echo "store: .ssd is not a store link; nothing to commit." >&2; exit 2
  fi
  if [[ ! -d "$tgt" ]]; then
    echo "store: store target $tgt is missing — cannot commit." >&2
    [[ $AUTO -eq 1 ]] && return 0
    exit 3
  fi
  repo="$(enclosing_repo "$tgt")"
  if [[ -z "$repo" ]]; then
    echo "store: $tgt is not inside a git repo — no history is being kept. Run: /ssd store init <root>" >&2
    [[ $AUTO -eq 1 ]] && return 0
    exit 3
  fi
  if [[ -z "$(git -C "$repo" status --porcelain -- "$tgt" 2>/dev/null)" ]]; then
    [[ $AUTO -eq 1 ]] || echo "STORE commit :: nothing to commit"
    return 0
  fi
  msg="${MSG:-ssd: $(basename "$ROOT") artifacts}"
  git -C "$repo" add -- "$tgt" >/dev/null 2>&1 || { echo "store: git add failed in $repo" >&2; [[ $AUTO -eq 1 ]] && return 0; exit 3; }
  # LOCAL ONLY. There is deliberately no push path here: committing is bookkeeping, pushing is an
  # outward action that stays under explicit human control.
  if git -C "$repo" commit -q -m "$msg" >/dev/null 2>&1; then
    echo "STORE commit :: $(git -C "$repo" rev-parse --short HEAD) \"$msg\" (local; not pushed)"
  else
    echo "store: commit failed in $repo" >&2
    [[ $AUTO -eq 1 ]] && return 0
    exit 3
  fi
}

do_push() {
  local tgt repo
  tgt="$(link_target)"; [[ -n "$tgt" ]] || { echo "store: .ssd is not a store link." >&2; exit 2; }
  repo="$(enclosing_repo "$tgt")"; [[ -n "$repo" ]] || { echo "store: $tgt is not inside a git repo." >&2; exit 3; }
  git -C "$repo" remote get-url origin >/dev/null 2>&1 || { echo "store: the store repo has no 'origin' remote; add one first." >&2; exit 2; }
  git -C "$repo" push || { echo "store: push failed" >&2; exit 3; }
  echo "STORE push :: pushed $repo"
}

case "$SUBCMD" in
  status) do_status ;;
  init)   do_init ;;
  link)   do_link; exit $? ;;
  commit) do_commit ;;
  push)   do_push ;;
  *) echo "store: unknown subcommand '$SUBCMD' (status|init|link|commit|push)" >&2; exit 2 ;;
esac
