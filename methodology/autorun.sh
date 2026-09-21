#!/usr/bin/env bash
# autorun.sh — the referee for the SSD autonomy ladder.
#
# ADR-0020. The orchestrator still EXECUTES phases (prose, exactly as today); this script decides
# whether it may. Everything the specification calls a ceiling, a refusal, a budget or an ordering
# guarantee lives here as an exit code, because `/ssd ship --force` was documented in four files for
# eleven releases and implemented by nothing: a mechanism described only in prose is a mechanism that
# does not exist.
#
# Subcommands:
#   preflight                                   validate autonomy.mode; print the resolved config
#   status     [--slug <s>]                     report any in-flight or stale auto-run
#   plan       --slug <s> [--until <p>]         print the transition plan; writes NOTHING (--dry-run)
#   start      --slug <s> --mode <run|advance> [--until <p>] [--max-loops N]
#              [--budget-transitions N] [--budget-wall-minutes N]
#   transition --slug <s> --from <p> --to <p> [--reason "<why>"]
#   finish     --slug <s> --stop <STOP-N> --phase-reached <p>
#              [--gate-output <file> | --gate-result <pass|fail|not_run>]
#   clear      --slug <s> [--confirm]           hand-clear a stale lock (FR-8 recovery)
#
# Every subcommand prints ONE machine-readable line first: `state=ok|stop|refused reason=<...>`.
# The orchestrator executes a phase IFF the preceding `transition` printed `state=ok` AND exited 0.
#
# Exit codes (matching store.sh / issue-sync.sh / migrate.sh / deviation.sh):
#   0 ok (including a STOP — the run ended normally) · 2 usage/validation refusal (the FM table)
#   3 failure · 10 needs-retry, or a dry-run that mutated nothing
#
# License: see /LICENSE.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export AR_ROOT="$ROOT"
export AR_CURRENT_YML="$ROOT/.ssd/current.yml"
export AR_PROJECT_YML="$ROOT/.ssd/project.yml"
export AR_GATE_YML="$ROOT/.ssd/gate.yml"

usage() {
  sed -n '11,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

die() { echo "autorun: $1" >&2; exit "${2:-3}"; }

SUBCMD="${1:-}"
case "$SUBCMD" in
  preflight|status|plan|start|transition|finish|clear) shift ;;
  -h|--help|"") usage ;;
  *) die "unknown subcommand '${SUBCMD}' (expected: preflight | status | plan | start | transition | finish | clear)" 2 ;;
esac

SLUG=""; MODE=""; UNTIL=""; FROM=""; TO=""; REASON=""; STOP=""; PHASE_REACHED=""
GATE_RESULT=""; GATE_OUTPUT=""; MAX_LOOPS=""; BUDGET_TRANSITIONS=""; BUDGET_WALL=""; CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)               SLUG="${2:-}";               shift 2 ;;
    --mode)               MODE="${2:-}";               shift 2 ;;
    --until)              UNTIL="${2:-}";              shift 2 ;;
    --from)               FROM="${2:-}";               shift 2 ;;
    --to)                 TO="${2:-}";                 shift 2 ;;
    --reason)             REASON="${2:-}";             shift 2 ;;
    --stop)               STOP="${2:-}";               shift 2 ;;
    --phase-reached)      PHASE_REACHED="${2:-}";      shift 2 ;;
    --gate-result)        GATE_RESULT="${2:-}";        shift 2 ;;
    --gate-output)        GATE_OUTPUT="${2:-}";        shift 2 ;;
    --max-loops)          MAX_LOOPS="${2:-}";          shift 2 ;;
    --budget-transitions) BUDGET_TRANSITIONS="${2:-}"; shift 2 ;;
    --budget-wall-minutes) BUDGET_WALL="${2:-}";       shift 2 ;;
    --confirm)            CONFIRM="1";                 shift   ;;
    *) die "unknown option '$1'" 2 ;;
  esac
done

# ----- validation ------------------------------------------------------------
# The slug is validated HERE and not only by whoever created the workstream. `lowered:` is a shell
# command string the record exists to have pasted into a terminal, and it is built from this value;
# "probably validated two commands away" is not the standard this library applied to `--reason` in
# ADR-0019 (systems-designer round 1, S2).
validate_slug() {
  local base="${1%%#*}" iter="" rest="$1"
  [[ "$rest" == *"#"* ]] && iter="${rest#*#}"
  [[ "$base" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "--slug '$base' must match [a-z0-9][a-z0-9-]*" 2
  if [[ -n "$iter" ]]; then
    [[ "$iter" =~ ^[A-Za-z0-9_-]+$ ]] || die "--slug iteration '$iter' must match [A-Za-z0-9_-]+" 2
  fi
}

case "$SUBCMD" in
  status)   [[ -z "$SLUG" ]] || validate_slug "$SLUG" ;;
  preflight) : ;;
  *) [[ -n "$SLUG" ]] || die "--slug is required for '$SUBCMD'" 2; validate_slug "$SLUG" ;;
esac

