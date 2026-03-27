<!-- License: See /LICENSE -->


# iOS / iPadOS Application Architecture Guide

World-class iOS apps are fast, responsive, and feel native. They handle unreliable networks gracefully, respect privacy, and pass App Store review without drama. This guide covers architecture for iPhone and iPad apps.

---

## UI Framework Decision: SwiftUI vs UIKit

| Approach | When to Use |
|---|---|
| **SwiftUI (default)** | iOS 16+ target, most new apps |
| **UIKit** | Complex custom animations, intricate gesture handling, very old OS support, existing UIKit codebase |
| **SwiftUI + UIKit bridging** | SwiftUI for most UI, `UIViewRepresentable` / `UIViewControllerRepresentable` for specific UIKit controls |

**Default choice:** SwiftUI. UIKit is appropriate for specific needs (custom `UICollectionView` layouts, complex custom transitions) but should not be chosen by default for new apps.

---

## Architecture Pattern: MVVM + Clean Architecture

```
┌──────────────────────────────────────────────────────┐
│                UI Layer (SwiftUI / UIKit)              │
│          Views, Screens, NavigationStack               │
│          Observes ViewModel state                      │
└──────────────────────┬───────────────────────────────┘
                       │ state / actions
┌──────────────────────▼───────────────────────────────┐
│               ViewModel Layer                          │
│   @Observable or ObservableObject                      │
│   Transforms domain models into display state          │
│   Calls use cases                                      │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│          Domain / Business Logic Layer                 │
│   Use cases, domain models, protocols                  │
│   Pure Swift — zero framework imports                  │
│   Fully unit testable without a simulator              │
└──────────────┬────────────────────────────┬──────────┘
               │                            │
┌──────────────▼──────────┐    ┌────────────▼──────────┐
│  Data Layer (persistence)│    │  Service Layer (API)   │
│  SwiftData / CoreData    │    │  URLSession + async    │
│  UserDefaults / Keychain │    │  await                 │
└─────────────────────────┘    └───────────────────────┘
```

**Rule:** The domain layer contains zero framework imports. It is pure Swift structs, enums, and protocols. This guarantees every piece of business logic is testable without a device or simulator.

### Considering TCA (The Composable Architecture)

TCA is a good fit when:
- Complex shared state across many screens
- Need for testable side effects (timers, notifications, network)
- Team has prior TCA experience

Do not use TCA as a default. It is substantial complexity for small apps.

---

## App Structure

```
MyApp/
├── MyApp.swift                  — @main App entry point
│
├── Features/                    — One folder per feature
│   ├── Home/
│   │   ├── HomeView.swift
│   │   └── HomeViewModel.swift
│   ├── Profile/
│   │   ├── ProfileView.swift
│   │   └── ProfileViewModel.swift
│   └── Onboarding/
│       ├── OnboardingView.swift
│       └── OnboardingViewModel.swift
│
├── Domain/
│   ├── Models/                  — Plain Swift structs/enums, no persistence annotations
│   ├── UseCases/                — Business operations (one struct/class per use case)
│   └── Protocols/               — Interfaces for repositories and services
│
├── Data/
│   ├── SwiftData/               — @Model classes, ModelContainer setup
│   ├── Repositories/            — Concrete implementations of Domain protocols
│   └── DTOs/                    — Decodable structs for API responses (not domain models)
│
├── Services/
│   ├── APIClient.swift          — Base networking
│   ├── AuthService.swift
│   └── NotificationService.swift
│
├── Core/
│   ├── Extensions/
│   ├── DependencyContainer.swift — Simple DI setup
│   └── Logger.swift             — os.Logger wrappers
│
└── Resources/
    ├── Assets.xcassets
    ├── Localizable.xcstrings    — String Catalog (Xcode 15+)
    └── Info.plist
```

---

## Navigation Architecture

### SwiftUI Navigation (iOS 16+)

Use `NavigationStack` with `NavigationPath` for programmatic navigation. Avoid `NavigationView` in new code.

