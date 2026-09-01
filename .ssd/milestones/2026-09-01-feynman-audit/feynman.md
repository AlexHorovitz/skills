---
skill: feynman
version: 1.1.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: repo @ 6642e9c (branch docs-store-deploy-log-postship, VERSION 2.10.1) — immediately post-release
consumed_by: [codebase-skeptic, refactor, ssd]
claim_counts:
  verified: 5
  unverified: 1
  unfalsifiable: 1
  misleading: 4
  contradicted: 7
  theater: 2
rituals_audited: 12
one_true_sentence: "SSD's executable core is real and genuinely self-correcting — its own gate found a MAJOR in its own shipped code this week, all 264 parity assertions are well-formed, and feynman-clean provably FAILs on a failing report — but the documentation asserts an enforcement layer that does not exist: no gate rule checks any of the eight rails invariants, rail_deviations: has never once been written across 15 workstreams, /ssd ship --force is described as a logged override in four documents and implemented in none, rail step 2 has been skipped 13 times out of 13, and 5,124 lines of shell have never been linted."
posture: drifting
gate_pass: false
not_examined:
  - the 41,482 lines of markdown as *instructions* — no harness executes SKILL.md prose, so every behavioural claim about the orchestrator is unfalsifiable by command
  - whether any project other than this repo has ever run SSD (zero external evidence exists in-repo)
  - the artifact store in real use — never linked outside fixtures and one throwaway dogfood
  - ADR bodies 0001–0016 except where cited; read ADR-0012/0017/0018 only
  - migrate.sh --apply against a real downstream project
  - production — a skills library has none; every claim here rests on internal evidence
  - CI runs older than the 100 most recent
  - the 6 of 13 feature dirs with no deploy log
  - the 39 code-review artifacts' findings for whether their closures were real
  - releases before v1.17.0 (VERSION did not exist as a file, so the C3 experiment could not reach them)
executed_evidence: 19
read_evidence: 2
---

# Feynman Audit — SSD Skills Library @ v2.10.1

**Scope.** `/Users/ahorovit/Development/insanelygreat/skills` @ `6642e9c`, VERSION 2.10.1, audited
2026-09-01 — hours after v2.10.1 was merged, tagged, and installed. This is the moment the skill's own
"When to Use" names first: *before a release, or right after one, when confidence is highest.*

**Freedom condition.** The reader is the author and sole maintainer. No organizational pressure exists
to soften this, and therefore no excuse for softening it. One complication worth naming up front:
**several claims under audit are mine, made in this session.** They are graded like any other, and one
of them is 🟠.

**Prior audit.** 2026-08-19 @ `487e10c` (v2.5.0), posture `drifting`, 4 contradicted / 1 theater. Its
remediations are re-tested below rather than trusted.

---

## Phase 1–2 — The Claim Ledger

