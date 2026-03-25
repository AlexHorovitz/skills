## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# macOS Application Architecture Guide

World-class macOS apps feel native, respect the platform, and scale gracefully from MVP to complex product. This guide covers architecture for apps distributed via the Mac App Store or direct download.

---

## UI Framework Decision: SwiftUI vs AppKit

| Approach | When to Use |
|---|---|
| **SwiftUI (default)** | macOS 12+ target, new apps, most use cases |
| **AppKit** | Complex custom controls, document-based apps with extensive NSDocument use, very old OS support |
| **SwiftUI + AppKit bridging** | SwiftUI for most UI, `NSViewRepresentable` / `NSViewControllerRepresentable` for specific AppKit controls that SwiftUI doesn't expose |

**Default choice:** SwiftUI. AppKit is necessary for specific controls (e.g., `NSTextView` for rich text, `NSTableView` for virtual scrolling of huge lists) but should not be the primary framework for new apps.

---

## Architecture Pattern: MVVM + Clean Architecture

The standard for testable, maintainable macOS apps:

```
┌──────────────────────────────────────────────────────┐
│                    UI Layer (SwiftUI)                  │
│              Views, Scenes, NavigationStack            │
│              Observe ViewModel via @StateObject        │
└──────────────────────┬───────────────────────────────┘
                       │ publishes state, receives actions
┌──────────────────────▼───────────────────────────────┐
│               ViewModel Layer                          │
│   @Observable or ObservableObject classes              │
│   Transforms domain models into view state             │
│   Calls use cases / services                           │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│               Domain / Business Logic Layer            │
│   Use cases, domain models, protocols                  │
│   Pure Swift — no UIKit, AppKit, or SwiftUI imports    │
│   Fully unit testable                                  │
└──────────┬───────────────────────────────┬───────────┘
           │                               │
┌──────────▼──────────┐         ┌──────────▼──────────┐
│  Data Layer          │         │  Service Layer       │
│  (persistence)       │         │  (network, APIs)     │
│  SwiftData / CoreData│         │  URLSession + async  │
│  UserDefaults        │         │  await               │
└─────────────────────┘         └─────────────────────┘
```

**Rule:** The domain layer has zero dependencies on any framework — no SwiftUI, no AppKit, no SwiftData. It is plain Swift. This makes it trivially testable and portable.

### When to Use TCA (The Composable Architecture)

Consider TCA (from pointfreeco) if:
- Your app has complex state shared across many screens
- You need testable side effects
- Your team is experienced with it

Do not adopt TCA as your first architecture choice — it has a steep learning curve and is over-engineered for simple apps.

---

## App Structure

```
MyApp/
├── MyApp.swift                  — App entry point, @main
├── AppDelegate.swift            — Optional, for lifecycle hooks
│
├── Features/                    — One folder per feature / screen group
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   └── DashboardViewModel.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── SettingsViewModel.swift
│   └── ...
│
├── Domain/                      — Business logic, domain models
│   ├── Models/                  — Plain Swift structs/enums (no persistence annotations)
│   ├── UseCases/                — Business operations
│   └── Protocols/               — Interfaces for dependencies (repositories, services)
│
├── Data/                        — Persistence implementations
│   ├── SwiftData/               — @Model classes, ModelContainer setup
│   ├── Repositories/            — Concrete implementations of Domain protocols
│   └── Migrations/              — SwiftData or CoreData migration code
│
├── Services/                    — External integrations
│   ├── APIClient.swift          — Networking
│   ├── AuthService.swift
│   └── ...
│
├── Core/                        — App-wide utilities
│   ├── Extensions/
│   ├── Logger.swift             — os.Logger wrappers
│   └── AppEnvironment.swift     — Environment config (debug / release flags)
│
└── Resources/
    ├── Assets.xcassets
    ├── Localizable.xcstrings    — Use String Catalog (Xcode 15+)
    └── Info.plist
```

---

## Data Persistence

### Decision Matrix

| Use Case | Solution |
|---|---|
| Structured app data, relationships, complex queries | SwiftData (macOS 14+) or CoreData |
| Simple key-value preferences | UserDefaults (via `@AppStorage` in SwiftUI) |
| iCloud sync with Apple's infrastructure | CloudKit (standalone or via SwiftData/CoreData sync) |
| Large files, documents | FileManager + user-chosen locations via `NSOpenPanel` |
| Encrypted sensitive data (tokens, credentials) | Keychain via `Security` framework |
| High-performance queries, offline-first sync | SQLite directly (via GRDB or SQLite.swift) |

### SwiftData (Preferred for New Apps)

```swift
// Domain model (pure Swift — no SwiftData imports here)
struct Document {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
}

// Persistence model
@Model
final class DocumentRecord {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date

    init(from document: Document) {
        self.id = document.id
        self.title = document.title
        self.content = document.content
        self.createdAt = document.createdAt
    }

    func toDomain() -> Document {
        Document(id: id, title: title, content: content, createdAt: createdAt)
    }
}
```

Keep your `@Model` classes separate from domain models. The domain layer does not import SwiftData.

### CoreData Migration Strategy

If using CoreData:
- Use lightweight migrations for additive changes (new optional attribute, new entity)
- Use custom `NSMigrationPolicy` for any transformation of existing data
- Never ship a migration that can fail without a recovery path
- Test migrations against real production-size data before release

---

## Concurrency Model

macOS apps are async by nature. Use Swift concurrency (`async/await`) throughout. Never use completion handlers in new code.

```swift
// ViewModel
@MainActor
final class DocumentListViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let repository: DocumentRepository

    func loadDocuments() async {
        isLoading = true
        defer { isLoading = false }

        do {
            documents = try await repository.fetchAll()
        } catch {
            self.error = error
        }
    }
}
```

