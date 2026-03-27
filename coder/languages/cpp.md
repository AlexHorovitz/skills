<!-- License: See /LICENSE -->


# C++ — Language Reference

Loaded by `coder/SKILL.md` when the project is C++ (C++17 or later preferred; note if targeting C++11/14).

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Classes / structs | UpperCamelCase | `SubscriptionService`, `PaymentResult` |
| Functions / methods | snake_case or lowerCamelCase (match codebase) | `create_subscription()` or `createSubscription()` |
| Variables / fields | snake_case | `is_active_`, `expires_at_` |
| Private members | trailing underscore | `user_id_`, `plan_id_` |
| Constants | `k` prefix + UpperCamelCase, or SCREAMING | `kMaxRetryCount` / `MAX_RETRY_COUNT` |
| Namespaces | lowercase | `namespace subscription { ... }` |
| Template params | Single uppercase letter or UpperCamelCase | `T`, `Container`, `ValueType` |

Pick one convention and apply it consistently across the project. Never mix.

---

## File Organization

```
include/
  subscription/
    subscription_service.h
    subscription.h
    errors.h
src/
  subscription/
    subscription_service.cpp
    subscription.cpp
tests/
  subscription/
    subscription_service_test.cpp
```

Headers go in `include/`, implementations in `src/`. One class per file; file name matches class name.

```cpp
// subscription.h
#pragma once

#include <chrono>
#include <optional>
#include <string>
#include "uuid.h"

namespace subscription {

enum class Status { Active, Paused, Cancelled, Expired };

struct Subscription {
    Uuid id;
    Uuid user_id;
    Uuid plan_id;
    Status status;
    std::chrono::system_clock::time_point expires_at;

    [[nodiscard]] bool is_valid() const noexcept;
};

} // namespace subscription
```

---

## RAII and Resource Management

**Never manage raw memory manually.** Wrap every resource in a RAII type.

```cpp
// ❌ Manual memory management
Subscription* sub = new Subscription(user_id, plan_id);
// ...
delete sub;  // easy to forget, leaks on exception

// ✅ Smart pointers — ownership is explicit and automatic
auto sub = std::make_unique<Subscription>(user_id, plan_id);

// ✅ Shared ownership
auto sub = std::make_shared<Subscription>(user_id, plan_id);
```

Rules:
- `std::unique_ptr<T>` for single ownership
- `std::shared_ptr<T>` only when ownership is genuinely shared
- Never store raw owning pointers; raw `T*` means "non-owning borrow"
- No `new`/`delete` in application code — only inside custom allocators

---

## Error Handling

Prefer exceptions for unexpected conditions; `std::expected<T, E>` (C++23) or `std::optional<T>` for expected absence.

```cpp
// Custom exception hierarchy
class SubscriptionError : public std::runtime_error {
public:
    explicit SubscriptionError(std::string_view msg) : std::runtime_error(std::string(msg)) {}
};

class AlreadySubscribedError : public SubscriptionError {
public:
    AlreadySubscribedError() : SubscriptionError("User already has an active subscription") {}
};

// Throwing on precondition violation
Subscription SubscriptionService::create(const User& user, const Plan& plan) {
    if (user.has_active_subscription()) {
        throw AlreadySubscribedError{};
    }
    // ...
}

// Catching at boundaries
try {
    auto sub = service_.create(user, plan);
    respond_ok(sub);
} catch (const AlreadySubscribedError& e) {
    respond_error(HttpStatus::Conflict, e.what());
} catch (const SubscriptionError& e) {
    respond_error(HttpStatus::BadRequest, e.what());
} catch (const std::exception& e) {
    log_error("Unexpected: {}", e.what());
    respond_error(HttpStatus::InternalServerError, "Internal error");
}
```

---

## Modern C++ Idioms (C++17/20)

Use modern features for clarity and correctness, not for cleverness.

