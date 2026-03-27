## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Laravel — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses Laravel.

---

## When to Choose Laravel

- **Your team knows PHP.** Laravel is the most productive framework in the PHP ecosystem.
- **Batteries included.** Auth, queues, mail, storage, caching, scheduling — all ship working. Features on Day 1, not infrastructure.
- **Eloquent fits your domain.** ActiveRecord trades query power for velocity. Relational data + object thinking = fast and expressive.
- **Rapid full-stack.** Blade + Livewire + Vite means one developer ships a complete product without a frontend team.

**When NOT:** async/event-driven concurrency needed (Go, Node, Elixir); team does not know PHP; pure SPA with thin API; domain requires complex raw SQL and you fight the ORM more than you use it.

## Project Structure

```
app/
├── Http/Controllers/    — Thin. Validate, delegate, respond.
├── Http/Middleware/      — Request/response filters
├── Http/Requests/       — FormRequest classes (validation + authorization)
├── Models/              — Eloquent models (relationships, scopes, accessors)
├── Policies/            — Authorization (can user X do Y to resource Z?)
├── Providers/           — Service providers (bindings, bootstrapping)
└── Services/            — Business logic. Not in controllers. Not in models.
config/                  — One file per concern (database, mail, queue)
database/
├── factories/           — Model factories for testing
├── migrations/          — Timestamped, forward-only schema changes
└── seeders/             — Dev/test seed data
resources/views/         — Blade templates
routes/
├── web.php              — Browser routes (session auth, CSRF)
├── api.php              — API routes (token auth, stateless)
└── console.php          — Artisan commands and scheduled tasks
tests/Feature/           — HTTP tests, full request lifecycle
tests/Unit/              — Isolated class tests, no framework boot
```

`app/Services/` does not exist by default. Create it. Laravel tempts you to put logic in controllers or models. Resist.

## Routing

```php
// routes/api.php
Route::middleware('auth:sanctum')->group(function () {
    Route::apiResource('subscriptions', SubscriptionController::class);
    Route::post('subscriptions/{subscription}/cancel', [SubscriptionController::class, 'cancel']);
});

// Route model binding — resolves {subscription} to Eloquent model automatically
public function show(Subscription $subscription): SubscriptionResource {
    $this->authorize('view', $subscription);
    return new SubscriptionResource($subscription->load('plan', 'invoices'));
}

// Middleware groups — register aliases in bootstrap/app.php, apply to groups
Route::middleware(['auth', 'subscribed'])->group(function () {
    Route::get('/dashboard', [DashboardController::class, 'index']);
});
```

`apiResource` generates index/store/show/update/destroy. Route model binding returns 404 for missing records — never write `findOrFail($id)` in a controller.

## Data Layer

### Eloquent Model

```php
class Subscription extends Model
{
    protected $fillable = ['user_id', 'plan_id', 'status', 'trial_ends_at',
        'current_period_start', 'current_period_end', 'cancelled_at'];

    protected function casts(): array {
        return ['status' => SubscriptionStatus::class, 'trial_ends_at' => 'datetime',
            'current_period_start' => 'datetime', 'current_period_end' => 'datetime',
            'cancelled_at' => 'datetime'];
    }

    public function user(): BelongsTo { return $this->belongsTo(User::class); }
    public function plan(): BelongsTo { return $this->belongsTo(Plan::class); }
    public function invoices(): HasMany { return $this->hasMany(Invoice::class)->latest(); }

    public function scopeActive(Builder $query): Builder {
        return $query->where('status', SubscriptionStatus::Active);
    }
    public function scopeExpiringSoon(Builder $query, int $days = 7): Builder {
        return $query->active()->where('current_period_end', '<=', now()->addDays($days));
    }

    protected function isOnTrial(): Attribute {
        return Attribute::make(get: fn () => $this->trial_ends_at?->isFuture() ?? false);
    }
}
```

Always `$fillable` (never `$guarded = []`). Cast every date and enum. Scopes return `Builder` and compose: `Subscription::active()->expiringSoon()->get()`.

### Migrations

```php
Schema::create('subscriptions', function (Blueprint $table) {
    $table->id();
    $table->foreignId('user_id')->constrained()->cascadeOnDelete();
    $table->foreignId('plan_id')->constrained();
    $table->string('status')->default('active');
    $table->timestamp('trial_ends_at')->nullable();
    $table->timestamp('current_period_start');
    $table->timestamp('current_period_end');
    $table->timestamp('cancelled_at')->nullable();
    $table->timestamps();
    $table->index(['user_id', 'status']);
});
```
### Factories

