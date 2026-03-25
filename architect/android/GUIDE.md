## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Android Application Architecture Guide

World-class Android apps work on thousands of device configurations, handle process death gracefully, and feel fast on mid-range hardware. This guide covers architecture for apps distributed via Google Play.

---

## UI Framework: Jetpack Compose (Default)

**Use Jetpack Compose** for all new Android apps. The View system (XML layouts) is in maintenance mode. Interop between Compose and Views is excellent when you need to embed existing View-based components.

| Approach | When to Use |
|---|---|
| **Jetpack Compose (default)** | All new apps and new screens |
| **View system (XML)** | Maintaining existing View-based code, embedding complex custom Views |
| **Compose + View interop** | `AndroidView` composable wraps legacy Views in Compose; `ComposeView` embeds Compose in legacy View hierarchy |

Minimum SDK for full Compose feature set: **API 24** (Android 7.0). Target SDK should always be the latest stable API.

---

## Architecture: MVVM + Clean Architecture (Official Android Recommendation)

This is the architecture documented in the Android developer guides. Follow it unless you have a strong reason not to.

```
┌──────────────────────────────────────────────────────┐
│                  UI Layer (Compose)                    │
│          Composable functions, Screens                 │
│          Collect UiState from ViewModel                │
└──────────────────────┬───────────────────────────────┘
                       │ UiState / events
┌──────────────────────▼───────────────────────────────┐
│               ViewModel Layer                          │
│   Extends ViewModel (survives config changes)          │
│   Exposes StateFlow<UiState>                           │
│   Calls domain use cases                               │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│              Domain Layer (optional for simple apps)   │
│   Use cases (pure Kotlin, no Android imports)          │
│   Domain models                                        │
└──────────────┬────────────────────────────┬──────────┘
               │                            │
┌──────────────▼──────────┐    ┌────────────▼──────────┐
│  Data Layer (local)      │    │  Data Layer (remote)   │
│  Room, DataStore         │    │  Retrofit, Ktor        │
│  Repositories            │    │  Repositories          │
└─────────────────────────┘    └───────────────────────┘
```

**Key rule:** The domain layer has no Android framework imports. It is pure Kotlin — testable on the JVM without an emulator or device.

---

## Project Structure

```
app/
└── src/main/
    ├── java/com/myapp/
    │   ├── MyApplication.kt          — Application class, Hilt setup
    │   │
    │   ├── features/                 — One package per feature
    │   │   ├── home/
    │   │   │   ├── HomeScreen.kt     — Composable screen
    │   │   │   ├── HomeViewModel.kt
    │   │   │   └── HomeUiState.kt
    │   │   ├── profile/
    │   │   └── settings/
    │   │
    │   ├── domain/                   — Pure Kotlin, no Android imports
    │   │   ├── model/                — Domain data classes
    │   │   ├── usecase/              — Business operations
    │   │   └── repository/           — Repository interfaces (not implementations)
    │   │
    │   ├── data/
    │   │   ├── local/
    │   │   │   ├── db/               — Room database, DAOs, entities
    │   │   │   └── datastore/        — DataStore preferences
    │   │   ├── remote/
    │   │   │   ├── api/              — Retrofit interfaces
    │   │   │   └── dto/              — Network response data classes
    │   │   └── repository/           — Repository implementations
    │   │
    │   ├── di/                       — Hilt modules
    │   │   ├── DatabaseModule.kt
    │   │   ├── NetworkModule.kt
    │   │   └── RepositoryModule.kt
    │   │
    │   └── core/
    │       ├── navigation/           — NavHost, route definitions
    │       ├── ui/                   — Design system: theme, colors, typography
    │       └── util/                 — Extensions, utilities
    │
    └── res/
        ├── values/
        │   ├── strings.xml           — All user-facing strings (for localization)
        │   └── ...
        └── ...
```

---

## ViewModel Pattern

ViewModels survive configuration changes (rotation, theme change). This is the correct way to handle state.

```kotlin
data class ItemListUiState(
    val items: List<Item> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

@HiltViewModel
class ItemListViewModel @Inject constructor(
    private val getItemsUseCase: GetItemsUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(ItemListUiState(isLoading = true))
    val uiState: StateFlow<ItemListUiState> = _uiState.asStateFlow()

    init {
        loadItems()
    }

    fun loadItems() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            getItemsUseCase()
                .onSuccess { items ->
                    _uiState.update { it.copy(items = items, isLoading = false) }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isLoading = false, errorMessage = error.message)
                    }
                }
        }
    }
}
```

```kotlin
@Composable
fun ItemListScreen(
    viewModel: ItemListViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    ItemListContent(
        uiState = uiState,
        onRetry = viewModel::loadItems
    )
}
```

