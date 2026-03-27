## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# Java — Language Reference

Loaded by `coder/SKILL.md` when the project is Java.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Methods | camelCase, verb phrase | `getSubscriptionById()`, `cancelSubscription()` |
| Classes | PascalCase, noun phrase | `SubscriptionService`, `PaymentProcessor` |
| Interfaces | PascalCase, noun or adjective | `Billable`, `SubscriptionRepository` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_RETRY_ATTEMPTS`, `DEFAULT_TIMEOUT_SECONDS` |
| Packages | all lowercase, reverse domain | `com.acme.billing.subscription` |
| Type Parameters | Single uppercase letter or short name | `T`, `E`, `K extends Comparable<K>` |
| Booleans | is, has, can, should prefix | `isActive`, `hasSubscription` |
| Enums | PascalCase type, UPPER_SNAKE values | `Status.ACTIVE`, `Status.CANCELLED` |

---

## File Organization

```java
// One top-level public class per file. File name matches class name.

package com.acme.billing.subscription;

// java.* imports
import java.time.Instant;
import java.time.Duration;
import java.util.List;
import java.util.Optional;

// javax.* imports
import javax.validation.constraints.NotNull;

// Third-party imports
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

// Local imports
import com.acme.billing.payment.PaymentService;
import com.acme.billing.user.User;

// Constants
private static final int MAX_RENEWAL_ATTEMPTS = 3;
private static final Duration GRACE_PERIOD = Duration.ofDays(7);
```

Import ordering: `java.*`, then `javax.*`, then third-party, then local. No wildcard imports. Let the IDE manage them.

---

## Modern Java

Use Java 17+ features. They reduce boilerplate and make intent explicit.

### Records for Data Carriers

Records replace POJOs for immutable data. Use them for DTOs, value objects, and anything that is just data.

```java
public record SubscriptionSummary(
    long subscriptionId,
    String planName,
    Instant expiresAt,
    boolean isActive
) {
    // Compact constructor for validation
    public SubscriptionSummary {
        if (planName == null || planName.isBlank()) {
            throw new IllegalArgumentException("planName must not be blank");
        }
    }
}
```

### Sealed Classes for Closed Hierarchies

Sealed classes define every possible subtype. The compiler enforces exhaustive pattern matching.

```java
public sealed interface PaymentResult
        permits PaymentResult.Success, PaymentResult.Declined, PaymentResult.Error {

    record Success(String transactionId, Instant processedAt) implements PaymentResult {}
    record Declined(String reason) implements PaymentResult {}
    record Error(Exception cause) implements PaymentResult {}
}
```

### Pattern Matching

```java
public String describeResult(PaymentResult result) {
    return switch (result) {
        case PaymentResult.Success s   -> "Paid: " + s.transactionId();
        case PaymentResult.Declined d  -> "Declined: " + d.reason();
        case PaymentResult.Error e     -> "Error: " + e.cause().getMessage();
    };
}

// Pattern matching for instanceof — no more manual casts
if (event instanceof SubscriptionCancelledEvent cancelled) {
    log.info("Subscription {} cancelled at {}", cancelled.subscriptionId(), cancelled.cancelledAt());
}
```

### Local Variable Type Inference

Use `var` when the type is obvious from the right-hand side. Do not use it when it obscures the type.

```java
var subscriptions = subscriptionRepository.findByUserId(userId); // clear: returns List<Subscription>
var summary = new SubscriptionSummary(1L, "Pro", Instant.now(), true); // clear: constructing a known type

// Do NOT do this — the return type is not obvious
var result = service.process(input);
```

### Text Blocks

```java
private static final String CANCELLATION_EMAIL = """
        Dear %s,

        Your subscription to the %s plan has been cancelled.
        Access continues until %s.

        — Billing Team
        """;
```

---

## Collections and Streams

### Immutable Collections

Default to immutable. Use mutable collections only when mutation is required.

```java
// Prefer these
var activePlans = List.of("Starter", "Pro", "Enterprise");
var featureFlags = Map.of("darkMode", true, "betaBilling", false);
var uniqueTags = Set.of("annual", "discounted");

// List.copyOf / Map.copyOf for defensive copies
public List<Subscription> getSubscriptions() {
    return List.copyOf(this.subscriptions);
}
```

### Stream Pipelines

Keep streams short and readable. If it takes more than three or four operations, extract a method.

```java
public List<SubscriptionSummary> getActiveSubscriptionSummaries(long userId) {
    return subscriptionRepository.findByUserId(userId).stream()
            .filter(Subscription::isActive)
            .map(this::toSummary)
            .sorted(Comparator.comparing(SubscriptionSummary::expiresAt))
            .toList();
}
```

### Optional

`Optional` is a return type, not a field type and not a parameter type.

```java
public Optional<Subscription> findActiveSubscription(long userId) {
    return subscriptionRepository.findByUserIdAndStatus(userId, Status.ACTIVE);
}

// Caller decides what to do
var subscription = subscriptionService.findActiveSubscription(userId)
        .orElseThrow(() -> new SubscriptionNotFoundException(userId));