if [[ "$SUBCMD" == "start" ]]; then
  case "$MODE" in
    run|advance) ;;
    "") die "--mode is required for 'start' (run | advance)" 2 ;;
    *) die "--mode '$MODE' is not a rung that can execute (expected: run | advance)" 2 ;;
  esac
fi

# FM-4. The ceiling is an exit code, not a setting. Pillar 5 says SSD trusts the DEVELOPER and does
# not lock the door — `/ssd ship <slug>` typed by a human is untouched. What is walled is an agent
# walking through it unattended, which is a different door and has never been open.
if [[ -n "$UNTIL" ]]; then
  case "$UNTIL" in
    design|code|review|gate) ;;
    ship|deploy|rollout-advance|rollout|flag-removal)
      echo "state=refused reason=FM-4"
      echo "autorun: --until '$UNTIL' is above the delegation wall. No autonomy rung reaches ship," >&2
      echo "         deploy, rollout-advance or flag removal — those are not configurable (ADR-0020 D3)." >&2
      echo "         A feature is bounded by two human decisions: the brief before, the ship after." >&2
      echo "         Type '/ssd ship <slug>' yourself when the gate is green." >&2
      exit 2 ;;
    *) die "--until '$UNTIL' is not a rail phase (expected: design | code | review | gate)" 2 ;;
  esac
fi

if [[ "$SUBCMD" == "transition" ]]; then
  [[ -n "$FROM" ]] || die "--from is required for 'transition'" 2
  [[ -n "$TO"   ]] || die "--to is required for 'transition'" 2
fi

if [[ "$SUBCMD" == "finish" ]]; then
  [[ -n "$STOP" ]] || die "--stop is required for 'finish' (STOP-1 .. STOP-7)" 2
  [[ "$STOP" =~ ^STOP-[1-7]$ ]] || die "--stop '$STOP' must be STOP-1 .. STOP-7" 2
  [[ -n "$PHASE_REACHED" ]] || die "--phase-reached is required for 'finish'" 2
  if [[ -n "$GATE_RESULT" ]]; then
    case "$GATE_RESULT" in
      pass|fail|not_run) ;;
      *) die "--gate-result '$GATE_RESULT' must be pass | fail | not_run" 2 ;;
    esac
  fi
  # D11 / S1. A run that reached the ceiling on a red gate and one that reached it on a green gate
  # produced byte-identical frontmatter, both reading STOP-7 = "normal completion". The consumers are
  # codebase-skeptic and feynman, which exist to catch exactly that substitution.
  if [[ "$PHASE_REACHED" == "gate" && -z "$GATE_RESULT" && -z "$GATE_OUTPUT" ]]; then
    echo "state=refused reason=FM-6"
    echo "autorun: a run that reached the 'gate' phase must record the gate's verdict." >&2
    echo "         Pass --gate-output <file> (preferred: the captured gate-rules.sh output) or" >&2
    echo "         --gate-result <pass|fail|not_run>." >&2
    exit 2
  fi
fi

# ----- prerequisites ---------------------------------------------------------
if [[ "$SUBCMD" != "preflight" ]]; then
  [[ -f "$AR_CURRENT_YML" ]] || die "$AR_CURRENT_YML not found. Refusing to create one — a fresh state file would lose every active workstream." 3
fi
python3 -c "import yaml" >/dev/null 2>&1 || die "PyYAML is required (pip3 install pyyaml). NOT skipping: an auto-run that cannot record is an auto-run that must not start." 3

export AR_SUBCMD="$SUBCMD" AR_SLUG="$SLUG" AR_MODE="$MODE" AR_UNTIL="$UNTIL" AR_FROM="$FROM" \
       AR_TO="$TO" AR_REASON="$REASON" AR_STOP="$STOP" AR_PHASE_REACHED="$PHASE_REACHED" \
       AR_GATE_RESULT="$GATE_RESULT" AR_GATE_OUTPUT="$GATE_OUTPUT" AR_MAX_LOOPS="$MAX_LOOPS" \
       AR_BUDGET_TRANSITIONS="$BUDGET_TRANSITIONS" AR_BUDGET_WALL="$BUDGET_WALL" AR_CONFIRM="$CONFIRM"

python3 - <<'PY'
import datetime, fcntl, os, re, shutil, sys, tempfile
import yaml

ROOT        = os.environ["AR_ROOT"]
CURRENT_YML = os.environ["AR_CURRENT_YML"]
PROJECT_YML = os.environ["AR_PROJECT_YML"]
SUB         = os.environ["AR_SUBCMD"]
SLUG_ARG    = os.environ["AR_SLUG"]

def env(name, default=""):
    return os.environ.get("AR_" + name, default)

def out(line):
    # Flushed: the machine-readable line is block-buffered when stdout is a pipe, and would
    # otherwise appear AFTER the human detail written to stderr.
    print(line, flush=True)

def refuse(reason, message, code=2):
    out(f"state=refused reason={reason}")
    print("autorun: " + message, file=sys.stderr)
    sys.exit(code)

def fail(message, code=3):
    print("autorun: " + message, file=sys.stderr)
    sys.exit(code)

def now():
    return datetime.datetime.now(datetime.timezone.utc)

def stamp(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def parse_stamp(text):
    try:
        return datetime.datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc)
    except (TypeError, ValueError):
        return None

