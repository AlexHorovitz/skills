<!-- License: See /LICENSE -->


# C# — Language Reference

Loaded by `coder/SKILL.md` when the project is C# / .NET.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Methods | PascalCase, verb phrase | `GetUserByEmail()`, `ValidateSubscription()` |
| Properties | PascalCase, noun/adjective | `IsActive`, `ExpiresAt`, `SubscriptionPlan` |
| Classes | PascalCase, noun phrase | `UserSubscription`, `PaymentProcessor` |
| Interfaces | IPascalCase | `IPaymentGateway`, `ISubscriptionRepository` |
| Local variables | camelCase | `remainingDays`, `paymentResult` |
| Parameters | camelCase | `userId`, `cancellationReason` |
| Private fields | _camelCase | `_subscriptionRepository`, `_logger` |
| Constants | PascalCase | `MaxRetryAttempts`, `DefaultTimeoutSeconds` |
| Enums | PascalCase (singular) | `SubscriptionStatus.Active` |

---

## File Organization

```csharp
// System namespaces first
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

// Microsoft / framework namespaces
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

// Third-party
using FluentValidation;

// Local project namespaces
using Billing.Domain.Entities;
using Billing.Domain.Exceptions;

namespace Billing.Application.Services;  // file-scoped namespace — always

public class SubscriptionService
{
    // ...
}
```

One type per file. File name matches the type name: `SubscriptionService.cs`. File-scoped namespaces reduce nesting — use them everywhere.

---

## Nullable Reference Types

Enable `<Nullable>enable</Nullable>` in every project. This is not optional.

```csharp
public class Subscription
{
    // Non-nullable: the compiler guarantees these are set
    public required string PlanName { get; init; }
    public required UserId UserId { get; init; }

    // Nullable: explicitly signals "this may be absent"
    public DateTime? CancelledAt { get; private set; }
    public string? CancellationReason { get; private set; }

    public void Cancel(string? reason = null)
    {
        CancelledAt = DateTime.UtcNow;
        CancellationReason = reason;
    }
}
```

Use `?` annotations honestly. Do not slap `!` (null-forgiving) on everything to silence warnings — fix the actual nullability instead. The only acceptable use of `!` is when you have knowledge the compiler cannot infer, such as after a framework call that guarantees non-null.

Pattern matching for null checks:

```csharp
// Good — pattern matching is clear
if (subscription is null) return NotFound();
if (subscription is { Status: SubscriptionStatus.Cancelled }) return BadRequest();

// Bad — old-style null checks
if (subscription == null) return NotFound();
```

---

## Async/Await

Every I/O operation is async. No exceptions.

```csharp
public async Task<Subscription> CreateSubscriptionAsync(
    CreateSubscriptionRequest request,
    CancellationToken cancellationToken = default)
{
    var user = await _userRepository.GetByIdAsync(request.UserId, cancellationToken)
        ?? throw new UserNotFoundException(request.UserId);

    var plan = await _planRepository.GetByIdAsync(request.PlanId, cancellationToken)
        ?? throw new PlanNotFoundException(request.PlanId);

    var payment = await _paymentGateway.ChargeAsync(
        user.PaymentMethodId,
        plan.Price,
        cancellationToken);

    var subscription = new Subscription
    {
        UserId = user.Id,
        PlanName = plan.Name,
        Status = SubscriptionStatus.Active,
        StartedAt = DateTime.UtcNow,
        ExpiresAt = DateTime.UtcNow.Add(plan.Duration),
        PaymentId = payment.Id,
    };

    await _subscriptionRepository.AddAsync(subscription, cancellationToken);
    await _unitOfWork.SaveChangesAsync(cancellationToken);

    return subscription;
}
```

Rules:

