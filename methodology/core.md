# SSD Core Doctrine

## Overview

**Shippable States Development** is a pragmatic engineering discipline for digital product development where the system maintains a deployable, production-ready state at all times throughout the development cycle.

**Core principle**: If you can't ship it right now, you don't have a product—you have a construction site.

**Origins**: Synthesizes lessons from continuous deployment, trunk-based development, feature flags, and decades of software engineering failures where "90% done" meant "months from shipping."

---

## Why This Matters

### The Fundamental Trade-off

Every project has exactly three variables:
1. **Scope** (what features/capabilities)
2. **Time** (when it ships)
3. **Quality** (how well it works)

**Iron Law**: You can fix at most ONE of these. The other two must flex.

- Fix scope + time → Quality suffers
- Fix scope + quality → Timeline slips
- Fix time + quality → Scope reduces

Most project failures come from pretending you can fix all three.

### The "90% Done" Problem

Traditional development creates this pattern:
- Week 1-8: "Making good progress!"
- Week 9: "We're 90% done!"
- Week 10: "Still 90% done..."
- Week 11: "Uh, still 90%..."
- Week 12: Panic, cut features, ship something broken

**Why?** The last 10% includes all the work no one budgeted for:
- Integration between components
- Error handling
- Performance under load
- Edge cases
- Production deployment
- Data migration
- Security hardening
- Cross-platform/device testing
- App Store / Play Store compliance
- Accessibility
- Documentation

**SSD Solution**: Do the hard "last 10%" work incrementally throughout development, not as a crisis at the end.

---

## Core Principles

### 1. Constant Production Parity

Your development environment must match production as closely as possible from day one.

**Traditional approach**:
```
Week 1-8:  Local development
Week 9:    "Okay let's deploy to staging..."  /  "Let's submit to TestFlight..."
Week 10:   "Why doesn't it work in staging?"  /  "Why does App Store reject our build?"
Week 11:   "Production is different from staging..."  /  "Why doesn't notarization work?"
Week 12:   "What do you mean SSL certs take 3 days?"  /  "Provisioning profiles expired?"
```

**SSD approach**:
```
Day 1:     Deploy "Hello World" to production
Day 2:     Deploy first feature to production
Day 3:     Deploy improved version to production
Day 30:    Deploy to production (like every other day)
```

**Why this works**:
- Deployment is never "the hard part" because you do it constantly
- Production issues surface immediately when they're easy to fix
- You know your deployment budget (time/cost) from day one

### 2. The Shippable State Invariant

**Invariant**: At the end of each work session, the system must be in a state where:
- All tests pass
- No compilation errors
- No broken user-facing features
- Documentation matches implementation
- Could be deployed to production without embarrassment

**Not required**: That it's feature-complete or meeting all goals. Just that what exists actually works.

**Practical test**: Ask yourself: "If I got hit by a bus right now and someone else had to ship what I've committed, would they hate me?"

### 3. Feature Flags Over Feature Branches

Long-lived feature branches are antithetical to shippable states.

**Problem with feature branches**:
```
Main branch:        A---B---C---D---E---F---G---H
                         \
Feature branch:           I---J---K---L---M
                                            \
                                             (merge hell)
```

Days of merge conflicts, integration bugs, "works on my branch" syndrome.

**SSD approach with flags**:
```
Main branch:        A---B---C---D---E---F---G---H

Day 1: Add feature code (behind flag, off by default)
Day 2: Expand feature (still flagged off)
Day 3: Feature works, flip flag to on
```

All work happens on main/trunk. Feature exists in production but is invisible until ready.

### 4. The Ratchet Principle

**Forward progress only**. Each commit improves the system in some measurable way.

Banned commits:
- "WIP" or "checkpoint" commits
- "Broken, will fix tomorrow"
- Commented-out code "for later"
- Partially implemented features visible to users

**Ratchet mechanism**:
- Every commit must pass CI/CD
- Every commit must maintain or improve code coverage
- Every commit must be deployable
- No "we'll fix it in the next commit" mentality