| ID | Claim (verbatim) | Source | Kind | Grade | Evidence |
|---|---|---|---|---|---|
| C0 | "give me a Feynman audit … immediately post-release" | user, this session | process | ✅ | Post-release is a named trigger. v2.10.1 verified merged (`f8cb746`), tagged, installed. The framing is warranted — and it produced 6 🔴 and 2 💀, so it was not a formality. |
| C1 | "PASS — 264/264 assertions" | `scripts/parity-test.sh`, every coder-status, my own ship report | quality | ✅ | Ran it: 264/264, exit 0. **And I audited the harness**, because `_assert` compares `[[ "$ok" -eq 0 ]]` and bash treats an **empty string as 0** — verified: `ok=""` PASSES, `ok="banana"` PASSES. So a substitution yielding nothing would score as a pass. I then checked all **211 call sites**: every one terminates in an `echo 0`/`echo 1` fallback, so **no current assertion can yield empty**. The claim is true. The harness hazard is latent, not active — see Finding H1. |
| C2 | "every skipped step appears in `rail_deviations:`" · "`codebase-skeptic` can audit 'did this feature walk the rails?' **mechanically**" | `ssd/rails.md` | process | 🔴 | `grep -cE '^\s+rail_deviations:' .ssd/current.yml` → **0**, across **15 archived workstreams**. No script writes the field (`grep -rn rail_deviations --include=*.sh` → only *parsers*). Deviations are recorded in **prose** in deploy logs — 3 artifacts. Nothing can audit rails-walking mechanically, because the field it would read is empty everywhere. |
| C3 | "No merge without a clean `/ssd gate`" (hard rule 1) · rails invariant 4: "at least one code review with `gate_pass: true`" | `ssd/SKILL.md`, `ssd/rails.md` | process | 🔴 | `grep -niE 'code.?review\|gate_pass' methodology/gate-rules.sh` → **no rule reads either**. The gate has 11 rules and **none of them is a rails invariant**. PR #43 merged with zero review artifacts and every check green. **See § "Phase 8" — the rule was built and the experiment run, and it cut down this claim's *implication* while confirming its letter.** |
| C4 | "an override (`/ssd ship --force`) **is logged**" | `ssd/SKILL.md:200`, `ssd/chapters/enforcement.md:44`, `ssd/chapters/phases.md:302`, `methodology/gate-rules.sh:914` | process | 🔴 | `grep -rn '\-\-force' methodology/*.sh` → the only hits are `gh label create --force` in `issue-sync.sh`. **`--force` is not implemented anywhere**, and its only plausible log target (`rail_deviations`) is never written (C2). ADR-0012 Pillar 5 discloses this honestly — "that wiring is tracked 2.0 work, not yet shipped." **One document tells the truth; four assert the mechanism exists.** |
| C5 | "Either job failing surfaces a red check … this REPORTS — it does not hard-block" | `.github/workflows/quality.yml:6-9` | process | 🔵 | `gh run list --limit 100` → **65 success, 1 cancelled, 0 failures. Ever.** The prior audit measured 40/40 and graded this 🔵; **26 more runs later the number is still zero.** No observation distinguishes "the CI gate protects this repo" from "the CI gate is decorative" — and PR #43, which violated a rails invariant, was **green**. |
| C6 | "no branch protection is required, **by design**" | `.github/workflows/quality.yml:8` | process | 🔴 | `gh api repos/.../rulesets` → ruleset **`Overwatch`**, `enforcement=active`, `target=branch`, `include=[~ALL]`, rules `[deletion, non_fast_forward, pull_request, required_signatures]`. Branch protection **is** required, on every branch, and has been long enough that every push this session reported `Bypassed rule violations`. The workflow's own header is contradicted by the repo's live configuration. |
| C7 | "PASS frontmatter-valid :: N artifact(s) validated against schemas" | gate output | quality | 🔴 | On a diff of **exactly one** SSD artifact the gate says **`SKIP frontmatter-valid :: no SSD artifacts in scope`**. The validator saw it: `SKIP … no matching schema`, exit 0. `rule_frontmatter_valid` branches on the count of `PASS` lines alone, so at `count == 0` it **claims absence** regardless of `skipped`. Found today by gating a docs PR. **This defect was created by the prior audit's C4 remediation** — that fix stopped `count > 0` from over-reporting coverage and left `count == 0` asserting something false. 5 schemas exist for 5+ artifact kinds; `brief` and `deploy` have none. |
| C8 | "PASS skill-version-sync :: 9 skill example(s) match banner; **2 exempt**" | gate output | quality | 🟠 | `python3 methodology/frontmatter-validate.py --check-skill-examples .` → the 2 exempt are **`ssd/SKILL.md` and `methodology/SKILL.md`** — the orchestrator and the doctrine, the two most load-bearing files in the library. Graded 🟠 by the prior audit and marked **"Fixed"**; the fix added the words *"2 exempt"* to the output. **The coverage gap is byte-identical.** Disclosure is not remediation. |
| C9 | "tag every release" (the §4 ratchet); "the missing-tags drift the post-v1.19 milestone **fixed**" | `methodology/core.md`, `ssd/chapters/phases.md:285` | process | 🔴 | Looped every `## [x.y.z]` heading in CHANGELOG against `refs/tags/` → **16 of 30 releases have no tag**: v1.0.0 through v1.14.0 inclusive. The milestone fixed the v1.17.0+ range and the ratchet was declared closed. Over half the library's release history is untagged. |
| C9b | "The release chain is unbroken **end to end**" | **me**, this session's ship report | status | 🟠 | Literally I verified twelve `v2.*` tags and said so in the next breath — but *"end to end"* invites the reader to hear "the whole history." C9 is what the whole history looks like. This is the exact shape of the failure this skill exists to catch, committed by the auditor, in the report the user was asked to trust. |
| C10 | `lint_results: {command: shellcheck…, exit_code: 127}` — "pre-existing environment gap" | 5+ coder-status artifacts | quality | 💀 | `command -v shellcheck` → **NOT INSTALLED**. Across the artifact tree `lint_results` records exit 127 (3×), `bash -n` — *syntax only, not linting* — or the literal string `"n/a — no linter configured"` (5 variants). **5,124 lines of shell — `gate-rules.sh`, `migrate.sh`, `issue-sync.sh`, `store.sh`, `parity-test.sh`, the entire executable substrate — have never been linted once.** The field is dutifully filled in every cycle and has never produced a finding. It cannot. |
| C11 | Rail step 2, "**Production check** — invoke `systems-designer`" | `ssd/chapters/phases.md:39-43`, `ssd/rails.md` | process | 💀 | `find .ssd -name "*systems-designer*"` → **0**. Zero, across 13 features, over the project's entire life. Every deploy log records it as a rail deviation with near-identical boilerplate. `phases.md` sanctions skipping it for a skills library — and `rails.md` documents the correct remedy: **fork `rails.md` and point `project.yml.rails:` at the variant.** That was never done. A step skipped 13 times out of 13 and excused each time is not a rail; it is a paragraph. |
| C12 | "PASS migration-manifest-current :: manifest valid (13 entries)" | gate output | quality | 🟠 | The manifest is internally valid — ids unique, ascending, ≤ VERSION. But `grep -nE 'store' methodology/migrations.yml` → **no store entry**. The feature that shipped as v2.10.0/v2.10.1 is **invisible to `/ssd upgrade`**, so no existing project can ever be offered it through the documented upgrade path. Disclosed as unbuilt in the deploy log; the gate line still says *current*. |
| C13 | "SSD has **one surface, progressively disclosed** … That is all most sessions need" | `ssd/SKILL.md` | quality | 🟠 | Measured: **17 `/ssd` verbs**, **21 `project.yml` keys**, **41,482 lines of markdown**, 11 skills, 18 ADRs. Progressive disclosure is real and well executed *for the reader*. It does not reduce the surface for the user who hits it. See the companion Jobs audit. |
| C14 | The `feynman-clean` rule "FAILs when `contradicted > 0` or `theater > 0`" | `feynman/SKILL.md`, ADR-0016 | process | ✅ | Built a synthetic repo, put **the real 2026-08-19 report** on a branch, ran the rule: `FAIL feynman-clean :: audit verdict stands against this change set: … (4 contradicted, 1 theater, posture=drifting)`, **exit 1**. It genuinely fails. It also reads the counters, not `gate_pass`, as documented. |
| C15 | The artifact store works | ADR-0018, `03-coder-status.md` | capability | 🟡 | `store-link-sane` **SKIPs in this repo** — `.ssd` is a real directory here, so the feature has never run in the project that ships it. All evidence is fixtures plus one throwaway dogfood. **Zero real projects use it.** Not a criticism of the code; a statement about what is known. |
| C16 | "the install is now correct" | **me**, ~1 hour ago | status | ✅ | `~/.claude/skills` fast-forwarded `e039961` → `f8cb746`; **264/264 from the installed tree**; `bash methodology/store.sh status` exit 0. Verified as *working*, not merely present. |
| C18 | "Second occurrence in this epic (**#41 was the first**)" | `CHANGELOG.md` §2.10.1, `.ssd/features/ssd-store/04-code-review.md`, **and this audit's own C3 row as first written** | status | 🔴 | Unsupported. `rails-walked` run against `7a2c389…7984dd8` → **PASS**: both feature dirs #41 touched carry a review with `gate_pass: true` (`recorded-defect-fixes/04-code-review.md`, and `ssd-private-mode/iterations/b/code-review/round-2.md`). I repeated this from the record instead of grading it — the exact failure of this skill's own rule 2, *"reading a claim in a second document is not corroboration; it is the same claim, twice."* |
| C17 | Prior audit C12 (💀, the inert gitignore allow-list) — "**Fixed**: deep denies added" | `.ssd/milestones/2026-08-19…/feynman.md:226` | quality | ✅ | Re-tested today: `.ssd/features/foo/secrets.env` → **IGNORED**; `.ssd/milestones/m/anything.txt` → **IGNORED**; `.ssd/features/x/00-brief.md` → committable (correct). The fix held through private mode *and* the store, both of which rewrote gitignore handling. This is the strongest remediation in the record. |

