---
skill: feynman
version: 1.0.0
produced_at: 2026-08-19T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: repo @ 487e10c (branch add-ssd-init-gate-readiness, VERSION 2.5.0)
consumed_by: [codebase-skeptic, refactor, ssd]
claim_counts:
  verified: 4
  unverified: 2
  unfalsifiable: 1
  misleading: 3
  contradicted: 4
  theater: 1
rituals_audited: 8
one_true_sentence: "The toolkit's executable core is real and independently verified — 69 parity assertions pass, the gate genuinely fails when it should, and the v2.5.0 detection fix works exactly as its commit message claims — but the library does not run its own methodology on itself: it carries no project.yml, its own gate skips five of nine checks, and the headline v2.5.0 fix was shipped to downstream projects without ever being applied here."
posture: drifting
gate_pass: false
not_examined:
  - the prose bodies of all 11 SKILL.md files as instructions (no harness exists to execute them)
  - ssd-init Step 6.5 as executed by an LLM (prose, not script — unfalsifiable by any command)
  - the 34,814 lines of markdown for internal contradiction beyond the claims sampled
  - GitHub Actions runs older than the 40 most recent
  - docs/decisions/ ADR bodies (read only ADR-0015 references via CHANGELOG/migrations)
  - architect/ platform guides, methodology/core.md, patterns.md, adoption.md
  - whether any downstream project has ever consumed this library
executed_evidence: 12
read_evidence: 2
---

# Feynman Audit — SSD Skills Library

**Scope.** `/Users/ahorovit/.claude/skills` @ `487e10c`, branch `add-ssd-init-gate-readiness`,
library `VERSION` 2.5.0, audited 2026-08-19.

**Freedom condition.** The reader is the author and sole maintainer. There is no organizational
pressure to soften this report, and therefore no excuse for softening it.

---

## Phase 1–2 — The Claim Ledger

