## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# Go — Language Reference

Loaded by `coder/SKILL.md` when the project is Go.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Exported (public) | UpperCamelCase | `SubscriptionService`, `CreateSubscription` |
| Unexported (private) | lowerCamelCase | `validateUser`, `buildQuery` |
| Acronyms | All-caps (standard) | `userID`, `parseJSON`, `HTTPClient` |
| Interfaces | Noun, or -er suffix | `SubscriptionRepository`, `Stringer` |
| Constants | UpperCamelCase (exported) or lowerCamelCase | `MaxRetryCount`, `defaultTimeout` |
| Package names | Lowercase, single word, no underscores | `subscription`, `payment`, `auth` |
| Test files | `_test.go` suffix | `subscription_service_test.go` |

---

## Package Organization

```
subscription/
  service.go          # SubscriptionService and its methods
  repository.go       # SubscriptionRepository interface
  model.go            # Subscription, Status types
  errors.go           # sentinel errors and error types
  service_test.go     # tests alongside the package
```

One package per directory. Package name matches directory name. Avoid `util`, `helpers`, `common` — name packages by what they do.

```go
// Package subscription manages subscription lifecycle.
package subscription
```

---

## Error Handling

Errors are values. Handle them at every call site.

```go
// ✅ Named sentinel errors for type-checking
var (
    ErrAlreadySubscribed = errors.New("user already has an active subscription")
    ErrPlanNotFound      = errors.New("plan not found")
    ErrPaymentFailed     = errors.New("payment processing failed")
)

// ✅ Structured error types for additional context
type ValidationError struct {
    Field   string
    Message string
}
func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation error on %s: %s", e.Field, e.Message)
}

// ✅ Wrap errors with context using fmt.Errorf %w
func (s *SubscriptionService) Create(ctx context.Context, userID, planID uuid.UUID) (*Subscription, error) {
    user, err := s.userRepo.Get(ctx, userID)
    if err != nil {
        return nil, fmt.Errorf("fetching user %s: %w", userID, err)
    }
    if user.HasActiveSubscription {
        return nil, ErrAlreadySubscribed
    }
    // ...
}
```

Check for specific errors with `errors.Is` and `errors.As`:

```go
sub, err := service.Create(ctx, userID, planID)
if err != nil {
    if errors.Is(err, subscription.ErrAlreadySubscribed) {
        http.Error(w, "already subscribed", http.StatusConflict)
        return
    }
    log.Printf("unexpected error creating subscription: %v", err)
    http.Error(w, "internal error", http.StatusInternalServerError)
    return
}
```

**Never ignore errors.** `_ = someFunc()` is nearly always wrong.

---

## Interfaces

Define interfaces where they are *used*, not where the type is *defined*:

```go
// In the service package — defines what the service needs
type SubscriptionRepository interface {
    Get(ctx context.Context, id uuid.UUID) (*Subscription, error)
    Create(ctx context.Context, sub *Subscription) error
    Cancel(ctx context.Context, id uuid.UUID) error
    ListActive(ctx context.Context, userID uuid.UUID) ([]*Subscription, error)
}

// Service depends on the interface, not the concrete type
type SubscriptionService struct {
    repo    SubscriptionRepository
    payment PaymentGateway
    logger  *slog.Logger
}

func NewSubscriptionService(
    repo    SubscriptionRepository,
    payment PaymentGateway,
    logger  *slog.Logger,
) *SubscriptionService {
    return &SubscriptionService{repo: repo, payment: payment, logger: logger}
}
```

Keep interfaces small — the Go proverb: "The bigger the interface, the weaker the abstraction."

---

## Context

Every function that does I/O takes `context.Context` as the first parameter:

```go
func (s *SubscriptionService) Create(ctx context.Context, userID, planID uuid.UUID) (*Subscription, error) {
    // ctx carries deadline, cancellation, and request-scoped values
    user, err := s.userRepo.Get(ctx, userID)
    // ...
}
```

Never store context in structs. Pass it through the call chain.

---