- Suffix async methods with `Async`.
- Accept `CancellationToken` as the last parameter and pass it through every call.
- Never use `async void` — the only exception is event handlers in UI frameworks.
- Never call `.Result` or `.Wait()`. They deadlock in synchronization contexts.
- Use `ConfigureAwait(false)` in library code. Omit it in application code (ASP.NET Core has no sync context, but libraries may be consumed elsewhere).

---

## Records and Pattern Matching

Use records for DTOs, value objects, and any immutable data. Classes are for entities with identity and mutable state.

```csharp
// Immutable request/response DTOs
public record CreateSubscriptionRequest(
    Guid UserId,
    Guid PlanId,
    string PaymentMethodId);

public record SubscriptionResponse(
    Guid Id,
    string PlanName,
    SubscriptionStatus Status,
    DateTime ExpiresAt);

// Value objects
public record Money(decimal Amount, string Currency)
{
    public static Money Usd(decimal amount) => new(amount, "USD");
}
```

Switch expressions replace verbose if/else chains:

```csharp
public decimal CalculateDiscount(Subscription subscription) => subscription switch
{
    { Status: SubscriptionStatus.Active, Plan.Tier: PlanTier.Enterprise } => 0.20m,
    { Status: SubscriptionStatus.Active, Plan.Tier: PlanTier.Business }  => 0.10m,
    { Status: SubscriptionStatus.Paused }                                => 0.0m,
    _                                                                    => 0.0m,
};
```

Use `with` expressions to create modified copies:

```csharp
var upgraded = currentResponse with { PlanName = "Enterprise", ExpiresAt = DateTime.UtcNow.AddYears(1) };
```

---

## Error Handling

Define a domain exception hierarchy:

```csharp
// Exceptions/SubscriptionException.cs
public class SubscriptionException : Exception
{
    public SubscriptionException(string message) : base(message) { }
    public SubscriptionException(string message, Exception inner) : base(message, inner) { }
}

public class SubscriptionNotFoundException : SubscriptionException
{
    public SubscriptionNotFoundException(Guid id)
        : base($"Subscription {id} not found") { }
}

public class SubscriptionAlreadyActiveException : SubscriptionException
{
    public SubscriptionAlreadyActiveException(Guid userId)
        : base($"User {userId} already has an active subscription") { }
}
```

For operations that can fail predictably, use a Result pattern instead of exceptions:

```csharp
public record Result<T>
{
    public T? Value { get; }
    public string? Error { get; }
    public bool IsSuccess => Error is null;

    private Result(T value) => Value = value;
    private Result(string error) => Error = error;

    public static Result<T> Success(T value) => new(value);
    public static Result<T> Failure(string error) => new(error);
}

public async Task<Result<Subscription>> TryRenewAsync(
    Guid subscriptionId, CancellationToken cancellationToken)
{
    var subscription = await _repository.GetByIdAsync(subscriptionId, cancellationToken);
    if (subscription is null)
        return Result<Subscription>.Failure("Subscription not found");

    if (subscription.Status is not SubscriptionStatus.Active)
        return Result<Subscription>.Failure("Only active subscriptions can be renewed");

    subscription.ExpiresAt = subscription.ExpiresAt.AddMonths(1);
    await _unitOfWork.SaveChangesAsync(cancellationToken);

    return Result<Subscription>.Success(subscription);
}
```

Guard clauses use `ArgumentException` and friends:

```csharp
public void SetPrice(decimal price)
{
    ArgumentOutOfRangeException.ThrowIfNegativeOrZero(price);
    Price = price;
}
```

---

## Testing (xUnit)

Use xUnit for tests, NSubstitute for mocks, FluentAssertions for readable assertions.

