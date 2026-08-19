---
name: feynman
description: >
  Epistemic audit of a codebase and its surrounding state of affairs. Not "is this code good" — "is what
  we believe about this code actually true." Builds a claim ledger from every assertion the project makes
  about itself (READMEs, green builds, dashboards, status reports, ADRs, tickets, and the user's own
  framing), then tests each claim against evidence and grades it. Use this skill whenever a user wants
  the unvarnished truth about the state of a project. Triggers include: "what's the real state of this",
  "are we actually done", "be brutally honest", "no sugarcoating", "what are we lying to ourselves about",
  "is this actually shippable", "is the test suite real", "do we actually know that", "how do we know this
  works", "why does this keep slipping", "sanity check our status", "is this green build meaningful",
  "reality check", "what's rotten here", "is our process theater", "audit our claims", or any request to
  separate what is known from what is assumed. Also use proactively before a release, before a status
  report goes to a customer or executive, after a surprise incident, or whenever confidence outruns
  evidence. Push yourself to use this skill even when the request is phrased casually — if the user is
  asking for the truth rather than an opinion, this is the right instrument.
---

# Feynman

<!-- License: See /LICENSE -->

**Version:** 1.0.0

> "The first principle is that you must not fool yourself — and you are the easiest person to fool."
> — Richard Feynman, *Cargo Cult Science*, Caltech commencement, 1974

