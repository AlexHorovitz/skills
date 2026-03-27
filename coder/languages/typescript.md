## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# TypeScript — Language Reference

Loaded by `coder/SKILL.md` when the project is TypeScript.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Functions / variables | camelCase, verb phrase for functions | `getUser()`, `validateSubscription()` |
| Types / interfaces | PascalCase, noun phrase | `UserSubscription`, `PaymentResult` |
| Classes | PascalCase, noun phrase | `SubscriptionService`, `PaymentProcessor` |
| Enum members | PascalCase | `Status.Active`, `Role.Admin` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_RETRY_ATTEMPTS`, `DEFAULT_TIMEOUT_MS` |
| Booleans | is, has, can, should prefix | `isActive`, `hasSubscription`, `canCancel` |
| Files | kebab-case | `subscription-service.ts`, `payment-gateway.ts` |

No `I` prefix on interfaces. `UserRepository`, not `IUserRepository`. The type system does not need Hungarian notation.

---

## File Organization

```typescript
// Node built-ins
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";

// Third-party
import { z } from "zod";
import { Hono } from "hono";

// Local — absolute paths (aliases)
import { db } from "@/lib/database";
import { logger } from "@/lib/logger";

// Local — relative paths
import { validatePlan } from "./validators";
import type { Subscription, Plan } from "./types";

// Constants
const MAX_RENEWAL_ATTEMPTS = 3;
const GRACE_PERIOD_DAYS = 7;

// Implementation below...
```

Always use ESM (`import`/`export`). Never use `require()`. Separate import groups with a blank line.

---

## Type System Discipline

Enable `strict: true` in `tsconfig.json`. No exceptions. This turns on `strictNullChecks`, `noImplicitAny`, `strictFunctionTypes`, and every other guard that matters.

Never use `any`. If you need an escape hatch, use `unknown` and narrow:

```typescript
// ❌ any discards all type safety
function processEvent(event: any) {
  event.data.subscription.cancel(); // no compiler help
}

// ✅ unknown + narrowing preserves safety
function processEvent(event: unknown): void {
  if (!isSubscriptionEvent(event)) {
    throw new InvalidEventError(event);
  }
  event.data.subscription.cancel(); // fully typed
}
```

Use discriminated unions for domain states. Never model mutually exclusive states as optional fields:

```typescript
// ❌ Ambiguous — which fields exist in which state?
interface Subscription {
  status: string;
  cancelledAt?: Date;
  pausedAt?: Date;
  expiresAt?: Date;
}

// ✅ Discriminated union — each state declares exactly what it carries
type Subscription =
  | { status: "active"; planId: string; expiresAt: Date }
  | { status: "paused"; planId: string; pausedAt: Date; resumesAt: Date }
  | { status: "cancelled"; planId: string; cancelledAt: Date; reason: string }
  | { status: "expired"; planId: string; expiredAt: Date };

function handleSubscription(sub: Subscription): string {
  switch (sub.status) {
    case "active":
      return `Renews on ${sub.expiresAt.toISOString()}`;
    case "paused":
      return `Resumes on ${sub.resumesAt.toISOString()}`;
    case "cancelled":
      return `Cancelled: ${sub.reason}`;
    case "expired":
      return `Expired on ${sub.expiredAt.toISOString()}`;
  }
  // No default needed — TypeScript enforces exhaustiveness
}
```

Prefer `interface` for object shapes that may be extended. Use `type` for unions, intersections, and mapped types. Use generics to avoid duplication:

```typescript
interface Repository<T> {
  findById(id: string): Promise<T | null>;
  create(data: Omit<T, "id" | "createdAt">): Promise<T>;
  delete(id: string): Promise<void>;
}

interface SubscriptionRepository extends Repository<Subscription> {
  findActiveByUserId(userId: string): Promise<Subscription[]>;
}
```

---

## Null Safety

With `strictNullChecks` on, the compiler forces you to handle `null` and `undefined`. Lean into it.

```typescript
// ❌ Non-null assertion operator hides bugs
const user = users.find((u) => u.id === id)!;

// ✅ Optional chaining + nullish coalescing
const displayName = user?.profile?.displayName ?? "Anonymous";

// ✅ Early return on null
function getSubscription(userId: string): Subscription {
  const sub = subscriptions.get(userId);
  if (!sub) {
    throw new SubscriptionNotFoundError(userId);
  }
  return sub; // type narrowed to Subscription
}
```

Never use the non-null assertion operator (`!`) in production code. It exists for migration, not for convenience.

---

## Error Handling

Define typed error classes per domain. Always extend `Error`:

```typescript
class SubscriptionError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = "SubscriptionError";
  }
}

class SubscriptionNotFoundError extends SubscriptionError {
  constructor(public readonly subscriptionId: string) {
    super(`Subscription ${subscriptionId} not found`, "SUBSCRIPTION_NOT_FOUND");
  }
}

