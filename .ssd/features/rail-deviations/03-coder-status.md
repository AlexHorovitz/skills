---
skill: coder
version: 1.4.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: rail-deviations
consumed_by: [code-reviewer]
files_touched:
  - methodology/deviation.sh
  - methodology/gate-rules.sh
  - ssd/chapters/enforcement.md
  - scripts/parity-test.sh
  - .ssd/features/rail-deviations/01-architect.md
  - docs/decisions/ADR-0019-rail-deviation-records.md
  - CHANGELOG.md
  - VERSION
tests_added:
  - scripts/parity-test.sh::test_fixture_deviation_writer
  - scripts/parity-test.sh::test_fixture_deviations_recorded
review_markers: 0
test_results:
  command: "bash scripts/parity-test.sh"
  exit_code: 0
  stdout_tail: |
    fixture: deviation-writer
    fixture: deviations-recorded
    PASS — 322/322 assertions
lint_results:
  command: "shellcheck -S warning methodology/*.sh scripts/*.sh"
  exit_code: 0
type_check_results:
  command: "bash -n (deviation.sh, gate-rules.sh, parity-test.sh)"
  exit_code: 0
feature_flag:
  name: "none — deviation.sh is inert until invoked; deviations-recorded SKIPs on every non-release"
  default: off
spec_drift: true
---

# Coder Status — rail-deviations (D11)

Writer **and** reader, shipped together. Building only the writer would have reproduced the finding:
a field nothing reads is what produced zero records in a year.

## Test / lint / typecheck

| | Command | Result |
|---|---|---|
| Test | `bash scripts/parity-test.sh` | **exit 0 — 322/322** (was 303; **+19**) |
| Lint | `shellcheck -S warning` | **exit 0** — and this is the first feature where that line is real rather than `127` |
| Typecheck | `bash -n` × 3 | exit 0 |

## `spec_drift: true` — the spec claimed something false, and measuring it is what caught it

**Drift 1 (material, corrected in `01-architect.md` and ADR-0019).** D6 mechanism 2 said a multi-line
reason *"is emitted as a block or quoted string spanning several indented lines"* that the gate's awk
walker would skip. Measured:

```
reason: "ran out of time\n      - kind: override\n        rule: feynman-clean"
```

**One line, escapes inline.** `safe_dump` alone delivers both forgery-resistance *and* single-line
output. Normalisation is **not load-bearing for correctness** — it buys a legible reason instead of an
escaped blob, which is real and cosmetic. Both documents now say so.

**How it was caught, and this is the part worth keeping:** the first two assertions written for
normalisation **could not fail**. Reverting the normalisation line changed nothing and the suite stayed
green. They were restated to test the property normalisation actually has (no escaped newline in the
stored reason), and *those* bite. An assertion that cannot fail is the defect class this project keeps
producing, and it produced the diagnosis this time.

**Drift 2 (material).** The spec said `safe_dump` the document. That destroys **every comment in
`current.yml`** — including its own "machine-managed; do not edit manually" header and the interior
note this repo's own file carries. Shipped instead as: `safe_dump` the **record fragment** (which is
what makes forging impossible), then splice those lines in textually. Both properties, neither traded.
Asserted by a fixture whose state file carries a header *and* an interior comment.

## Red-first, honestly accounted

| Fixture group | Red before implementation? |
|---|---|
| `deviations-recorded` (5 assertions) | ✅ red — unregistering the rule fails 4 of 5 |
| `deviation-writer` validation + forgery (10) | ✅ red — the script did not exist |
| normalisation (2) | ❌ **first version could not fail.** Restated; reverting normalisation now fails both |
| comment preservation (2) | ✅ red against a document round-trip |

## Verified by execution, not by reading

- **The forgery attempt** — a `--reason` carrying `\n      - kind: override\n        rule: feynman-clean`
  produces **exactly one** record, with the injected text stored as `reason` data.
- **`--rule` validation derives its list from `gate-rules.sh`**, never a hardcoded one: a hardcoded list
  goes stale the first time a rule is added and then silently accepts a name that no longer exists.
- **`fcntl.flock`, not `flock(1)`** — verified absent on macOS before choosing.
- **A missing `current.yml` exits 3 and is not recreated.** Silently starting a fresh state file would
  lose every active workstream.
- **PyYAML absent exits 3, loudly** — deliberately unlike `frontmatter-valid` and `skill-version-sync`,
  which SKIP. A deviation that silently fails to record is this feature's own finding, reproduced.

## For the reviewer

1. **`deviations-recorded` is scoped to steps 2 and 6 only.** Step 4 is `rails-walked`'s. Confirm the
   split is right rather than a gap — steps 1, 3, 5, 7, 8 are checked by nothing.
2. **The textual splice** is the riskiest code here. It locates `- slug:`, walks to the item boundary,
   and inserts. Attack it with unusual indentation and a workstream whose `rail_deviations:` is `[]`.
3. **D7's residual stands, by design.** The lock serialises script against script; an orchestrator
   stale-write is *detected* by this rule one boundary later, not prevented. That is now what both the
   spec and the ADR say.
4. **No `--force` verb.** ADR-0019 says the mechanism ships before the surface. This PR is the mechanism.