```swift
// App-level coordinator
@Observable
final class AppRouter {
    var path = NavigationPath()

    func navigate(to destination: AppDestination) {
        path.append(destination)
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

enum AppDestination: Hashable {
    case profile(userID: UUID)
    case settings
    case itemDetail(itemID: UUID)
}

// Root view
struct RootView: View {
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .profile(let id): ProfileView(userID: id)
                    case .settings: SettingsView()
                    case .itemDetail(let id): ItemDetailView(itemID: id)
                    }
                }
        }
        .environment(router)
    }
}
```

**Tab bars:** Use `TabView`. Each tab should have its own `NavigationStack` — do not share a single path across tabs.

---

## Data Persistence

| Use Case | Solution |
|---|---|
| Structured app data, relationships | SwiftData (iOS 17+) or CoreData |
| Simple key-value preferences | UserDefaults / `@AppStorage` |
| Tokens, credentials, sensitive data | Keychain (`Security` framework) |
| iCloud sync | CloudKit or SwiftData + CloudKit sync |
| Large media files | FileManager in app's Documents directory |
| High-performance offline-first sync | SQLite via GRDB |

### SwiftData Setup (Preferred)

```swift
// @main
@main
struct MyApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            UserRecord.self,
            ItemRecord.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
```

Keep `@Model` classes separate from domain models. The domain layer never imports SwiftData.

---

## Networking

### URLSession + async/await (Default)

```swift
struct APIClient {
    private let session: URLSession
    private let baseURL: URL
    private let authProvider: AuthProvider

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(await authProvider.currentToken())",
            forHTTPHeaderField: "Authorization"
        )

        if let body = endpoint.body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

**Rules:**
- Never call network code from a SwiftUI `View` body
- All network calls are `async throws`
- Decode into DTOs first, then map to domain models
- Handle offline state explicitly — show cached data, not a blank screen

---

## Concurrency

- All UI updates happen on `@MainActor` — mark ViewModels with `@MainActor`
- Background work (network, disk) happens in `Task { }` or on a custom `Actor`
- Never use `DispatchQueue` in new code. Use `async/await` and actors.
- `Task.detached` is rarely needed and often wrong — use structured concurrency

```swift
@MainActor
@Observable
final class ItemListViewModel {
    var items: [Item] = []
    var isLoading = false
    var errorMessage: String?

    private let useCase: FetchItemsUseCase

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await useCase.execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

---

## Push Notifications

Plan your notification architecture before building the app. Retrofitting is painful.

```swift
// AppDelegate or @main
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
}

// Request permission at the right moment (not on cold launch)
func requestNotificationPermission() async -> Bool {
    do {
        return try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
    } catch {
        return false
    }
}
```

**Rules:**
- Never request notification permission on first launch. Explain value first.
- Register for remote notifications after permission granted
- Send device token to your server immediately after registration (tokens rotate)
- Handle notification taps that launch the app from cold state (deep link into content)
- Silent notifications for background refresh must be handled gracefully (system may throttle)

---

## Privacy & App Tracking Transparency

iOS 14.5+ requires user permission before tracking. Plan for this:

- Add `NSUserTrackingUsageDescription` to Info.plist
- Call `ATTrackingManager.requestTrackingAuthorization` before any tracking
- App must function fully if the user denies tracking
- Privacy Manifest (required since iOS 17): declare all privacy-sensitive API usage

Required privacy manifest entries for common operations:
- `NSPrivacyAccessedAPITypes`: disk space, file timestamps, user defaults, system boot time
- Data use declarations: every data type you collect, with purpose and linkage to identity

---

## Background Processing

| Need | API |
|---|---|
| Periodic data sync | `BGAppRefreshTask` |
| Long data processing | `BGProcessingTask` |
| Network calls while backgrounded | Background URLSession |
| Real-time updates while backgrounded | Silent push notifications |

Register background tasks in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers` and in code during `applicationDidFinishLaunching`. The system decides when to run them — you only request.

---

## Dependency Injection

Avoid singletons. Use constructor injection for testability.

```swift
// Simple DI container (no third-party library needed for most apps)
struct AppDependencies {
    let apiClient: APIClient
    let authService: AuthService
    let itemRepository: ItemRepository