# ----- the rails, as a table rather than as a promise -------------------------
# NG5 says an auto-run writes ZERO rail deviations. The strongest available form of that is not a
# rule the agent follows: it is a writer that cannot EXPRESS an off-rails transition. Because the act
# is conditional on a successful log, an edge refused here is a phase that does not run.
RAILS_NEXT = {
    "brief":  {"design"},
    "design": {"code"},
    "code":   {"review"},
    "review": {"gate", "code"},   # `code` is the gate-failed loop-back (rails step 5)
    "gate":   set(),              # the ceiling: no edge leaves it
}
PHASE_ORDER = ["brief", "design", "code", "review", "gate"]
DEFAULT_BUDGETS = {"review_loops": 3, "transitions": 12, "wall_minutes": 30}

def phase_index(phase):
    return PHASE_ORDER.index(phase) if phase in PHASE_ORDER else -1

def split_slug(raw):
    base, _, iteration = raw.partition("#")
    return base, (iteration or None)

BASE_SLUG, ITERATION = split_slug(SLUG_ARG) if SLUG_ARG else (None, None)

def lowered_command(to_phase):
    """The copyable command for a transition. CONSTRUCTED from validated parts, never passed in:
    a field whose purpose is to be pasted into a shell is not assembled from free text (D12)."""
    return f"/ssd {to_phase} {SLUG_ARG}"

def normalise_reason(text):
    """One line. Two reasons, and only the first is about safety: safe_dump makes the value unable to
    introduce structure, and a multi-line scalar is emitted as indented continuation lines that the
    gate's hand-rolled awk walker SKIPS — leaving a structurally valid record whose reason no
    consumer can read (ADR-0019 D4)."""
    return " ".join((text or "").split())

# ----- config ----------------------------------------------------------------
def read_yaml(path):
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return yaml.safe_load(fh.read()) or {}
    except yaml.YAMLError as exc:
        fail(f"{path} is not parseable YAML: {exc}")

def autonomy_config():
    doc = read_yaml(PROJECT_YML)
    block = ((doc.get("ssd") or {}).get("autonomy")) or {}
    if not isinstance(block, dict):
        refuse("FM-5", f"ssd.autonomy in {PROJECT_YML} is not a mapping")
    mode = block.get("mode", "propose")
    # FM-5. Exactly three literals, and a typo is NOT a silent default — the ADR-0017 gitignore_mode
    # precedent, where a misspelled mode disabled leak detection without saying so.
    if mode not in ("propose", "advance", "run"):
        refuse("FM-5",
               f"unrecognized autonomy.mode '{mode}'. Exactly three literals are recognized: "
               "propose | advance | run. Refusing rather than defaulting — a typo must not "
               "masquerade as a deliberate setting.")
    budgets = dict(DEFAULT_BUDGETS)
    for key, cfg in (("review_loops", "max_review_loops"),
                     ("transitions", "budget_transitions"),
                     ("wall_minutes", "budget_wall_minutes")):
        if cfg in block:
            try:
                budgets[key] = int(block[cfg])
            except (TypeError, ValueError):
                refuse("FM-5", f"autonomy.{cfg} must be an integer; got {block[cfg]!r}")
    announce = block.get("announce", "full")
    if announce not in ("full", "compact"):
        refuse("FM-5", f"autonomy.announce must be full | compact; got {announce!r}")
    return mode, budgets, announce

def effective_budgets(budgets):
    for key, name in (("review_loops", "MAX_LOOPS"),
                      ("transitions", "BUDGET_TRANSITIONS"),
                      ("wall_minutes", "BUDGET_WALL")):
        raw = env(name)
        if raw:
            try:
                budgets[key] = int(raw)
            except ValueError:
                refuse("FM-5", f"--{name.lower().replace('_', '-')} must be an integer; got {raw!r}")
    return budgets

# ----- current.yml -----------------------------------------------------------
def load_current():
    with open(CURRENT_YML, "r", encoding="utf-8") as fh:
        text = fh.read()
    try:
        doc = yaml.safe_load(text) or {}
    except yaml.YAMLError as exc:
        fail(f"{CURRENT_YML} is not parseable YAML: {exc}. Refusing to guess.")
    # PARSEABLE is not the same as WELL-SHAPED. A list, a string or a number at the document root
    # parses fine and then raises AttributeError on the first `.get` — a traceback and exit 1, which
    # is not in this script's documented exit family (review round 1, MINOR-1).
    if not isinstance(doc, dict):
        fail(f"{CURRENT_YML} parses but is a {type(doc).__name__}, not a mapping. "
             "Expected a schema_version/active/archived document. Refusing to guess.")
    active = doc.get("active")
    if active is not None and not isinstance(active, list):
        fail(f"{CURRENT_YML} has an `active:` that is a {type(active).__name__}, not a list.")
    return text, doc

def entry_iteration(entry):
    """`iteration:` normalised. Absent, null and empty all mean the flat workstream."""
    value = entry.get("iteration")
    return str(value) if value not in (None, "", "null") else None

