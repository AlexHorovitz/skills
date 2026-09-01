---
skill: feynman
version: 1.1.0
produced_at: 2026-09-01T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: repo @ 6ac7f92 (main, VERSION 2.11.0) + the published site @ ebe5aaa — post-v2.11.0
consumed_by: [codebase-skeptic, refactor, ssd]
claim_counts:
  verified: 8
  unverified: 1
  unfalsifiable: 0
  misleading: 3
  contradicted: 3
  theater: 1
rituals_audited: 8
one_true_sentence: "v2.11.0's five claimed closures are all real and all verified by execution — but this audit ran the experiments first and found a BLOCKER the release did not: diff_files() has never used -z, so git C-quotes any non-ASCII path and the leak detector that private mode's entire premise rests on returns PASS on a genuinely committed file, a control test confirms it (plain.md FAILs, café.md PASSes), it has been true since v1.5.0 across 27 releases, six of the gate's twelve rules inherit it, the class was already found and fixed in migrate.sh in this same epic and never swept, and I shipped rails-walked with the same hole six hours after fixing it next door."
posture: drifting
gate_pass: false
not_examined:
  - the 400+ lines of the published site I did not change (only the claims I edited were fact-checked)
  - whether any non-ASCII path exists in a real user's SSD tree — the defect is proven, its incidence is unknown
  - the other three scripts' quoting exposure beyond grepping for `-z` (store.sh, issue-sync.sh)
  - 41,482 lines of markdown as instructions — still no harness executes SKILL.md prose
  - whether any project other than this one has ever run SSD
  - the artifact store in real use
  - the 39 prior code-review artifacts' findings
  - releases before v1.17.0 (no VERSION file to key the rails-walked sweep on)
executed_evidence: 20
read_evidence: 1
---

# Feynman Audit — post-v2.11.0

**Scope.** `main` @ `6ac7f92`, VERSION 2.11.0, plus the site published at `ebe5aaa`. Roughly five
hours after the previous audit and about ninety minutes after the release that closed five of its
findings.

**Method note, and it is the one process change that mattered.** The previous audit wrote its verdict
and then ran its experiment, and the experiment contradicted the verdict. **This audit ran every
experiment before a word of the verdict was written.** The BLOCKER below is what that reordering
bought.

**Freedom condition.** Unchanged: the reader is the author and sole maintainer. One thing is different
and worse than last time — **the code under audit is code I wrote today, and one finding is a defect I
personally introduced hours after fixing the identical class next door.** Phase 7 says what that does
to this report's independence.

---

## The finding that matters

### 🔴 D1 — the leak detector returns PASS on a leaked file, if the filename is not ASCII

**Claim under test** (from `ssd/chapters/enforcement.md`, `guide.html`, and ADR-0017): *under
`private` mode `no-leaky-state` "is the primary enforcement of the privacy boundary."*

**Control test.** Same repo, same policy path, same force-add, same commit. Only the filename differs:

```
.ssd/archive/plain.md   →  FAIL no-leaky-state :: 1 file(s) gitignored by policy but tracked
.ssd/archive/café.md    →  PASS no-leaky-state :: no gitignored-by-policy files in diff
                           git's own view of that diff: ".ssd/archive/caf\303\251.md"
                           git ls-tree HEAD: the file IS tracked. It leaked.
```

**Cause.** `diff_files()` runs `git diff --name-only` **without `-z`**. Git C-quotes any path with
non-ASCII bytes, wrapping it in `"` and octal-escaping it. Every downstream path comparison then
misses: the quoted string does not match `.ssd/archive/`, does not match `^\.ssd/features/`, does not
match anything.

**Blast radius — six of the gate's twelve rules read `diff_files()`:**