```cpp
// Structured bindings (C++17)
auto [user, subscription] = fetch_user_and_subscription(user_id);

// std::optional for nullable values
std::optional<Discount> find_discount(std::string_view code) {
    if (auto it = discounts_.find(code); it != discounts_.end()) {
        return it->second;
    }
    return std::nullopt;
}

// Ranges (C++20) for collection transforms
auto active_subs = subscriptions
    | std::views::filter([](const auto& s) { return s.is_valid(); })
    | std::views::transform([](const auto& s) { return s.id; });

// std::string_view for read-only string params (no copy)
void log_cancellation(std::string_view reason) {
    logger_.info("Subscription cancelled: {}", reason);
}
```

---

## Class Design

```cpp
class SubscriptionService {
public:
    // Constructor injection — dependencies are explicit
    explicit SubscriptionService(
        std::unique_ptr<ISubscriptionRepository> repo,
        std::unique_ptr<IPaymentGateway> gateway
    );

    // Rule of five / zero — define all or none
    // This class has unique_ptr members → move-only is fine
    SubscriptionService(const SubscriptionService&)            = delete;
    SubscriptionService& operator=(const SubscriptionService&) = delete;
    SubscriptionService(SubscriptionService&&)                 = default;
    SubscriptionService& operator=(SubscriptionService&&)      = default;
    ~SubscriptionService()                                     = default;

    // [[nodiscard]] on functions whose return value must be checked
    [[nodiscard]] Subscription create(const User& user, const Plan& plan);

private:
    std::unique_ptr<ISubscriptionRepository> repo_;
    std::unique_ptr<IPaymentGateway> gateway_;
};
```

---

## Interface Abstractions

```cpp
class ISubscriptionRepository {
public:
    virtual ~ISubscriptionRepository() = default;

    virtual Subscription create(Uuid user_id, Uuid plan_id) = 0;
    virtual std::optional<Subscription> find(Uuid id) = 0;
    virtual void cancel(Uuid id) = 0;
};
```

All external dependencies go behind interfaces. Concrete types are injected at construction.

---

## Testing (GoogleTest / Catch2)

```cpp
// GoogleTest
#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include "subscription_service.h"

class MockSubscriptionRepository : public ISubscriptionRepository {
public:
    MOCK_METHOD(Subscription, create, (Uuid, Uuid), (override));
    MOCK_METHOD(std::optional<Subscription>, find, (Uuid), (override));
    MOCK_METHOD(void, cancel, (Uuid), (override));
};

TEST(SubscriptionServiceTest, CreateReturnsActiveSubscription) {
    auto repo    = std::make_unique<MockSubscriptionRepository>();
    auto gateway = std::make_unique<MockPaymentGateway>();

    EXPECT_CALL(*repo, create(testing::_, testing::_))
        .WillOnce(testing::Return(Subscription{.status = Status::Active}));

    SubscriptionService service(std::move(repo), std::move(gateway));
    auto sub = service.create(test_user, test_plan);

    EXPECT_EQ(sub.status, Status::Active);
}
```

---

## C++-Specific Quality Checklist

- [ ] No `new`/`delete` — use `std::make_unique` / `std::make_shared`
- [ ] No raw owning pointers — raw `T*` means non-owning only
- [ ] Rule of zero followed, or Rule of five fully defined
- [ ] All throwing functions documented in comments
- [ ] `[[nodiscard]]` on functions whose return value must be checked
- [ ] `const` correctness applied (methods that don't mutate are `const`)
- [ ] No `using namespace std;` in header files
- [ ] All external dependencies behind abstract interfaces

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Use after free | Raw pointer to local/temp | Use `unique_ptr`; don't store raw pointers |
| Object slicing | Storing derived by value in base container | Use `unique_ptr<Base>` in containers |
| Dangling reference | Returning `const T&` to local | Return by value; use `std::optional` |
| Memory leak | Exception before `delete` | RAII — wrap in smart pointer |
| Undefined behavior | Signed overflow, out-of-bounds | Use `std::array`, checked iterators in debug |
| Linker errors | Template definition in `.cpp` | Template bodies go in headers |
| Performance regression | Copying `std::string` | Use `std::string_view` for read-only params |