def qualified(entry):
    """`feat#b` for an iterated workstream, `feat` for a flat one. What the user typed, and what a
    refusal has to print back for them to act on it."""
    iteration = entry_iteration(entry)
    return f"{entry.get('slug')}#{iteration}" if iteration else str(entry.get("slug"))

def find_workstream(doc, slug, iteration=None):
    """Resolve on the PAIR. Two active iterations of one feature are two active[] entries with the
    SAME slug and different `iteration:` — `/ssd feature new` treats (slug, iteration) as the key for
    exactly that reason. Matching on slug alone returned the first entry, which let `start` read a
    sibling iteration's phase and budget and so walk straight past FM-3 and the over-budget refusal
    (review round 1, MAJOR-2)."""
    matches = [e for e in ((doc or {}).get("active") or [])
               if isinstance(e, dict) and e.get("slug") == slug and entry_iteration(e) == iteration]
    # Making the key a PAIR did not make the pair UNIQUE (review round 2, MINOR-5). `/ssd feature new`
    # rejects creating a duplicate, so this can only come from hand-edited YAML — which is exactly the
    # provenance the spine describes for duplicate `branch:` values, where the orchestrator "emits an
    # error and refuses to guess rather than picking a first match". Same corruption, same answer.
    if len(matches) > 1:
        label = f"{slug}#{iteration}" if iteration else slug
        fail(f"{len(matches)} active workstreams share (slug, iteration) = '{label}' in "
             f"{CURRENT_YML}. That is a state corruption from manual editing, not something to "
             "guess past: delete or re-key the duplicate, then re-run.")
    return matches[0] if matches else None

def active_slugs(doc):
    return [qualified(e) for e in ((doc or {}).get("active") or [])
            if isinstance(e, dict) and e.get("slug")]

def _block_end(lines, start, item_indent):
    for j in range(start + 1, len(lines)):
        line = lines[j]
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= item_indent and (line.lstrip().startswith("- ") or indent == 0):
            return j
    return len(lines)

def _block_iteration(lines, start, end, field_indent):
    for j in range(start + 1, end):
        m = re.match(rf"^ {{{field_indent}}}iteration:\s*(.*)$", lines[j])
        if m:
            value = m.group(1).split("#", 1)[0].strip().strip("'\"")
            return value if value not in ("", "null", "~", "None") else None
    return None

def item_bounds(lines, slug, iteration=None):
    """Locate the `- slug: <slug>` block for THIS (slug, iteration) and its half-open line range.

    The splice has to disambiguate exactly as find_workstream does, or the lock lands on one
    iteration's entry while the record is written under another's directory (review round 1,
    MAJOR-2)."""
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*)-\s+slug:\s*(\S+)\s*$", line)
        if not (m and m.group(2).strip("'\"") == slug):
            continue
        item_indent = len(m.group(1))
        end = _block_end(lines, i, item_indent)
        if _block_iteration(lines, i, end, item_indent + 2) == iteration:
            return i, end, item_indent
    label = f"{slug}#{iteration}" if iteration else slug
    fail(f"'{label}' is in active[] but its `- slug:` line could not be located")

def splice_auto_run(text, slug, iteration, value):
    """Set or clear `auto_run:` on one workstream by TEXTUAL splice.

    A whole-document safe_dump would destroy every comment in current.yml, including its own
    "created by …" header. So the VALUE is serialised by safe_dump (which is what makes a forged
    record impossible) and those lines are spliced in. Both properties, neither traded away
    (ADR-0019 D4)."""
    lines = text.splitlines(keepends=True)
    start, end, item_indent = item_bounds(lines, slug, iteration)
    field_indent = item_indent + 2

    if value is None:
        frag = [" " * field_indent + "auto_run: null\n"]
    else:
        dumped = yaml.safe_dump({"auto_run": value}, sort_keys=False, default_flow_style=False,
                                allow_unicode=True)
        frag = [" " * field_indent + ln if ln.strip() else ln
                for ln in dumped.splitlines(keepends=True)]

    at = None
    for j in range(start + 1, end):
        if re.match(rf"^ {{{field_indent}}}auto_run:", lines[j]):
            at = j
            break

    if at is None:
        insert_at = end
        while insert_at > start + 1 and not lines[insert_at - 1].strip():
            insert_at -= 1
        lines[insert_at:insert_at] = frag
    else:
        stop = at + 1
        while stop < end and (not lines[stop].strip()
                              or (len(lines[stop]) - len(lines[stop].lstrip())) > field_indent):
            stop += 1
        lines[at:stop] = frag

    out_text = "".join(lines)
    yaml.safe_load(out_text)          # never write something we cannot read back
    return out_text

def write_current(new_text, mtime_before):
    if os.stat(CURRENT_YML).st_mtime_ns != mtime_before:
        print("autorun: current.yml changed while we were writing; nothing written, retry",
              file=sys.stderr)
        sys.exit(10)
    shutil.copy2(CURRENT_YML, CURRENT_YML + ".bak")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CURRENT_YML), prefix=".current.yml.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(new_text)
    # mkstemp creates 0600 and os.replace keeps the TEMP file's mode: without this the state file
    # silently becomes owner-only on its first write (measured on deviation.sh: 644 -> 600).
    shutil.copymode(CURRENT_YML, tmp)
    os.replace(tmp, CURRENT_YML)