| ID | Claim (verbatim) | Source | Grade | Evidence (re-runnable) |
|---|---|---|---|---|
| C0 | "run the skill against the current SSD toolkit" | user, this session | 🟡 | The skill was authored ~40 min before it was run. It has no track record; this is its first execution. Nothing about it has been validated except that its four field-kit greps exit 0. |
| C1 | "this repo tracks its own SSD artifacts … Read the history of how the methodology was built using the methodology itself" | `README.md:14` | 🟠 | 84 artifacts are genuinely committed (`git ls-files .ssd \| wc -l` → 84). But `.ssd/project.yml` and `.ssd/current.yml` are **absent**, and `ssd/SKILL.md:26` says `/ssd` must "refuse to proceed" without project.yml. The record is real; the live loop is not runnable in its own repo. |
| C2 | "`ssd-init` now leaves the gate **functional, not merely present.** Before this change … `/ssd gate` SKIPped `tests-pass` and `feature-flag-present` in *every* project" | `CHANGELOG.md` §2.5.0 | 🔴 | `bash methodology/gate-rules.sh --base origin/main` on the branch that shipped this fix still emits `SKIP tests-pass` and `SKIP feature-flag-present`. The repo is still in the "before" state the entry describes as fixed. |
| C3 | "`.ssd/gate.yml` is the *only* committed `.ssd/*` config file (the `!.ssd/gate.yml` exception is in `methodology/selective.gitignore`)" | `ssd-init/SKILL.md:399` | 🔴 | `.ssd/gate.yml` does not exist here, and `grep -n gate.yml .gitignore` → no match. The template has the negation (`methodology/selective.gitignore:10`); the repo's own `.gitignore` never received it. `git check-ignore .ssd/gate.yml` → IGNORED. The file could not be committed here even if written. |
| C4 | "PASS frontmatter-valid :: 51 artifact(s) validated against schemas" | gate output | 🟠 | 84 tracked `.ssd/**/*.md`, **all 84 carry frontmatter**; only 4 schemas exist (`methodology/schemas/`). 33 artifacts (39%) — every brief, deploy note, skeptic report, refactor plan, verification — pass through unvalidated and unmentioned. The line reads as coverage; it is a subset. |
| C5 | "PASS skill-version-sync :: 9 skill example(s) match banner" | gate output | 🟠 | 11 `SKILL.md` files exist. `python3 methodology/frontmatter-validate.py --check-skill-examples .` shows 9 PASS and **2 SKIP** — `methodology/SKILL.md` and `ssd/SKILL.md`. The orchestrator, the most load-bearing skill in the library, is structurally exempt from the version check, and the gate's one-line summary does not say so. |
| C6 | "`/codebase-skeptic` \| Deep architectural critique through **10 expert lenses**" | `README.md:140` | 🔴 | `codebase-skeptic/SKILL.md` has said **fifteen** since v1.5.0 (2026-07-20) — lines 10, 22, 30, 106, 278. The README was not updated with the skill. One month of drift on the public-facing description. |
| C7 | "A skill's `**Version:**` banner tracks the **library** version *at the point this skill last changed*" (banner-lag) | `ssd/SKILL.md:7-11` | ✅ | `git log --oneline -5 -- ssd/SKILL.md` → last touched in `9992e34 … (v2.4.0)`. Banner reads 2.4.0. The doctrine is falsifiable and it holds. |
| C8 | The gate is executable enforcement, not an LLM vibe check (ADR-0005/0006) | `.github/workflows/quality.yml` header | ✅ | Built a synthetic repo with a deliberate `WIP:` commit and ran `gate-rules.sh --base main` → `FAIL wip-commits :: 1 commit(s) match WIP/checkpoint patterns`. The gate genuinely fails when it should. |
| C9 | "Either job failing surfaces a red check on the PR … this REPORTS — it does not hard-block the merge (no branch protection is required, by design)" | `quality.yml:6-9` | 🔵 | `gh run list --limit 40` → **40 of 40 `success`. Zero failures, ever.** Combined with warnings-not-walls and no branch protection, no observation distinguishes "the CI gate protects this repo" from "the CI gate is decorative." The claim cannot be wrong, which is why it needs a different kind of evidence. |
| C10 | "PASS — 69/69 assertions" across 27 fixtures | `scripts/parity-test.sh` | ✅ | Ran it. 69/69, exit 0. Fixtures include **negative** cases (`wip-commit-fails`, `missing-flag-fails`, `frontmatter-invalid`, `skill-version-drift`) — it asserts the gate fails when it should, not merely that it runs. This is the strongest artifact in the repo. |
| C11 | "Verified: `Cargo.toml` + `tests/` → `cargo test`; `pyproject.toml` → `pytest`" | commit `a7fed6f` | ✅ | Executed `migrate.sh --from 2.4.0 --apply` against five synthetic projects, each with a `tests/` dir: rust→`cargo test`, python→`pytest`, go→`go test ./...`, makefile→`make test`, npm→`npm test`. The commit message is exactly true. |
| C12 | The selective `.gitignore` allow-list implements ADR-0008 selective commit | `.gitignore:14-27` | 💀 | `.ssd/*` matches only depth-1 children. Once `!.ssd/features/` re-includes the directory, **everything beneath it is committable regardless of the allow-list**. Verified: `git check-ignore` says `.ssd/features/foo/secrets.env` and `.ssd/milestones/m/anything.txt` are COMMITTABLE. **And it has already been bypassed in this repo's own history** — `git log --diff-filter=A --name-only -- .ssd/` shows `review-r1.md`, `review-r3-r4.md`, `review-r5-r8.md` committed under `milestones/` though no allow-list entry covers them. The 12 per-file `!` lines constrain nothing. The real protection is the 5 explicit *deny* lines. |
| C14 | `code-reviewer` output path `.ssd/milestones/<milestone>/review-<pr>.md` | `code-reviewer/SKILL.md:21` | 🔴 | `methodology/selective.gitignore` has **no `review-*.md` entry** for milestones (only `features/**/04-code-review*.md` and `iterations/**/code-review/round-*.md`). The declared output path is not in the commit contract. Those three artifacts are tracked **only because C12's allow-list is inert** — one bug is silently compensating for another. **Fixing the gitignore would break the code-reviewer contract.** |
| C13 | "Iters B (library-root resolution + hook fix), C (Step 9 gate-readiness reporting), and D (workflow-rule docs + CI validator vendoring) remain pending." | `CHANGELOG.md` §2.5.0 | 🟡 | Iter A shipped 2026-08-06/07; 13 days elapsed. No date was ever promised for B–D, and one interval is not a trend. Insufficient evidence for a slippage finding — recorded so the next audit has a baseline. |