```php
class SubscriptionFactory extends Factory
{
    public function definition(): array {
        return ['user_id' => User::factory(), 'plan_id' => Plan::factory(),
            'status' => SubscriptionStatus::Active,
            'current_period_start' => now(), 'current_period_end' => now()->addMonth()];
    }
    public function cancelled(): static {
        return $this->state(fn () => ['status' => SubscriptionStatus::Cancelled, 'cancelled_at' => now()]);
    }
    public function onTrial(): static {
        return $this->state(fn () => ['trial_ends_at' => now()->addDays(14)]);
    }
}
```

States compose: `Subscription::factory()->onTrial()->cancelled()->create()`. One factory per model, named states for every variation.

## Middleware

```php
class EnsureUserIsSubscribed
{
    public function handle(Request $request, Closure $next): Response {
        if (! $request->user()?->subscription?->status->isActive()) {
            return $request->expectsJson()
                ? response()->json(['error' => ['code' => 'subscription_required']], 403)
                : redirect()->route('billing.show');
        }
        return $next($request);
    }
}
```

Global middleware (CORS, TrimStrings) in `bootstrap/app.php`. Route middleware (auth, subscription checks) registered as aliases, applied to groups. Middleware answers one question: "Should this request continue?"

## Authentication

**Breeze** (default starter): login, registration, password reset, email verification with Blade + Tailwind. Do not over-engineer auth on Day 1.

**Sanctum** (API tokens): SPA cookie auth and API token auth. Scope tokens with abilities — never wildcard when the client only needs read:

```php
$token = $user->createToken('api', ['subscriptions:read', 'invoices:read']);
```

**Jetstream** (teams): team/org management with invitations, role switching, per-team permissions. Heavier than Breeze but saves weeks. Do not build team management from scratch.

## Template Patterns

### Blade Components

```blade
@props(['subscription'])
<div class="rounded-lg border p-6">
    <h3>{{ $subscription->plan->name }}</h3>
    <p>${{ number_format($subscription->plan->price / 100, 2) }}/mo</p>
    @if ($subscription->is_on_trial)
        <span>Trial ends {{ $subscription->trial_ends_at->diffForHumans() }}</span>
    @endif
    <x-status-badge :status="$subscription->status" />
</div>
```
Anonymous components for presentation. Class-based components when logic is needed.

### Livewire for Interactivity

```php
class SubscriptionSwitcher extends Component
{
    public Subscription $subscription;
    public function switchPlan(int $planId): void {
        $this->authorize('update', $this->subscription);
        app(SubscriptionService::class)->changePlan($this->subscription, Plan::findOrFail($planId));
        $this->subscription->refresh();
    }
    public function render(): View {
        return view('livewire.subscription-switcher', ['plans' => Plan::active()->get()]);
    }
}
```

Livewire replaces JS frameworks for most CRUD apps. If you need client-side routing and complex state, use Inertia.js with React/Vue.

## API Patterns

### API Resources

```php
class SubscriptionResource extends JsonResource
{
    public function toArray(Request $request): array {
        return ['id' => $this->id, 'status' => $this->status->value,
            'is_on_trial' => $this->is_on_trial,
            'current_period_end' => $this->current_period_end->toIso8601String(),
            'plan' => new PlanResource($this->whenLoaded('plan')),
            'invoices' => InvoiceResource::collection($this->whenLoaded('invoices'))];
    }
}
```

Never return Eloquent models directly. Resources are your API contract. `whenLoaded` prevents N+1s when relationships are not eager-loaded.
### FormRequests

```php
class StoreSubscriptionRequest extends FormRequest
{
    public function authorize(): bool {
        return ! $this->user()->subscription?->status->isActive();
    }
    public function rules(): array {
        return ['plan_id' => ['required', 'exists:plans,id'],
            'payment_method_id' => ['required', 'string', 'max:255']];
    }
}
```

Every `store`/`update` gets its own FormRequest. No inline `$request->validate()` — it obscures the contract.

### Versioning

Version in the URL. Controllers under `Api/V1/`, `Api/V2/`. Services shared — only controller and resource layers change:

```php
Route::prefix('v1')->group(fn () => Route::apiResource('subscriptions', V1\SubscriptionController::class));
```

## Testing Strategy

Pest is the default since Laravel 11. Use it.

```php
it('creates a subscription', function () {
    $user = User::factory()->create();
    $plan = Plan::factory()->create(['price' => 2999]);
    $this->actingAs($user)->postJson('/api/v1/subscriptions', [
        'plan_id' => $plan->id, 'payment_method_id' => 'pm_test_123',
    ])->assertCreated()->assertJsonPath('data.status', 'active');
    expect($user->subscription)->not->toBeNull();
});
it('prevents a second active subscription', function () {
    $user = User::factory()->has(Subscription::factory())->create();
    $this->actingAs($user)->postJson('/api/v1/subscriptions', [
        'plan_id' => Plan::factory()->create()->id, 'payment_method_id' => 'pm_test_456',
    ])->assertForbidden();
});
it('cancels a subscription', function () {
    $sub = Subscription::factory()->create();
    $this->actingAs($sub->user)->postJson("/api/v1/subscriptions/{$sub->id}/cancel")
        ->assertOk()->assertJsonPath('data.status', 'cancelled');
    expect($sub->fresh()->cancelled_at)->not->toBeNull();
});
```

`RefreshDatabase` on every test. Factories, never raw inserts. Test HTTP endpoints, not methods. Mock external services (`Http::fake()`, `Mail::fake()`, `Queue::fake()`), never the database.

## Deployment (Walking Skeleton)

1. **Hosting provisioned.** Forge (managed servers), Vapor (serverless), or Docker on Fly.io/Railway
2. **Database provisioned.** Managed PostgreSQL. `php artisan migrate` in the pipeline, never manually
3. **Queue worker running.** Deploy from Day 1 — Supervisor or your host's worker management
4. **Scheduler configured.** `php artisan schedule:run` in cron (every minute). Schedule in code, not crontab
5. **Environment locked down.** `APP_ENV=production`, `APP_DEBUG=false`, `APP_KEY` set
6. **CI pipeline.** Push to main triggers `composer install` → `php artisan test` → deploy
7. **Error tracking.** Sentry or Flare. If production throws and nobody is notified, you have no monitoring

## Laravel-Specific Quality Checklist

- [ ] Every write endpoint has a FormRequest — no inline validation
- [ ] Controllers contain zero business logic — validate, call service, respond
- [ ] Relationships eager-loaded where used — `Model::preventLazyLoading()` in dev
- [ ] No raw queries without justification — `DB::select()` with bindings when needed
- [ ] Backed enums for status fields — no magic strings, no integer codes
- [ ] Every date column cast in `casts()` — no manual `Carbon::parse()`
- [ ] Config via `config()`, never `env()` outside config files
- [ ] Long-running work queued — anything > 200ms belongs in a job
- [ ] Policies for authorization — `$this->authorize()`, no inline checks
- [ ] No business logic in Blade — complex conditions go to accessors or view models

## Common Failure Modes

| Failure | What Goes Wrong | Fix |
|---|---|---|
| **N+1 queries** | Relationship in a loop = query per row. Degrades linearly. | `Model::preventLazyLoading()` in AppServiceProvider. `->with()` on every query. |
| **Fat controllers** | Validation, logic, email tangled in 200+ line methods. | Extract service classes. Controllers call services. |
| **`env()` in app code** | Returns `null` after `config:cache`. Silent production failures. | `env()` only in `config/*.php`. Use `config()` everywhere else. |
| **Missing eager loading** | `whenLoaded('plan')` silently empty when controller forgot `->with('plan')`. | Pair every `whenLoaded` with `->with()`. Test nested data. |
| **Global helpers in services** | `auth()`, `request()` couples services to HTTP. Breaks in queues/CLI. | Pass dependencies explicitly. Services get a `User`, not `auth()->user()`. |
| **No queue worker** | Jobs dispatched but never processed. Emails never send. Silent. | Queue worker from Day 1. Monitor `queue:failed`. |
| **`$guarded = []`** | Attackers set `is_admin = true` via mass assignment. | `$fillable` with explicit columns. FormRequests whitelist input. |
| **Monolithic route files** | `web.php` at 500+ lines. Merge conflicts constant. | Split: `routes/billing.php`, `routes/admin.php`. |
