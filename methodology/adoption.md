# SSD Adoption Guide

Reference material for teams adopting SSD, evaluating it against other methodologies, and getting started. Not needed in most AI coding sessions — load this when the user has questions about team dynamics, objections, or onboarding.

---

## Getting Started Checklist

Week 1: **Foundation**
- [ ] Set up CI/CD pipeline
- [ ] Deploy "Hello World" to your distribution channel (production server, TestFlight, Play Internal, notarized build)
- [ ] Configure automated testing
- [ ] Establish feature flag system (server-side for web, SDK-based for mobile/desktop)

Week 2: **First Feature**
- [ ] Build one feature end-to-end
- [ ] Deploy to production (behind flag)
- [ ] Verify in production
- [ ] Enable for internal users

Week 3: **Rhythm**
- [ ] Deploy to production daily
- [ ] Every commit passes CI
- [ ] All features behind flags
- [ ] Documentation current

Week 4: **Optimization**
- [ ] Reduce deploy time
- [ ] Increase test coverage
- [ ] Remove old feature flags
- [ ] Retrospective: what's working?

Platform-specific Day 1 checklists are in the architect platform guides (`architect/web/`, `architect/ios/`, `architect/android/`, `architect/macos/`, `architect/headless/`).

**Success criteria**: On day 30, you should be able to deploy to your distribution channel with confidence in under 10 minutes.

If you can't, you've identified your constraints. Fix those first.

---

## Common Objections Addressed

### "This sounds like more work"

**You're doing the work either way**. Two options:

A) Panic-driven development:
- Days 1-85: Build features, ignore deployment/testing/edge cases
- Days 86-90: Discover deployment takes a week
- Days 91-100: Frantic debugging, cutting corners, shipping half-broken product

B) Shippable States Development:
- Every day: Build features + deployment + testing + edge cases incrementally
- Day 90: Ship the fully-working subset you completed
- Days 91-100: Already shipped, now working on v2

Same total effort, drastically different stress level and quality.

### "Our stakeholders need to see progress"

**SSD gives you better demos**:

Traditional: "Here's a mockup... this button doesn't work yet... imagine when this is connected to the backend..."

SSD: "Here's the actual working product. It doesn't do X yet, but everything you see actually works. Press any button."

**Which demo builds more confidence?**

### "We need to iterate quickly, not worry about shipping"

**False dichotomy**. Shippable states don't slow iteration—they enable it.

**With shippable states**:
- Every iteration is testable by real users
- No "integration phase" blocking feedback
- Can pivot immediately based on feedback
- Sunk cost is always minimal (already shipped working version)

**Without shippable states**:
- Feedback requires waiting for integration
- Pivots expensive (so much half-done work to throw away)
- High sunk cost creates path dependency

### "This won't work for our domain/language/framework"

The principles apply universally to digital work:

- **Web apps**: Deploy to production server daily
- **iOS apps**: Submit to TestFlight daily
- **Android apps**: Push to Play Internal Testing daily
- **macOS apps**: Archive, notarize, and distribute daily
- **ML models**: Train and deploy to staging daily
- **Hardware firmware**: Flash to test devices daily
- **Content/writing**: Publish drafts to private URLs daily
- **Infrastructure**: Apply Terraform changes to dev account daily

The specific **mechanisms** differ, but the **principle** is the same: maintain production parity and shippable states.

### "This won't work for mobile / desktop apps"

It works. The mechanisms differ; the principle doesn't.

**Deployment frequency**: You cannot deploy to the App Store daily (review takes 1-3 days). But you CAN deploy to TestFlight / Play Internal Testing daily. SSD targets the *internal deployment pipeline*, not the store review process. TestFlight is your "production" for SSD purposes until you cut a release.

**Feature flags on mobile**: Use Firebase Remote Config, LaunchDarkly, or a custom remote config service. Flag changes take effect on next app launch (not instant like web). Design your flag checks to handle this gracefully.

