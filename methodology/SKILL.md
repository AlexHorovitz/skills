## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Shippable States Development (SSD)

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

## Implementation Patterns

### Pattern 1: Deployed Day One

**Universal Day 1 checklist** (every platform):
```
□ Build system producing a deployable artifact
□ Artifact deployed to a real distribution channel
□ CI pipeline running tests on every push
□ Monitoring / crash reporting wired up
□ One route or screen returns "Hello World"

This is your MVP. It does nothing useful, but it's REAL.
```

**What "Deployed Day One" means per platform:**

| Step | Web | iOS | Android | macOS | Headless |
|---|---|---|---|---|---|
| Distribution channel | Domain + SSL + server | TestFlight | Play Internal Testing | Notarize + distribute | Container registry |
| Deployable artifact | Deployed bundle | .ipa archive | .aab bundle | Signed .app | Docker image |
| CI system | GitHub Actions | Xcode Cloud / GH Actions | GH Actions / Bitrise | Xcode Cloud / GH Actions | GH Actions |
| Crash reporting | Sentry + Datadog | Crashlytics / Sentry | Crashlytics / Sentry | Sentry / Bugsnag | Sentry + metrics endpoint |

For detailed Day 1 checklists per platform, see the architect platform guides (`architect/web/`, `architect/ios/`, `architect/android/`, `architect/macos/`, `architect/headless/`).

**Why**: If deployment takes 2 weeks and you budget 0 weeks, you're starting 2 weeks late on day one.

### Pattern 2: Walking Skeleton

Build one feature "end to end" before building any feature "fully complete."

**Traditional**: Build all UI, then all backend/persistence, then connect them
**SSD**: Build one flow through user action → persistence → verify → back to user

**Example: Todo App**

❌ **Wrong order**:
1. Design all UI screens (login, todo list, settings, sharing, etc.)
2. Build all database tables / persistence layer
3. Write all API endpoints / services
4. Connect everything
5. Discover they don't fit together

✅ **Right order**:
1. Build login flow end-to-end (user action → persist → relaunch → still there)
2. Build "add todo" end-to-end
3. Build "complete todo" end-to-end
4. Build "delete todo" end-to-end
5. Each step shippable (even if feature set is minimal)

"End-to-end" means different things by platform: on web, UI → API → DB → response. On iOS, View → SwiftData → relaunch → verify. On Android, Compose → Room → relaunch → verify. The principle is the same: one complete flow before breadth.

### Pattern 3: Dark Launching

Launch features in production before they're visible to users.

**Technique**:
```javascript
// JavaScript (Web)
if (featureFlags.newDashboard && user.isInternalTester) {
  return <NewDashboard />;
}
return <OldDashboard />;
```

```swift
// Swift (iOS / macOS)
if featureFlags.isEnabled("newDashboard", user: user) {
    return NewDashboardView()
}
return OldDashboardView()
```

```kotlin
// Kotlin (Android)
if (featureFlags.isEnabled("newDashboard", user)) {
    NewDashboardScreen()
} else {
    OldDashboardScreen()
}
```

**Benefits**:
- Test in production without risk
- Gradual rollout (internal → beta → everyone)
- Easy rollback (flip flag)
- Development never blocks deployment

**Platform note**: Web feature flags can be server-side (hot-swap, no deploy needed). Mobile and desktop feature flags use an SDK (Firebase Remote Config, LaunchDarkly) and typically take effect on next app launch. Plan accordingly — flag changes are not instant on mobile.

**Critical rule**: Feature is not "done" until the flag is removed. Flag code is technical debt—pay it off quickly.

### Pattern 4: Timebox with Eject

For risky or exploratory work, timebox it with a pre-committed eject plan.

**Pattern**:
```
"We'll spend 3 days exploring this approach.
On day 3, we decide: ship it, iterate it, or abandon it.
If abandon, we revert to last shippable state."
```

**This prevents**:
- Sunk cost fallacy ("we've invested so much...")
- Endless exploration
- Half-finished experiments sitting in the codebase

**Key**: The eject plan must be decided BEFORE starting, not when you're attached to the code.

### Pattern 5: The Nightly Ritual

End each day with a shippable state.

**Daily checklist** (last 30 minutes of work):
□ All tests pass locally
□ Code committed and pushed
□ CI/CD pipeline green
□ Latest build available in distribution channel (staging URL / TestFlight / Play Internal / notarized build)
□ Feature flags set appropriately
□ Documentation updated if APIs changed
□ Tomorrow's first task identified

**Mental model**: Your future self (or your teammate) should be able to pick up exactly where you left off, with no confusion about what state things are in.

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

### vs. Continuous Deployment

**SSD ⊆ Continuous Deployment**