## Goroutines and Channels

Every goroutine must have a defined owner responsible for its lifetime:

```go
// ✅ Bounded concurrency with errgroup
func (s *SubscriptionService) LoadDashboard(ctx context.Context, userID uuid.UUID) (*Dashboard, error) {
    g, ctx := errgroup.WithContext(ctx)

    var user *User
    var subs []*Subscription

    g.Go(func() error {
        var err error
        user, err = s.userRepo.Get(ctx, userID)
        return err
    })
    g.Go(func() error {
        var err error
        subs, err = s.repo.ListActive(ctx, userID)
        return err
    })

    if err := g.Wait(); err != nil {
        return nil, fmt.Errorf("loading dashboard: %w", err)
    }
    return &Dashboard{User: user, Subscriptions: subs}, nil
}
```

Never start a goroutine you can't stop. Use context cancellation or `sync.WaitGroup` to manage lifecycle.

---

## Struct Design

```go
type Subscription struct {
    ID        uuid.UUID        `json:"id"         db:"id"`
    UserID    uuid.UUID        `json:"user_id"    db:"user_id"`
    PlanID    uuid.UUID        `json:"plan_id"    db:"plan_id"`
    Status    SubscriptionStatus `json:"status"   db:"status"`
    ExpiresAt time.Time        `json:"expires_at" db:"expires_at"`
    CreatedAt time.Time        `json:"created_at" db:"created_at"`
}

type SubscriptionStatus string

const (
    StatusActive    SubscriptionStatus = "active"
    StatusPaused    SubscriptionStatus = "paused"
    StatusCancelled SubscriptionStatus = "cancelled"
    StatusExpired   SubscriptionStatus = "expired"
)

func (s *Subscription) IsValid() bool {
    return s.Status == StatusActive && s.ExpiresAt.After(time.Now())
}
```

---

## Testing (Table-Driven)

Go's standard testing package + table-driven tests are idiomatic:

```go
func TestSubscriptionService_Create(t *testing.T) {
    tests := []struct {
        name    string
        user    *User
        wantErr error
    }{
        {
            name:    "creates subscription for eligible user",
            user:    &User{ID: uuid.New(), HasActiveSubscription: false},
            wantErr: nil,
        },
        {
            name:    "returns ErrAlreadySubscribed when user has active plan",
            user:    &User{ID: uuid.New(), HasActiveSubscription: true},
            wantErr: ErrAlreadySubscribed,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            repo := &mockSubscriptionRepo{}
            svc  := NewSubscriptionService(repo, &mockPaymentGateway{}, slog.Default())

            _, err := svc.Create(context.Background(), tt.user.ID, uuid.New())

            if !errors.Is(err, tt.wantErr) {
                t.Errorf("got err %v, want %v", err, tt.wantErr)
            }
        })
    }
}
```

---

## Go-Specific Quality Checklist

- [ ] All returned errors checked — no `_ = ...` discards
- [ ] Errors wrapped with `%w` to preserve unwrapping
- [ ] All I/O functions accept `context.Context` as first param
- [ ] Interfaces defined at usage site, not definition site
- [ ] No goroutines started without defined lifecycle management
- [ ] `go vet` and `golangci-lint` pass clean
- [ ] `go test -race ./...` passes (race detector)
- [ ] No `init()` functions except for registration patterns (and documented)

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Goroutine leak | Goroutine blocks forever, never exits | Use context cancellation; `errgroup` |
| Nil pointer panic | Interface with nil concrete value | Check concrete value, not interface nil |
| Silent error loss | `_ = f()` discarding error | Handle every error explicitly |
| Data race | Concurrent map/slice access | Use `sync.Mutex`, `sync.Map`, or channels |
| Context not propagated | `context.Background()` deep in call chain | Thread ctx from entry point through all I/O |
| Unexpected copy of large struct | Passing struct by value | Pass pointer `*T` for large or mutex-containing structs |
| Test not isolated | Global state mutated in test | Reset state in `t.Cleanup`; prefer dependency injection |