**"But App Store review takes days"**: SSD distinguishes between *internal deploy* (daily — TestFlight / Play Internal Testing) and *production release* (weekly or biweekly — App Store / Play Store). The shippable state invariant applies to the internal deploy. When you cut a store release, it should be a non-event because you've been shipping to testers daily.

**macOS desktop**: Notarization is your deployment gate. Automate it in CI from Day 1 so it never becomes a bottleneck. Direct distribution (signed + notarized DMG) gives you web-like deployment frequency. Mac App Store distribution has review cycles similar to iOS.

**Cross-platform projects**: If your project spans multiple platforms (e.g., iOS app + backend API), each platform maintains its own shippable state independently. The backend deploys to production; the mobile app deploys to TestFlight. Both are shippable at all times.

### "My team isn't disciplined enough"

**This is exactly why you need this**. Discipline problems are solved with systems, not willpower.

Undisciplined team with SSD:
- CI/CD pipeline forces tests to pass
- Can't commit broken code (pipeline blocks it)
- Daily deployments force completion
- Visible production state keeps everyone honest

Undisciplined team without SSD:
- "I'll fix it later" accumulates
- No external forcing function
- Last-minute chaos reveals accumulated debt

**SSD creates discipline through automation and forcing functions**.

---

## Organizational Adoption

### Start Small: One Team, One Project

**Don't**: Mandate company-wide adoption on day one

**Do**: Find one willing team on one project to pilot

**Pilot project characteristics**:
- Greenfield if possible (no legacy constraints)
- 2-6 week timeline
- Team actually wants to try this
- Has clear success metrics

### Create Forcing Functions

**Automate enforcement**:
```yaml
# CI/CD pipeline
on_commit:
  - run_tests (block if fail)
  - check_coverage (block if decreased)
  - deploy_to_staging (automatic)
  - smoke_tests (block if fail)

on_main_branch:
  - deploy_to_production (automatic or 1-click)
```

**Human discipline fails. Automated enforcement succeeds.**

### Communicate in Business Terms

To executives:
- "Reduces last-minute delays by deploying continuously"
- "Lower risk: every release is small and reversible"
- "Faster time to market: can ship any feature independently"

To product managers:
- "Better visibility: see working features daily, not mockups"
- "Flexible scope: can adjust priorities based on progress"
- "Earlier feedback: users test real features, not prototypes"

To engineers:
- "Less merge hell: everyone on trunk"
- "Better work-life balance: no heroic end-of-sprint crunches"
- "Build resume: modern practices like CI/CD, feature flags"

### Reward the Right Behaviors

**Celebrate**:
- First production deployment
- 100th consecutive day of green CI
- Successful scope cut that saved the project
- Quick rollback of broken feature

**Don't celebrate**:
- "Heroic" all-nighters (system failure, not success)
- Hitting deadlines with broken features
- "Percentage complete" milestones

---

## Comparison to Other Methodologies

> *Comparisons last reviewed: 2026-05-24. Per `methodology/SKILL.md`, refresh if > 12 months old.*

### vs. Agile/Scrum

**Compatible**:
- Iterative development ✓
- Customer feedback ✓
- Flexible scope ✓

**Key difference**:
- Agile: "Potentially shippable at end of sprint"
- SSD: "Actually shippable at end of each day"

**Improves Agile by**:
- Eliminating "done vs done-done" confusion
- Forcing infrastructure work up front
- Making retrospectives concrete (did we ship?)