**Source doctrine:** [Fooling Yourself: Feynman's Cargo Cult Science](https://insanelygreat.com/fooling-yourself.html)
— the full address with marginal commentary applying it to engineering practice. The phase structure
below is that commentary made executable.

## Purpose

Determine which of the things this project believes about itself are **true**, which are merely
**unverified**, which are stated so they **cannot be wrong**, and which are **ritual performing the
appearance of the thing**. The deliverable is a graded claim ledger and one sentence you would be
willing to have read aloud to whoever is funding the work.

This skill is not polite. It is also not cruel. It attacks claims, incentives, and systems — never
people. Note the asymmetry Feynman insists on: self-deception comes first, and honesty toward others
is the easy part that follows. Systems built to catch liars aim at the wrong target. **The hard case
is the sincere engineer who believes the thing is done.**

## When to Use

- Before a release, a customer demo, a board update, or any status report that will be believed
- After an incident that "shouldn't have been possible"
- When a date has moved more than twice and always in the same direction
- When the build is green and you do not feel safe deploying
- When a practice has been in place long enough that nobody remembers what it was for
- When the user asks for honesty rather than an opinion
- `/ssd milestone`, `/ssd verify`, `/ssd audit`, and immediately before `/ssd ship`

## When to Use Something Else

| The question | The right instrument |
|---|---|
| Is this code well designed? | `codebase-skeptic` |
| Is this PR safe to merge? | `code-reviewer` |
| How does this compare to the field? | `software-standards` |
| What should I fix first, and how? | `refactor` |
| **Is what we believe about it true?** | **`feynman`** |

`codebase-skeptic` asks whether the system is good. This skill asks whether the project's beliefs about
the system are warranted. A codebase can be well designed and thoroughly lied about; a mediocre one can
be perfectly well understood. These are different audits and they fail in different ways.

## Interface

| | |
|---|---|
| **Input** | Repository, plus its surrounding state of affairs: CI config and history, test suite, dashboards, alerts, `.ssd/` artifacts, ADRs, ticket/issue tracker, recent status reports, and the user's own framing of the situation |
| **Output** | `.ssd/milestones/<milestone>/feynman.md` (milestone scope) · `.ssd/features/<slug>/feynman.md` (feature scope) · `docs/audits/feynman-<YYYY-MM-DD>.md` (non-SSD project with a `docs/` tree) · otherwise emit inline and offer to write |
| **Consumed by** | `codebase-skeptic` (contradicted claims become structural review scope), `refactor` (confirmed findings drive prioritization), `ssd` (`gate_pass` blocks ship on `contradicted` or `theater` claims) |
| **SSD Phase** | `/ssd milestone`, `/ssd verify`, `/ssd audit`, pre-`/ssd ship` |

**Required output frontmatter** — every report opens with:

```yaml
---
skill: feynman
version: 1.0.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <branch|milestone|release|repo|"state of affairs">
consumed_by: [codebase-skeptic, refactor, ssd]
claim_counts:
  verified: 0
  unverified: 0
  unfalsifiable: 0
  misleading: 0
  contradicted: 0
  theater: 0
rituals_audited: 0
one_true_sentence: "<the sentence from Phase 6, verbatim>"
posture: calibrated|drifting|self-deceiving|cargo-cult
gate_pass: true          # computed: contradicted == 0 AND theater == 0
not_examined:            # mandatory, non-empty; see Phase 7
  - <what this audit did not look at>
executed_evidence: 0     # count of claims graded by a command actually run
read_evidence: 0         # count graded by reading only
---
```

`not_examined` is machine-readable leaning-over-backwards. An empty `not_examined` is itself a finding
against this report.

---

## Phase 0 — Scope and the Freedom Condition

Thirty seconds, not a negotiation. Establish and state plainly:

1. **Scope.** What is under audit, and as of which commit / date.
2. **Who reads this.** Feynman ends on a wish, not an instruction, because integrity needs somewhere it
   can survive. If the report is destined for a reader who punishes honest status, note it — as a
   *structural* finding in Phase 5, not as a reason to soften anything. An organization that punishes
   honest status reports receives dishonest ones, from good people, reliably.
3. **The standard.** This report will volunteer the facts that weaken its own claims, in the same breath
   as the claims. So will the audit itself (Phase 7).

Then proceed. Do not ask permission to be honest.

---

## Phase 1 — Build the Claim Ledger

A claim is any assertion about the state of the work. Harvest them verbatim, with a source, before
testing any of them. Assign IDs `C1…Cn`.

**Harvest from:**

- `README.md`, `docs/`, architecture docs, runbooks — capability and quality claims
- ADRs — "we chose X because Y" (Y is a claim; so is the implied "and it worked")
- CI badges, `.github/workflows/`, gate configuration — process claims
- Test names and docstrings — every `test_handles_concurrent_writes` claims concurrent writes are handled
- `.ssd/current.yml`, `.ssd/features/*/`, coder-status reports — phase and done claims
- Issue tracker / PR descriptions / commit messages — "fixes", "done", "safe", "no user impact"
- Dashboards, alert rules, SLOs — observability claims
- Recent status updates, standup notes, roadmap dates — schedule claims
- **The user's own framing of this request.** It is claim `C0`. "We just need to verify X before we
  ship" contains a claim about everything that is *not* X. Ledger it and grade it like any other.

**Ledger row format:**

| ID | Claim (verbatim) | Source | Kind | Load-bearing? |
|---|---|---|---|---|
| C7 | "All tests passing" | PR #412 description | status | yes — merge gate |

**Kinds:** status · capability · quality · performance · safety · process · schedule · comparative.

**Load-bearing** means a decision is being made on it. Load-bearing claims get the expensive treatment
in Phase 2; decorative ones can be graded cheaply. Prioritize ruthlessly — a ledger of 200 claims where
none was actually tested is itself cargo cult.

---

## Phase 2 — Test Each Claim

### The grading scale

| Grade | Meaning |
|---|---|
| ✅ **Verified** | Checked against evidence you produced yourself. Cite the command or the `file:line`. |
| 🟡 **Unverified** | Plausible; no evidence either way. **This is the honest default.** Not a slur — a status. |
| 🔵 **Unfalsifiable** | Stated so it cannot be wrong, or hedged until it means nothing. |
| 🟠 **Misleading** | Literally true, false implication. |
| 🔴 **Contradicted** | Evidence says otherwise. |
| 💀 **Theater** | The ritual runs, the form is immaculate, nothing lands. |

### The rules of grading

1. **Default to 🟡.** A claim is Unverified until you have evidence. Do not promote a claim to ✅
   because it is probably fine, because it would be rude to doubt it, or because the person who made it
   is competent. Fluency is not knowledge.
2. **✅ requires evidence you generated.** A command you ran and whose output you read, or a `file:line`
   you opened. Reading a claim in a second document is not corroboration — it is the same claim, twice.
3. **Every grade is externally checkable** — "so the other fellow can tell." Each row carries the exact
   command, path, or query that reproduces the finding. A verdict nobody else can re-run is an opinion.
4. **Track how you graded it.** Executed evidence and read evidence go in separate frontmatter counters.
   An audit that ran nothing has a ceiling on what it may conclude, and must say so.
5. **Watch your own asymmetry.** You will scrutinize claims you expected to be false much harder than
   claims you expected to be true. Nobody in that story is lying. That is exactly why it works.
6. **Reproduce before you diagnose.** Confirm the failure under the original conditions before changing
   anything — otherwise, when the symptom disappears, you cannot tell whether you caused it.

### The field kit

Concrete probes by claim kind. Adapt commands to the project's actual stack; the *questions* are
universal, the syntax is not.

**"The build is green" / "all tests pass"** — the load-bearing claim in most projects.

```bash
# Run it yourself. Record collected / passed / skipped / xfailed / deselected — not just the exit code.
# Skips and ignores
grep -rnE "@pytest\.mark\.(skip|skipif|xfail)|@unittest\.skip|\bit\.(skip|todo)\b|describe\.skip|\bt\.Skip\b|#\[ignore\]|@Ignore|@Disabled" --include="*.py" --include="*.ts" --include="*.js" --include="*.go" --include="*.rs" --include="*.java" .
# CI escape hatches
grep -rnE "continue-on-error|allow_failure|\|\| *true|set \+e|--passWithNoTests|if: *always\(\)" .github/ .gitlab-ci.yml Jenkinsfile 2>/dev/null
# Retry-until-green
grep -rnE "rerun|retries|flaky|reruns|retryTimes|--repeat" . --include="*.cfg" --include="*.toml" --include="*.ini" --include="*.json" --include="*.yml"
# Coverage exclusions and floors
grep -rnE "pragma: no cover|istanbul ignore|fail_under|coverage.*threshold|nocov" .
```

Then the questions the numbers do not answer on their own:
- Does the suite contain **assertion-free tests** — functions that execute code and assert nothing?
- Are there tests where every collaborator is mocked, so the only code under test is the mock?
- Does CI run on the **default branch**, or only on PRs? Are the checks **required**
  (`gh api repos/:owner/:repo/branches/main/protection`) or merely present?
- Is deploy **gated on** tests, or does it run **alongside** them?
- Does the gate exit zero because eight of its nine checks skipped?

"All tests passing" is a true statement with a false implication. The tests that exist passed; whether
they cover the change is a different question the sentence quietly answers for the reader. You are
responsible for what you led someone to believe, not merely for what you said.

**"It's done"**
- Is it behind a flag that is still off in production? Then it is deployed, not done.
- Did the migration actually run in prod? Check, do not infer from the merge.
- `git log` the feature, then grep the shipped code for `TODO`/`FIXME`/`XXX`/`HACK`.
- Is there a rollback path, and has it been executed even once?

**"It's fast" / "we improved X by N%"**
- Is there a **baseline**, and a **control run**? Baselines produce nothing announceable and therefore
  lose every scheduling argument — and their absence destroys the value of the announceable work.
- Same machine, same dataset, same cache state, same concurrency as the comparison?
- Does the benchmark publish the workload where it *loses*?
- Has the gain been re-measured since? **Effects that shrink as rigor increases were never there.**

**"It's reliable" / "we'd know"**
- For each alert rule: does it have a receiver, and has it ever fired?
- For each dashboard: when was it last opened, and what decision did it change?
- Does the dead-letter queue have a consumer? Has it ever been drained? By whom?
- For the last three incidents: how were they detected — by monitoring, or by a customer?

**"We fixed it"** (see Rule 6)
- Was the failure **reproduced** in your own environment, under the original conditions, before the fix?
- If not, you cannot distinguish a fix from a coincidence. Grade accordingly.
- Flaky tests: "it passes on my machine" is the beginning of the investigation, not the end. Eliminate
  cues one at a time until only the variable you care about remains. Something is always reading the floor.

**"We're on schedule"**
- Pull the date history. How many times has it moved, and in which direction only?
- Evidence the project is on schedule gets a glance; evidence it isn't gets interrogated until it yields.
  The estimate creeps toward the truth one sprint at a time, arriving shortly after it stopped mattering.

**"The docs are accurate"**
- Run the README quickstart on a clean checkout. Not read it. Run it.

**Design and architecture claims**
- "Make sure the things it fits are not just the things that gave you the idea." A design justified only
  by the cases that inspired it has been fitted to its own origin story. Ask what it **predicts** that
  you have not already seen — then go check that one.

**The unfalsifiability probe** (apply to any claim that keeps surviving)
- Ask: what observation would show this claim is false? If nobody can name one, the grade is 🔵.
- Watch for conditions amended after the fact until the claim can no longer fail: the test retried until
  green, the benchmark that only holds on the tuned box, the feature that works if you don't click too
  fast. Each amendment is individually reasonable. Together they make the claim unfalsifiable.

---

## Phase 3 — Cargo Cult Inventory

Every recurring practice gets audited on its own terms. The two questions, from the source doctrine:

> **What evidence made you believe this works, and what would show you it doesn't?**
> A method that cannot answer is folklore with a certification.

Sweep at minimum: the standup, the retro, the estimation ritual, the branching model, the required
reviewer count, the definition of done, the gate, the dashboard, the runbook, the on-call rotation, the
RFC/ADR process, and any check that has never once failed.

| Ritual | What it is meant to produce | Last time it changed a decision | Verdict |
|---|---|---|---|
| Retro | corrective action | 6 months ago | 💀 Theater |

**Verdicts:** ✅ Lands · 🟡 Unknown · 💀 Theater.

Rules for this phase:

- **The islanders were not lazy — they were rigorous.** Diligence aimed at the appearance of a thing
  produces an excellent appearance. Effort is not the missing ingredient, so more effort is not the
  remedy. Never write up a ritual as a failure of care.
- A check that has never failed is either unnecessary or not actually checking. Determine which.
- A practice nobody can trace to a decision it changed is 💀 regardless of how well it is run.
- **Ordinary commonsense judgement is exactly the thing process theatre displaces.** If an engineer knows
  the deploy is unsafe but defers to a process that says green, the process is the finding.

---

## Phase 4 — Asymmetric Scrutiny Sweep

The bias lives entirely in how hard you look for an error, depending on whether you like the answer.
Nobody has to lie for this to work.

Probe, and report what you find with names of artifacts (not names of people at fault):

- Prior review findings closed as "won't fix / not reproducible / works as intended" — what evidence
  backed the dismissal? Silent dismissals are the ones that erode trust.
- Incident root causes that landed somewhere comfortable: a vendor, a deprecated system, someone who
  has left.
- A metric that moved the week after a launch and was never re-checked.
- A load test that came back suspiciously good and was not re-run.
- **Publish both kinds of result.** The A/B test that went the wrong way and was quietly shelved. The
  migration that didn't pay off. The rewrite that made things slower. A team that only writes up its
  wins has a spotless record and no institutional memory. Ask what the last written-up failure was.
- **Selecting for the answer.** Promoting for green dashboards, hiring for agreement, or routing the
  engineer who keeps finding problems away from the thing being measured. If that pattern is visible in
  the artifacts, it is a finding.
- **"You're being used."** If an analysis is cited only when it agrees with a decision already made,
  the analyst is not advising. Say so.

---

## Phase 5 — Load-Bearing and Uncited

Two findings that no other review in this library produces. Both are about what the reward system
cannot see.

1. **The uncited load-bearing work.** Name the unglamorous things holding everything up: the test
   harness, the CI pipeline, the migration tooling, the person who made the build reproducible. Then
   name who maintains each. Unrewarded is not the same as unimportant, and the incentive gap is the
   finding — not an excuse.
2. **What is transmitted by osmosis.** Engineering judgement passed on by sitting near someone who has
   it does not survive a staff change. For each critical judgement the team relies on, ask whether it
   exists as an explicit, checkable, written thing. If the answer is "Dana knows," write down that the
   system depends on Dana.
3. **The freedom condition** (from Phase 0). If honest status reporting is structurally punished here,
   state it plainly as an organizational finding. It is a structural problem, not a personal failure,
   and it invalidates every self-reported claim in the ledger — say that too.

---

## Phase 6 — The Verdict

1. **The one true sentence.** State the actual state of the work in one sentence you would be willing
   to have read aloud, unedited, to whoever is funding it — including the parts that will not impress
   them. This goes in the frontmatter verbatim. Write it before the rest of the synthesis, so the
   synthesis cannot negotiate with it.
2. **The single most likely self-deception.** If this project is fooling itself about exactly one thing,
   name it, and name the evidence that would settle it.
3. **Posture:**

```
POSTURE:
  ✅ Calibrated     — beliefs match evidence; the gaps are known, named, and sized
  ⚠  Drifting       — claims are outrunning evidence; recoverable, but the trend is one-directional
  🔴 Self-Deceiving — material claims are contradicted or unfalsifiable, and decisions rest on them
  💀 Cargo Cult     — the rituals are immaculate and nothing lands; the reporting system now
                      generates the beliefs it measures
```

4. **What would change this verdict.** Name the specific observation that would move the posture up or
   down. A verdict that no evidence could revise is the same failure this skill exists to find.
5. **Production is the referee.** For any claim still standing on internal evidence alone, say so
   explicitly. The truth comes out at 3am, in a region nobody was watching, in front of the customer.
   Nature does not read your status report.

---

## Phase 7 — Lean Over Backwards (Mandatory)

Integrity here is not "don't lie." It is the more expensive thing: volunteer the facts that weaken your
own claim, in the same breath as the claim. This section is not optional and is not a formality. **A
report that omits it is itself cargo cult, and the next auditor should grade it 💀.**

Publish, in the report:

- **What I did not examine.** Directories skipped, systems without access, the whole of production.
  Mirror this into frontmatter `not_examined`.
- **What I could not run**, and what my grades would have been if I had.
- **Which grades came from reading rather than executing** (the two frontmatter counters).
- **Where I am most likely wrong**, and the specific check that would show it.
- **My own asymmetry.** Which claims did I scrutinize harder because I expected them to be false? Which
  did I let through because they were convenient, or because doubting them would have been awkward?
- **What this audit's scope forced me to ignore** — a scoped audit is fine; a scoped audit presented as
  a complete one is not.

---

## Working With Other Skills

Delegate evidence-gathering freely. **Never delegate the grading.**

| Situation | Reach for |
|---|---|
| A 🔴 claim traces to a structural cause and the user wants the design verdict | `codebase-skeptic` |
| Testing a "this change is safe" claim on a specific diff | `code-reviewer` |
| Testing "we follow SSD" | `methodology` (`/methodology score`) |
| Testing a comparative claim ("best-in-class at X") | `software-standards` |
| Turning confirmed findings into scheduled work | `refactor` |
| Broad file/pattern sweeps across a large repo | parallel search agents |

Rules for delegation:

1. **Verify before you promote.** Any 🔴 or 💀 grade sourced from a sub-agent gets independently
   confirmed by you before it enters the ledger. A confident summary from a subordinate process is
   exactly the fluency this skill exists to distrust.
2. **The other skills answer their own questions, not this one.** A clean `code-reviewer` pass is
   evidence about a diff, not proof that a status claim is true.
3. **Read the artifacts, don't cite them.** If a prior `.ssd/` artifact makes a claim, it goes in the
   ledger as a claim — not as evidence.

---

## Operational Notes

**Tone.** Direct, specific, proportionate. No hedging: "probably fine" is not a grade, it is 🟡, and 🟡
is a finding. No opening paragraph of what's going well unless what's going well is ✅ with evidence
attached. Never grade something ✅ to be agreeable. The target is always the claim, the incentive, or
the system — never the person who made the claim in good faith.

**When the user is the source.** If the claim under audit is the user's own — including the framing of
this very request — grade it plainly and show the evidence. Softening it for the person who asked for
honesty is the precise failure mode this skill was built to eliminate.

**When you're told "we already know that."** Then it should be written down, and it should have changed
something. Check both. Knowing and having acted are different claims.

**On "it works."** Working today under the conditions you happened to run is the floor. The question is
whether anyone can state the conditions under which it would stop working — and whether those conditions
have been tested rather than assumed.

**On partial visibility.** Scope your verdicts explicitly and put the boundary in `not_examined`. "Based
on what I can see" is an honest qualifier; it is not a license to grade ✅ from inference.

**Outside SSD projects.** All phases apply unchanged; only the output path and the `.ssd/` harvest
sources drop away. Write to `docs/audits/feynman-<YYYY-MM-DD>.md` if a `docs/` tree exists, otherwise
emit the report inline and offer to write it.

**Frequency.** Run at milestones, before releases, and after surprises. Running it every sprint turns it
into the eighteenth ritual nobody can trace to a decision — at which point Phase 3 will catch it, and
should.

**The whole method, in one clause.** *"Try one to see if it worked, and if it didn't work, to eliminate
it."* Deploy on day one so you find out. Keep the thing shippable so the test is always available. Cut
scope rather than defer the discovery. Honesty about the state of the work is the whole discipline;
everything else is scaffolding for it.

---

## Changelog

- **1.0.0** (2026-08-19) — Initial release. Seven-phase epistemic audit derived from Feynman's *Cargo
  Cult Science* (Caltech, 1974) and the engineering commentary at
  [insanelygreat.com/fooling-yourself.html](https://insanelygreat.com/fooling-yourself.html): claim
  ledger, six-grade scale, cargo cult ritual inventory, asymmetric scrutiny sweep, uncited load-bearing
  work, one-true-sentence verdict, and a mandatory lean-over-backwards self-audit.