class StateLock:
    """The SAME lock deviation.sh takes, deliberately: the two writers become mutually exclusive and
    no new lock file enters the project (NG4). fcntl.flock, never flock(1) — absent on BSD/macOS.
    The OS releases it on process exit, so there is no stale-lock state to detect."""
    def __enter__(self):
        self.handle = open(CURRENT_YML + ".lock", "w")
        try:
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print("autorun: another writer holds the lock; retry", file=sys.stderr)
            sys.exit(10)
        return self
    def __exit__(self, *exc):
        self.handle.close()
        return False

# ----- the record ------------------------------------------------------------
FM_RE = re.compile(r"\A---\n(.*?)\n---\n(.*)\Z", re.DOTALL)

def feature_dir(slug, iteration):
    base = os.path.join(ROOT, ".ssd", "features", slug)
    if iteration:
        return os.path.join(base, "iterations", iteration)
    return base

def read_record(path):
    if not os.path.isfile(path):
        fail(f"auto-run record {path} is missing. The lock names a file that does not exist; "
             "see docs/runbooks/ssd-state-recovery.md")
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    m = FM_RE.match(text)
    if not m:
        fail(f"auto-run record {path} has no YAML frontmatter")
    try:
        return yaml.safe_load(m.group(1)) or {}, m.group(2)
    except yaml.YAMLError as exc:
        fail(f"auto-run record {path} frontmatter is not parseable: {exc}")

def write_record(path, meta, body):
    # safe_dump for the WHOLE frontmatter is correct here (unlike current.yml): the record is
    # machine-generated and carries no comments to destroy. It is also what makes `reason` unable to
    # introduce structure.
    dumped = yaml.safe_dump(meta, sort_keys=False, default_flow_style=False, allow_unicode=True)
    text = "---\n" + dumped + "---\n" + body
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".autorun.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    if os.path.exists(path):
        shutil.copymode(path, tmp)
    else:
        os.chmod(tmp, 0o644)
    os.replace(tmp, path)