**Rules:**
- ViewModel never holds a reference to a `Context`, `Activity`, or `Fragment` — use `ApplicationContext` via Hilt if needed
- Use `viewModelScope.launch` for coroutines
- Expose state as `StateFlow<UiState>`, not `LiveData` in new code
- Use `collectAsStateWithLifecycle()` in Compose (lifecycle-aware, not `collectAsState()`)

---

## Dependency Injection: Hilt (Required)

Hilt is the standard DI framework for Android. Use it from day one.

```kotlin
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient =
        OkHttpClient.Builder()
            .addInterceptor(AuthInterceptor())
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = if (BuildConfig.DEBUG)
                    HttpLoggingInterceptor.Level.BODY
                else
                    HttpLoggingInterceptor.Level.NONE
            })
            .build()

    @Provides
    @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl(BuildConfig.API_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(MoshiConverterFactory.create())
            .build()
}
```

Never use manual singletons (`companion object { val instance = ... }`). They break testing.

---

## Navigation: Jetpack Navigation with Compose

```kotlin
// Route definitions
sealed class Screen(val route: String) {
    object Home : Screen("home")
    object Profile : Screen("profile/{userId}") {
        fun createRoute(userId: String) = "profile/$userId"
    }
    object Settings : Screen("settings")
}

// NavHost
@Composable
fun AppNavHost(
    navController: NavHostController = rememberNavController()
) {
    NavHost(
        navController = navController,
        startDestination = Screen.Home.route
    ) {
        composable(Screen.Home.route) {
            HomeScreen(
                onNavigateToProfile = { userId ->
                    navController.navigate(Screen.Profile.createRoute(userId))
                }
            )
        }
        composable(
            route = Screen.Profile.route,
            arguments = listOf(navArgument("userId") { type = NavType.StringType })
        ) { backStackEntry ->
            ProfileScreen(userId = backStackEntry.arguments?.getString("userId")!!)
        }
        composable(Screen.Settings.route) { SettingsScreen() }
    }
}
```

Pass the `navController` only to the NavHost. Individual screens receive lambda callbacks for navigation actions — they never hold a reference to `NavController`.

---

## Data Persistence

### Room (Structured Data)

```kotlin
// Entity — separate from domain model
@Entity(tableName = "items")
data class ItemEntity(
    @PrimaryKey val id: String,
    val title: String,
    val description: String,
    val createdAt: Long
)

// DAO
@Dao
interface ItemDao {
    @Query("SELECT * FROM items ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<ItemEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(item: ItemEntity)

    @Delete
    suspend fun delete(item: ItemEntity)
}

// Database
@Database(entities = [ItemEntity::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun itemDao(): ItemDao
}
```

- Use `Flow` from DAOs for reactive UI updates
- Map between `Entity` and domain `Model` in the repository layer — never expose entities to the domain
- Always provide a migration or `fallbackToDestructiveMigration()` (only in dev) when incrementing database version

### DataStore (Preferences)

Use Jetpack DataStore instead of SharedPreferences for all new preference storage:

```kotlin
val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

val THEME_KEY = booleanPreferencesKey("dark_mode_enabled")

// Write
suspend fun setDarkMode(context: Context, enabled: Boolean) {
    context.dataStore.edit { preferences ->
        preferences[THEME_KEY] = enabled
    }
}

// Read (as Flow)
val isDarkMode: Flow<Boolean> = context.dataStore
    .data.map { preferences -> preferences[THEME_KEY] ?: false }
```

---

## Networking: Retrofit + Kotlin Coroutines

```kotlin
interface ItemApi {
    @GET("v1/items")
    suspend fun getItems(
        @Query("page") page: Int,
        @Query("per_page") perPage: Int
    ): Response<ItemListResponse>

    @POST("v1/items")
    suspend fun createItem(@Body request: CreateItemRequest): Response<ItemResponse>
}

// Repository implementation
class ItemRepositoryImpl @Inject constructor(
    private val api: ItemApi,
    private val dao: ItemDao
) : ItemRepository {

    override fun observeItems(): Flow<List<Item>> =
        dao.observeAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun syncItems(): Result<Unit> = runCatching {
        val response = api.getItems(page = 1, perPage = 50)
        if (response.isSuccessful) {
            val items = response.body()!!.items.map { it.toEntity() }
            dao.upsert(*items.toTypedArray())
        } else {
            throw HttpException(response)
        }
    }
}
```

**Offline-first pattern:** Serve from local DB immediately. Sync from network in background. Emit updates via `Flow`.

---

## Coroutines & Flow

Android's async model is Kotlin Coroutines + Flow. Master these.

