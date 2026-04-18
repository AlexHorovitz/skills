# SSD Methodology

<!-- License: See /LICENSE -->

**Version:** 1.2.0

## Purpose

Explain and apply the Shippable States Development doctrine. Answer questions about SSD principles, help users evaluate whether they are following SSD correctly, and guide decision-making in ambiguous situations. Also provides the machine-checkable rule source that `/ssd gate` enforces and the self-adherence scoring invoked by `/methodology score`.

## Interface

| | |
|---|---|
| **Input** | User question about SSD doctrine, or the active project's repo/metrics for a `/methodology score` run |
| **Output** | Explanation of the relevant SSD principle (reference mode) OR an SSD-adherence score report (`ssd/methodology-score-YYYY-MM-DD.md`) |
| **Consumed by** | `ssd` (`/ssd gate` reads doctrine rules from `core.md` for mechanical enforcement) |
| **SSD Phase** | Reference for any phase; `/methodology score` runs on-demand |

## When to Use

Invoke this skill when:
- A user asks "what does SSD say about X?"
- A user wants to understand a specific principle (shippable state, ratchet, feature flags)
- A user is evaluating whether a decision is consistent with SSD
- A user is onboarding to SSD and wants the full doctrine

Do not invoke this skill for active coding sessions — use `/ssd feature` instead.

---

## Reference Files

This skill is organized into three focused files. Load the relevant file based on the user's question:

| File | Contents | Load when |
|---|---|---|
| `core.md` | Iron Law, Five Principles, Decision Framework, Metrics, Mindset | User asks about SSD principles or doctrine |
| `patterns.md` | Five implementation patterns, Advanced topics (dependencies, DB migrations, emergencies) | User asks "how do I implement X with SSD?" |
| `adoption.md` | Getting started checklist, Common objections, Org adoption, Comparisons to Agile/CD/TBD, Resources | User is onboarding a team, handling pushback, or comparing SSD to other methods |

**Default**: Load `core.md`. It covers the stable doctrine that answers most questions.

**On first invocation**: Read `core.md` and answer from it. If the user's question is about implementation specifics, also read `patterns.md`. If about team dynamics or objections, also read `adoption.md`.

Note: the `adoption.md` file mixes individual-team onboarding with organization-wide change management.
When loading it, select the relevant subsection for the user's audience (team onboarding vs. executive
rollout) and skip the other. If `adoption.md` has been split into `adoption-team.md` and
`adoption-org.md`, load only the one that matches the question.

Methodology comparisons in `adoption.md` (Agile, CD, TBD, etc.) are date-stamped at the top of the
section. If the comparison is > 12 months old, note that to the user and offer to refresh it rather
than repeating it as fact.

---

## `/methodology score` — Self-Adherence Metric

Invoke this mode when the user asks "are we following SSD?" or when `/ssd milestone` wants a baseline
for methodology adherence. The skill reads the repo and computes the five SSD metrics:

| Metric | Source | Target |
|---|---|---|
| Deployment frequency | `git log` on main; deploy markers in CI logs | ≥ 1/day (team); ≥ 1/week (solo) |
| % of new code behind feature flag | Delta of `feature_flags` config; grep for flag decorators | > 90% |
| Test coverage | Project test command with coverage flag | > 70% baseline; trend ≥ 0 |
| Mean time-to-deploy | CI run duration on main | < 15 min |
| Shippable states per week | Count of commits on main that passed `/ssd gate` | ≥ 5 |

Output: `ssd/methodology-score-YYYY-MM-DD.md` with the score table, trends vs. the prior score (if
any), and the two lowest-scoring metrics flagged as remediation candidates.

---

## Changelog

- **1.2.0** (2026-04-18) — Clarified that methodology now provides machine-checkable rule source for
  `/ssd gate` enforcement (M1); added `/methodology score` self-adherence metric invocation (M2);
  documented audience-split expectation for `adoption.md` (M3); required date-stamped comparisons to
  other methodologies with 12-month refresh prompt (M4).
- **1.1.0** — Split into `core.md`, `patterns.md`, `adoption.md`.
- **1.0.0** — Initial release.
