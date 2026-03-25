# Rust — Language Reference

Loaded by `coder/SKILL.md` when the project is Rust.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Types (struct, enum, trait) | UpperCamelCase | `SubscriptionService`, `PaymentError` |
| Functions / methods | snake_case | `create_subscription()`, `fetch_user()` |
| Variables / fields | snake_case | `is_active`, `expiration_date` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_RETRY_COUNT` |
| Modules | snake_case | `subscription_service` |
| Lifetimes | short lowercase | `'a`, `'conn` |
| Traits | UpperCamelCase, often verb-noun or -able | `Subscribable`, `UserRepository` |

---

## Crate / Module Organization

```
src/
  main.rs           # binary entry point (or lib.rs for libraries)
  lib.rs            # library crate root
  domain/
    mod.rs
    subscription.rs # Subscription struct and domain logic
    user.rs
  services/
    mod.rs
    subscription_service.rs
  repository/
    mod.rs
    postgres.rs
  errors.rs         # crate-wide error types
```

```rust
// In each module, re-export what callers need:
pub use self::subscription::Subscription;
pub use self::subscription::SubscriptionStatus;
```

---

## Ownership and Borrowing — Key Discipline

The borrow checker is the reviewer that never sleeps. Follow these rules:

- Pass values by value when the caller is done with them
- Pass `&T` when the callee only reads
- Pass `&mut T` when the callee needs to mutate
- Return owned values from constructors and transformations

```rust
// ❌ Unnecessary clone (usually)
fn process(name: String) -> String {
    name.clone()
}

// ✅ Borrow if you only need to read
fn process(name: &str) -> String {
    format!("Hello, {}!", name)
}
```

When you find yourself cloning frequently to satisfy the borrow checker, it usually means the design has a structural issue. Consider refactoring ownership rather than cloning your way out.

---

## Error Handling

Use `Result<T, E>` for recoverable errors. Never `unwrap()` or `expect()` in production code paths.

### Define a crate-level error type

Use `thiserror` for library crates:

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SubscriptionError {
    #[error("user {user_id} already has an active subscription")]
    AlreadySubscribed { user_id: uuid::Uuid },

    #[error("plan {plan_id} not found")]
    PlanNotFound { plan_id: uuid::Uuid },

    #[error("payment failed: {reason}")]
    PaymentFailed { reason: String },

    #[error("database error")]
    Database(#[from] sqlx::Error),
}
```

Use `anyhow` for application binaries where context matters more than type:

```rust
use anyhow::{Context, Result};

fn load_config(path: &Path) -> Result<Config> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read config from {}", path.display()))?;
    toml::from_str(&content).context("failed to parse config")
}
```

### Propagate with `?`

```rust
async fn create_subscription(
    &self,
    user_id: Uuid,
    plan_id: Uuid,
) -> Result<Subscription, SubscriptionError> {
    let user = self.user_repo.get(user_id).await?;

    if user.has_active_subscription {
        return Err(SubscriptionError::AlreadySubscribed { user_id });
    }

    let plan = self.plan_repo.get(plan_id).await?;
    let payment = self.payment_gateway.charge(&user, plan.price).await?;
    self.subscription_repo.create(user_id, plan_id, payment).await
}
```

---

## Traits for Abstraction (Testability)

Define behavior through traits; depend on trait objects or generics:

```rust
#[async_trait::async_trait]
pub trait SubscriptionRepository: Send + Sync {
    async fn get(&self, id: Uuid) -> Result<Subscription, SubscriptionError>;
    async fn create(&self, user_id: Uuid, plan_id: Uuid, payment: Payment) -> Result<Subscription, SubscriptionError>;
    async fn cancel(&self, id: Uuid) -> Result<(), SubscriptionError>;
}

// Use trait bounds in service
pub struct SubscriptionService<R: SubscriptionRepository> {
    repo: R,
}

// Or dynamic dispatch when concrete type matters less
pub struct SubscriptionService {
    repo: Arc<dyn SubscriptionRepository>,
}
```

---

## Async (Tokio)

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let config = Config::load()?;
    let pool = PgPool::connect(&config.database_url).await?;
    let app = build_router(pool);
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await?;
    axum::serve(listener, app).await?;
    Ok(())
}
```

For concurrent work:

```rust
// ✅ Concurrent, independent tasks
let (user, subscriptions) = tokio::try_join!(
    user_service.get(user_id),
    subscription_service.list_active(user_id),
)?;
```

---

## Structs and Builders

Prefer the builder pattern for structs with many optional fields:

```rust
#[derive(Debug, Default)]
pub struct SubscriptionBuilder {
    user_id: Option<Uuid>,
    plan_id: Option<Uuid>,
    coupon_code: Option<String>,
}

impl SubscriptionBuilder {
    pub fn user(mut self, user_id: Uuid) -> Self {
        self.user_id = Some(user_id);
        self
    }
    pub fn plan(mut self, plan_id: Uuid) -> Self {
        self.plan_id = Some(plan_id);
        self
    }
    pub fn coupon(mut self, code: impl Into<String>) -> Self {
        self.coupon_code = Some(code.into());
        self
    }
    pub fn build(self) -> Result<SubscriptionRequest, SubscriptionError> {
        Ok(SubscriptionRequest {
            user_id: self.user_id.ok_or(SubscriptionError::MissingField("user_id"))?,
            plan_id: self.plan_id.ok_or(SubscriptionError::MissingField("plan_id"))?,
            coupon_code: self.coupon_code,
        })
    }
}
```

---

## Testing

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn creates_subscription_for_eligible_user() {
        let repo = MockSubscriptionRepository::new();
        let gateway = MockPaymentGateway::new();
        let service = SubscriptionService::new(Arc::new(repo), Arc::new(gateway));

        let result = service.create_subscription(Uuid::new_v4(), Uuid::new_v4()).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn returns_error_when_already_subscribed() {
        let user_id = Uuid::new_v4();
        let repo = MockSubscriptionRepository::with_active_subscription(user_id);
        let service = SubscriptionService::new(Arc::new(repo), Arc::new(MockPaymentGateway::new()));

        let result = service.create_subscription(user_id, Uuid::new_v4()).await;
        assert!(matches!(result, Err(SubscriptionError::AlreadySubscribed { .. })));
    }
}
```

---

## Rust-Specific Quality Checklist

- [ ] No `unwrap()` or `expect()` in non-test code paths
- [ ] All `Result` and `Option` values explicitly handled — no `let _ = ...` to discard errors
- [ ] No unnecessary `clone()` — examine ownership first
- [ ] Shared state uses `Arc<Mutex<T>>` or `Arc<RwLock<T>>` — no raw `unsafe` for shared access
- [ ] `unsafe` blocks have a comment explaining why it is sound
- [ ] All public items have doc comments (`///`)
- [ ] `cargo clippy -- -D warnings` passes clean
- [ ] `cargo fmt` applied

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Borrow checker fight | Trying to own and borrow simultaneously | Redesign ownership; use indices or `Arc` |
| Panic in production | `unwrap()` on `None`/`Err` | Replace with `?` or explicit match |
| Deadlock | Holding `MutexGuard` across `.await` | Drop guard before await; use `tokio::sync::Mutex` |
| Slow compile times | Monomorphization explosion | Use `dyn Trait` for non-hot paths |
| Subtle data race (pre-compile) | Interior mutability misused | Prefer `RwLock`; document invariants |
| Stack overflow | Deep recursion | Convert to iterative or use `async` with heap |
