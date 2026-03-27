<!-- License: See /LICENSE -->


# PHP — Language Reference

Loaded by `coder/SKILL.md` when the project is PHP.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Methods / functions | camelCase, verb phrase | `getActiveSubscriptions()`, `cancelPlan()` |
| Classes | PascalCase, noun phrase | `SubscriptionService`, `PaymentProcessor` |
| Interfaces | PascalCase, adjective or noun | `Subscribable`, `PaymentGateway` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_RETRY_ATTEMPTS`, `DEFAULT_CURRENCY` |
| Properties | camelCase | `$expiresAt`, `$isActive` |
| Enums | PascalCase (backed values lowercase) | `SubscriptionStatus::Active` |
| Booleans | is, has, can, should prefix | `$isExpired`, `$hasPaymentMethod` |
| Files | PascalCase matching class name | `SubscriptionService.php` |

Follow PSR-12 unconditionally. Configure your formatter and never argue about style.

---

## File Organization

```php
<?php

declare(strict_types=1);

namespace App\Services\Subscription;

// PHP built-in / SPL
use DateTimeImmutable;
use RuntimeException;

// Framework / third-party
use Illuminate\Support\Facades\DB;
use Stripe\PaymentIntent;

// Local
use App\Models\{Subscription, User};
use App\Exceptions\SubscriptionException;
```

Group use statements: PHP built-ins, then third-party/framework, then local — blank-line separated, alphabetized within groups. One class per file.

---

## Type Declarations

Every file starts with `declare(strict_types=1);`. No exceptions.

```php
class SubscriptionService
{
    public function __construct(
        private readonly PaymentGateway $gateway,
        private readonly SubscriptionRepository $subscriptions,
    ) {}

    public function createSubscription(User $user, Plan $plan, string $paymentMethodId): Subscription
    {
        if ($user->hasActiveSubscription()) {
            throw SubscriptionException::alreadyActive($user->id);
        }
        return DB::transaction(function () use ($user, $plan, $paymentMethodId): Subscription {
            $payment = $this->gateway->charge($user, $plan->price, $paymentMethodId);
            return $this->subscriptions->create(
                user: $user, plan: $plan, payment: $payment,
                expiresAt: new DateTimeImmutable("+{$plan->durationDays} days"),
            );
        });
    }

    /** @return list<Subscription> */
    public function getExpiring(int $withinDays = 7): array
    {
        return $this->subscriptions->findExpiring(withinDays: $withinDays);
    }

    public function cancel(Subscription $subscription, ?string $reason = null): void
    {
        $subscription->cancel(reason: $reason);
    }
}
```

- Type every parameter and every return. Use `void` when returning nothing.
- Use `?Type` for nullable. Use union types sparingly — prefer a single concrete type.
- Use `mixed` only at framework boundaries. Add PHPDoc `@return` only when the type system cannot express it (e.g., generics like `list<Subscription>`).

---

## Modern PHP (8.x)

### Enums

```php
enum SubscriptionStatus: string
{
    case Active    = 'active';
    case Paused    = 'paused';
    case Cancelled = 'cancelled';
    case Expired   = 'expired';

    public function isTerminal(): bool
    {
        return match ($this) { self::Cancelled, self::Expired => true, default => false };
    }
}
```

### Named Arguments

Use when a function takes more than two parameters or has boolean flags:

```php
$subscription = $service->createSubscription(
    user: $currentUser,
    plan: $selectedPlan,
    paymentMethodId: $request->input('payment_method_id'),
);
```

### Match Expressions

Prefer `match` over `switch` — strict comparison, returns a value, no fallthrough:

```php
$label = match ($subscription->status) {
    SubscriptionStatus::Active    => 'Your subscription is active',
    SubscriptionStatus::Cancelled => 'Your subscription has been cancelled',
    SubscriptionStatus::Expired   => 'Your subscription has expired',
    default                       => 'Unknown status',
};
```

### Readonly Properties and Constructor Promotion

```php
final class PaymentResult
{
    public function __construct(
        public readonly string $transactionId,
        public readonly int $amountCents,
        public readonly DateTimeImmutable $processedAt,
    ) {}
}
```

### Fibers

For library authors building async runtimes (ReactPHP, Amp). Application code should not create fibers directly.

---

## Error Handling

Define a hierarchy of domain exceptions with named constructors:

```php
class SubscriptionException extends \DomainException
{
    public static function alreadyActive(int $userId): self
    {
        return new self("User {$userId} already has an active subscription", 1001);
    }
    public static function expired(int $subscriptionId): self
    {
        return new self("Subscription {$subscriptionId} has expired", 1002);
    }
}

