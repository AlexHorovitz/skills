#!/usr/bin/env bash
# deviation.sh — write a rail deviation record into .ssd/current.yml.
#
# ADR-0019. `ssd/rails.md` has promised since v1.15.0 that "every skipped step appears in
# rail_deviations:". Measured 2026-09-01: ZERO such fields across 15 archived workstreams, and no
# script wrote one. This is the writer. `deviations-recorded` in gate-rules.sh is the reader, and the
# two ship together on purpose — a writer nothing reads decays into the same silence.
#
# Subcommands:
#   record   --slug <s> --step <1-8> --reason "<why>"   a rail step that applied and was not walked
#   override --slug <s> --rule <name> --reason "<why>"  a FAILing gate rule shipped past deliberately
#
# Exit codes (matching store.sh / issue-sync.sh / migrate.sh):
#   0 ok · 2 usage/validation · 3 failure · 10 needs-retry (the file changed under us)
#
# License: see /LICENSE.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CURRENT_YML="$ROOT/.ssd/current.yml"
GATE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-rules.sh"

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

die()   { echo "deviation: $1" >&2; exit "${2:-3}"; }

# The valid rule names are DERIVED from gate-rules.sh, never hardcoded. A hardcoded list goes stale
# the first time a rule is added, and then silently accepts a name that no longer exists.
known_rules() {
  [[ -f "$GATE_SCRIPT" ]] || return 0
  grep -oE '^rule_[a-z_]+\(\)' "$GATE_SCRIPT" | sed 's/^rule_//; s/()$//; s/_/-/g'
}

KIND=""; SLUG=""; STEP=""; RULE=""; REASON=""
case "${1:-}" in
  record)   KIND="skip"     ;;
  override) KIND="override" ;;
  -h|--help|"") usage ;;
  *) die "unknown subcommand '${1}' (expected: record | override)" 2 ;;
esac
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)   SLUG="${2:-}";   shift 2 ;;
    --step)   STEP="${2:-}";   shift 2 ;;
    --rule)   RULE="${2:-}";   shift 2 ;;
    --reason) REASON="${2:-}"; shift 2 ;;
    *) die "unknown option '$1'" 2 ;;
  esac
done

# ----- validation ------------------------------------------------------------
# Every one of these is a `--` argument, i.e. user input. safe_dump (below) makes each value SAFE;
# nothing here makes it TRUE, and a well-formed record naming a step or rule that does not exist would
# satisfy a `deviations-recorded` check it does not describe (systems-designer round 2, MINOR-1).
[[ -n "$SLUG"   ]] || die "--slug is required" 2
[[ -n "$REASON" ]] || die "--reason is required — a record with no reason is the boilerplate this feature exists to replace" 2

if [[ "$KIND" == "skip" ]]; then
  [[ -n "$STEP" ]] || die "--step is required for 'record'" 2
  [[ "$STEP" =~ ^[1-8]$ ]] || die "--step must be an integer 1-8 (the rails have eight steps); got '$STEP'" 2
  [[ -z "$RULE" ]] || die "--rule is not valid for 'record' (did you mean 'override'?)" 2
else
  [[ -n "$RULE" ]] || die "--rule is required for 'override'" 2
  [[ -z "$STEP" ]] || die "--step is not valid for 'override' (did you mean 'record'?)" 2
  if [[ -n "$(known_rules)" ]] && ! known_rules | grep -qx -- "$RULE"; then
    echo "deviation: --rule '$RULE' is not a rule gate-rules.sh emits. Known rules:" >&2
    known_rules | sed 's/^/  /' >&2
    exit 2
  fi
fi

[[ -f "$CURRENT_YML" ]] || die "$CURRENT_YML not found. Refusing to create one — a fresh state file would lose every active workstream." 3
python3 -c "import yaml" >/dev/null 2>&1 || die "PyYAML is required to record a deviation (pip3 install pyyaml). NOT skipping: a deviation that silently fails to record is the exact defect this feature exists to fix." 3

# ----- write -----------------------------------------------------------------
KIND="$KIND" SLUG="$SLUG" STEP="$STEP" RULE="$RULE" REASON="$REASON" CURRENT_YML="$CURRENT_YML" \
python3 - <<'PY'
import fcntl, os, re, shutil, sys, tempfile, datetime, yaml

path   = os.environ["CURRENT_YML"]
kind   = os.environ["KIND"]
slug   = os.environ["SLUG"]
reason = os.environ["REASON"]

# Normalise the reason to ONE line. Two reasons, and only the first is about safety:
#   1. combined with safe_dump below, a reason cannot introduce structure;
#   2. a multi-line scalar is emitted across indented continuation lines, and the gate's reader is a
#      hand-rolled awk walker whose rule is `!have || ind <= bnd { next }` — it would SKIP those lines,
#      leaving a structurally valid record whose reason the consumer cannot read (ADR-0019 D4).
reason = " ".join(reason.split())
if not reason:
    print("deviation: --reason is empty after normalisation", file=sys.stderr); sys.exit(2)

record = {"kind": kind}
if kind == "skip":
    record["step"] = int(os.environ["STEP"])
else:
    record["rule"] = os.environ["RULE"]