| Rule | Effect |
|---|---|
| `no-leaky-state` | **proven blind.** The privacy boundary. Worst case in the set |
| `rails-walked` | **proven blind** — see D2 |
| `frontmatter-valid` | partially blind: in a mixed diff it validated the ASCII artifact and silently skipped the accented one. In an accented-*only* diff it is rescued by the private-mode tree-walk fallback — correct by accident, not by design |
| `feature-flag-present` · `adr-delta` · `feynman-clean` | same input, unaudited for this |

**Age.** `git log -S` puts the un-`-z`'d call in **`ee3b897`, v1.5.0, 2026-04-29** — the commit that
made the gate executable. **27 releases.** It is not a v2.11.0 regression; v2.11.0 is where it was
finally looked for.

**The part that is actually damning.** This exact class was found, reproduced, and fixed **in this same
epic**: iteration B's code review, MAJOR-1, *"`git ls-files` C-quotes unusual paths."* The fix was
`-z`. It went into `migrate.sh` and nowhere else:

```
migrate.sh          uses -z:  1
gate-rules.sh       uses -z:  0        ← 6 rules
store.sh            uses -z:  0
issue-sync.sh       uses -z:  0
```

There is even a **non-ASCII fixture in this repo** (`elect-handles-unusual-filenames`) proving the team
knew the class was real. It was never pointed at the gate.

---

## Phase 1–2 — The Claim Ledger

Prior-audit claims are cited as **C**n; this audit's as **D**n.