    static func live() -> AppDependencies {
        let apiClient = APIClient(baseURL: Config.apiURL)
        let authService = AuthService(apiClient: apiClient)
        let itemRepository = ItemRepositoryImpl(apiClient: apiClient)
        return AppDependencies(
            apiClient: apiClient,
            authService: authService,
            itemRepository: itemRepository
        )
    }

    static func preview() -> AppDependencies {
        // Stub implementations for SwiftUI previews
        AppDependencies(
            apiClient: MockAPIClient(),
            authService: MockAuthService(),
            itemRepository: MockItemRepository()
        )
    }
}
```

Pass dependencies via SwiftUI `.environment` or ViewModel initializers. Never use `shared` singletons.

---

## SwiftUI Previews

Previews are your fast feedback loop. They only work if your architecture allows it.

- Every View must be previewable without a real network or database
- Use `static func preview()` factories on your dependency container
- Use `@Previewable @State` (Xcode 16+) for stateful previews
- Previews that work = architecture that's properly decoupled

---

## Performance

### Key Rules

- Never do work in `var body: some View` — compute in ViewModel
- Use `@Observable` (Swift 5.9) instead of `ObservableObject` for better render granularity
- Use `LazyVStack` / `LazyHStack` / `List` (which is already lazy) for any scrolling list
- Profile with Instruments — Time Profiler for CPU, Allocations for memory
- Main thread is sacred: no disk I/O, no network calls, no heavy computation

### Memory

- Watch for retain cycles in closures: `[weak self]` when capturing self in long-lived closures
- Use `@WeakReference` wrappers for delegate patterns
- Cache images with `NSCache` — never hold all images in memory simultaneously
- Run Instruments Leaks before every TestFlight release

---

## App Store Checklist

Before submitting to App Store review:

- [ ] App runs on minimum supported iOS version
- [ ] iPad layout tested (if not iPad-only, Universal apps must look correct on iPad)
- [ ] Dark Mode supported
- [ ] Dynamic Type supported (respect `@Environment(\.dynamicTypeSize)`)
- [ ] VoiceOver passes basic test (every interactive element labeled)
- [ ] Privacy Manifest present and accurate
- [ ] ATT prompt implemented (if tracking)
- [ ] All required Info.plist usage descriptions present
- [ ] In-App Purchase implemented via StoreKit 2 (if applicable)
- [ ] No private API usage (`@_silgen_name`, undocumented selectors)
- [ ] App does not crash on launch on any supported device

---

## Architecture Decisions for iOS Apps

Decisions to make explicitly before building:

1. **Minimum iOS version**: this determines which APIs are available (SwiftData = iOS 17, `@Observable` = iOS 17, `NavigationStack` = iOS 16)
2. **Universal vs iPhone-only**: Universal apps require iPad layout work from the start
3. **Persistence strategy**: SwiftData vs CoreData vs network-only (no local storage)
4. **iCloud sync**: yes/no, mechanism
5. **Offline support**: none vs cached reads vs full offline-first
6. **Auth mechanism**: Sign in with Apple (required if any social login exists), email/password, magic link
7. **Monetization**: free, IAP (consumable, non-consumable, subscription), freemium — affects architecture if StoreKit 2 is involved
8. **Push notifications**: APNs directly vs Firebase Cloud Messaging vs third-party (OneSignal, etc.)

---

## Walking Skeleton for iOS Apps

Day 1 must include:

1. App builds and runs on minimum target device/simulator
2. Main tab/navigation structure in place (empty screens are fine)
3. One piece of data persisted end-to-end: create → persist → relaunch → still there
4. Authenticated session working: log in → token stored in Keychain → cold launch restores session
5. CI: Xcode Cloud or GitHub Actions builds and runs tests on every push
6. App archived and submitted to TestFlight (even a Hello World build)
7. Crash reporting wired up (Sentry, Crashlytics, or Bugsnag)
8. App Store Connect record created with bundle ID matching the app