### Finding H1 — the assertion harness cannot distinguish "verified" from "produced nothing"

Not a ledger claim; a property of the instrument every other quality claim rests on.

```bash
ok="";       [[ "$ok" -eq 0 ]] && echo PASSES   # → PASSES
ok="banana"; [[ "$ok" -eq 0 ]] && echo PASSES   # → PASSES
```

All 211 call sites are currently guarded by an `echo 0`/`echo 1` fallback, so **the suite is sound
today**. But nothing enforces that guard, and the failure is silent and *green*. This session already
produced one instance of the class — a reversion test whose `str.replace` matched nothing, reported
264/264, and was briefly read as "the fixture doesn't catch it." One line fixes it:
`[[ "$ok" =~ ^[0-9]+$ ]] || { FAIL_COUNT=…; return; }`.

**My own asymmetry, declared:** I expected this to be the report's headline and went looking for
victims. There are none. The evidence says the call sites are clean, and saying so cost the audit its
best story.

---

## Phase 3 — Cargo Cult Inventory

> What evidence made you believe this works, and what would show you it doesn't?

| Ritual | Meant to produce | Last time it changed a decision | Verdict |
|---|---|---|---|
| `/ssd gate` | catch unshippable state | **today** — found `frontmatter-valid`'s false message; last week, #43's missing review; before that, the store key collision | ✅ Lands |
| Code review | block BLOCKER/MAJOR | **this week** — MAJOR-1 in already-shipped v2.10.0 code | ✅ Lands |
| The Feynman audit | recalibrate beliefs | 2026-08-19 → 9 same-day fixes, 2 of which re-verified as holding today | ✅ Lands |
| ADR process | record contested decisions | ADR-0018 took a *correcting addendum* within 24h of shipping | ✅ Lands |
| Deploy logs | record what actually shipped | 7 of 13 features have one; each surfaced outstanding items that survived into later work | ✅ Lands |
| `lint_results` frontmatter | catch shell defects | **never** — shellcheck has never been installed | 💀 Theater |
| Rail step 2 / systems-designer | production readiness | **never** — 0 artifacts in 13 features | 💀 Theater |
| `rail_deviations:` field | durable deviation trace | **never written**, 15 workstreams | 💀 Theater |
| CI `quality` workflow | red check on bad PRs | 66 runs, **0 failures ever**; green on the PR that violated invariant 4 | 🟡 Unknown |
| `feature-flag-present` | enforce hard rule 2 | always SKIP here by design; no evidence it has ever fired anywhere | 🟡 Unknown |
| `/ssd upgrade` + manifest | migrate projects forward | no evidence any project has ever run it; the newest feature isn't in it | 🟡 Unknown |
| tag-every-release ratchet | navigable history | works for v1.17.0+; 16 releases untagged | 🟠 Partial |