**At small team size (1–5), standard Scrum fails** — it was designed for 5–9 person teams with a dedicated Scrum Master and Product Owner. Below 3 people, the ceremony costs more than it delivers. See the full analysis at [insanelygreat.com/scrum-alternatives.html](https://insanelygreat.com/scrum-alternatives.html).

### vs. Continuous Deployment / Continuous Delivery

**SSD ⊆ Continuous Deployment**, but with a stricter cadence requirement.

- **Continuous Delivery**: software *can* be shipped at any time.
- **Continuous Deployment**: software *is* automatically shipped whenever it passes CI.
- **Shippable States Development**: software *is* shipped every working day, and a day without a ship is treated as a process failure.

SSD is the **engineering discipline** that makes continuous deployment safe and sustainable. CD is the **automation** that enforces the discipline. You can do SSD without full automation (deploy manually but frequently). You cannot do meaningful CD without SSD (you'd be automating shipping broken code).

### vs. Trunk-Based Development

**Highly compatible**. Trunk-based development is one **implementation** of SSD principles.

SSD adds:
- Production deployment from day one
- Explicit shippable state invariant
- Scope flexibility framework
- Daily-ship cadence requirement

### vs. Feature-Driven Development

**Key conflict**:

FDD: Features are the organizing principle
SSD: Shippable states are the organizing principle

**Resolution**: Use feature flags
- Work is organized around features (FDD)
- Features hidden until shippable (SSD)
- Best of both worlds

### vs. Shape Up

**Compatible for 3–5 person teams doing discrete feature work**.

Shape Up's 6-week cycles + cool-down rhythm can run *inside* SSD: the daily-ship invariant continues to hold within each cycle. SSD provides the engineering discipline (shippable states, feature flags, the ratchet); Shape Up provides a product-bet rhythm. The two compose cleanly.

**Where they diverge**: Shape Up assumes a betting table and a product manager. For solo developers, this overhead is wasted. Use SSD alone.

### vs. Kanban

**SSD provides what Kanban omits.** Kanban specifies flow and WIP limits but is silent on shipping discipline. Pair them: Kanban for the board and pull-based flow; SSD for the deployment cadence and code-quality ratchet.

### Decision summary

| Team size | Work shape | Best fit |
|---|---|---|
| 1 (solo) | Continuous product | SSD |
| 2–3 | Continuous product | SSD |
| 3–5 | Discrete feature bets | SSD + Shape Up cycles |
| 3–5 | Interrupt-driven / support | SSD + minimal Kanban |
| 6+ | Mixed | SSD + Scrum-lite ceremonies as needed |

Full comparison: [insanelygreat.com/methodologies-small-teams.html](https://insanelygreat.com/methodologies-small-teams.html).

---

## Resources for Deeper Learning

**Canonical methodology pages** (insanelygreat.com):
- [Shippable States Development](https://insanelygreat.com/ssd.html) — the methodology in full, with FAQ and structured data
- [The InsanelyGreat Guide](https://insanelygreat.com/guide.html) — practical, opinionated implementation
- [Agile²](https://insanelygreat.com/agile2.html) — companion manifesto on process-as-tool
- [The Solo Developer's Engineering Manifesto](https://insanelygreat.com/solo-developer-manifesto.html) — for the team of one
- [Code Quality Without a QA Team: The Ratchet Principle](https://insanelygreat.com/ratchet-principle.html) — quality encoded in CI, with a working GitHub Actions example
- [Why Standard Scrum Fails Small Teams](https://insanelygreat.com/scrum-alternatives.html)
- [How Small Teams Should Think About Releases](https://insanelygreat.com/releases-small-teams.html)
- [The Simplest Engineering Lifecycle That Actually Works](https://insanelygreat.com/simplest-lifecycle.html)
- [Methodologies for Small Teams: An Honest Comparison](https://insanelygreat.com/methodologies-small-teams.html)

**Books**:
- *Accelerate* by Forsgren, Humble, Kim (research on high-performing teams)
- *Continuous Delivery* by Humble and Farley (deployment automation)
- *The Phoenix Project* by Kim et al (DevOps principles in narrative form)
- *Shape Up* by Ryan Singer (cycles and cool-down for product bets)

**Practices to study**:
- Trunk-based development
- Continuous Integration
- Feature flags / Feature toggles
- Dark launching and gradual rollouts
- Blue-green deployments
- Database migrations
- Contract testing

**Key insight**: None of these ideas are new. What's new is combining them into a **coherent discipline** that solves the "90% done" problem.

High-performing teams have been doing this for years—now you can too.