**Totals:** ✅ 4 · 🟡 2 · 🔵 1 · 🟠 3 · 🔴 4 · 💀 1

---

## Phase 3 — Cargo Cult Inventory

The islanders were not lazy. Everything below is meticulously built; the question is only what lands.

| Ritual | Meant to produce | Last time it changed a decision | Verdict |
|---|---|---|---|
| `parity-test.sh` (27 fixtures, 69 assertions) | proof the gate's logic is correct | continuously — negative fixtures encode past bugs | ✅ Lands |
| `/ssd gate` run locally by the agent | findings that block a merge | **round 1 of the current feature** — caught MAJOR-1 pytest misdetection, fixed in `a7fed6f` | ✅ Lands |
| `quality.yml` CI job | a red check on the PR | **never** — 40/40 green, no branch protection | 🟡 Unknown |
| ADR process (15 ADRs) | traceable decisions | ADR-0015 → migrations → executable `detect()`/`apply_*()` | ✅ Lands |
| Committed `.ssd/` artifact trail (84 files) | institutional memory | ADR-0010's reversal is preserved in the record (README:19) — a *published negative result* | ✅ Lands |
| Selective `.gitignore` allow-list | prevent machine state leaking into commits | never — it is inert at depth (C12) | 💀 Theater |
| `pre-commit-no-leaky-state.sh` | catch leaks before push | never in this repo — `.git/hooks/` contains only samples | 🟡 Unknown (explicitly opt-in per `hooks/README.md`; no false claim made) |
| Frontmatter schema validation | machine-checked artifact contracts | on the 61% that has a schema | ✅ Lands, partially |

**A check that has never failed is either unnecessary or not actually checking.** For the CI job the
answer is neither — it is *untested*. The local gate has failed and caught a real MAJOR; the CI job
has never been exercised in anger, so its value is asserted rather than demonstrated.

---

## Phase 4 — Asymmetric Scrutiny Sweep

**What survives scrutiny.** The round-1 → round-2 record on `ssd-init-gate-readiness` is the opposite
of asymmetric: a MAJOR was found, the failure trace was written out in full (`04-code-review.md`), the
fix was verified across project types, and the review artifact was committed *including* the finding
that had to be fixed. `README.md:19` keeps the ADR-0010 profile-audit reversal visible with the note
"*Later removed wholesale by SSD 2.0 — the dogfood record keeps the reversal honest.*" **That is
publishing both kinds of result, and it is rare.** Credit where it is earned.

**Where the asymmetry actually lives.** Not in the reviews — in what gets *measured*. Every gate
summary line reports its successes as a count (`51 artifact(s)`, `9 skill example(s)`) and its
omissions as nothing at all. The SKIPs are printed by the underlying validator but do not survive into
the gate's one-line summary. Nobody chose to hide them; the reporting format simply has a slot for
what passed and no slot for what was never looked at. That is how Millikan's electron drifted.

**The dismissal that was never written down.** `ssd-init` Step 6.5 is prose instructing an LLM to
detect a test command. `migrate.sh` is bash doing the same detection. Only the bash half has a
parity fixture. The prose half — the path a *new* project actually takes — has no test and no
recorded decision that it should not have one.