**The islanders were not lazy.** Every 💀 above is *diligently maintained*. `lint_results` is filled in
every cycle with a precise command and a truthful exit code. The deviation tables in the deploy logs
are careful and specific. Effort is not the missing ingredient, so more effort is not the remedy — in
two of the three cases the remedy is **deletion**: stop requiring a field nothing reads.

---

## Phase 4 — Asymmetric Scrutiny Sweep

- **Two prior 🟠 findings were closed by making the output more honest rather than making the coverage
  better** (C8 skill-version-sync, C7/C4 frontmatter). Both were marked **"Fixed"** in the same-day
  remediation table. Disclosure is genuinely progress, and it is not what "Fixed" means. C7 shows the
  cost: the C4 remediation *introduced* a false message that survived four releases.
- **The comfortable landing.** `shellcheck` has been recorded as a "pre-existing environment gap" in at
  least five artifacts across three features. It is phrased as environmental — outside the project's
  control — and `brew install shellcheck` has never been run. The attribution is doing work.
- **Where the scrutiny was hardest, the answer was convenient.** I attacked the parity harness (H1)
  expecting to find rot, because I had personally been fooled by that class earlier in the session.
  I attacked the CI claim expecting decoration and found 66/66 green, which is *ambiguous*, not clean —
  and ambiguity is the finding.
- **Where the scrutiny was softest.** I graded C16 ✅ ("the install is correct") on evidence I generated
  one hour earlier and wanted to be true. It is verified — I re-ran the suite from the installed tree —
  but I did not check whether the install's *skills* actually load, only that its scripts run.