| ID | Claim (verbatim) | Source | Grade | Evidence |
|---|---|---|---|---|
| D0 | "run another Feynman audit now" | user, this session | 🟠 | Defensible — a release shipped, and "before/after a release" is a named trigger. But **this is substantially a verification pass, not a fresh sweep**: 8 of 18 claims are re-tests of the previous audit's closures, and five hours ago I advised waiting for Track A2 rather than running on a cadence. Calling it "another audit" overstates its independence. It earned its keep anyway — it found D1 |
| D1 | `no-leaky-state` is "the primary enforcement of the privacy boundary" | enforcement.md · guide.html · ADR-0017 | 🔴 | Control test above. Identical policy, ASCII FAILs, accented PASSes, file tracked |
| D2 | "`rails-walked` closes rails invariant 4" | CHANGELOG 2.11.0 · enforcement.md · **the site, published today** | 🟠 | True for ASCII, and the 25-release sweep stands. But a release with an accented feature dir and **zero** reviews returns `SKIP rails-walked :: release touches no .ssd/features/ directory` — a reassuring message for a check that did not run. Shipped by me, six hours after I fixed the same class in `migrate.sh` |
| D3 | iteration B MAJOR-1 "the `git ls-files` C-quoting defect" was fixed | `.ssd/features/ssd-private-mode/iterations/b/code-review/round-1.md` | 🟠 → ✅ | Graded 🟠 on a grep for `-z` and **the grep overstated it.** A real sweep (§ Phase 8) found the library enumerates git paths in exactly **two** places: `migrate.sh` (already fixed) and `diff_files()` (the defect). `store.sh` and `issue-sync.sh` never enumerate paths at all, and `gate-rules.sh:697` passes a literal ASCII path. The *finding* was real — one of two enumerators was blind — but "three other scripts unswept" was my inference, not a measurement. Closed with the correction on the record |
| D4 | "Parity 281/281" | CHANGELOG · coder-status | ✅ | Ran it. 281/281, exit 0 |
| D5 | "shellcheck 0 findings" | CHANGELOG 2.11.0 | ✅ | `shellcheck -S warning methodology/*.sh scripts/*.sh` → clean |
| D6 | C10 is "closed durably, not locally" by the CI job | feynman.md Phase 9 · CHANGELOG | 🟡 | The job has run **once** and passed. It demonstrably executes (8s on ubuntu), so not theater — but one opportunity cannot distinguish a guard from a decoration, which is this skill's own standing rule |
| D7 | "the install is current" | my report, ~2h ago | ✅ | `~/.claude/skills` and the repo are both `6ac7f92` / VERSION 2.11.0. Exact match |
| D8 | C5's regrade — the CI gate can fail | feynman.md Phase 9 | ✅ | Re-verified: **2 failures** in 69 runs now, both `feynman-clean` on PR #46 |
| D9 | C7 closed — the false "no artifacts in scope" message, plus schemas | CHANGELOG 2.11.0 | ✅ | `elif` branch present; whole-tree validation 98 PASS / 10 SKIP, exit 0. **Note the treadmill:** SKIPs went 8 → 10, because this audit's own `refactor-plan.md` and `review-*.md` have no schema. Closing two classes created two more |
| D10 | C4 fully closed, including the public site | my report, ~1h ago | ✅ | Live `curl` of guide.html: the correction present, the old *"is logged and leaves a durable trace"* string **0 occurrences**. tutorial.html carries "There is no `--force` flag" |
| D11 | "every skipped step appears in `rail_deviations:`" | `ssd/rails.md` | 🔴 | Carried from C2, re-verified: **0** writers in any script (the single grep hit is a fixture's YAML *input*), **0** fields across 15 workstreams, and rails.md still promises it. The last of the three conditions for `calibrated` |
| D12 | "no branch protection is required, **by design**" | `.github/workflows/quality.yml:7` | 🔴 | Carried from C6, re-verified: ruleset `Overwatch`, `enforcement=active`, all branches, requires PR + signatures |
| D13 | the `core.md` §4 ratchet, "tag every release" | `ssd/chapters/phases.md:320` | 🔴 | Carried from C9 (16 of 30 releases untagged) **and worse than C9 said**: `phases.md` puts *"tag every release"* in quotation marks and attributes it to `core.md` §4. `grep -cwi tag methodology/core.md` → **0**. §4 is the Ratchet Principle — tests, types, lint. The whole tagging obligation cites a line that does not exist |
| D14 | "Second occurrence in this epic (#41 was the first)" | CHANGELOG 2.10.1 · ssd-store review · deploy log · current.yml | 🟠 | Partially closed. The CHANGELOG's 2.11.0 entry annotates it, so a forward reader sees the correction. It still stands **uncorrected** in `ssd-store/04-code-review.md:28`, `05-deploy.md:98`, and `current.yml:45` — anyone landing on the review gets the falsified claim straight |
| D15 | `rails-walked` passes on the v2.11.0 release itself | — | ✅ | `--base v2.10.1` → `PASS :: 3 feature dir(s)`. (The prior audit's claim that it would SKIP on its own PR was already corrected in-flight) |
| D16 | the site's new factual claims | guide.html · index.html | ✅ | Spot-checked against the library: 7 schemas, the five store verbs, `link`'s exit 10, store requires private-or-blanket, and "rails invariant 4" really is *"at least one code review with `gate_pass: true`"* in rails.md's guarantee list. **Caveat:** the site now also publishes D2, which is 🟠 |
| D17 | Rail step 2, "**Production check** — invoke `systems-designer`" | phases.md · rails.md | 💀 | Carried from C11, unchanged: `find .ssd -name '*systems-designer*'` → **0**, now across **13** feature dirs. No `rails-*.md` fork exists; `project.yml` still points at `rails.md`. The remedy rails.md itself documents was not taken |

---

## Phase 3 — Cargo Cult Inventory (the eight that changed or are newly testable)

| Ritual | Last time it changed a decision | Verdict |
|---|---|---|
| `/ssd gate` | v2.11.0's own manifest ordering mistake, caught by `migration-manifest-current` | ✅ Lands |
| Code review | **it did not, this time.** Round 1 of v2.11.0 returned `gate_pass: true` on code carrying D1/D2 | 🟡 see below |
| The Feynman audit | **twice in six hours** — see below | 🟡 at risk |
| `shellcheck` CI job | one run, passed | 🟡 Unknown |
| `rails-walked` | fired in fixtures and on the historical sweep; never yet in anger on a live PR | 🟡 Unknown |
| `lint_results` frontmatter | was 💀; now records a real linter with a real exit 0 | ✅ Closed |
| `rail_deviations` field | never written, 15 workstreams | 💀 (= D11) |
| systems-designer / rail step 2 | never, 13 features | 💀 (= D17) |

**The code review is the interesting one.** Its "What I checked hardest" table lists **seven**
adversarial probes against `rule_rails_walked` — a `feynman.md` with `gate_pass: true`, a deleted
feature dir, an empty array under `set -u`, `grep -qx` versus `docs/VERSION.md`. Non-ASCII paths is not
among them, **in a repo whose own epic had already produced a MAJOR of exactly that class**. The ritual
runs, and it runs well; what it lacks is a probe list **derived from the project's own defect history**.
That is a cheap, mechanical fix, and it is a better lesson than "review harder."

**And this audit is now the eighteenth-ritual risk its own skill warns about.** Two runs, five hours
apart, the second largely re-testing the first. The § "Frequency" rule is explicit that this is the
failure mode Phase 3 exists to catch. It is graded 🟠 as D0 rather than excused. **It found a BLOCKER,
so it paid for itself — but "it worked this time" is exactly the argument that turns a check into a
ceremony.** The next one waits for Track A2 or a surprise.

---

## Phase 4 — Asymmetric Scrutiny Sweep

- **The direction of my scrutiny was self-serving, and I want it on the record.** I went hunting in
  code I had written that day and found a defect. That is a *flattering* discovery for an auditor and an
  *unflattering* result for the engineer — and I am both. The finding is real and control-tested; the
  incentive to go looking there rather than somewhere less legible is not neutral.
- **What I did not attack.** The 400+ lines of the published site I did not edit. I fact-checked only
  the claims I changed, which is the smaller and easier set.
- **A convenient claim I let stand until forced.** D6 (the shellcheck CI job "closes C10 durably") is
  mine, from ninety minutes ago, and one green run is not durability. Graded 🟡 only because the
  standing rule about never-failed checks made it awkward to grade otherwise.
- **The comfortable landing that has now moved.** C10's five artifacts blamed "a pre-existing
  environment gap." The real answer was a 30-second install. The same shape appears in D3: a defect got
  attributed to *a function* when it belonged to *a class*, and the narrower attribution was the one
  that required no further work.
- **Published losses, credited.** v2.11.0's CHANGELOG voluntarily records that the audit's own
  prediction was wrong (18/19 compliance, not the ≥2 failures predicted), and that three documents in
  that release asserted an unchecked claim about the rule they were describing. Writing that down when
  nobody would have noticed is the single strongest signal in this report.

---

## Phase 5 — Load-Bearing and Uncited

1. **`diff_files()` is the most load-bearing eleven lines in the library, and nothing tests it.**
   Six of twelve gate rules read it. `grep -c diff_files scripts/parity-test.sh` → **0**. Two hundred
   and eighty-one assertions, none of them on the function every diff-scoped rule depends on. That is
   how a defect survives 27 releases.
2. **The non-ASCII fixture is uncited institutional memory.** `elect-handles-unusual-filenames` exists,
   passes, and encodes a lesson learned the expensive way. Nothing connects it to the six other places
   the lesson applies. Knowledge in a fixture is only as broad as the fixture's target.
3. **Transmitted by osmosis, updated.** Add to the prior list: *`git diff`/`ls-files` C-quote non-ASCII
   paths unless you pass `-z`.* It has now caused **two** defects in one epic. After this it should
   exist as a fixture against `diff_files`, not as a sentence in a review nobody re-reads.

---

## Phase 6 — The Verdict

### The one true sentence

> v2.11.0's five claimed closures are all real and all verified by execution — but this audit ran the
> experiments first and found a BLOCKER the release did not: `diff_files()` has never used `-z`, so git
> C-quotes any non-ASCII path and the leak detector that private mode's entire premise rests on returns
> PASS on a genuinely committed file, a control test confirms it (`plain.md` FAILs, `café.md` PASSes),
> it has been true since v1.5.0 across 27 releases, six of the gate's twelve rules inherit it, the class
> was already found and fixed in `migrate.sh` in this same epic and never swept, and I shipped
> `rails-walked` with the same hole six hours after fixing it next door.

### The single most likely self-deception

**That a defect found and fixed once is fixed.** This project reliably fixes the *instance* and
reliably fails to sweep the *class*. Three data points, all inside two weeks:

1. `-z` went into `migrate.sh` and nowhere else — 1 of 4 scripts (D3).
2. The 2026-08-19 audit's C4 remediation fixed the `count > 0` branch and left `count == 0` asserting
   something false, which survived four releases as C7.
3. `rails-walked` shipped with a defect I had personally fixed elsewhere the same day.

**The observation that would settle it:** for each of the last five closed findings, grep the whole
library for the pattern the fix addressed. If the fix appears in exactly one file each time, the
diagnosis holds and the remedy is a sweep step in the review checklist — not more care.

### Posture

```
⚠  DRIFTING
```

Same grade as the previous audit, **different failure mode, and the change of mode is the news.** Last
time documentation had outrun implementation. Documentation has now caught up: five findings closed,
each verified by execution, the false `--force` claim struck from all five publications including the
public site. What is drifting now is **implementation hygiene** — a known defect class left unswept
across three scripts and six rules, and reproduced by the person who fixed it.

Not `self-deceiving`, on two grounds worth stating rather than assuming: the defect was found the first
time anyone looked for it, using the project's own instrument, and nothing was concealing it. Not
`calibrated`, because a documented enforcement boundary demonstrably does not enforce.

### What would change this verdict

- **Up to calibrated:** `-z` swept across all four scripts with a fixture pinning `diff_files` against
  a non-ASCII path, **plus** `rail_deviations:` written by something (D11 — still the last of the
  previous audit's three conditions).
- **Down to self-deceiving:** another release ships without sweeping the class, now that it is named,
  measured, and recorded here.

### Production is the referee

Still no production, and D1 sharpens what that costs. The defect is **proven**; its **incidence is
unknown**, because exactly one SSD project exists and its filenames are ASCII. A second project in a
non-English codebase would have found this in a week. Every severity estimate in this report is an
argument, not a measurement.

---

## Phase 7 — Lean Over Backwards

**What I did not examine.** See `not_examined`. The two that most limit this report: the site's
unedited content, and whether `store.sh` / `issue-sync.sh` are *actually* exposed to the quoting bug
rather than merely lacking `-z` — I grepped, I did not test them.

**What I could not run.** Any test of incidence. Any test of the orchestrator's prose behaviour.

**Read vs executed.** 17 of 18 claims graded by a command I ran and read; D0 (the framing) is the sole
read-only grade.

**Where I am most likely wrong.** D1's *severity*. I have called it a BLOCKER on the strength of a
control test plus documentation calling `no-leaky-state` the primary privacy enforcement. The check
that would move it: does any real SSD user have a non-ASCII path under `.ssd/` or the three `docs/`
trees? If the honest answer for every existing project is no, this is a latent BLOCKER, not an active
one — and the label should say so. I have not been able to test that, and n=1 says the likely answer is
"not here."

**My own asymmetry.** Declared in Phase 4 and I will not soften it: I audited my own fresh code, which
is where I was most motivated to look impressive, and I did not audit the site prose, which is where I
would have looked careless. I also graded my own ninety-minute-old claim 🟡 rather than ✅ only because
a standing rule made ✅ indefensible, not because I arrived at 🟡 on my own.

**What scope forced me to ignore.** This is a release-verification audit wearing a fresh audit's name —
D0 says so. Eight of eighteen claims are re-tests. A genuinely independent sweep would have
re-interrogated the claims the previous audit graded ✅ and I largely took forward.

**And one structural problem no phase of this skill can fix.** Author, implementer, reviewer and auditor
are the same party, in one session, hours apart. The round-1 review that returned `gate_pass: true` on
code containing D1 was written by me, about my code, four hours ago. That is the argument for
`rails-walked` and for a `diff_files` fixture over any amount of further auditing: **a rule does not
care who wrote the code it is checking.**

---

## Phase 8 — D1 closed, and the sweep the audit itself failed to do

Written after the fix, on branch `fix-diff-files-quotepath` (v2.11.1).

### The fix is one line, not six

The audit assumed `-z` — the shape of `migrate.sh`'s fix. Tested first, and it was the wrong shape:

```
plain --name-only          ".ssd/features/caf\303\251.md"
-c core.quotepath=false     .ssd/features/café.md         ← also space, apostrophe, umlaut
-z                          .ssd/features/café.md         ← same result, 6 consumer rewrites
```

`-z` changes `diff_files()`'s contract from newline- to NUL-delimited and forces all six consumers to
move together. `core.quotepath=false` changes nothing but the two git invocations. Taken, with the
**residual recorded in the function**: a path containing a literal newline still breaks a
newline-delimited pipeline, and `-z` would survive that. A newline in a path under `.ssd/` is
pathological; an accent is a Tuesday in a French codebase.

### The sweep, and it shrank D3

The audit graded D3 🟠 on `grep -c '\-z'` across four scripts. That grep measured *the absence of a
flag*, not *the presence of an exposure*. The real sweep — every place the library enumerates paths out
of git:

| Site | Exposed? |
|---|---|
| `gate-rules.sh:300,302` (`diff_files`) | **yes — the defect.** Now fixed |
| `migrate.sh:488` (`ls-files -z`) | no, fixed in iteration B |
| `gate-rules.sh:697` (`ls-files --error-unmatch .ssd`) | no — a literal ASCII path, exit status only |
| `store.sh`, `issue-sync.sh` | **no — neither enumerates paths at all** |
| `frontmatter-validate.py` | no — filesystem walk, never git |

So the exposure was **one of two enumerators**, not "three unswept scripts." D3 regraded ✅ with that
correction stated rather than quietly dropped. The audit was right that the class was under-swept and
wrong about how far it spread — and it was wrong in the direction that made the finding sound worse,
which Phase 4 named as the harder bias to catch.

### Verification

| | |
|---|---|
| Red first | **5 assertions failed** against the unfixed enumerator |
| Green | **291/291**, exit 0 (was 281; +10) |
| Reversion | stripping the flag re-fails exactly those 5 |
| Live control | outside the fixture: `FAIL no-leaky-state :: 1 file(s) gitignored by policy but tracked: .ssd/archive/café.md` |
| shellcheck | 0 findings |

**One assertion passed for the wrong reason on the first red run,** and it is worth recording because
it is the suite's recurring defect: *"an ACCENTED policy-ignored file is caught too"* passed while the
ASCII control was still in the diff, because the rule FAILed on the control. The fixture now removes
the control from the index first, and asserts that it is gone. Caught on the red run, not by review.

### The process fix, which matters more than the one-liner

`code-reviewer` Phase 3.5 gains **step 8 — "Was the CLASS swept, or only the instance?"** Before
accepting a fix as closed, grep the project for the pattern. Three findings in two weeks were closed at
the wrong granularity, and in each case the reviewer read the diff carefully and the diff was not where
the rest of the defect lived. Step 8 also says to derive the adversarial probe list from *this
project's* defect history — round 1 of v2.11.0 ran seven probes against a new rule and non-ASCII paths
was not one, in a repo whose own epic had produced a MAJOR of exactly that class.

### Still open after this

**D11** (`rail_deviations` never written — the last `calibrated` condition), **D12** (workflow header vs
the `Overwatch` ruleset), **D13** (16 untagged releases, and a `core.md` §4 citation to a line that does
not exist), **D17** 💀 (rail step 2, 0 of 13). Each needs its own change and two of them need a decision
that is not mine.
