## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# Swift — Language Reference

Loaded by `coder/SKILL.md` when the project is Swift (iOS, macOS, watchOS, tvOS, visionOS, or server-side Swift).

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Types (class, struct, enum, protocol) | UpperCamelCase | `UserProfile`, `PaymentStatus` |
| Functions / methods | lowerCamelCase, verb phrase | `fetchUser(byID:)`, `validateSubscription()` |
| Properties / variables | lowerCamelCase | `isActive`, `expirationDate` |
| Enum cases | lowerCamelCase | `.active`, `.cancelled` |
| Constants | lowerCamelCase (let) | `let maxRetryCount = 5` |
| Protocols | Noun or -able/-ing suffix | `Subscribable`, `UserProviding` |

Use full words. Abbreviations are acceptable only when they are universally understood (URL, ID, JSON, HTTP).

---

## File Organization

```swift
// MARK: - Imports
import Foundation
import Combine

// MARK: - Types
struct SubscriptionService {

    // MARK: Properties
    private let repository: SubscriptionRepositoryProtocol
    private let paymentGateway: PaymentGatewayProtocol

    // MARK: Init
    init(repository: SubscriptionRepositoryProtocol, paymentGateway: PaymentGatewayProtocol) {
        self.repository = repository
        self.paymentGateway = paymentGateway
    }

    // MARK: Public Interface
    func createSubscription(for user: User, plan: Plan) async throws -> Subscription { ... }

    // MARK: Private Helpers
    private func validateUserEligibility(_ user: User) throws { ... }
}
```

Use `// MARK: -` sections to divide large files. Each type gets its own file.

---

## Optionals

Treat optionals as a first-class part of the type system, not noise to work around.

```swift
// ❌ Force-unwrap crashes in production
let name = user.name!

// ✅ Guard early, return/throw on nil
guard let name = user.name else {
    throw UserError.missingName
}

// ✅ Optional chaining for reads
let city = user.address?.city ?? "Unknown"

// ✅ if let for conditional work
if let discount = coupon?.discount {
    amount -= discount
}
```

Never use `!` except in tests, `@IBOutlet`, and cases where nil is a programmer bug (not a runtime condition).

---

## Error Handling

Define typed errors with associated values:

```swift
enum SubscriptionError: LocalizedError {
    case alreadySubscribed
    case paymentFailed(reason: String)
    case planNotFound(planID: UUID)

    var errorDescription: String? {
        switch self {
        case .alreadySubscribed:
            return "User already has an active subscription."
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .planNotFound(let planID):
            return "Plan \(planID) not found."
        }
    }
}
```

Use `throws` + `try`/`catch` for recoverable errors. Use `Result<Success, Failure>` for values that cross async boundaries:

```swift
func createSubscription(for user: User, plan: Plan) async throws -> Subscription {
    guard !user.hasActiveSubscription else {
        throw SubscriptionError.alreadySubscribed
    }
    let payment = try await paymentGateway.charge(user: user, amount: plan.price)
    return try await repository.create(userID: user.id, planID: plan.id, payment: payment)
}
```

---

## Concurrency (Swift Concurrency / async-await)

Prefer structured concurrency over callbacks and Combine for new code:

```swift
// ✅ async/await
func loadDashboard() async throws -> Dashboard {
    async let user = userService.currentUser()
    async let subscriptions = subscriptionService.activeSubscriptions()
    return try await Dashboard(user: user, subscriptions: subscriptions)
}

// ✅ Task for fire-and-forget from sync context
Task {
    await analytics.track(.dashboardViewed)
}

// ✅ Actor for shared mutable state
actor SubscriptionCache {
    private var cache: [UUID: Subscription] = [:]

    func get(_ id: UUID) -> Subscription? { cache[id] }
    func set(_ subscription: Subscription) { cache[subscription.id] = subscription }
}
```

Annotate types that must run on the main actor:

```swift
@MainActor
final class SubscriptionViewModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []

    func load() async {
        do {
            subscriptions = try await service.fetchAll()
        } catch {
            // handle error
        }
    }
}
```

---

## Protocol-Oriented Design

Define behavior through protocols for testability and flexibility:

```swift
protocol SubscriptionRepositoryProtocol {
    func create(userID: UUID, planID: UUID, payment: Payment) async throws -> Subscription
    func fetchAll(forUserID userID: UUID) async throws -> [Subscription]
    func cancel(_ subscriptionID: UUID) async throws
}

// Production implementation
final class SubscriptionRepository: SubscriptionRepositoryProtocol { ... }

// Test double
final class MockSubscriptionRepository: SubscriptionRepositoryProtocol {
    var createdSubscriptions: [Subscription] = []
    func create(userID: UUID, planID: UUID, payment: Payment) async throws -> Subscription {
        let sub = Subscription(userID: userID, planID: planID)
        createdSubscriptions.append(sub)
        return sub
    }
}
```

---

## Value Types vs Reference Types

- Prefer `struct` for data (models, DTOs, value objects)
- Use `class` for things with identity, shared state, or lifecycle (view models, services, managers)
- Use `enum` for a fixed set of states or discriminated unions

```swift
// ✅ Data model as struct
struct Subscription: Identifiable, Codable {
    let id: UUID
    let planName: String
    let expiresAt: Date
    var status: Status

    enum Status: String, Codable {
        case active, paused, cancelled, expired
    }
}

// ✅ Service as class (has lifecycle, injected dependencies)
final class SubscriptionService {
    private let repository: SubscriptionRepositoryProtocol
    init(repository: SubscriptionRepositoryProtocol) {
        self.repository = repository
    }
}
```

---

## Testing (XCTest / Swift Testing)

```swift
// Using Swift Testing framework (Swift 5.9+)
import Testing

@Suite("SubscriptionService")
struct SubscriptionServiceTests {
    @Test("creates subscription for eligible user")
    func createSubscription() async throws {
        let repo = MockSubscriptionRepository()
        let gateway = MockPaymentGateway()
        let service = SubscriptionService(repository: repo, paymentGateway: gateway)

        let subscription = try await service.createSubscription(for: .fixture, plan: .pro)

        #expect(subscription.status == .active)
        #expect(repo.createdSubscriptions.count == 1)
    }

    @Test("throws alreadySubscribed when user has active plan")
    func createSubscriptionWhenAlreadySubscribed() async throws {
        let user = User.fixture(hasActiveSubscription: true)
        let service = SubscriptionService(repository: MockSubscriptionRepository(), paymentGateway: MockPaymentGateway())

        await #expect(throws: SubscriptionError.alreadySubscribed) {
            try await service.createSubscription(for: user, plan: .pro)
        }
    }
}
```

---

## Swift-Specific Quality Checklist

- [ ] No force-unwraps (`!`) outside of tests and `@IBOutlet`
- [ ] Optionals handled via `guard`, `if let`, or `??` — never ignored
- [ ] `async throws` used for async work — no completion handler callbacks in new code
- [ ] Shared mutable state isolated behind `actor`
- [ ] `@MainActor` applied to types/methods that update UI
- [ ] Protocol abstractions on all external dependencies (for testability)
- [ ] Value types (`struct`) used for data models
- [ ] No `AnyObject` or `Any` without a specific reason documented

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Crash on launch or in field | Force-unwrap on nil | Replace `!` with `guard let` or optional chaining |
| UI updates off main thread | Missing `@MainActor` | Annotate view model or dispatch to `MainActor.run {}` |
| Memory leak in async code | Strong capture in closure | Use `[weak self]` capture list |
| Data races in concurrency | Shared mutable state | Isolate behind `actor` |
| Test can't inject dependency | Concrete type, no protocol | Extract protocol, inject via init |
| Retain cycle in Combine | Strong `self` in `sink` | Use `[weak self]` in `sink` closure |