---

## Phase 5 — Load-Bearing and Uncited

1. **`scripts/parity-test.sh` and `methodology/gate-rules.sh` are the library.** 2,797 lines of
   executable bash/python hold up 34,814 lines of markdown — a 1:12 ratio. Everything this audit was
   able to grade ✅ traces to those two files. They produce no headline; every CHANGELOG entry is
   named for the skill or ADR they enforce, not for them.
2. **The single maintainer is the whole bus factor.** Every commit in the visible history is authored
   by one person. The judgement encoded in "which SKIP is acceptable" exists nowhere as a written,
   checkable rule — it lives in the author's head. `gate-rules.sh` emits SKIP for nine distinct
   reasons and the library has no doctrine stating which SKIPs are benign and which are the gate
   failing to do its job. **That judgement is currently transmitted by osmosis, and there is nobody
   to osmose from.**
3. **Freedom condition: not a problem here.** Author and reader are the same person; no structural
   pressure distorts the status reporting. This is the one axis on which the project is unambiguously
   safe.

---

## Phase 6 — The Verdict

### The one true sentence

> The toolkit's executable core is real and independently verified — 69 parity assertions pass, the
> gate genuinely fails when it should, and the v2.5.0 detection fix works exactly as its commit
> message claims — but the library does not run its own methodology on itself: it carries no
> `project.yml`, its own gate skips five of nine checks, and the headline v2.5.0 fix was shipped to
> downstream projects without ever being applied here.

### The single most likely self-deception

**That the SSD skills library is an SSD project.** It has the artifacts of one — 84 committed briefs,
reviews, and deploy notes — but not the machinery: no `project.yml`, no `current.yml`, no `gate.yml`,
five of nine gate rules skipping, an inert gitignore allow-list, and an uninstalled hook. The
artifacts are produced *about* the work rather than *by* the loop, and because the artifacts are the
visible part, the gap does not announce itself.

**The evidence that would settle it:** run `/ssd-init` in this repo and then `/ssd gate`. If the gate
comes back with `tests-pass` PASSing on `bash scripts/parity-test.sh`, the loop is real. If it still
skips, it never was.

### Posture

```
⚠  DRIFTING — claims are outrunning evidence; recoverable, and the trend is one-directional.
```

Not 🔴: the executable core is genuinely good, the review process demonstrably catches real bugs, and
negative results are published. Not ✅: three contradicted claims, one 💀, and the flagship v2.5.0
feature is unapplied in its own repo.

### What would change this verdict

- **Up to ✅ Calibrated:** `.ssd/project.yml` + `.ssd/gate.yml` present with
  `test_command: bash scripts/parity-test.sh`, README corrected to fifteen voices, gate summary lines
  reporting `N validated / M skipped`.
- **Down to 🔴 Self-Deceiving:** a contradicted claim shipping *after* this report, or a
  downstream project discovering that Step 6.5's prose path does not do what `migrate.sh` does.

### Production is the referee

Every ✅ in this report rests on **internal evidence only**. There is no evidence in this repository
that any project outside it has ever run these skills. The prose half of `ssd-init` — the path a real
downstream user takes on day one — has never been executed under audit by anyone, and cannot be, by
any command. That is where this library will first find out it was wrong.

---

## Phase 7 — Lean Over Backwards

**What I did not examine.** The prose bodies of all 11 `SKILL.md` files as *instructions* — no harness
exists to execute them, so their correctness is entirely ungraded here. The `architect/` platform
guides, `methodology/core.md`, `patterns.md`, `adoption.md`, and every ADR body except ADR-0015's
references. GitHub Actions runs beyond the 40 most recent. Whether any downstream project exists.

**What I could not run.** `ssd-init` Step 6.5, because it is prose addressed to a model, not a script.
This is the most important untested path in the library and I have no way to test it. Had I been able
to, C2's grade would rest on far more than this repo's own state.

