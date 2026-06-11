---
skill: codebase-skeptic
version: 1.2.1
produced_at: 2026-06-10T00:00:00Z
produced_by: claude-opus-4-7
project: InsanelyGreat's SSD Skills Library
scope: full repo at SHA 264c69dd5faf3a9c19bb4df7461afecbd1cefb62 (v1.19.0)
consumed_by: [refactor, code-reviewer]
finding_counts:
  structural_risk: 1
  problem: 4
  concern: 7
  question: 2
voices_activated: [fowler, feathers, beck, hohpe, humble, jobs, wozniak, evans]
posture: drifting
gate_pass: true
---

# Milestone Audit — InsanelyGreat's SSD Skills Library

**SHA:** `264c69d` · **Version:** v1.19.0 · **Date:** 2026-06-10 · **Epoch:** first milestone audit after 9 shipped epics and 11 months of work

## Phase 1 — Intake (verdicts)

- **Domain:** prescriptive software-engineering methodology delivered as a Claude Code skills library. Not a runtime system. The "code" is ~22k lines of markdown documentation + ~500 lines of bash + ~280 lines of Python.
- **Age:** 11 months active, 9 shipped epics, 19 minor releases (v1.5.0 → v1.19.0; older versions exist as `v1.0.0`–`v1.4.0`).
- **Deployment target:** the library "ships" by tagged GitHub release; users install via `~/.claude/skills/<skill>/` symlink. Distribution channel: direct-install. No production service; no telemetry.
- **Team size & velocity:** solo developer (you), with Claude as the implementation peer. Velocity has been consistent — multiple epics per quarter — and the methodology dogfoods itself.
- **Test suite:** `scripts/parity-test.sh` provides 14 regression assertions against `gate-rules.sh` (per CHANGELOG v1.13.0). No test coverage on the markdown SKILL.md prose itself — by necessity, since the "behavior" of those files is LLM-interpreted.
- **Integration boundaries:** git (shell-out), GitHub (gh CLI for PRs/issues), insanelygreat.com (canonical docs cross-link). No live API dependencies.
- **Primary language:** markdown (dominant), bash (gate-rules.sh + hooks), Python (frontmatter-validate.py). The methodology operates on markdown artifacts.
- **Greenfield, legacy, or pre-refactor?** None of the above exactly — this is a mature, actively-extended specification system. The closest analog is a *living style guide* or *living standard* (think the C++ standard library, or RFC documents). That posture is unusual for "codebases" the skeptic skill was designed for; calibration below reflects it.

## Phase 2 — Voice Activation

Activated (8 of 10):
- **Fowler** — architecture & simplicity. The orchestrator + 10 sub-skills + 8 ADRs is non-trivial architecture even if the runtime is small.
- **Feathers** — change discipline on legacy material. The 19 versions of `ssd/SKILL.md` accumulate carefully; the methodology must remain editable.
- **Beck** — testing posture, given that the only mechanical tests are the bash parity harness.
- **Hohpe** — integration patterns. The orchestrator → sub-skill → executable-helper chain *is* an integration architecture even though it's all local.
- **Humble** — deployment pipeline. There's no CI on this repo, and tags are missing for v1.16.0–v1.18.0.
- **Jobs** — coherence and user-facing UX. Both the LLM-as-user and the human-installing-skills surfaces.
- **Wozniak** — low-level pragmatism, applied to the bash and Python helpers.
- **Evans** — domain modeling. The methodology *is* the domain model; the artifact tree is its physical schema.