// Never do this
Optional<String> name = Optional.of("value"); // pointless wrapping
public void process(Optional<Config> config) {} // Optional as parameter
```

---

## Error Handling

Use unchecked exceptions for domain errors. Checked exceptions are for recoverable I/O boundaries.

### Custom Exception Hierarchy

```java
// Base exception for the subscription domain
public class SubscriptionException extends RuntimeException {
    public SubscriptionException(String message) { super(message); }
    public SubscriptionException(String message, Throwable cause) { super(message, cause); }
}

public class SubscriptionNotFoundException extends SubscriptionException {
    public SubscriptionNotFoundException(long userId) {
        super("No active subscription found for user " + userId);
    }
}

public class SubscriptionExpiredException extends SubscriptionException {
    public SubscriptionExpiredException(long subscriptionId, Instant expiredAt) {
        super("Subscription %d expired at %s".formatted(subscriptionId, expiredAt));
    }
}
```

### Try-With-Resources

Every `AutoCloseable` must use try-with-resources. No exceptions.

```java
public SubscriptionReport generateReport(long orgId) {
    try (var connection = dataSource.getConnection();
         var statement = connection.prepareStatement(REPORT_QUERY)) {
        statement.setLong(1, orgId);
        try (var resultSet = statement.executeQuery()) {
            return mapToReport(resultSet);
        }
    } catch (SQLException e) {
        throw new ReportGenerationException("Failed to generate report for org " + orgId, e);
    }
}
```

Handle at boundaries. Let domain exceptions propagate to the controller layer:

```java
@ExceptionHandler(SubscriptionException.class)
public ResponseEntity<ErrorResponse> handleSubscriptionError(SubscriptionException e) {
    log.info("Subscription error: {}", e.getMessage());
    return ResponseEntity.badRequest().body(new ErrorResponse(e.getMessage()));
}
```

---

## Testing (JUnit 5)

Use JUnit 5 + Mockito for unit tests. Use AssertJ for fluent, readable assertions.

```java
@ExtendWith(MockitoExtension.class)
class SubscriptionServiceTest {

    @Mock
    private SubscriptionRepository subscriptionRepository;

    @Mock
    private PaymentService paymentService;

    @InjectMocks
    private SubscriptionService subscriptionService;

    @Test
    void createSubscription_happyPath_returnsActiveSubscription() {
        var user = new User(1L, "user@example.com");
        var plan = new Plan("Pro", Money.of(29_99, "USD"), Duration.ofDays(30));

        when(subscriptionRepository.findActiveByUserId(1L)).thenReturn(Optional.empty());
        when(paymentService.charge(any())).thenReturn(new PaymentResult.Success("txn_123", Instant.now()));

        var subscription = subscriptionService.createSubscription(user, plan, "pm_test");

        assertThat(subscription.status()).isEqualTo(Status.ACTIVE);
        assertThat(subscription.userId()).isEqualTo(1L);
        assertThat(subscription.planName()).isEqualTo("Pro");
        verify(subscriptionRepository).save(any(Subscription.class));
    }

    @Test
    void createSubscription_alreadySubscribed_throws() {
        when(subscriptionRepository.findActiveByUserId(1L))
                .thenReturn(Optional.of(mock(Subscription.class)));

        assertThatThrownBy(() ->
                subscriptionService.createSubscription(new User(1L, "a@b.com"), mock(Plan.class), "pm_test"))
            .isInstanceOf(SubscriptionException.class)
            .hasMessageContaining("already has an active subscription");
    }
}
```

Test naming: `methodName_scenario_expectedBehavior`. Each test verifies one behavior. No logic in tests — no `if`, no loops.

---

## Java-Specific Quality Checklist

- [ ] No raw types — always `List<Subscription>`, never `List`
- [ ] Records used for DTOs and value objects instead of mutable POJOs
- [ ] All `AutoCloseable` resources use try-with-resources
- [ ] `Optional` used only as return type, never as field or parameter
- [ ] Immutable collections (`List.of`, `Map.of`) by default; mutable only when required
- [ ] No `null` returns from public methods — use `Optional` or throw
- [ ] Sealed classes for closed type hierarchies with exhaustive `switch`
- [ ] `@Override` on every overridden method
- [ ] Domain exceptions extend a base unchecked exception, not `Exception` directly
- [ ] Streams kept short — extract a method if the pipeline exceeds four operations

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| `NullPointerException` at runtime | Returning `null` from methods | Return `Optional` or throw a domain exception |
| Resource leak warnings / connection exhaustion | Missing try-with-resources | Wrap every `AutoCloseable` in try-with-resources |
| `ClassCastException` | Raw types or unchecked casts | Use generics everywhere; eliminate `@SuppressWarnings("unchecked")` |
| Unintended mutation of shared state | Returning mutable collections from getters | Return `List.copyOf()` or use `Collections.unmodifiableList()` |
| Flaky tests with shared state | Mutable static or shared fields | Use `@BeforeEach` setup; avoid static mutable state |
| `UnsupportedOperationException` on `List.of().add()` | Treating immutable collections as mutable | Choose the right collection type up front |
| Silent swallowing of errors | Empty `catch` blocks | Log and rethrow, or throw a domain exception wrapping the cause |
| Compile warnings about missing `switch` cases | Non-sealed hierarchy in pattern match | Use sealed interfaces; handle all permitted subtypes |