- **Published failures exist.** ADR-0017 states plainly that moving *out* of private mode is not built.
  ADR-0018's addendum documents its own rejected alternative. The prior audit's C13 recorded
  insufficient evidence for a slippage finding rather than manufacturing one. This project does write
  up its losses; that is rarer than it sounds and it is why the posture is not worse.

---

## Phase 5 — Load-Bearing and Uncited

1. **`scripts/parity-test.sh` holds up everything.** 264 assertions, 67 fixtures, and it is the only
   reason any claim about `gate-rules.sh` is checkable. It is also the artifact most likely to be
   treated as done. Its harness has the H1 hazard and nobody would notice if it regressed to silent
   passes. **Maintained by:** the sole maintainer, in the same sessions as feature work.
2. **`methodology/frontmatter-validate.py` is the quietest load-bearing thing here** — it backs two of
   eleven gate rules, and it is the component whose *reporting layer* has now produced two false
   statements (C7, and the prior audit's C4). Nothing tests the validator's own messages.
3. **What is transmitted by osmosis.** Several judgements this library depends on exist only in prose
   asides and one person's head: *trailing-slash gitignore patterns match directories only*; *a bare
   pattern excluding a directory makes every `!` negation inert*; *tab is IFS whitespace so consecutive
   tabs collapse*; *`stat -f` means something different on GNU*. Each of these has already caused a
   defect. Two are now pinned by fixtures. The rest are comments. **If the maintainer stops, the
   fixtures survive and the reasoning does not.**
4. **Freedom condition.** No structural punishment for honest status; the maintainer audits their own
   work adversarially and publishes the results. The risk here is the opposite one — a single reader
   who is also the author, with no second party to notice that "Fixed" was used twice for "disclosed."

---

## Phase 6 — The Verdict

### The one true sentence

> SSD's executable core is real and genuinely self-correcting — its own gate found a MAJOR in its own
> shipped code this week, all 264 parity assertions are well-formed, and `feynman-clean` provably FAILs
> on a failing report — but the documentation asserts an enforcement layer that does not exist: no gate
> rule checks any of the eight rails invariants, `rail_deviations:` has never once been written across
> 15 workstreams, `/ssd ship --force` is described as a logged override in four documents and
> implemented in none, rail step 2 has been skipped 13 times out of 13, and 5,124 lines of shell have
> never been linted.

### The single most likely self-deception

**That the gate enforces the rails.** It does not — it enforces eleven mechanical hygiene rules, not
one of which is a rails invariant. The belief is load-bearing: it is why a green gate reads as "this
feature walked the path," and it is why #41 and #43 both merged without a review while every check was
green and CI was passing.

**The observation that would settle it:** write one rule — *every feature directory containing a
deploy log must contain a review artifact with `gate_pass: true`* — and run it over the 13 existing
feature dirs. If it FAILs on features already archived as `done`, the belief was false the whole time.
That is a ~20-line rule and the data is already on disk.

**→ The rule was written and the experiment run the same day. Read § "Phase 8" before citing this
section: the prediction stated here was wrong, and the way it was wrong matters more than the finding.**

### Posture

```
⚠  DRIFTING
```

Not calibrated: six material claims are contradicted, and two of the six are *process* claims that
decisions rested on. Not self-deceiving: the machinery that catches this is real, it runs, it fired
three times this week, and several of the gaps are disclosed honestly in the ADRs rather than papered
over. The trend is one-directional in one specific way — **documentation describes enforcement that
implementation has not caught up to**, and each release adds more description than mechanism.

### What would change this verdict

- **Up to calibrated:** one rails-invariant gate rule shipped, `rail_deviations` written by something,
  and `--force` either implemented or struck from all four documents.
- **Down to self-deceiving:** a third rails invariant violated on a merge with no rule added — at which
  point the pattern is not lag, it is a belief maintained against evidence.

### Production is the referee

There is no production. A skills library's referee is **a project other than this one**, and no
evidence exists in-repo that any such project has ever run SSD. Every capability claim in this ledger —
including the ✅ ones — stands on internal evidence alone. The store (C15) is the sharpest case: it
shipped, it is tagged, it is installed, and it has never been used.

---

## Phase 7 — Lean Over Backwards

**What I did not examine.** See `not_examined`. The largest omission by far: **41,482 lines of markdown
are *instructions*, and no harness executes them.** Every claim about what `/ssd` "proposes" or
"never" does is unfalsifiable by command. I graded process claims where a script or artifact could
settle them and left the orchestrator's behaviour alone. A reader who takes this report as covering
"does SSD work" has over-read it; it covers "are the checkable claims true."

**What I could not run.** `shellcheck` (not installed — C10 is therefore graded on its own absence, the
one grade that is self-proving). A real `/ssd upgrade` against a downstream project. The store in
anger. Had I run shellcheck on 5,124 unlinted lines, my honest guess is a handful of MINORs and at
least one genuine quoting bug; that guess is not evidence and is not in the counters.

**Read vs executed.** 17 of 19 claims were graded by a command I ran and read. The two read-only grades
are C0 (the user's framing) and C15 (an absence — nothing to execute).

**Where I am most likely wrong.** C11 (systems-designer 💀). `phases.md` *does* sanction skipping it for
a markdown library, so the step is arguably correctly N/A rather than theatrical, and 💀 may be one
grade too harsh. The check that would settle it: does any deploy log's deviation entry ever cite a
*specific* production concern the step would have caught? I read three and found identical boilerplate,
which is what moved me to 💀 — but three is not thirteen.

**My own asymmetry.** Declared in Phase 4 and at H1: I hunted hardest where I had personally been
fooled, and the evidence exonerated the harness. I was softest on C16, my own hour-old claim. And I
graded my own C9b 🟠 only because C9's loop happened to print sixteen untagged versions — had I checked
only `v2.*`, as I did the first time, I would have left "unbroken end to end" standing.

**What scope forced me to ignore.** This is a release audit, not a milestone audit. I did not evaluate
architecture, and the 39 code-review artifacts were counted, not read — so "the reviews catch things"
rests on the three I watched catch something, in a session I was part of. A structural verdict is
`codebase-skeptic`'s job, and one lens of it runs alongside this report.

---

## Phase 8 — The experiment, run

Everything above was written before the rule existed. `rails-walked` shipped in v2.11.0 and was run
against **every VERSION-bumping commit in the library's history** — 25 releases, each in a detached
worktree, gate invoked for real.

| | |
|---|---|
| **FAIL** | **1** — `c445d08` (v2.10.0), `.ssd/features/ssd-store`, the case already known |
| PASS | 18 |
| SKIP | 6 — releases touching no `.ssd/features/` directory |

### The prediction was wrong, and this is the part worth reading

Phase 6 predicted *"FAILs on at least 2; more than 4 means the rails were never walked and the
deviation-recording ritual is the actual product."* The result is **one**, and it is the one that was
already on the record.

So C3 splits cleanly, and only one half survives:

- **The letter of the finding holds.** For eleven releases the gate ran eleven hygiene rules and
  checked **zero** rails invariants. That was true, it is now fixed, and it is why v2.10.0 shipped
  unreviewed with every light green.
- **The implication was false.** I wrote that the belief "the gate enforces the rails" was
  *load-bearing* and concealing something. It was concealing **one release out of nineteen.** Actual
  compliance was 18/19 — the rails were walked, consistently, by hand, for a year. The gap was in
  **checking**, not in **doing**, and an audit that cannot tell those apart is measuring its own
  suspicion.

### And it caught a false claim in the record — mine

Running the rule over #41 returned **PASS**. The sentence *"second occurrence in this epic (#41 was
the first)"* appears in `CHANGELOG.md` §2.10.1, in `ssd-store/04-code-review.md`, and in the first
draft of C3 above. It is unsupported: #41's touched feature dirs each carry a review with
`gate_pass: true`. Ledgered as **C18 🔴**.

Nobody checked it because it was *plausible and unflattering*, which is the direction this audit is
least equipped to doubt. Phase 4's asymmetry sweep looked for convenient claims let through; it did
not think to look for **inconvenient claims let through**, and a pessimistic error is still an error.

### What this changes about the proposal

It vindicates the mechanism and rebukes the framing. *Prefer a dumb rule that runs to a smart audit
that has to be trusted* — the rule found the audit wrong within an hour of existing, which is exactly
the argument for building rules instead of writing more reports. It also means the next audit should
run its experiments **before** writing its verdict, not after. This one had the order backwards, and
got away with it only because someone went and looked.