record["reason"] = reason
record["ts"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

lock_path = path + ".lock"
# fcntl.flock, NOT flock(1): `command -v flock` is ABSENT on BSD/macOS. The OS releases this on process
# exit, so there is no stale-lock state to detect and no age-based escape hatch to get wrong — strictly
# better than the portable mkdir-lock alternative, which needs both (ADR-0019 D5).
with open(lock_path, "w") as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("deviation: another writer holds the lock; retry", file=sys.stderr); sys.exit(10)

    mtime_before = os.stat(path).st_mtime_ns
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        print(f"deviation: {path} is not parseable YAML: {exc}", file=sys.stderr); sys.exit(3)

    # Resolve on the PAIR (slug, iteration). Two active iterations of one feature are two active[]
    # entries with the SAME slug — matching on slug alone recorded the deviation against whichever
    # came first, and an iteration-qualified `--slug feat#b` matched nothing at all. Same defect the
    # autonomy referee had; fixed in both rather than in one (autorun.sh review round 1, MAJOR-2).
    base, _, iteration = slug.partition("#")
    iteration = iteration or None

    def entry_iteration(entry):
        value = entry.get("iteration")
        return str(value) if value not in (None, "", "null") else None

    def qualified(entry):
        it = entry_iteration(entry)
        return f"{entry.get('slug')}#{it}" if it else str(entry.get("slug"))

    active = (doc or {}).get("active") or []
    known = [qualified(w) for w in active if isinstance(w, dict) and w.get("slug")]
    matches = [w for w in active
               if isinstance(w, dict) and w.get("slug") == base and entry_iteration(w) == iteration]
    if not matches:
        print(f"deviation: no active workstream '{slug}'. Active: {', '.join(known) or '(none)'}",
              file=sys.stderr)
        sys.exit(2)
    # A duplicate (slug, iteration) is state corruption from hand-edited YAML. The spine refuses to
    # guess past duplicate `branch:` values for the same reason; recording a deviation against a
    # coin-flip entry is worse than not recording one (autorun.sh review round 2, MINOR-5).
    if len(matches) > 1:
        print(f"deviation: {len(matches)} active workstreams share (slug, iteration) = '{slug}'. "
              "Delete or re-key the duplicate in .ssd/current.yml, then re-run.", file=sys.stderr)
        sys.exit(3)

    lines = text.splitlines(keepends=True)

    # TEXTUAL insertion, not a document round-trip. safe_dump of the WHOLE file would destroy every
    # comment in it — including current.yml's own "machine-managed; do not edit manually" header and any
    # interior note. So the RECORD is serialised by safe_dump (which is what makes a forged record
    # impossible) and those lines are spliced in. Both properties, neither traded away.
    frag = yaml.safe_dump([record], sort_keys=False, default_flow_style=False, allow_unicode=True)

    def block_end(at, indent):
        for j in range(at + 1, len(lines)):
            ln = lines[j]
            if not ln.strip():
                continue
            ind = len(ln) - len(ln.lstrip())
            if ind <= indent and (ln.lstrip().startswith("- ") or ind == 0):
                return j
        return len(lines)

    def block_iteration(at, stop_at, indent):
        for j in range(at + 1, stop_at):
            m = re.match(rf"^ {{{indent}}}iteration:\s*(.*)$", lines[j])
            if m:
                value = m.group(1).split("#", 1)[0].strip().strip("'\"")
                return value if value not in ("", "null", "~", "None") else None
        return None

    # The splice must disambiguate exactly as the check above does, or the record lands on a
    # sibling iteration's entry.
    start = None
    for i, ln in enumerate(lines):
        m = re.match(r"^(\s*)-\s+slug:\s*(\S+)\s*$", ln)
        if not (m and m.group(2).strip("'\"") == base):
            continue
        indent = len(m.group(1))
        stop_at = block_end(i, indent)
        if block_iteration(i, stop_at, indent + 2) == iteration:
            start, item_indent, end = i, indent, stop_at
            break
    if start is None:
        print(f"deviation: '{slug}' is in active[] but its `- slug:` line could not be located",
              file=sys.stderr); sys.exit(3)

    field_indent = item_indent + 2

    body = "".join(" " * (field_indent + 2) + l if l.strip() else l for l in frag.splitlines(keepends=True))

    dev_at = None
    for j in range(start + 1, end):
        if re.match(rf"^ {{{field_indent}}}rail_deviations:", lines[j]):
            dev_at = j
            break

    if dev_at is None:
        insert_at = end
        while insert_at > start + 1 and not lines[insert_at - 1].strip():
            insert_at -= 1
        lines[insert_at:insert_at] = [" " * field_indent + "rail_deviations:\n", body]
    else:
        k = dev_at + 1
        while k < end and (not lines[k].strip() or (len(lines[k]) - len(lines[k].lstrip())) > field_indent):
            k += 1
        # an empty `rail_deviations:` (or `[]`) becomes a real list
        if re.match(rf"^ {{{field_indent}}}rail_deviations:\s*\[\s*\]\s*$", lines[dev_at]):
            lines[dev_at] = " " * field_indent + "rail_deviations:\n"
        lines[k:k] = [body]

    out = "".join(lines)
    yaml.safe_load(out)          # never write something we cannot read back

    if os.stat(path).st_mtime_ns != mtime_before:
        print("deviation: current.yml changed while we were writing; nothing written, retry",
              file=sys.stderr); sys.exit(10)

    shutil.copy2(path, path + ".bak")     # matches migrate.sh's backup_pj() rather than a new convention
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".current.yml.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(out)
    # mkstemp creates 0600 and os.replace keeps the TEMP file's mode, so without this the state file
    # silently becomes owner-only on its first deviation (measured: 644 -> 600). Copy the original's
    # mode across before replacing.
    shutil.copymode(path, tmp)
    os.replace(tmp, path)                 # atomic; R4

print(f"DEVIATION recorded :: {slug} :: {record.get('step') or record.get('rule')} :: {reason[:60]}")
PY