SSD is the **engineering discipline** that makes continuous deployment possible. CD is the **automation** that enforces SSD.

- SSD: "We maintain shippable states"
- CD: "We automatically deploy those states"

You can do SSD without full CD (deploy manually but frequently). You cannot do CD without SSD (nothing to deploy).

### vs. Trunk-Based Development

**Highly compatible**. Trunk-based development is one **implementation** of SSD principles.

SSD adds:
- Production deployment from day one
- Explicit shippable state invariant
- Scope flexibility framework

### vs. Feature-Driven Development

**Key conflict**:

FDD: Features are the organizing principle
SSD: Shippable states are the organizing principle

**Resolution**: Use feature flags
- Work is organized around features (FDD)
- Features hidden until shippable (SSD)
- Best of both worlds

---

## Advanced Topics

### Handling Dependencies

**Problem**: "We can't ship the UI until the backend API is ready"

**SSD solution**: Mock the dependency with a proper contract. The language differs, the principle doesn't.

```typescript
// API contract (Day 1)
interface UserService {
  getUser(id: string): Promise<User>;
  updateUser(id: string, data: Partial<User>): Promise<User>;
}

// Mock implementation (Day 1-3)
class MockUserService implements UserService {
  async getUser(id: string) {
    return { id, name: "Test User", email: "test@example.com" };
  }
  // ...
}

// Real implementation (Day 4+)
class ApiUserService implements UserService {
  async getUser(id: string) {
    return fetch(`/api/users/${id}`).then(r => r.json());
  }
  // ...
}
```

The same pattern in Swift:

```swift
// Swift
protocol UserService {
    func getUser(id: UUID) async throws -> User
    func updateUser(id: UUID, data: UserUpdate) async throws -> User
}

// Mock implementation (Day 1-3)
struct MockUserService: UserService {
    func getUser(id: UUID) async throws -> User {
        User(id: id, name: "Test User", email: "test@example.com")
    }
    // ...
}

// Real implementation (Day 4+)
struct APIUserService: UserService {
    func getUser(id: UUID) async throws -> User {
        // network call
    }
    // ...
}
```

**Result**: UI team ships daily with mock, swaps to real implementation when ready. No blocking dependencies.

### Monorepo vs Polyrepo

**SSD works with both**, but has opinions:

**Monorepo advantages for SSD**:
- Atomic commits across services
- Shared tooling/CI
- Easier to maintain internal consistency

**Polyrepo with SSD requires**:
- Strong API contracts
- Version pinning discipline
- More sophisticated CI/CD

**Recommendation**: Monorepo for startups/small teams, polyrepo for large orgs with clear service boundaries

### Database Migrations

**Critical for shippable states**: Database changes must be backward-compatible

**Wrong** (breaks shippable states):
```sql
-- Breaks existing code instantly
ALTER TABLE users DROP COLUMN old_name;
ALTER TABLE users ADD COLUMN new_name VARCHAR(255);
```

**Right** (maintains shippable states):
```sql
-- Day 1: Add new column
ALTER TABLE users ADD COLUMN new_name VARCHAR(255);

-- Day 2-3: Dual write to both columns in application code

-- Day 4: Backfill old data
UPDATE users SET new_name = old_name WHERE new_name IS NULL;

-- Day 5: Switch reads to new column

-- Day 6: Drop old column (after verifying no code uses it)
ALTER TABLE users DROP COLUMN old_name;
```

**Pattern**: Expand → Migrate → Contract (each step shippable)

### Handling Emergencies

**"But what if there's a critical production bug?"**

**With shippable states**:
1. Fix bug on trunk
2. Tests pass (you have tests, right?)
3. Deploy immediately
4. Total time: 30 minutes

**Without shippable states**:
1. Figure out which branch has the bug
2. Try to fix just the bug without breaking in-progress work
3. Merge hell with conflicting changes
4. Deploy and hope
5. Total time: 4 hours + prayers

**Shippable states make emergencies routine**. Every deployment is low-risk because you deploy dozens of times per week.

---

## Conclusion: The Engineering Mindset

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

## Resources for Deeper Learning

**Books**:
- *Accelerate* by Forsgren, Humble, Kim (research on high-performing teams)
- *Continuous Delivery* by Humble and Farley (deployment automation)
- *The Phoenix Project* by Kim et al (DevOps principles in narrative form)

**Practices to study**:
- Trunk-based development
- Continuous Integration
- Feature flags / Feature toggles
- Blue-green deployments
- Database migrations
- Contract testing

**Key insight**: None of these ideas are new. What's new is combining them into a **coherent discipline** that solves the "90% done" problem.

High-performing teams have been doing this for years—now you can too.