def library_version():
    try:
        with open(os.path.join(ROOT, "VERSION"), "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return "unknown"

def project_name():
    doc = read_yaml(PROJECT_YML)
    return ((doc.get("project") or {}).get("name")) or "unknown"

def render_body(meta):
    """The prose body is RENDERED from the frontmatter, never written twice. A crash loses the
    narration and nothing else: every announce line is reconstructible from transitions[], which was
    written before each act (D9)."""
    run = meta["run"]
    lines = [f"# Auto-run — {run['slug']} ({run['mode']})", "",
             f"Ceiling `{run['until']}`. Budgets: "
             f"{run['budgets']['review_loops']} review loops, "
             f"{run['budgets']['transitions']} transitions, "
             f"{run['budgets']['wall_minutes']} wall minutes.", "",
             "## Announced transitions", ""]
    if not run["transitions"]:
        lines.append("_None. The run stopped before its first transition._")
    for entry in run["transitions"]:
        lines.append(f"- `{entry['ts']}` → `{entry['lowered']}`"
                     + (f" — {entry['reason']}" if entry.get("reason") else ""))
    lines += ["", "## Outcome", "",
              f"- stop reason: `{run['stop_reason']}`",
              f"- phase reached: `{run['phase_reached']}`",
              f"- gate result: `{run['gate_result']}`",
              f"- outcome: `{run['outcome']}`",
              f"- review loops consumed: {run['loops_consumed']}", ""]
    return "\n".join(lines)

# ----- subcommands -----------------------------------------------------------
def cmd_preflight():
    mode, budgets, announce = autonomy_config()
    out(f"state=ok reason=- mode={mode} announce={announce} "
        f"review_loops={budgets['review_loops']} transitions={budgets['transitions']} "
        f"wall_minutes={budgets['wall_minutes']}")

def cmd_status():
    _, doc = load_current()
    held = []
    for entry in ((doc or {}).get("active") or []):
        if isinstance(entry, dict) and entry.get("auto_run"):
            if SLUG_ARG and qualified(entry) != SLUG_ARG:
                continue
            held.append(entry)
    if not held:
        out("state=ok reason=- in_flight=0")
        return
    out(f"state=stop reason=in-flight in_flight={len(held)}")
    for entry in held:
        lock = entry["auto_run"]
        print(f"  {qualified(entry)}: started {lock.get('started')} until {lock.get('until')}",
              file=sys.stderr)
        print(f"    record: {lock.get('record')}", file=sys.stderr)
        record_path = os.path.join(ROOT, lock.get("record", ""))
        if os.path.isfile(record_path):
            meta, _ = read_record(record_path)
            transitions = (meta.get("run") or {}).get("transitions") or []
            last = transitions[-1] if transitions else None
            print(f"    last announced: {last['lowered'] + ' at ' + last['ts'] if last else '(none)'}",
                  file=sys.stderr)
            print(f"    stop_reason: {(meta.get('run') or {}).get('stop_reason')}", file=sys.stderr)
        else:
            print("    record: MISSING on disk", file=sys.stderr)
    print("  Recovery: verify the working tree, then "
          f"`bash methodology/autorun.sh clear --slug {qualified(held[0])} --confirm`", file=sys.stderr)

def cmd_plan():
    _, doc = load_current()
    entry = find_workstream(doc, BASE_SLUG, ITERATION)
    if entry is None:
        refuse("FM-1", f"no active workstream '{SLUG_ARG}'. Active: "
                       f"{', '.join(active_slugs(doc)) or '(none)'}")
    _, budgets, _ = autonomy_config()
    budgets = effective_budgets(budgets)
    until = env("UNTIL") or "gate"
    phase = entry.get("phase") or "brief"
    out(f"state=ok reason=- planned_from={phase} until={until}")
    if phase_index(phase) < 0:
        print(f"  phase '{phase}' is not a rail phase; nothing to plan", file=sys.stderr)
        return
    steps, current, guard = [], phase, 0
    while phase_index(current) < phase_index(until) and guard < budgets["transitions"]:
        nexts = RAILS_NEXT.get(current) or set()
        forward = [p for p in nexts if phase_index(p) > phase_index(current)]
        if not forward:
            break
        nxt = forward[0]
        steps.append((current, nxt))
        current, guard = nxt, guard + 1
    if not steps:
        print("  nothing to walk — already at or past the ceiling", file=sys.stderr)
    for frm, to in steps:
        print(f"  {frm} -> {to}    {lowered_command(to)}", file=sys.stderr)
    print("  (optimistic: a failing review adds review -> code loops, "
          f"up to {budgets['review_loops']})", file=sys.stderr)
    print("  DRY RUN — no record written, no state changed.", file=sys.stderr)

def cmd_start():
    mode_cfg, budgets, _ = autonomy_config()
    budgets = effective_budgets(budgets)
    mode = env("MODE")
    until = env("UNTIL") or "gate"

    with StateLock():
        text, doc = load_current()
        mtime_before = os.stat(CURRENT_YML).st_mtime_ns
        entry = find_workstream(doc, BASE_SLUG, ITERATION)
        if entry is None:
            refuse("FM-1", f"no active workstream '{SLUG_ARG}'. Active: "
                           f"{', '.join(active_slugs(doc)) or '(none)'}")

        # FM-2. One auto-run per project. No bypass flag exists, and that absence is the feature:
        # `--force` is what a bypass becomes.
        for other in ((doc or {}).get("active") or []):
            if isinstance(other, dict) and other.get("auto_run"):
                lock = other["auto_run"]
                refuse("FM-2",
                       f"an auto-run is already held by '{qualified(other)}' "
                       f"(started {lock.get('started')}, until {lock.get('until')}).\n"
                       f"         record: {lock.get('record')}\n"
                       "         If that run died, this lock is stale. Recovery: read the record "
                       "above (it names the last announced phase), verify the working tree, then\n"
                       f"         bash methodology/autorun.sh clear --slug {qualified(other)} --confirm")

        phase = entry.get("phase") or "brief"
        if phase == "done":
            refuse("FM-3", f"'{SLUG_ARG}' is at phase 'done' — nothing to run")
        if phase_index(phase) < 0:
            refuse("FM-3", f"'{SLUG_ARG}' is at phase '{phase}', which is above the ceiling. "
                           "No autonomy rung reaches deploy or beyond.")
        if phase_index(phase) >= phase_index(until):
            refuse("FM-3", f"'{SLUG_ARG}' is already at or past '{until}' (phase: {phase})")

        # STOP-3 semantics BEFORE starting. Over budget means a scope-cut conversation, not more
        # automated work — existing doctrine (chapters/state.md), applied to the agent.
        elapsed, budget_hours = entry.get("elapsed_hours"), entry.get("budget_hours")
        if isinstance(elapsed, (int, float)) and isinstance(budget_hours, (int, float)) \
                and elapsed > budget_hours:
            refuse("STOP-3", f"'{SLUG_ARG}' is over budget ({elapsed}h of {budget_hours}h). "
                             "Over budget means a scope cut, not more automated work.")

        started = now()
        rel_dir = os.path.relpath(feature_dir(BASE_SLUG, ITERATION), ROOT)
        # Colon-free: an ISO-8601 instant contains colons, which are illegal on NTFS/FAT and shown as
        # `/` by the macOS Finder. A record that cannot survive a Windows checkout disappears exactly
        # when someone audits the repo from another machine (D3). Full precision lives in produced_at.
        filename = started.strftime("%Y-%m-%dT%H%M%SZ") + "-run.md"
        rel_path = os.path.join(rel_dir, "auto-runs", filename)
        abs_path = os.path.join(ROOT, rel_path)

        meta = {
            "skill": "ssd",
            "version": library_version(),
            "produced_at": stamp(started),
            "produced_by": os.environ.get("SSD_AGENT", "claude-opus-5"),
            "project": project_name(),
            "scope": "feature",
            "consumed_by": ["codebase-skeptic", "feynman"],
            "run": {
                "mode": mode,
                "slug": SLUG_ARG,
                "iteration": ITERATION,
                "until": until,
                "budgets": budgets,
                "transitions": [],
                "loops_consumed": 0,
                "stop_reason": None,
                "phase_reached": phase,
                "gate_result": "not_run",
                "outcome": "incomplete",
            },
        }
        # The RECORD is written before the lock that points at it. The reverse order leaves a lock
        # naming a file that does not exist; this order leaves at worst an orphan record whose null
        # stop_reason marks it (D8).
        write_record(abs_path, meta, render_body(meta))
        new_text = splice_auto_run(text, BASE_SLUG, ITERATION,
                                   {"started": stamp(started), "until": until, "record": rel_path})
        write_current(new_text, mtime_before)

    out(f"state=ok reason=- record={rel_path} mode={mode} until={until} from_phase={phase} "
        f"configured_mode={mode_cfg}")

def cmd_transition():
    frm, to = env("FROM"), env("TO")
    _, budgets_cfg, _ = autonomy_config()

    with StateLock():
        _, doc = load_current()
        entry = find_workstream(doc, BASE_SLUG, ITERATION)
        if entry is None:
            refuse("FM-1", f"no active workstream '{SLUG_ARG}'")
        lock = entry.get("auto_run")
        if not lock:
            refuse("FM-2", f"no auto-run is in flight for '{SLUG_ARG}'. Call `start` first.")

        # STOP-4. `--from` is supplied by the orchestrator — the component this whole design treats
        # as untrusted — and until now nothing checked it against where the workstream actually is.
        # The consequence was not cosmetic: the review-loop counter only increments on the literal
        # `review -> code` edge, so announcing `code -> review` each round consumed ZERO loops and
        # never tripped STOP-1 (review round 1, MAJOR-1). The budget that exists to stop an agent
        # thrashing was enforced against a string the agent supplied.
        recorded = entry.get("phase") or "brief"
        if frm != recorded:
            out("state=stop reason=STOP-4")
            print(f"autorun: --from '{frm}' disagrees with the recorded phase '{recorded}' for "
                  f"'{SLUG_ARG}'. Proceeding would mean guessing which one is true.\n"
                  "         The orchestrator writes active[].phase after each act; if the phase is "
                  "stale, the last act did not finish the way it reported.", file=sys.stderr)
            return

        record_path = os.path.join(ROOT, lock["record"])
        meta, _body = read_record(record_path)
        run = meta["run"]
        budgets = run.get("budgets") or budgets_cfg

        # STOP-2 — the edge is not on the rails. Nothing else in this script needs to know what a
        # deviation is: an auto-run cannot express one, so it cannot write one.
        if to not in (RAILS_NEXT.get(frm) or set()):
            out("state=stop reason=STOP-2")
            print(f"autorun: {frm} -> {to} is not a rails edge. Leaving the rails is engineering "
                  "judgment (ADR-0019) and an auto-run records zero deviations by construction. "
                  "Handing back.", file=sys.stderr)
            return

        if phase_index(to) > phase_index(run["until"]):
            out("state=stop reason=STOP-7")
            print(f"autorun: '{to}' is above the ceiling '{run['until']}'. Handing back.",
                  file=sys.stderr)
            return

        if len(run["transitions"]) >= budgets["transitions"]:
            out("state=stop reason=STOP-3")
            print(f"autorun: transition budget exhausted ({budgets['transitions']}). Handing back.",
                  file=sys.stderr)
            return

        started_at = parse_stamp(meta.get("produced_at"))
        # TWO numbers, because one field was carrying two meanings (review round 1, MINOR-4):
        # `since_start_minutes` is what the wall budget is measured against, and `phase_minutes` is
        # how long the previous phase actually took — which is the data D13 wants for choosing a
        # future default, and which was only recoverable by differencing consecutive entries.
        since_start_minutes = 0.0
        phase_minutes = 0.0
        if started_at:
            since_start_minutes = round((now() - started_at).total_seconds() / 60.0, 1)
            previous = run["transitions"][-1]["ts"] if run["transitions"] else meta["produced_at"]
            previous_at = parse_stamp(previous) or started_at
            phase_minutes = round((now() - previous_at).total_seconds() / 60.0, 1)
            wall = budgets.get("wall_minutes", 0)
            elapsed_minutes = since_start_minutes
            # The wall bounds STARTING new work, not the call in flight. A single long sub-skill can
            # overrun it, and the chapter says so in those words (D13).
            if wall and elapsed_minutes > wall:
                out("state=stop reason=STOP-3")
                print(f"autorun: wall-clock budget exhausted ({elapsed_minutes} of {wall} minutes). "
                      "Handing back.", file=sys.stderr)
                return

        loops = run["loops_consumed"]
        if frm == "review" and to == "code":
            if loops + 1 > budgets["review_loops"]:
                out("state=stop reason=STOP-1")
                print(f"autorun: the gate still fails after {budgets['review_loops']} review "
                      "round(s). Persistent failure needs human judgment, not another loop.",
                      file=sys.stderr)
                return
            loops += 1

        lowered = lowered_command(to)
        run["transitions"].append({
            "ts": stamp(now()),
            "from": frm,
            "to": to,
            "lowered": lowered,
            "reason": normalise_reason(env("REASON")) or None,
            "since_start_minutes": since_start_minutes,
            "phase_minutes": phase_minutes,
        })
        run["loops_consumed"] = loops
        run["phase_reached"] = to
        write_record(record_path, meta, render_body(meta))

    out(f"state=ok reason=- lowered={lowered} transition={len(run['transitions'])}"
        f"/{budgets['transitions']} loops={loops}/{budgets['review_loops']}")

def derive_gate_result():
    """Prefer the CAPTURED gate output over a relayed word. `gate-rules.sh` writes no file of its
    own, so the orchestrator redirects its stdout and points here — which turns a verdict relayed by
    an LLM into an artifact a human can re-read (systems-designer round 2, S5)."""
    path = env("GATE_OUTPUT")
    if not path:
        return env("GATE_RESULT") or "not_run", None
    if not os.path.isfile(path):
        fail(f"--gate-output '{path}' does not exist")
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    fails = len(re.findall(r"^FAIL\s", text, re.MULTILINE))
    passes = len(re.findall(r"^PASS\s", text, re.MULTILINE))
    if fails:
        return "fail", f"{fails} FAIL rule(s) in {os.path.basename(path)}"
    if passes:
        return "pass", f"{passes} PASS rule(s), 0 FAIL in {os.path.basename(path)}"
    return "not_run", f"no rule lines found in {os.path.basename(path)}"

def cmd_finish():
    stop = env("STOP")
    phase_reached = env("PHASE_REACHED")
    gate_result, gate_detail = derive_gate_result()

    with StateLock():
        text, doc = load_current()
        mtime_before = os.stat(CURRENT_YML).st_mtime_ns
        entry = find_workstream(doc, BASE_SLUG, ITERATION)
        if entry is None:
            refuse("FM-1", f"no active workstream '{SLUG_ARG}'")
        lock = entry.get("auto_run")
        if not lock:
            # Idempotent by design: a retry after a partial hand-back must not wedge the lock.
            out("state=ok reason=already-finished")
            return

        record_path = os.path.join(ROOT, lock["record"])
        meta, _body = read_record(record_path)
        run = meta["run"]
        run["stop_reason"] = stop
        run["phase_reached"] = phase_reached
        run["gate_result"] = gate_result
        # `stop_reason` says WHY the run ended; `outcome` says HOW IT WENT (D11). The mapping is
        # principled rather than residual (review round 1, QUESTION-1):
        #   red        — something JUDGED the work and said no
        #   incomplete — the run stopped BEFORE anything judged it
        #   green      — the ceiling was reached and the executable gate passed
        # STOP-3 (out of budget) and STOP-2 (would need a deviation) are not verdicts on the code,
        # and calling them `red` made "ran out of room" indistinguishable from "the work is failing".
        if stop == "STOP-7":
            run["outcome"] = {"pass": "green", "fail": "red"}.get(gate_result, "incomplete")
        elif stop in ("STOP-1", "STOP-6"):
            run["outcome"] = "red"
        else:
            run["outcome"] = "incomplete"
        write_record(record_path, meta, render_body(meta))
        write_current(splice_auto_run(text, BASE_SLUG, ITERATION, None), mtime_before)

    out(f"state=ok reason={stop} outcome={run['outcome']} gate_result={gate_result} "
        f"phase_reached={phase_reached} record={lock['record']}")
    if gate_detail:
        print(f"  gate verdict from output file: {gate_detail}", file=sys.stderr)
    if run["outcome"] == "red":
        print("  This run did NOT end green. Read the record before continuing.", file=sys.stderr)

def cmd_clear():
    with StateLock():
        text, doc = load_current()
        mtime_before = os.stat(CURRENT_YML).st_mtime_ns
        entry = find_workstream(doc, BASE_SLUG, ITERATION)
        if entry is None:
            refuse("FM-1", f"no active workstream '{SLUG_ARG}'")
        lock = entry.get("auto_run")
        if not lock:
            refuse("FM-2", f"'{SLUG_ARG}' holds no auto-run lock — nothing to clear")
        if not env("CONFIRM"):
            # Dry-run by default for the destructive direction, matching `store.sh link`.
            out("state=stop reason=dry-run")
            print(f"autorun: would clear the auto-run lock on '{SLUG_ARG}'.", file=sys.stderr)
            print(f"         started: {lock.get('started')}  until: {lock.get('until')}",
                  file=sys.stderr)
            print(f"         record:  {lock.get('record')}", file=sys.stderr)
            print("         Read that record (it names the last announced phase) and verify the "
                  "working tree FIRST.", file=sys.stderr)
            print("         Re-run with --confirm to clear.", file=sys.stderr)
            sys.exit(10)
        write_current(splice_auto_run(text, BASE_SLUG, ITERATION, None), mtime_before)
    out(f"state=ok reason=- cleared={SLUG_ARG} record={lock.get('record')}")

DISPATCH = {
    "preflight": cmd_preflight, "status": cmd_status, "plan": cmd_plan, "start": cmd_start,
    "transition": cmd_transition, "finish": cmd_finish, "clear": cmd_clear,
}
DISPATCH[SUB]()
PY