**Rules:**
- All UI updates on `@MainActor`
- All I/O (network, disk) on a background actor or `Task { ... }`
- Avoid `DispatchQueue.main.async` — use `@MainActor` instead
- Never call `Thread.sleep` or `DispatchSemaphore.wait` on the main thread

---

## App Sandbox & Entitlements

Sandbox is required for Mac App Store distribution. Plan for it early — retrofitting is painful.

### Common Entitlements

| Entitlement | When Needed |
|---|---|
| `com.apple.security.network.client` | Any outbound network requests |
| `com.apple.security.network.server` | Accepting inbound connections |
| `com.apple.security.files.user-selected.read-write` | Reading/writing user-chosen files |
| `com.apple.security.files.downloads.read-write` | Downloads folder access |
| `com.apple.security.personal-information.addressbook` | Contacts |
| `com.apple.security.device.camera` | Camera |
| `com.apple.security.device.microphone` | Microphone |

### Security-Scoped Bookmarks

For accessing files outside the sandbox across launches, you must use security-scoped bookmarks:

```swift
// When user selects a file via NSOpenPanel
let bookmarkData = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
// Persist bookmarkData to UserDefaults or SwiftData

// Later, to access the file again
var isStale = false
let resolvedURL = try URL(
    resolvingBookmarkData: bookmarkData,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)
resolvedURL.startAccessingSecurityScopedResource()
defer { resolvedURL.stopAccessingSecurityScopedResource() }
```

---

## Menu Bar & Window Management

### Window Architecture

macOS apps can have multiple windows. Design your state model accordingly.

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            AppCommands()  // Custom menu items
        }

        Settings {
            SettingsView()
        }

        // Menu bar extra (optional)
        MenuBarExtra("My App", systemImage: "circle.fill") {
            MenuBarView()
        }
    }
}
```

### State Restoration

Users expect apps to restore their previous state. Use `@SceneStorage` for window-level state:

```swift
struct ContentView: View {
    @SceneStorage("selectedTab") private var selectedTab = "home"
    @SceneStorage("searchQuery") private var searchQuery = ""
}
```

---

## Distribution Strategy

| Distribution | Requirements | Notes |
|---|---|---|
| **Mac App Store** | Sandbox, notarization, app review | Best for discoverability. Requires entitlement for every capability. |
| **Direct (signed + notarized)** | Developer ID certificate, notarization | Full control. Faster updates. User must allow in Security & Privacy if unsigned. |
| **TestFlight (Mac)** | Mac App Store account | Best beta distribution for Mac App Store apps. |

**Never ship an unnotarized app.** Gatekeeper blocks it by default on macOS 10.15+.

Notarization checklist:
- [ ] App signed with Developer ID Application certificate (direct) or Distribution certificate (MAS)
- [ ] Hardened Runtime enabled
- [ ] No deprecated/disallowed API usage
- [ ] `xcrun notarytool submit` passes
- [ ] `xcrun stapler staple` applied to DMG/PKG before distribution

---

## Performance

### Instruments — Use It Early

Profile before optimizing. The three most common macOS performance problems:

1. **Main thread I/O** — Use `Thread Sanitizer` and `Time Profiler` in Instruments. Any disk read/write or network call on the main thread is a bug.
2. **View body re-renders** — In SwiftUI, use `Self._printChanges()` in view bodies during development to detect unnecessary renders.
3. **Memory leaks / retain cycles** — Run Leaks instrument. Common cause: closures capturing `self` strongly in long-lived objects.

### SwiftUI Performance Rules

- `@Observable` (Swift 5.9 macro) is more performant than `ObservableObject` — use it for new code
- Break large views into smaller components with their own `@State` to limit render scope
- Use `LazyVStack` / `LazyHStack` for long lists
- Avoid heavy computation in `var body: some View` — compute in the ViewModel

---

## Accessibility

macOS has first-class accessibility. Required for App Store and best practice everywhere:

- All interactive elements have an accessibility label
- All images have alt text (`Image("x").accessibilityLabel("Description")`)
- Custom controls implement `AccessibilityRepresentation` or use `.accessibility*` modifiers
- Test with VoiceOver enabled (Cmd+F5) before each release
- Respect `@Environment(\.accessibilityReduceMotion)` — don't animate if the user asked not to

---

## Architecture Decisions for macOS Apps

Decisions to make explicitly before building:

1. **OS target**: minimum macOS version determines SwiftUI feature availability (use Swift Charts? SwiftData? `@Observable`?)
2. **Distribution**: App Store vs direct download — affects sandbox design from day one
3. **Persistence**: SwiftData vs CoreData vs SQLite vs UserDefaults-only
4. **iCloud sync**: yes/no, and which mechanism (CloudKit, iCloud Drive, SwiftData sync)
5. **Document-based vs single-window**: use `DocumentGroup` scene for document apps
6. **Menu bar presence**: main window app, menu bar extra only, or both
7. **Privileged operations**: if you need root access, plan XPC service + SMJobBless early — it's complex

---

## Walking Skeleton for macOS Apps

Day 1 must include:

1. App builds and launches on the minimum target OS
2. Main window with placeholder navigation
3. One real piece of persisted data: create it, see it in the UI, relaunch — still there
4. Basic Settings window
5. CI: Xcode Cloud or GitHub Actions builds and runs tests on every push
6. Archive and notarization working (even for a Hello World app)
7. Crash reporting wired up (Sentry, Bugsnag, or Crashlytics)

If distribution is Mac App Store: App Store Connect app record created and first TestFlight build submitted.
