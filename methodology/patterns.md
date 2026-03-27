# SSD Implementation Patterns

Concrete patterns for maintaining shippable states throughout development. Each pattern is platform-aware — the principle is universal, the mechanism adapts to your stack.

---

## Pattern 1: Deployed Day One

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

---

## Pattern 2: Walking Skeleton

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

---

## Pattern 3: Dark Launching

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

---

## Pattern 4: Timebox with Eject

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

---

## Pattern 5: The Nightly Ritual

End each day with a shippable state.

**Daily checklist** (last 30 minutes of work):
```
□ All tests pass locally
□ Code committed and pushed
□ CI/CD pipeline green
□ Latest build available in distribution channel (staging URL / TestFlight / Play Internal / notarized build)
□ Feature flags set appropriately
□ Documentation updated if APIs changed
□ Tomorrow's first task identified
```

**Mental model**: Your future self (or your teammate) should be able to pick up exactly where you left off, with no confusion about what state things are in.

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