```csharp
public class SubscriptionServiceTests
{
    private readonly ISubscriptionRepository _repository = Substitute.For<ISubscriptionRepository>();
    private readonly IPaymentGateway _paymentGateway = Substitute.For<IPaymentGateway>();
    private readonly IUnitOfWork _unitOfWork = Substitute.For<IUnitOfWork>();
    private readonly SubscriptionService _sut;

    public SubscriptionServiceTests()
    {
        _sut = new SubscriptionService(_repository, _paymentGateway, _unitOfWork);
    }

    [Fact]
    public async Task CreateSubscriptionAsync_ValidRequest_ReturnsActiveSubscription()
    {
        // Arrange
        var request = new CreateSubscriptionRequest(Guid.NewGuid(), Guid.NewGuid(), "pm_test");
        _paymentGateway.ChargeAsync(Arg.Any<string>(), Arg.Any<Money>(), Arg.Any<CancellationToken>())
            .Returns(new Payment { Id = Guid.NewGuid() });

        // Act
        var result = await _sut.CreateSubscriptionAsync(request, CancellationToken.None);

        // Assert
        result.Status.Should().Be(SubscriptionStatus.Active);
        result.UserId.Should().Be(request.UserId);
        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task CreateSubscriptionAsync_UserAlreadySubscribed_Throws()
    {
        // Arrange
        var userId = Guid.NewGuid();
        _repository.HasActiveSubscriptionAsync(userId, Arg.Any<CancellationToken>())
            .Returns(true);

        var request = new CreateSubscriptionRequest(userId, Guid.NewGuid(), "pm_test");

        // Act
        var act = () => _sut.CreateSubscriptionAsync(request, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<SubscriptionAlreadyActiveException>();
    }

    [Theory]
    [InlineData(SubscriptionStatus.Cancelled)]
    [InlineData(SubscriptionStatus.Expired)]
    public async Task RenewAsync_InactiveStatus_ReturnsFailure(SubscriptionStatus status)
    {
        // Arrange
        var sub = new Subscription { Status = status };
        _repository.GetByIdAsync(sub.Id, Arg.Any<CancellationToken>()).Returns(sub);

        // Act
        var result = await _sut.TryRenewAsync(sub.Id, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeFalse();
        result.Error.Should().Contain("active");
    }
}
```

---

## C#-Specific Quality Checklist

- [ ] `<Nullable>enable</Nullable>` in every `.csproj`
- [ ] No `async void` methods (except UI event handlers)
- [ ] No `.Result` or `.Wait()` — always `await`
- [ ] `CancellationToken` accepted and forwarded in all async methods
- [ ] File-scoped namespaces in every file
- [ ] Records used for DTOs and value objects; classes for mutable entities
- [ ] `ConfigureAwait(false)` in all library/shared code
- [ ] No `catch (Exception)` without logging — catch specific types first
- [ ] `IDisposable`/`IAsyncDisposable` implemented where unmanaged resources are held
- [ ] Guard clauses use `ArgumentException.ThrowIf*` static methods (C# 10+)

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Deadlock on `.Result`/`.Wait()` | Blocking on async in sync context | Replace with `await` — restructure the call chain to be async all the way |
| `ObjectDisposedException` on `DbContext` | Context disposed before async operation completes | Ensure scoped lifetime; do not capture context across threads |
| `NullReferenceException` at runtime despite no warnings | Null-forgiving operator `!` used to silence compiler | Remove `!`, fix the actual nullability, add null checks |
| `InvalidOperationException: second operation started` | Two EF queries on the same `DbContext` concurrently | Do not use `Task.WhenAll` with the same context; sequence the calls |
| Tests pass locally, fail in CI | Missing `ConfigureAwait(false)` in library consumed by sync test runner | Add `ConfigureAwait(false)` to all library async methods |
| `TaskCanceledException` in production | `CancellationToken` not wired through to HTTP calls | Accept and forward `CancellationToken` in every async method |
| Enum serializes as integer | Default `System.Text.Json` behavior | Add `[JsonConverter(typeof(JsonStringEnumConverter))]` or configure globally |
| Memory leak in long-running service | Event handlers or delegates prevent GC | Unsubscribe from events; use weak references or `IDisposable` cleanup |