Like a ratchet, you can only move forward, never backward. If you need to save work that's not ready, use:
- Local stash (not committed)
- Draft PR with "DO NOT MERGE" (not on main)
- Feature flag (committed, but invisible)

### 5. Scope Flexibility is a Feature, Not a Bug

**Traditional thinking**: "We must deliver all planned features by the deadline"
**Result**: Deliver nothing on time, or deliver broken features

**SSD thinking**: "We deliver whatever is shippable by the deadline"
**Result**: Deliver working software, adjust scope based on reality

**This requires**:
- Breaking work into independently shippable units
- Prioritizing ruthlessly (what MUST ship vs. what's nice-to-have)
- Accepting that scope will change as you learn what's actually hard
- Communicating scope changes early and often

**Key mental shift**: Reducing scope is not failure—it's engineering judgment.

---

## Decision Framework

### Choosing Your Constraint

At project kickoff, declare your primary constraint:

**Time-Constrained Projects**:
- Hard deadline (conference, contract, regulatory)
- Scope must flex to meet deadline
- Build prioritized feature list
- Ship what's done when time expires

Examples: Conference demos, MVP for funding rounds, contractual deliveries

**Scope-Constrained Projects**:
- Specific features non-negotiable
- Timeline must flex to complete features
- No "we'll add it in v2" allowed
- Ship when feature list is complete

Examples: API compliance, platform migrations, feature parity with competitor

**Quality-Constrained Projects**:
- Performance, security, or reliability requirements
- Both time and scope must flex
- Can't ship until quality bar is met

Examples: Medical devices, financial systems, infrastructure

**Most projects**: Time-constrained (ship for deadline, adjust scope)

### When to Cut Scope

Scope cuts should happen **early and often**, not as last-minute panic.

**Weekly review questions**:
1. If we shipped today, what would be broken/missing?
2. What are we most likely to cut if we run out of time?
3. What could we pre-cut now to increase confidence in shipping?

**Indicators you should cut scope**:
- It's Wednesday and you're not confident about Friday's shippable state
- You're accumulating technical debt faster than paying it
- Tests are being skipped "temporarily"
- Documentation is falling behind
- "We'll clean it up after shipping" appearing in conversation

**How to cut scope well**:
- Cut entire features, not quality of existing features
- Cut depth, not breadth (fewer powerful features beats many broken features)
- Hide features behind flags rather than deleting (easy to resurrect)
- Communicate cuts early to stakeholders

---

## Metrics That Matter

Traditional metrics (often misleading):
- Lines of code written
- Number of commits
- Features "in progress"
- Percentage complete

SSD metrics (actually useful):
- Days since last production deployment
- Percentage of code behind feature flags (target: <5%)
- Test coverage (and is it passing?)
- Mean time to deploy a change
- Number of shippable states per week

**Key metric**: **Deployment frequency**
- Once per month = traditional waterfall
- Once per week = decent
- Once per day = excellent
- Multiple times per day = world-class

**Platform note:** "Deployment" means pushing to your primary distribution channel. For web, that's the production server. For mobile, that's TestFlight / Play Internal Testing (daily). For App Store / Play Store production releases, weekly is excellent — daily is not possible due to review cycles. The metric that matters is: **how quickly can a committed change reach a real tester?**

If you can't deploy daily, you don't have shippable states—you have deployment problems masquerading as development problems.

---

## The Engineering Mindset

Shippable States Development is not a process—it's a **mindset**:

**Old mindset**: "We'll integrate and polish at the end"
**New mindset**: "Every day is a potential end"

**Old mindset**: "We need two weeks to deploy"
**New mindset**: "We deploy dozens of times per week"

**Old mindset**: "We must hit this deadline with all features"
**New mindset**: "We must hit this deadline with working software"

**Old mindset**: "This branch will be ready soon"
**New mindset**: "This feature is in production behind a flag"

**Old mindset**: "90% done"
**New mindset**: "These 5 things ship, these 3 things don't, all 5 working perfectly"

The methodology is simple: **maintain a deployable state at all times**.

The discipline is hard: **no shortcuts, no "we'll fix it later," no broken code on main**.

The payoff is enormous: **no death marches, predictable delivery, high quality, low stress**.
