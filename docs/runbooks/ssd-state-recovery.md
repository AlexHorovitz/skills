# Runbook: recovering a corrupted `.ssd/current.yml`

**The library's first runbook.** It exists because appending to the project's state file from a script
is a new operational surface ([ADR-0019](../decisions/ADR-0019-rail-deviation-records.md) D5/D8), which
is what rails invariant 8 is about — and it applies **today**, before `deviation.sh` exists, because
`migrate.sh` already mutates `.ssd/` state files.

## Symptoms

- `/ssd` reports a malformed `current.yml` and refuses to guess (it is designed to refuse — see
  `ssd/SKILL.md` § "Falls back to ask")
- `bash methodology/gate-rules.sh` emits `SKIP issue-sync-current` with an unexpected reason, or a rule
  that reads workstream state behaves as though no workstream exists
- a workstream you were working on has vanished from `active:`
- a `rail_deviations` entry you recorded is not there

## Step 1 — confirm it is actually malformed

```bash
python3 -c "import yaml; yaml.safe_load(open('.ssd/current.yml')); print('parses OK')"
```

**"parses OK" does not mean the content is right.** A lost update produces a *valid* file missing a
record. If it parses, go to Step 4.

## Step 2 — look before you restore

```bash
ls -la .ssd/current.yml .ssd/current.yml.bak
diff <(python3 -c "import yaml,sys; print(yaml.safe_dump(yaml.safe_load(open('.ssd/current.yml.bak'))))") \
     <(python3 -c "import yaml,sys; print(yaml.safe_dump(yaml.safe_load(open('.ssd/current.yml'))))")
```

The `.bak` is written **once per run** by whichever script mutated the file, so it is the state *before
that script ran* — not a general-purpose history. If two scripts ran, the `.bak` reflects the second.

## Step 3 — restore

```bash
cp .ssd/current.yml .ssd/current.yml.broken     # keep the evidence
cp .ssd/current.yml.bak .ssd/current.yml
python3 -c "import yaml; yaml.safe_load(open('.ssd/current.yml')); print('parses OK')"
```

Then **re-run whatever wrote last** — a `deviation.sh record`, a `/ssd upgrade --apply`, a phase
advance. Restoring undoes the write; it does not remember what the write was for.

## Step 4 — a record is missing but the file parses

This is the **lost-update** case (ADR-0019 D5): a script appended under its lock while the orchestrator
held a stale copy, and the orchestrator's write won.

```bash
grep -n "rail_deviations" .ssd/current.yml            # is the field there at all?
python3 -c "
import yaml; d=yaml.safe_load(open('.ssd/current.yml'))
for w in d.get('active') or []:
    print(w['slug'], '->', len(w.get('rail_deviations') or []), 'deviation(s)')"
```

The writer exits **10** when it detects the file changed under it, so a genuine lost update should be
loud. If a record is missing and nothing exited 10, **that is a defect worth reporting** — not a
routine recovery. Capture `.ssd/current.yml`, the `.bak`, and the command you ran.

## Step 5 — no `.bak` exists

Then nothing has mutated the file through a script, and the corruption came from a hand edit or an
orchestrator write. Reconstruct from git if `current.yml` is tracked (`blanket` mode), or from
`.ssd/archive/` plus the feature directories under `.ssd/features/` — every phase leaves an artifact,
so the phase is recoverable even when the index is not.

Under `selective` mode `current.yml` is **gitignored by policy** (`no-leaky-state` enforces this), so
there is no git history to fall back on. That is deliberate and it is the cost of keeping machine state
local.

## A stale `auto_run` lock

**Symptom:** `/ssd run` refuses with `state=refused reason=FM-2`, naming a workstream and a record
path, and you are certain no run is in flight. An orchestrator that died between `autorun.sh start`
and `autorun.sh finish` leaves the lock set (v2.14.0,
[ADR-0020](../decisions/ADR-0020-autonomy-ladder.md)).

**This is not a bug and it is not auto-cleared.** An age-based expiry would silently resume a run
whose working tree nobody checked. The lock is loud, and clearing it is a decision.

### Step A — see what is held

```bash
bash methodology/autorun.sh status
```

It prints the holding slug, when the run started, its ceiling, the record path, **the last announced
transition**, and the record's `stop_reason` (`None` means it never finished).

### Step B — read the record before touching anything

```bash
sed -n '1,60p' .ssd/features/<slug>/auto-runs/<ts>-run.md
```

The last entry in `run.transitions[]` is the last phase the orchestrator **announced**, and therefore
the last one that may have run — the record is written *before* the act, so reality is at most one
announced step ahead of this file. That is the whole reason the ordering exists.

### Step C — verify the working tree against it

```bash
git status --short
git diff --stat
```

Ask the question the record cannot answer: did that last announced phase **finish**? A half-written
artifact is possible — sub-skills are not atomic, and the chapter says so. Finish or discard it by
hand before continuing.

### Step D — clear the lock

```bash
bash methodology/autorun.sh clear --slug <slug>            # dry run: prints, changes nothing, exit 10
bash methodology/autorun.sh clear --slug <slug> --confirm  # acts
```

`clear` writes `current.yml.bak` first, like every other mutation here. Afterwards `/ssd run` works
again; the old record stays on disk with `stop_reason: null`, which is the permanent marker that this
run died rather than ended.

### If the record is missing but the lock is set

`autorun.sh status` prints `record: MISSING on disk`. The lock names a file nothing wrote — the
failure happened inside `start`, between the record write and the state write, or the file was
deleted. There is nothing to reconstruct: clear the lock and re-run. Nothing was announced, so
nothing ran.

## Known limitation, not a bug

**A deviation recorded against the wrong workstream cannot be detected.** A typo'd `--slug` that
happens to match another *active* workstream writes a true record in a false place, and no rule can
tell. If you suspect it, the `ts` field is the only discriminator — compare it against when you were
actually working on that slug.

## Escalation

Solo-maintained project. Escalation is: stop, keep `.ssd/current.yml.broken`, and do not re-run the
mutating command until you know what it did.