```kotlin
// Dispatcher selection
Dispatchers.Main       // UI updates, ViewModel
Dispatchers.IO         // Network, disk, database
Dispatchers.Default    // CPU-intensive work (parsing, sorting)

// Always use structured concurrency
viewModelScope.launch(Dispatchers.IO) {
    val result = repository.fetchData()
    withContext(Dispatchers.Main) {
        // update UI
    }
}

// Flow operators for UI
repository.observeItems()
    .map { items -> items.filter { it.isActive } }
    .catch { error -> emit(emptyList()) }  // handle errors
    .stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = emptyList()
    )
```

---

## Process Death & State Restoration

Android can kill your app's process at any time. Your architecture must handle this.

| State Type | Survives Config Change | Survives Process Death | Solution |
|---|---|---|---|
| ViewModel state | ✅ | ❌ | Persist to DB/DataStore |
| `rememberSaveable` | ✅ | ✅ (up to size limit) | Small UI state only |
| Persistent storage | ✅ | ✅ | Room / DataStore |
| Navigation back stack | ✅ | ✅ | NavController handles this |

**Rule:** Any data the user would be frustrated to lose must be persisted to Room or DataStore, not just held in ViewModel memory.

---

## Material You Design

Follow Material 3 (Material You) design guidelines:

```kotlin
// Theme setup with dynamic color (Android 12+)
@Composable
fun MyAppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,  // Material You wallpaper-based color
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context)
            else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        content = content
    )
}
```

All apps must support:
- **Dark mode**: `isSystemInDarkTheme()` — test it, not optional
- **Dynamic color** (Android 12+): graceful fallback to branded colors on older versions
- **Edge-to-edge**: call `enableEdgeToEdge()` in Activity, handle insets with `WindowInsets`

---

## Performance

### Key Rules

- **No work on the main thread.** Network and disk I/O are always on `Dispatchers.IO`. Use `StrictMode` in debug builds to catch violations.
- **Lazy loading in lists.** Use `LazyColumn` / `LazyRow` for all scrolling lists. Never use a `Column` with a forEach for potentially long lists.
- **Pagination.** Use Paging 3 library for any list that can grow beyond ~50 items.
- **Image loading.** Use Coil (Compose-native). Never load bitmaps manually.
- **Baseline Profiles.** Add a Baseline Profile to pre-compile critical code paths. Dramatically improves startup time.

### Profiling Tools

- **Android Profiler** in Android Studio: CPU, Memory, Network traces
- **Systrace / Perfetto**: system-level tracing for jank analysis
- **Macrobenchmark**: measure cold/warm start time in CI

---

## Play Store Checklist

- [ ] `targetSdkVersion` is the latest stable API
- [ ] App tested on API 24+ (minimum) and latest API
- [ ] 64-bit supported (required since August 2019)
- [ ] App Bundle (`.aab`) uploaded, not APK
- [ ] All required permissions declared with rationale strings
- [ ] Permissions requested at time of use, not on cold launch
- [ ] Large screen / foldable layout tested
- [ ] Dark mode tested
- [ ] RTL layout tested (`layoutDirection = Rtl`)
- [ ] Data safety section in Play Console accurately filled out
- [ ] Sensitive data (passwords, tokens) excluded from Android backups (`android:allowBackup` / backup rules)

---

## Architecture Decisions for Android Apps

Decisions to make explicitly before building:

1. **Minimum SDK**: API 24 (Android 7.0, ~97% of active devices) is the practical floor for most apps
2. **Offline support**: none vs cached reads vs full offline-first (Room + sync)
3. **Auth mechanism**: Google Sign-In, email/password (Firebase Auth is the simplest option), custom backend
4. **Push notifications**: Firebase Cloud Messaging (standard) vs direct APNs
5. **Crash reporting**: Firebase Crashlytics (most common) vs Sentry
6. **Analytics**: Firebase Analytics vs custom — decide before writing event tracking
7. **In-app purchases**: Google Play Billing Library (mandatory for paid features in Play Store apps)
8. **Background sync**: WorkManager for guaranteed background execution (battery-safe)

---

## Walking Skeleton for Android Apps

Day 1 must include:

1. App builds and runs on minimum target API
2. Hilt dependency injection wired and working
3. Navigation structure in place with NavHost
4. One piece of data persisted end-to-end in Room: create → persist → kill app → relaunch → still there
5. Authenticated session working: login → token in DataStore/EncryptedSharedPreferences → relaunch restores session
6. CI: GitHub Actions or Bitrise builds debug APK and runs unit tests on every push
7. Internal Testing track on Play Console with a working build uploaded
8. Firebase Crashlytics (or equivalent) initialized and sending test crashes