class PaymentDeclinedError extends SubscriptionError {
  constructor(public readonly reason: string) {
    super(`Payment declined: ${reason}`, "PAYMENT_DECLINED");
  }
}
```

Use a `Result` type for operations that fail as part of normal control flow. Reserve `throw` for truly exceptional conditions:

```typescript
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

async function createSubscription(
  userId: string,
  planId: string,
  paymentMethodId: string,
): Promise<Result<Subscription, SubscriptionError>> {
  const user = await userRepo.findById(userId);
  if (!user) {
    return { ok: false, error: new SubscriptionNotFoundError(userId) };
  }
  if (user.hasActiveSubscription) {
    return { ok: false, error: new SubscriptionError("Already subscribed", "ALREADY_SUBSCRIBED") };
  }

  const payment = await paymentGateway.charge(user, planId, paymentMethodId);
  if (!payment.ok) {
    return { ok: false, error: new PaymentDeclinedError(payment.error.reason) };
  }

  const subscription = await subscriptionRepo.create({
    userId,
    planId,
    status: "active",
    expiresAt: calculateExpiration(planId),
  });

  return { ok: true, value: subscription };
}
```

At API boundaries, catch and translate:

```typescript
app.post("/subscriptions", async (c) => {
  const result = await createSubscription(c.get("userId"), body.planId, body.paymentMethodId);
  if (!result.ok) {
    logger.info("Subscription creation failed", { error: result.error.code });
    return c.json({ error: result.error.message }, 400);
  }
  return c.json({ subscription: result.value }, 201);
});
```

---

## Testing (Vitest)

Vitest is the default test runner. Use Jest only when the project already depends on it.

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";

describe("SubscriptionService", () => {
  let service: SubscriptionService;
  let mockRepo: SubscriptionRepository;
  let mockGateway: PaymentGateway;

  beforeEach(() => {
    mockRepo = {
      findById: vi.fn(),
      create: vi.fn(),
      findActiveByUserId: vi.fn(),
      delete: vi.fn(),
    };
    mockGateway = {
      charge: vi.fn(),
    };
    service = new SubscriptionService(mockRepo, mockGateway);
  });

  it("creates subscription for eligible user", async () => {
    vi.mocked(mockRepo.findActiveByUserId).mockResolvedValue([]);
    vi.mocked(mockGateway.charge).mockResolvedValue({ ok: true, value: mockPayment });
    vi.mocked(mockRepo.create).mockResolvedValue(mockSubscription);

    const result = await service.create("user-1", "plan-pro", "pm-test");

    expect(result.ok).toBe(true);
    expect(mockGateway.charge).toHaveBeenCalledWith(
      expect.objectContaining({ id: "user-1" }),
      "plan-pro",
      "pm-test",
    );
  });

  it("returns error when user already has active subscription", async () => {
    vi.mocked(mockRepo.findActiveByUserId).mockResolvedValue([mockSubscription]);

    const result = await service.create("user-1", "plan-pro", "pm-test");

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("ALREADY_SUBSCRIBED");
    }
    expect(mockGateway.charge).not.toHaveBeenCalled();
  });
});
```

Use `vi.fn()` for mocks, `vi.mocked()` for type-safe mock access. Keep tests focused: one behavior per `it` block. Name tests as sentences describing what happens and when.

---

## TypeScript-Specific Quality Checklist

- [ ] `strict: true` in `tsconfig.json` — no partial strict mode
- [ ] Zero uses of `any` — use `unknown` and narrow instead
- [ ] No non-null assertions (`!`) in production code
- [ ] Discriminated unions for domain states, not optional fields
- [ ] All API responses and external data validated at the boundary (Zod, ArkType, or similar)
- [ ] No `enum` keyword — use `as const` objects or union types for string enums
- [ ] Explicit return types on exported functions
- [ ] Barrel files (`index.ts`) are thin re-exports only — no logic
- [ ] No `@ts-ignore` — use `@ts-expect-error` with an explanation if truly unavoidable

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Runtime crash on `.property` access | Non-null assertion (`!`) on a null value | Remove `!`, add proper null check |
| Type says `string` but value is `undefined` | External data not validated at boundary | Add Zod schema validation at API/IO edges |
| Exhaustiveness not checked | Missing `never` check in switch | Add `default: const _exhaustive: never = value` |
| Import cycle crashes at runtime | Circular module dependencies | Extract shared types into a separate module |
| Tests pass but types are wrong | Mocks typed as `any` | Use `vi.mocked()` or type mocks against the interface |
| Bundle includes unused code | Barrel file re-exports everything | Import directly from source module, not barrel |
| `Object is possibly undefined` everywhere | Optional chaining overuse without narrowing | Guard early with `if (!value)` and return/throw |
| Slow type-checking | Deep conditional types or large unions | Simplify types, break into smaller modules |