Not activated:
- **Uncle Bob** — per user direction (markdown isn't OO). Where Clean Code concerns apply, they're rolled into Fowler.
- **Kleppmann** — `current.yml` is the only durable state, and it's single-writer single-reader by design. No replication or consistency surface to evaluate.

## Phase 2.5 — Operational Failure Modes Sweep

| Surface | Verdict |
|---|---|
| Queue / message infrastructure | **N/A.** No queues; the orchestrator shells out to git synchronously. |
| Caching | **N/A.** |
| Database | **Limited surface.** `current.yml` is the only durable orchestrator state. **Single-writer assumption is doctrine** (ADR-0007 § non-goals: "No bespoke locking on shared `current.yml`. If multiple users edit it simultaneously, git's normal conflict resolution handles it"). But the new parallel-features commands write `current.yml` from multiple workstream contexts. **Concern raised in Hohpe section.** |
| Deploy pipeline | **Partial.** `methodology/gate-rules.sh` enforces pre-merge gate locally; **no CI** runs the gate on this repo. The pre-commit hook is opt-in. Manual tag-and-push is the "deploy." See Humble section. |
| External dependencies | **Light.** git is hard-required (orchestrator shells out throughout). GitHub via `gh` is soft-required for PR/issue work. insanelygreat.com is link-only. No 5-min/1-hour outage scenarios apply. |
| Secrets & config | **`project.yml` only.** No secrets stored. `developer_profile`, integration toggles, gitignore_mode. All keys are optional with documented defaults. |

---

## Phase 3 — Voice-by-Voice Findings

### Fowler (architecture & simplicity)

#### 💀 Structural Risk — Version-drift between `**Version:**` banner and the `version:` example in each sub-skill's required-frontmatter block

Every single sub-skill SKILL.md has a `Required output frontmatter` example showing a `version:` value that **does not match its own banner**:

| Skill | Banner version | Example `version:` in frontmatter block | Drift |
|---|---|---|---|
| `architect/SKILL.md` | 1.2.0 | 1.1.0 | -1 minor |
| `coder/SKILL.md` | 1.2.0 | 1.1.0 | -1 minor |
| `code-reviewer/SKILL.md` | 1.5.0 | 1.3.0 | -2 minor |
| `codebase-skeptic/SKILL.md` | 1.2.1 | 1.2.0 | -1 patch |
| `systems-designer/SKILL.md` | 1.3.0 | 1.2.0 | -1 minor |
| `ssd-init/SKILL.md` | 1.8.0 | **1.0.0** | **-8 minor** |

**Why it's structural risk, not a nit:** the "Required output frontmatter" block is exactly what an LLM reads when told "produce frontmatter matching this." Every artifact produced from the most-recent state of these skills carries a stale `version:` field. The `frontmatter-validate.py` schema check enforces **field presence and top-level type only** (per the validator source — `TYPE_MAP` covers `string|int|bool|list|dict|timestamp`, not value-match-against-skill-version). So this drift is *silent* — `frontmatter-valid` PASSes on artifacts produced by every skill, even though every artifact misreports the skill version that produced it.

Real impact: the 24 committed feature artifacts under `.ssd/features/` and the milestone artifacts created today both inherit the drift. A future reader running `git blame` on a code-review will see "produced by code-reviewer 1.3.0" when the actual reviewer was 1.5.0 with materially different rules (OVERLAP-N from v1.5.0, deferred-findings from v1.4.0). The historical record is wrong.

**Recommendation.** Three layers of fix:
1. **Immediate (mechanical):** sync the `version:` example in each SKILL.md's frontmatter block to the banner. Trivial edit.
2. **Forward-defense (cheap):** extend the per-skill schema in `methodology/schemas/<skill>.yml` to assert `version: <banner>` is the only acceptable value. The validator would then fail on stale frontmatter.
3. **Pattern-defense (structural):** Carmack-style — instead of asserting a string value in two places, generate the frontmatter example from the banner via a `methodology/render-skill-template.sh` script, or just remove the example version entirely (state "version: <current SKILL banner version>" as instruction, not as literal).

**Severity:** 💀 — silent historical-record corruption across the entire methodology's audit trail. Not a runtime failure; a doctrine-integrity failure. The methodology asserts strong opinions about provenance; the provenance itself is broken.

---

#### 🔴 Problem — `ssd/SKILL.md` has accreted into a single 2748-line document with 8+ distinct chapters

The orchestrator skill is the methodology's load-bearing artifact. It currently contains, in one file:

- 8 phase playbook sections (`/ssd start` through `/ssd ship`)
- Workstream Lifecycle Commands (~270 lines, v1.16.0+)
- Developer Profile + Teaching Mode (~80 lines, v1.10.0+)
- The Rails cross-reference (+ rails.md as separate file)
- Hard Rules Invariants
- The SSD Artifact Tree (with the v1.18.0 commit-split table)
- Structured Output Requirements
- Iterations Inside a Feature
- Session Continuity (including the `current.yml` v2 schema doc)
- Methodology Enforcement (rule table)
- Sub-Skill Reference table
- Review Tier Selection
- Resolving Skill Overlap
- ~250-line Changelog

**Token cost:** ~25k tokens. Some Claude Code variants (and most other LLMs) have smaller working contexts than that. For a *prescription-document the LLM is supposed to obey*, sitting near the ceiling of a session window is uncomfortable.

**Cognitive cost:** there is no "where does X live" map. A new contributor (human or LLM) has to read the whole file to learn the methodology. The Table-of-Contents-by-grep is the closest thing to navigation.

**Fowler's lens:** the orchestrator is doing what well-designed orchestrators *should* do — coordinate sub-skills — but the document has organically accumulated everything that touches the orchestrator. The Workstream Lifecycle Commands section could plausibly live in `ssd/workstream.md` (alongside `ssd/rails.md`). The `current.yml` v2 schema reference could live in `ssd/schema.md`. The Profile + Teaching mode section could live in `ssd/profiles.md`. The orchestrator entry point would shrink to ~1000 lines (the phase playbooks plus cross-references). The deep modules would each be browsable in isolation.

**Counter-argument (acknowledged):** SSD doctrine values single-file authoritative documents. ADR-0003 lifted `rails.md` out as a first-class artifact precisely because folklore-scattered-across-files is the smell. Pulling chapters out of `ssd/SKILL.md` could be the same smell in reverse. **My response:** the criterion is whether each chapter has standalone semantic identity. "Workstream lifecycle commands" passes that test (it's a coherent feature surface). "The `current.yml` v2 schema" passes (it's a data model that other docs reference). "Hard Rules / Invariants" should probably *stay* in the orchestrator (they're the heart of what `/ssd gate` enforces).

**Recommendation.** Consider extracting 2–3 chapters during the next major version cut. Specifically:
- `ssd/workstream.md` — the Workstream Lifecycle Commands section (v1.16.0+ feature surface)
- `ssd/schema.md` — `current.yml` v2 schema + `project.yml` schema (Session Continuity contents)
- `ssd/profiles.md` — Developer Profile + Teaching Mode (already cross-referenced from ssd-init)

Leave the phase playbooks, Hard Rules, Artifact Tree, Methodology Enforcement, and Sub-Skill Reference in `ssd/SKILL.md`. That cuts the file roughly in half while preserving its identity as "the orchestrator's contract."

**Severity:** 🔴 — not blocking, but the cost compounds. Every future epic that touches the orchestrator faces a longer, slower diff to review. The very next change to a Workstream Lifecycle Command will conflict with whoever's editing the `current.yml` schema; today that's the same file.

---

### Feathers (change discipline on legacy material)

#### 🔴 Problem — Profile-awareness prose is scattered across the orchestrator + init without a single source of truth

Searched for `developer_profile|novice|standard|expert` across the SKILL.md files:

| Skill | Reference count |
|---|---|
| `ssd/SKILL.md` | 25 |
| `ssd-init/SKILL.md` | 22 |
| `software-standards/SKILL.md` | 4 |
| `coder/SKILL.md` | 1 |
| `code-reviewer/SKILL.md` | 1 |
| `codebase-skeptic/SKILL.md` | 1 |
| `architect/SKILL.md` | **0** |
| `systems-designer/SKILL.md` | **0** |
| `methodology/SKILL.md` | **0** |
| `refactor/SKILL.md` | **0** |

The orchestrator and ssd-init talk about profile constantly. Most sub-skills don't mention it at all. ADR-0004 ratified the profile system in v1.10.0; eight months later most sub-skills haven't been touched to participate. The Profile-aware defaults table sits in `ssd/SKILL.md` and currently encodes 6 columns of behavior delta — including, since v1.15.0, the `switch_note_default` knob that affects `/ssd switch`. Sub-skills that *should* gate behavior on profile (verbosity in coder-status output? Strictness in architect ADR enforcement? Detail level in code-reviewer findings?) currently don't.

**Feathers' lens:** this is the legacy-material smell. The profile system was added in v1.10.0; subsequent skill changes have been merged without "does this need profile-awareness?" being asked. Five skills (architect, systems-designer, methodology, refactor, plus zero-mention-in-coder) are profile-blind. They're not broken — they degrade gracefully to "standard" behavior — but the doctrine has drifted from the system.

**Recommendation.** Two paths:
1. **Audit each sub-skill against the Profile-aware defaults table:** does this skill have behaviors that *should* vary by profile? If yes, add the per-profile branches. If no, add a single-line note ("This skill's behavior is profile-invariant by design.").
2. **Move the canonical Profile-aware defaults table out of `ssd/SKILL.md`** and into `ssd/profiles.md` (per the Fowler recommendation above). Every skill that wants to opt into a profile-driven default cross-references the same table. Single source.

Neither is urgent. But the question "what does novice see vs expert in code-reviewer?" should have a documented answer, not silence.

**Severity:** 🔴 — drift between the methodology's ratified design (ADR-0004) and the methodology's implementation across the skill chain.

---

#### ⚠ Concern — `ssd/SKILL.md` skill-version banner (1.18.0) lags library version (1.19.0)

Iter B of ssd-commit-split (v1.19.0) shipped without bumping `ssd/SKILL.md`'s **Version:** banner, because iter B touched ssd-init/SKILL.md + the hook + the gate-rules.sh `--staged` flag but didn't touch the orchestrator SKILL.md itself. This is the documented pattern — sub-skill versions only bump when that skill changes — but it's worth flagging because **it's the second time in this codebase's history that the orchestrator skill version diverged from the library version**, and the pattern from previous divergence (1.10.0 → 1.15.0 jump in parallel-features iter A) was to re-align the banner with the library version on the next-touching change.

**Recommendation.** Document the divergence-and-realign pattern explicitly in `ssd/SKILL.md` Changelog or in a one-line note near the version banner: "Skill version tracks library version when the skill changes; otherwise it diverges and re-aligns on next change." Removes ambiguity for future contributors.

---

### Beck (testing posture)

#### 🔴 Problem — `scripts/parity-test.sh` exists but is not run by anything

Per CHANGELOG v1.13.0, the parity-test harness has 14 assertions against `gate-rules.sh` across 7 synthetic git fixtures. It is the *only* mechanical regression suite for the executable artifacts. It is:

- **Not invoked** by any other script in the repo (no `make test`, no `npm test`, no CI workflow).
- **Not referenced** in `methodology/gate-rules.sh` itself.
- **Not part of** the `/ssd gate` flow (only the rules themselves are; the rules' own tests aren't).
- Not mentioned in the development workflow docs.

It exists as a discoverable file that the user runs manually when they remember. Beck would say: a test suite that requires human willpower to run is not a test suite, it's a hopeful document.

**Recommendation.** One of:
1. **Add a GitHub Actions workflow** that runs `bash scripts/parity-test.sh` on every PR. Even without a full CI suite, a single workflow file enforces "parity tests still pass." ~15 lines of YAML. Highest leverage.
2. **Add the parity-test as a 7th gate rule** (`rule_parity_test`) in `gate-rules.sh` itself, so `/ssd gate` runs it. Risk: rules calling rules creates recursion potential.
3. **At minimum,** add the parity-test invocation to `methodology/README.md` (if it exists) or `CONTRIBUTING.md` (which doesn't exist yet — also a Beck finding implicit in this).

**Severity:** 🔴 — the only test the library has is effectively never run.

---

#### ⚠ Concern — No `CONTRIBUTING.md` for this repo

The library has 8 ADRs documenting its own design decisions, a 24-artifact `.ssd/features/` corpus showing every shipped epic's brief/architect/code/review, and a clean methodology — but no document explaining "how to contribute to this repo." If a second contributor showed up tomorrow, they would have to:
1. Read `ssd/SKILL.md` (2748 lines) cover to cover.
2. Read `methodology/core.md`.
3. Infer that the project dogfoods itself.
4. Discover `scripts/parity-test.sh` exists.

**Recommendation.** A 50-line `CONTRIBUTING.md` covering: "this repo dogfoods SSD on itself; use `/ssd` commands per the orchestrator; the parity-test harness is `scripts/parity-test.sh`; new ADRs go in `docs/decisions/`; tag conventions are X."

---

### Hohpe (integration patterns)

#### ⚠ Concern — `current.yml` is single-writer-by-doctrine, but parallel-features commands write it from multiple workstream contexts

ADR-0007 § non-goals explicitly says: *"Multi-user / multi-machine coordination — out of scope. Single-developer workflow only."* And: *"Locking on shared `current.yml`. If multiple users edit it simultaneously, git's normal conflict resolution handles it. No bespoke locking protocol."*

But the parallel-features feature in v1.16.0 added `/ssd feature new`, `/ssd switch`, `/ssd worktree` — all of which write to `current.yml`. The doctrine says "single developer." In practice, a single developer running two `/ssd` invocations in two terminals (one in main checkout, one in a worktree) could write to `current.yml` simultaneously and race. The orchestrator's self-verification block says: *"current.yml and current.notes.yml writes are atomic (write to a temp file + rename, OR prepare the full new content in memory before writing — never partial-write)"* — but that's a prose instruction the LLM-executing orchestrator is supposed to follow, not a mechanical guarantee.

**Hohpe's lens:** atomicity is an asserted property the system relies on but doesn't verify. In a real concurrency event (two terminals, both `/ssd` invocations writing), the temp-file-rename atomicity would protect against partial writes but NOT against lost-writes (one writer's full state replacing the other's). The current.notes.yml has no schema validation; the current.yml has only the loose v2 schema check.

**Recommendation (not urgent):** document the *known* concurrency assumption explicitly in `ssd/SKILL.md` § "Session Continuity" — single Claude session per project at a time. If parallel sessions become a real use case, ADR-0009 introduces a lockfile or version-counter scheme. Today, write the assumption down.

**Severity:** ⚠ — the doctrine says "single-developer" and the typical user follows that; the orchestrator's "atomic write" claim is asserted, not proven; the conceivable failure case is rare and recoverable. But future-self should know this is undocumented.

---

#### ⚠ Concern — Python validator and bash gate-rules.sh are two languages of enforcement

`methodology/frontmatter-validate.py` (Python + PyYAML) and `methodology/gate-rules.sh` (bash) are two enforcement layers for two distinct concerns:
- frontmatter-validate.py: per-artifact YAML schema enforcement
- gate-rules.sh: per-PR rule enforcement

ADR-0006 chose Python for the validator (because `yaml_get` in gate-rules.sh is scalar-only and can't read the nested structures in artifact frontmatter). ADR-0005 chose bash for gate-rules.sh (because shell-out + git + grep is the right toolset for git-history rules).

The two are independently sound. But they're **two integration points** the orchestrator depends on, and **two installation surfaces** users must keep working:
- Python 3 + PyYAML for the validator
- Bash 3.2+ (macOS-compatible) for gate-rules.sh

Both have soft-fall-back behavior (validator missing → frontmatter-valid SKIPs; PyYAML missing → SKIP), but the cumulative dependency surface is non-trivial. A user running SSD on a fresh machine needs Python + bash + git + (optionally) Python-yaml.

**Hohpe lens:** the bifurcation is justified by the design constraints but it does create two maintenance loci. Future SSD changes that touch validation may touch one, the other, or both. Coherent today; worth keeping an eye on.

**Recommendation.** Document the bash-vs-python boundary in `methodology/SKILL.md` (or in a new `methodology/architecture.md`): "gate-rules.sh handles git/file-system rules in bash; frontmatter-validate.py handles per-artifact YAML schema in Python. These are intentionally separate per ADR-0005 and ADR-0006. New gate rules go in bash; new artifact-schema constraints go in Python."

---

### Humble (deployment pipeline)

#### 🔴 Problem — Tags missing for v1.16.0, v1.17.0, v1.17.1, v1.18.0

`v1.15.0` was tagged and pushed (the parallel-features iter A release). Subsequent releases — four of them, including the entire rest of parallel-features and v1.17.1 docs pass and v1.18.0 ssd-commit-split iter A — were not tagged. The CHANGELOG documents them, and the merge commits (`098d35e`, `0ce2953`, `a0ff836`, `810d64e`, `264c69d`) exist, but `git tag --list` shows only `v1.15.0`.

**Why this matters:**
- A user trying `git checkout v1.18.0` to test a specific release fails.
- Release notes on GitHub (auto-generated from tags) only exist for v1.15.0.
- The "ratchet principle" (`methodology/core.md` § 4 — forward progress only, each commit deployable) is technically intact at the commit level, but the *release* layer of the ratchet is broken.
- `methodology/core.md` references `insanelygreat.com/ratchet-principle.html` which has a working `.github/workflows/quality.yml` — this repo doesn't have that workflow.

**Humble's lens:** the methodology explicitly endorses "deploy daily" and "tag every release." This repo demonstrates strong commit-level discipline but loose release-level discipline. The methodology asks for both.

**Recommendation.** Three actions:
1. **Tag the missing releases retroactively.** `git tag -a v1.16.0 098d35e -m "v1.16.0 — ..." && git push origin v1.16.0`. Repeat for v1.17.0, v1.17.1, v1.18.0, v1.19.0. ~5 minutes.
2. **Add a release post-merge step** to the orchestrator's `/ssd ship` doc: "After merge, tag the release: `git tag -a v<version> <merge-sha> -m '<one-line>' && git push origin v<version>`." This is mechanical; could even be a small `methodology/hooks/post-merge-tag.sh` script the user runs.
3. **Add a GitHub Actions workflow** that runs `gate-rules.sh` on every PR and parity-test.sh on every push to main. This catches Beck's finding above and Humble's "the ratchet should be encoded in CI" point from `methodology/core.md` § 4 ("Encode the ratchet in CI").

---

#### ⚠ Concern — No GitHub Actions workflow runs on this repo, despite the doctrine

`methodology/core.md` § 4 says: *"Encode the ratchet in CI. Human willpower is a finite resource; the build system is not. See [The Ratchet Principle](https://insanelygreat.com/ratchet-principle.html) for a working `.github/workflows/quality.yml` that enforces every tooth."*

This repo has no `.github/workflows/` directory. The methodology explicitly endorses CI; the methodology's own implementation lacks it. The contradiction is mild (this repo is markdown + bash, not the kind of codebase the ratchet workflow targets), but it deserves naming.

**Recommendation.** Add `.github/workflows/quality.yml` with at minimum:
- Run `bash methodology/gate-rules.sh --base origin/main` on every PR.
- Run `bash scripts/parity-test.sh` on every push.

~30 lines of YAML. Closes both this concern AND the parity-test-not-run finding from Beck.

---

### Jobs (coherence and UX)

#### 🔴 Problem — Cross-skill priority-rule completeness in ssd/SKILL.md § "Resolving Skill Overlap" is stale

The orchestrator's overlap table currently documents 3 pairs:
1. `coder` vs `python-django-coder`
2. `code-reviewer` vs `codebase-skeptic` (≤500 LOC threshold)
3. `codebase-skeptic` vs `software-standards`

**Latent overlap pairs not documented:**

- **`refactor` vs `code-reviewer` in remediation contexts.** Both can be invoked during `/ssd milestone` step 3 ("Validate — invoke `code-reviewer` on each refactoring PR"). The `remediation_mode: true` frontmatter flag triggers Phase 1.5 in code-reviewer. But `refactor` produces the plan; if a `refactor` finding ID doesn't get closed, who flags it? The orchestrator's milestone playbook says "Each refactor item cites a specific finding ID from skeptic-before.md. No cite → not in scope." — but no priority rule documents the refactor-vs-reviewer boundary explicitly.

- **`architect` vs `systems-designer` in `/ssd design` bundled pass.** Both run in the same step. Who wins on disagreement? The orchestrator's `/ssd design` doc says: *"Surfaces any architect-spec gaps that systems-designer rejected back to the user as a single actionable block."* That's a *coordination* rule, not a *priority* rule. If architect says "this is fine" and systems-designer says "missing migration plan," who has authority? The bundled-pass section assumes systems-designer is purely additive review of architect — which is the design intent, but not explicit in the overlap table.

- **`methodology` vs everything.** The methodology skill provides `/methodology score` for self-adherence measurement. It can also be invoked as reference. The overlap table doesn't document when to invoke methodology directly vs. when to read from it via `methodology/core.md`. Mostly a non-issue because methodology is reference-tier, but worth a row.

- **`codebase-skeptic` vs `refactor` in `/ssd verify`.** The verify flow re-invokes both; the priority is implicit (skeptic produces the *before/after* comparison; refactor produces the *plan to close*). Documented behaviorally but not in the overlap table.

**Jobs' lens:** the priority-rule table is the *contract* for which skill wins when two could apply. With 10 sub-skills, the table is undersized. A new contributor (or future-Claude) will guess wrong.

**Recommendation.** Expand the table. Even non-priority "these two cooperate; here's how" rows add value. Make the overlap table the canonical "which skill handles what."

---

#### ⚠ Concern — README dogfood paragraph references "`.ssd/features/`" but doesn't link discoverably

Per iter B of ssd-commit-split, `README.md` says: *"This repo tracks its own SSD artifacts under [.ssd/features/](.ssd/features/) — briefs, architect specs, coder-status reports, and code-reviews for every epic shipped in v1.5.0+."*

The link goes to a directory listing on GitHub, which is functional but uninspiring. The 9 epics aren't named. A casual visitor doesn't get drawn into the dogfood unless they click and explore.

**Recommendation (cheap):** Add a short list under the paragraph:
- `ssd-skill-upgrades/` — 9-iteration epic implementing v1.5–v1.14 (5 ADRs)
- `parallel-features/` — multi-feature workflow (3 iterations, v1.15–v1.17)
- `ssd-commit-split/` — the convention that makes this list visible (2 iterations, v1.18–v1.19)

Three lines. The reader who clicks `parallel-features/01-architect.md` now sees a real-world architect spec. **That's the marketing value of the dogfood** — show, don't tell.

---

### Wozniak (low-level pragmatism on bash + Python)

#### ⚠ Concern — `gate-rules.sh` is 502 lines and approaching the "single big bash file" smell

Function inventory:
- 9 helpers: `should_run`, `emit`, `yaml_get`, `yaml_get_list`, `matches_deny_pattern`, `read_lines_into_array`, `is_git_repo`, `diff_files`, `diff_scope_label`
- 6 rules: `wip_commits`, `tests_pass`, `feature_flag_present`, `adr_delta`, `frontmatter_valid`, `no_leaky_state`
- Setup + arg parsing + result accumulator + JSON/text output: ~80 lines

Started ~50 lines at v1.4.0; now 502 lines after three rule additions, the glob matcher, and `--staged` mode. Still readable — Kernighan would approve — but the trajectory is the concern.

**Wozniak/Kernighan lens:** if the next rule (CI integration check? something for parallel-features overlap consumption?) lands at v1.20.0+, this file crosses 600 lines. Bash readability degrades at that size. The signal is not "refactor today"; it's "next addition should consider whether the file should split."

**Recommendation.** Don't refactor preemptively. But on the next gate-rules.sh change, evaluate whether splitting per-rule into `methodology/rules/<rule-name>.sh` makes the system easier or harder to follow. The rule-runner block at the bottom is the obvious extension point.

---

#### ⚠ Concern — `frontmatter-validate.py` does NOT enforce `version:` value matches skill banner

Already raised under Fowler/Structural Risk above. Restated from Wozniak's angle: the Python validator has the *capacity* to match `version: <expected>` (the schema files are YAML and could include literal-value assertions), and the `TYPE_MAP` shows the intent — types only, currently. The structural risk is that the validator's "version is just a string" rule is *too permissive*; a one-line extension would catch the silent drift documented under Fowler.

**Recommendation.** See Fowler's Recommendation #2 — extend per-skill schemas in `methodology/schemas/<skill>.yml` to assert exact-banner-match on `version:`. Coder-level change, ~5 lines in the validator + ~1 line per schema.

---

### Evans (domain modeling)

#### ⚠ Concern — The `.ssd/` artifact tree is the domain model; ADR-0008's commit-split correctly separates "artifact" from "machine state" but `current.yml` is in an awkward middle

The artifact tree (briefs, architect specs, coder-status, code-reviews, deploy notes) is the methodology's bounded context. ADR-0008 split this into:
- **Durable artifacts** (committed): briefs, architect specs, coder-status, code-reviews, deploy notes, milestone records
- **Machine state** (gitignored): `current.yml`, `current.notes.yml`, `init-log.md`, `archive/`, `audits/`

But `current.yml.archived[]` contains the *historical record* of which workstreams shipped, with what artifacts, when, authoring which ADRs. That's domain-model-grade information. It lives in `current.yml`, which is gitignored.

**Evans' lens:** the historical record of "which workstreams ran when" is a different *aggregate* than the current-workstream-state. Conflating them means committing the durable history-of-the-methodology requires either:
- Treating `current.yml.archived[]` as machine state (today), which loses the history when the file is regenerated or moved between machines
- Or splitting `current.yml` further: `current.yml` for in-flight, `archived.yml` (committed) for the durable history

The current approach loses history on machine migration. The 9-epic archive entries in this very file would be lost if `current.yml` were corrupted or the project were re-cloned without the local file.

**Recommendation.** Consider splitting `current.yml.archived[]` into a separate committed file. ADR-0009 candidate: "Separate the durable workstream-history aggregate from the active workstream state." Not urgent; raise it next time the schema is touched.

---

#### 💭 Question — Is "milestone" the right verb for what `/ssd milestone` does on a markdown library?

The `/ssd milestone` playbook is designed for codebases with measurable metrics (coverage, perf, etc.). For this skills library, "milestone" reads as a documentation/governance review more than a coverage-regression review. The Step 0 snapshot in this current audit captured ADR counts, skill counts, line counts — not test coverage or perf metrics, because none exist here.

**Question:** does the methodology need a separate verb (`/ssd review` ? `/ssd governance` ?) for milestone-like reviews on documentation-heavy projects? Or is "milestone" intentionally elastic and this is fine? The brief should weigh in; the answer determines whether future milestone audits on similar libraries will be standardized or improvised.

---

## Phase 4 — Synthesis

### Dominant failure mode

**Doctrine drift.** Multiple findings (Fowler version-drift, Feathers profile-scatter, Humble missing tags, Jobs overlap-table-stale) describe the same root cause: the methodology was ratified in successive epics, but **the methodology's *own* documentation has not been kept in sync with the methodology's *own* implementation**. The library asks every project to maintain "production parity from Day 1" — but the methodology itself is drifting from its own design.

This is not a structural collapse. It's the entropy of an 11-month, 9-epic library that has been correctly extended but never *consolidated*. The first milestone audit catches it at the right moment.

### Highest-leverage intervention

**One change unlocks the most:** add `.github/workflows/quality.yml` that runs `gate-rules.sh` + `parity-test.sh` on every PR.

That single workflow:
- Closes the Beck finding (parity-tests now run)
- Closes the Humble "no CI on this repo" finding
- Catches future doctrine drift mechanically (no human willpower needed)
- Models for downstream SSD-adopting projects what their CI should look like
- Satisfies the `methodology/core.md` § 4 ratchet principle

Estimated effort: 30 lines of YAML, ~30 minutes.

### Voice conflicts

**Fowler vs Feathers on the orchestrator split.** Fowler argues `ssd/SKILL.md` should split into chapters (`workstream.md`, `schema.md`, `profiles.md`). Feathers points out that the legacy material has been carefully maintained; arbitrary file-splits could break cross-references the existing artifacts rely on.

**Resolution:** Fowler wins on direction but Feathers wins on caution. Don't split today. *Plan* the split for a future major-version release (v2.0.0?) with explicit deprecation period and migration script. Document the intent as a deferred decision in `current.notes.yml`.

**Beck vs Humble on test enforcement.** Beck wants parity-tests run *somewhere*. Humble wants CI for the ratchet. They converge on the same recommendation (add a GH Actions workflow); no real conflict.

### POSTURE

**⚠ Drifting** — coherent intent undermined by accumulating decisions.

The library is functional. The methodology is mature. Real users (you) ship real epics with it. The shippable-state invariant holds across 19 versions.

But the *internal* discipline has slipped:
- 6 of 6 sub-skills carry stale `version:` example values
- 5 of 10 sub-skills don't acknowledge the v1.10.0+ profile system
- 4 of 5 recent releases lack git tags
- `current.yml.archived[]` is the only durable history of the methodology's own evolution, and it's gitignored
- The library that preaches "encode the ratchet in CI" has no CI

None individually crisis-grade. Together they describe a methodology drifting from its own posture.

### Forward-Looking Pass

| Question | Answer (one sentence) | Finding ID |
|---|---|---|
| **Scale.** What breaks first at 10× usage? | `ssd/SKILL.md` becomes too large for some LLMs' working context (~25k tokens today); a smaller-context Claude or a different model entirely would either truncate or skim, producing wrong behavior — see Fowler's `ssd/SKILL.md` size finding. | F1 |
| **Team.** What will a new hire misunderstand and break in their first month? | The `developer_profile` system — they'll skip it because most sub-skills don't mention it, and they'll add new skills/features without profile-awareness, deepening the Feathers drift. | F2 |
| **Incident.** At 3am during an outage, what will be hardest to diagnose? | A `current.yml` corruption or a parallel-write race — the orchestrator asserts "atomic writes" in prose but has no runtime guarantee, and `current.yml.archived[]` would lose history. | F3 |
| **Friday deploy.** What change shipped Friday at 4pm carries unacceptable risk? | A `gate-rules.sh` edit. The script is the load-bearing enforcement layer; there's no CI to catch a regression; the parity-test exists but isn't enforced. **What *should* carry unacceptable risk but doesn't:** any change to `gate-rules.sh` should be blocked from merge unless `scripts/parity-test.sh` passes. Today it isn't. | F4 |

### Hook for `/code-reviewer`

When code-reviewer reviews future PRs, flag these structural concerns from this milestone audit:

| Finding | Files/patterns | Trigger for code-reviewer |
|---|---|---|
| Version-drift in frontmatter examples | Any `<skill>/SKILL.md` with a "Required output frontmatter" block | If the PR changes the skill's `**Version:**` banner, verify the example `version:` in the frontmatter block was bumped too. |
| Profile-blind sub-skills | `architect/SKILL.md`, `systems-designer/SKILL.md`, `methodology/SKILL.md`, `refactor/SKILL.md` | If the PR adds behavior to one of these skills, ask: should this branch on `developer_profile`? |
| `ssd/SKILL.md` growth | `ssd/SKILL.md` | If the PR adds >100 lines to ssd/SKILL.md, ask: does the new content belong in a separate `ssd/<chapter>.md`? |
| `current.yml` writes from new commands | Any new orchestrator command in `ssd/SKILL.md` or any skill that writes to `current.yml` | Verify the doctrine "single Claude session per project" is documented near the new write. |
| `gate-rules.sh` rule additions | `methodology/gate-rules.sh` | Verify `scripts/parity-test.sh` has been updated with fixtures for the new rule. If a CI workflow exists, verify the new rule passes there too. |
| Missing tag on release | Any merged PR whose title starts `v1.` and that bumps `VERSION` | After merge, the user must `git tag -a v<version> <merge-sha>` and push the tag. Today this is manual; flag if absent on merge. |

---

## Prioritized Remediation Order

Ordered for the `refactor` skill (next phase). Each item cites a finding from above.

| # | Item | Finding | Effort | Impact |
|---|---|---|---|---|
| 1 | Add `.github/workflows/quality.yml` running `gate-rules.sh` + `parity-test.sh` on every PR | Beck `parity-test` + Humble CI + F4 (Friday deploy) | ~30 min | Highest — closes 3 concerns + 1 forward finding mechanically |
| 2 | Sync `version:` example value in each sub-skill SKILL.md's frontmatter block to the banner | Fowler structural risk | ~15 min | High — silent historical-record corruption stopped |
| 3 | Tag v1.16.0, v1.17.0, v1.17.1, v1.18.0, v1.19.0 retroactively | Humble missing tags | ~10 min | Medium — release history navigable |
| 4 | Extend `methodology/schemas/<skill>.yml` to assert exact-banner-match on `version:` | Fowler structural risk (forward defense) | ~20 min | High — prevents future drift mechanically |
| 5 | Expand `ssd/SKILL.md` § "Resolving Skill Overlap" with the 4 latent pairs | Jobs overlap-table | ~20 min | Medium — coordination clarity |
| 6 | Audit each profile-blind sub-skill for "should this branch on profile?" | Feathers profile-scatter | ~2 hr | Medium — doctrine-implementation alignment |
| 7 | Add README list of dogfooded `.ssd/features/` epics with one-line descriptions | Jobs README polish | ~10 min | Low — marketing value of the dogfood |
| 8 | Document `ssd/SKILL.md` divergence-and-realign pattern in its changelog header | Feathers banner-lag | ~5 min | Low — clarity for future contributors |
| 9 | Document single-Claude-session-per-project assumption in `ssd/SKILL.md` § "Session Continuity" | Hohpe current.yml races + F3 | ~10 min | Medium — failure mode documented for incident response |
| 10 | Plan future `ssd/SKILL.md` split into chapters (`workstream.md`, `schema.md`, `profiles.md`) — deferred to next major version | Fowler size + F1 | (planning only) | High deferred — biggest readability gain when realized |
| 11 | Consider ADR-0009 candidate: split `current.yml.archived[]` into separate committed file | Evans current.yml middle-aggregate | (planning only) | Medium deferred — schema change with backward-compat work |
| 12 | Add `CONTRIBUTING.md` (50 lines covering dogfood pattern + parity-test + ADR location + tag conventions) | Beck `CONTRIBUTING.md` | ~30 min | Medium — onboarding for second contributor |

**Items 1–4 cover ~75 minutes of work and close the highest-leverage findings.** Items 5–9 are <1 hour total. Items 10–12 are larger; deferred for explicit planning.

---

## Self-Verification (codebase-skeptic discipline)

1. **Read actual files cited?** Yes — `ssd/SKILL.md` (full, via embedded skill context), `methodology/core.md` (full), `methodology/gate-rules.sh` (full, function inventory + key rule body), `methodology/frontmatter-validate.py` (key sections incl. `TYPE_MAP` + schema-matching), `.ssd/milestones/2026-06-10-post-v1.19/metrics-before.yml` (full), `docs/decisions/ADR-0001-iterations-as-schema-substrate.md` (verified the iterations design matches current schema), `coder/SKILL.md` (verified version-drift example).
2. **Verified each 💀 / 🔴 claim by tracing the execution path?** Yes — version-drift verified across 6 skills via grep; profile-scatter verified by grep count per skill; missing-tags verified via `git tag --list`.
3. **For each citation (file:line), does the line still exist at that number?** Citations are by section name and file, not line number (the markdown evolves too fast). All sections referenced exist at HEAD 264c69d.
4. **Claims that depend on assumptions I haven't stated?** Stated explicitly: "this is a documentation-heavy library, not a runtime system; standard codebase-skeptic calibration may overweight some voices." Findings calibrated accordingly.
5. **Sub-agents?** None used.
6. **Downgraded speculative claims?** Yes — considered MAJOR for `ssd/SKILL.md` size (current state would be too big for some LLMs), downgraded to PROBLEM because it's not yet observed-broken on Claude Code. Considered MAJOR for the current.yml concurrency, downgraded to CONCERN because the single-Claude-session-at-a-time doctrine holds in practice for solo developers.

---

**End of report.** Hand-off to `refactor` for prioritized remediation planning. Items 1–4 are the high-leverage cluster; consider running them as a single "v1.19.1 doctrine-tightening" patch release before any feature work resumes.
