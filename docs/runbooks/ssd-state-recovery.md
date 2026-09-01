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

## Known limitation, not a bug

**A deviation recorded against the wrong workstream cannot be detected.** A typo'd `--slug` that
happens to match another *active* workstream writes a true record in a false place, and no rule can
tell. If you suspect it, the `ts` field is the only discriminator — compare it against when you were
actually working on that slug.

## Escalation

Solo-maintained project. Escalation is: stop, keep `.ssd/current.yml.broken`, and do not re-run the
mutating command until you know what it did.