class PaymentFailedException extends SubscriptionException {}
```

Handle at boundaries; let domain exceptions propagate up to controllers:

```php
try {
    $subscription = $this->subscriptionService->createSubscription(...);
    return response()->json(['subscription_id' => $subscription->id], 201);
} catch (SubscriptionException $e) {
    Log::info('Subscription failed', ['error' => $e->getMessage()]);
    return response()->json(['error' => $e->getMessage()], 400);
} catch (\Throwable $e) {
    Log::error('Unexpected error', ['exception' => $e]);
    return response()->json(['error' => 'An unexpected error occurred'], 500);
}
```

Never catch `\Exception` or `\Throwable` in domain code. Catch at the controller or middleware level only.

---

## Testing (PHPUnit)

```php
final class SubscriptionServiceTest extends TestCase
{
    private SubscriptionService $service;
    private PaymentGateway&MockObject $gateway;

    protected function setUp(): void
    {
        $this->gateway = $this->createMock(PaymentGateway::class);
        $this->service = new SubscriptionService(
            $this->gateway, $this->createMock(SubscriptionRepository::class),
        );
    }

    #[Test]
    public function createsSubscriptionForEligibleUser(): void
    {
        $user = UserFactory::make(hasActiveSubscription: false);
        $plan = PlanFactory::make(price: 1999, durationDays: 30);
        $this->gateway->expects($this->once())->method('charge')
            ->willReturn(new PaymentResult('txn_123', 1999, new \DateTimeImmutable()));
        $subscription = $this->service->createSubscription($user, $plan, 'pm_test');
        self::assertSame(SubscriptionStatus::Active, $subscription->status);
    }

    #[Test]
    public function rejectsSubscriptionWhenUserAlreadySubscribed(): void
    {
        $this->expectException(SubscriptionException::class);
        $user = UserFactory::make(hasActiveSubscription: true);
        $this->service->createSubscription($user, PlanFactory::make(), 'pm_test');
    }

    #[Test]
    #[DataProvider('terminalStatusProvider')]
    public function identifiesTerminalStatuses(SubscriptionStatus $status, bool $expected): void
    {
        self::assertSame($expected, $status->isTerminal());
    }

    public static function terminalStatusProvider(): array
    {
        return [
            'active is not terminal' => [SubscriptionStatus::Active, false],
            'cancelled is terminal'  => [SubscriptionStatus::Cancelled, true],
            'expired is terminal'    => [SubscriptionStatus::Expired, true],
        ];
    }
}
```

Use `self::assert*` over `$this->assert*` — the methods are static. Prefer PHP 8 attributes (`#[Test]`, `#[DataProvider]`) over docblock annotations.

**Pest** is a modern alternative built on PHPUnit. If the project already uses Pest, follow its conventions. Do not mix PHPUnit and Pest test styles in the same project.

---

## PHP-Specific Quality Checklist

- [ ] `declare(strict_types=1)` in every file
- [ ] All parameters and return types declared
- [ ] PHPStan at level 8+ passes clean
- [ ] No `==` — use `===` everywhere
- [ ] No `@` error suppression operator
- [ ] No untyped `array` when a class or typed collection works
- [ ] Caught exceptions are logged or rethrown — never silenced
- [ ] `readonly` on properties that must not change after construction
- [ ] `final` on classes not designed for extension
- [ ] No `die()`, `exit()`, `var_dump()`, or `dd()` in production code

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Unexpected type coercion | Missing `declare(strict_types=1)` | Add to every file; enforce via PHPStan rule |
| Silent `null` bugs | Loose comparison with `==` | Use `===` everywhere; enable strict PHPStan |
| Missing method crashes | Untyped parameter accepts wrong object | Add type declarations to all parameters |
| Enum comparison fails | Comparing enum case to its backed value | Compare enum to enum, or use `->value` explicitly |
| Test pollution | Shared mutable state between tests | Use `setUp()` to reinitialize; avoid static state |
| Slow test suite | Real database/network in unit tests | Mock external dependencies; reserve integration tests for boundaries |
| Memory exhaustion | Loading full collection into array | Use generators (`yield`) or chunked queries |
| Inconsistent dates | Mutable `DateTime` passed by reference | Use `DateTimeImmutable` exclusively |
