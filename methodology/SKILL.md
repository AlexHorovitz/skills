<!-- License: See /LICENSE -->

**Version:** 1.1.0

# SSD Methodology

## Purpose

Explain and apply the Shippable States Development doctrine. Answer questions about SSD principles, help users evaluate whether they are following SSD correctly, and guide decision-making in ambiguous situations.

## Interface

| | |
|---|---|
| **Input** | User question about SSD doctrine, principles, or application to their situation |
| **Output** | Explanation of the relevant SSD principle, applied to the user's context |
| **Consumed by** | None — reference skill, not consumed by other skills |
| **SSD Phase** | Reference only; not invoked by `/ssd` workflow |

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