**Reading vs. executing.** 12 of 14 claims were graded by a command I ran; 2 (C0, C13) by reading
alone. Both read-only grades are 🟡, which is the correct ceiling for that evidence.

**Where I expected to be wrong, and was not.** I first wrote C12 (💀 Theater) on
`git check-ignore` evidence alone, and flagged that the inertness might be harmless redundancy if in
practice only allow-listed names are ever written. The settling check was
`git log --diff-filter=A --name-only -- .ssd/` filtered against the allow-list. **I then ran it, and
it came back dirty** — three milestone review artifacts already committed outside the allow-list.
That escalated the finding rather than retiring it, and surfaced C14: the `code-reviewer` contract
depends on the gitignore bug. Recording the sequence because the first version of this report would
have shipped a softer, weaker, and less useful C12.

**My own asymmetry, stated plainly.** I went looking for the skipping-gate finding because the source
article names it explicitly ("the gate that exits zero because eight of its nine checks skipped"), and
I found it fast. I scrutinized the *positive* findings much less hard: I accepted `parity-test.sh`'s
69/69 without reading a single fixture body to check whether the assertions are meaningful or merely
numerous. C10 is ✅ on the strength of an exit code and a fixture-name list. That is thinner evidence
than the ✅ implies, and I am recording it rather than quietly rounding up.

**What scope forced me to ignore.** This is a repo-state audit, not a review of whether SSD is a good
methodology. Every claim about SSD's *value* — that shippable-state discipline produces better
software — is entirely outside what I examined and entirely ungraded.

---

## Remediation — same day (v2.6.0)

The grades above are **left as they were found**. Rewriting them to reflect the fixes would be
exactly the asymmetry this report exists to catch. Status appended instead.

| ID | Grade at audit | Status | Evidence |
|---|---|---|---|
| C1 | 🟠 | **Fixed** | `.ssd/project.yml` written; `/ssd` will now run in its own repo |
| C2 | 🔴 | **Fixed** | `.ssd/gate.yml` + `test_command: bash scripts/parity-test.sh`; `tests-pass` now PASSes |
| C3 | 🔴 | **Fixed** | `!.ssd/gate.yml` added to the repo `.gitignore`; `git check-ignore` confirms committable |
| C4 | 🟠 | **Fixed** | `PASS frontmatter-valid :: 51 validated; 34 unvalidated (no matching schema)` |
| C5 | 🟠 | **Fixed** | `PASS skill-version-sync :: 9 match banner; 2 exempt (no example block)` |
| C6 | 🔴 | **Fixed** | README says fifteen; `/feynman` registered; `.ssd` → `/ssd` typo corrected |
| C9 | 🔵 | **Partially addressed** | Still warnings-not-walls by design, but the CI gate job now runs a real test command instead of skipping it, and every run prints `GATE N pass · N skip · N fail` |
| C12 | 💀 | **Fixed** | Deep denies added; `secrets.env` under a feature dir now blocked; 84/84 tracked artifacts unaffected |
| C14 | 🔴 | **Fixed** | `!.ssd/milestones/**/review-*.md` + `feynman.md` added to the canonical template |
| C13 | 🟡 | Unchanged | Schedule finding; nothing to fix |
| C0 | 🟡 | Unchanged | The skill now has exactly one run behind it — this one |

**Also shipped:** a `strict-selective-gitignore` migration so existing downstream projects receive the
C12/C14 fix. Without it the library would have fixed itself and left every consumer holed — a verbatim
repeat of C2, the finding that opened this report. Verified end-to-end against a pre-change project and
covered by a new parity fixture whose negative assertions were confirmed to fail when the migration is
deliberately broken. Parity harness 69 → 77 assertions.

**Still open, and the most important thing in this file:** `ssd-init` Step 6.5 is prose executed by a
model. There is no harness that can test it, so it remains ungraded and unprotected. Every other fix
here was mechanical precisely because it *could* be; that path could not be, and it is the one a new
downstream user hits first.
