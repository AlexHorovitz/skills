## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

**Version:** 1.0.0

# Refactoring Skill

## Purpose
Continuously scan codebases for refactoring opportunities—improving code quality, reducing technical debt, and enhancing maintainability without changing external behavior. Be opportunistic but disciplined: refactor with purpose, not for sport.

## When to Use
- After features ship and dust settles
- When code review reveals systemic issues
- Before adding features to messy areas
- During dedicated tech debt sprints
- When test coverage makes refactoring safe

## Interface

| | |
|---|---|
| **Input** | `codebase-skeptic` or `code-reviewer` findings (when available); otherwise, codebase scan |
| **Output** | Prioritized refactor plan + refactored code submitted as separate PRs from feature work |
| **Consumed by** | `code-reviewer` (each refactoring PR goes through the same gate as feature work) |
| **SSD Phase** | `/ssd milestone` |

---

## Refactoring Philosophy

### The Boy Scout Rule
> Leave the code better than you found it.

But also:
> Don't rewrite the campsite while others are trying to use it.

### When to Refactor

**Good times to refactor:**
- You're already changing the code for a feature
- Tests exist and are passing
- You understand the code deeply
- The improvement has clear benefits
- The team agrees on the direction

**Bad times to refactor:**
- Right before a major release
- When you don't understand the code
- When tests are missing or failing
- For purely aesthetic reasons
- When it blocks others' work

### The Refactoring Contract

1. **Behavior must not change.** If users notice anything different, it's not a refactor—it's a bug.
2. **Tests must pass.** Before and after. No exceptions.
3. **Small steps.** Each commit should be independently safe to deploy.
4. **Revert-ready.** If anything goes wrong, roll back immediately.

---

## Scanning for Opportunities

### Code Smells to Hunt

Run these scans regularly to identify refactoring candidates:

#### 1. Complexity Hotspots

```bash
# Find files with highest cyclomatic complexity
radon cc . -a -s --min C

# Find longest files (often doing too much)
find . -name "*.py" -exec wc -l {} \; | sort -rn | head -20

# Find longest functions
# (Use AST analysis or IDE tools)
```

**Thresholds:**
| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| File length | < 300 lines | 300-500 | > 500 |
| Function length | < 30 lines | 30-50 | > 50 |
| Cyclomatic complexity | < 10 | 10-15 | > 15 |
| Parameters per function | < 5 | 5-7 | > 7 |

#### 2. Duplication

```bash
# Find duplicate code blocks
pylint --disable=all --enable=duplicate-code .

# Or use dedicated tools
flay .  # Ruby
jscpd . # JavaScript
```

**Rule of Three:** If you see the same code three times, extract it.

#### 3. Dependency Analysis

```bash
# Find circular imports
pydeps --cluster . --max-bacon 2

# Find highly coupled modules
# (Modules with many incoming/outgoing dependencies)
```

#### 4. Test Coverage Gaps

```bash
# Find untested code
pytest --cov=. --cov-report=term-missing

# Focus on: High complexity + Low coverage = High risk
```

#### 5. Code Age Analysis

```bash
# Find code that changes frequently (churn)
git log --format=format: --name-only --since="6 months ago" | \
  grep -v '^$' | sort | uniq -c | sort -rn | head -20

# High churn + High complexity = Refactoring priority
```

---

## Common Refactoring Patterns

### 1. Extract Method

**Smell:** Long function doing multiple things

```python
# Before: 45-line function
def process_order(order):
    # Validate order (15 lines)
    if not order.items:
        raise ValidationError("Order has no items")
    for item in order.items:
        if item.quantity <= 0:
            raise ValidationError(f"Invalid quantity for {item.product}")
        if not item.product.is_available:
            raise ValidationError(f"{item.product} is not available")
    # ... more validation
    
    # Calculate totals (15 lines)
    subtotal = sum(item.price * item.quantity for item in order.items)
    tax = subtotal * Decimal('0.08')
    shipping = calculate_shipping(order)
    total = subtotal + tax + shipping
    
    # Create records (15 lines)
    order.subtotal = subtotal
    order.tax = tax
    order.shipping = shipping
    order.total = total
    order.status = 'confirmed'
    order.save()
    # ... more record creation
    
    return order

# After: Clear, single-responsibility functions
def process_order(order):
    validate_order(order)
    totals = calculate_order_totals(order)
    return finalize_order(order, totals)

def validate_order(order):
    """Validate order has items and all items are available."""
    if not order.items:
        raise ValidationError("Order has no items")
    for item in order.items:
        validate_order_item(item)

def validate_order_item(item):
    """Validate a single order item."""
    if item.quantity <= 0:
        raise ValidationError(f"Invalid quantity for {item.product}")
    if not item.product.is_available:
        raise ValidationError(f"{item.product} is not available")

def calculate_order_totals(order) -> OrderTotals:
    """Calculate all order totals."""
    subtotal = sum(item.price * item.quantity for item in order.items)
    return OrderTotals(
        subtotal=subtotal,
        tax=subtotal * Decimal('0.08'),
        shipping=calculate_shipping(order),
    )

def finalize_order(order, totals: OrderTotals):
    """Apply totals and mark order confirmed."""
    order.subtotal = totals.subtotal
    order.tax = totals.tax
    order.shipping = totals.shipping
    order.total = totals.total
    order.status = 'confirmed'
    order.save()
    return order
```

### 2. Replace Conditional with Polymorphism

**Smell:** Switch statements or long if/elif chains based on type

```python
# Before: Type checking everywhere
def calculate_price(product):
    if product.type == 'subscription':
        base = product.monthly_price
        if product.billing_cycle == 'annual':
            base = product.monthly_price * 12 * 0.8  # 20% discount
        return base
    elif product.type == 'one_time':
        return product.price
    elif product.type == 'usage_based':
        return product.base_price + (product.usage * product.per_unit_price)
    else:
        raise ValueError(f"Unknown product type: {product.type}")

def get_description(product):
    if product.type == 'subscription':
        return f"${product.monthly_price}/month"
    elif product.type == 'one_time':
        return f"${product.price} one-time"
    # ... same pattern repeated

# After: Polymorphism
class Product(models.Model):
    class Meta:
        abstract = True
    
    def calculate_price(self) -> Decimal:
        raise NotImplementedError
    
    def get_description(self) -> str:
        raise NotImplementedError

class SubscriptionProduct(Product):
    monthly_price = models.DecimalField(...)
    billing_cycle = models.CharField(...)
    
    def calculate_price(self) -> Decimal:
        if self.billing_cycle == 'annual':
            return self.monthly_price * 12 * Decimal('0.8')
        return self.monthly_price
    
    def get_description(self) -> str:
        return f"${self.monthly_price}/month"

class OneTimeProduct(Product):
    price = models.DecimalField(...)
    
    def calculate_price(self) -> Decimal:
        return self.price
    
    def get_description(self) -> str:
        return f"${self.price} one-time"

class UsageBasedProduct(Product):
    base_price = models.DecimalField(...)
    per_unit_price = models.DecimalField(...)
    
    def calculate_price(self) -> Decimal:
        return self.base_price + (self.usage * self.per_unit_price)
```

### 3. Introduce Parameter Object

**Smell:** Functions with many parameters, especially when they're passed together

```python
# Before: Too many parameters
def create_subscription(
    user_id,
    plan_id,
    payment_method_id,
    coupon_code,
    trial_days,
    billing_email,
    billing_address,
    billing_city,
    billing_state,
    billing_zip,
    billing_country,
):
    ...

# After: Grouped into objects
@dataclass
class BillingAddress:
    email: str
    address: str
    city: str
    state: str
    zip_code: str
    country: str

@dataclass
class SubscriptionRequest:
    user_id: int
    plan_id: int
    payment_method_id: str
    coupon_code: str | None = None
    trial_days: int = 0
    billing: BillingAddress | None = None

def create_subscription(request: SubscriptionRequest):
    ...
```

### 4. Replace Magic Values with Constants

**Smell:** Numbers or strings with unclear meaning

```python
# Before: Magic values everywhere
if user.role == 1:  # What is 1?
    ...
if order.status == 'PEND':  # Abbreviation unclear
    ...
if len(password) < 8:  # Why 8?
    ...
if retry_count > 3:  # Why 3?
    ...

# After: Self-documenting constants
class UserRole(models.IntegerChoices):
    GUEST = 0, "Guest"
    MEMBER = 1, "Member"
    ADMIN = 2, "Admin"
    SUPERADMIN = 3, "Super Admin"

class OrderStatus(models.TextChoices):
    PENDING = "pending", "Pending"
    CONFIRMED = "confirmed", "Confirmed"
    SHIPPED = "shipped", "Shipped"
    DELIVERED = "delivered", "Delivered"

# In settings.py or constants.py
MIN_PASSWORD_LENGTH = 8
MAX_RETRY_ATTEMPTS = 3

# Usage is now clear
if user.role == UserRole.MEMBER:
    ...
if order.status == OrderStatus.PENDING:
    ...
if len(password) < MIN_PASSWORD_LENGTH:
    ...
```

### 5. Extract Class

**Smell:** Class doing too many things (low cohesion)

```python
# Before: User class doing everything
class User(models.Model):
    # User fields
    email = models.EmailField()
    name = models.CharField()
    
    # Subscription fields (should be separate)
    subscription_plan = models.CharField()
    subscription_started = models.DateTimeField()
    subscription_expires = models.DateTimeField()
    
    # Notification preferences (should be separate)
    email_notifications = models.BooleanField()
    sms_notifications = models.BooleanField()
    push_notifications = models.BooleanField()
    notification_frequency = models.CharField()
    
    # Billing info (should be separate)
    billing_address = models.TextField()
    payment_method_id = models.CharField()
    
    def send_notification(self, message):
        ...  # 50 lines of notification logic
    
    def charge_subscription(self):
        ...  # 30 lines of billing logic

# After: Separated concerns
class User(models.Model):
    email = models.EmailField()
    name = models.CharField()

class Subscription(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    plan = models.ForeignKey(Plan, on_delete=models.PROTECT)
    started_at = models.DateTimeField()
    expires_at = models.DateTimeField()
    
    def renew(self):
        ...

class NotificationPreferences(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    email_enabled = models.BooleanField(default=True)
    sms_enabled = models.BooleanField(default=False)
    push_enabled = models.BooleanField(default=True)
    frequency = models.CharField(...)

class BillingProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    address = models.TextField()
    payment_method_id = models.CharField()
    
    def charge(self, amount):
        ...
```

### 6. Replace Nested Conditionals with Guard Clauses

**Smell:** Deep nesting that's hard to follow

```python
# Before: Deeply nested
def process_payment(user, amount):
    if user is not None:
        if user.is_active:
            if user.billing_profile is not None:
                if user.billing_profile.payment_method_id:
                    if amount > 0:
                        if amount <= user.spending_limit:
                            # Finally, the actual logic
                            return charge_card(user.billing_profile, amount)
                        else:
                            raise PaymentError("Exceeds spending limit")
                    else:
                        raise PaymentError("Invalid amount")
                else:
                    raise PaymentError("No payment method")
            else:
                raise PaymentError("No billing profile")
        else:
            raise PaymentError("User inactive")
    else:
        raise PaymentError("No user")

# After: Guard clauses (fail fast)
def process_payment(user, amount):
    # Validate preconditions upfront
    if user is None:
        raise PaymentError("No user")
    
    if not user.is_active:
        raise PaymentError("User inactive")
    
    if user.billing_profile is None:
        raise PaymentError("No billing profile")
    
    if not user.billing_profile.payment_method_id:
        raise PaymentError("No payment method")
    
    if amount <= 0:
        raise PaymentError("Invalid amount")
    
    if amount > user.spending_limit:
        raise PaymentError("Exceeds spending limit")
    
    # Happy path is now clear and un-nested
    return charge_card(user.billing_profile, amount)
```

---

## Refactoring Workflow

### Step 1: Ensure Test Coverage

Before touching anything:

```bash
# Check coverage for the area you're refactoring
pytest --cov=apps/subscriptions --cov-report=html
# Open htmlcov/index.html and verify critical paths are covered
```

**If coverage is insufficient, write tests first.** Characterization tests that capture current behavior, even if that behavior is buggy.

### Step 2: Make a Refactoring Plan

```markdown
## Refactoring: Extract SubscriptionService

### Current State
Subscription logic is scattered across views, models, and management commands.

### Target State  
All subscription business logic in SubscriptionService class.

### Steps
1. [ ] Create SubscriptionService with empty methods
2. [ ] Move create logic from view to service
3. [ ] Move cancel logic from view to service
4. [ ] Move renew logic from management command to service
5. [ ] Update views to use service
6. [ ] Update management command to use service
7. [ ] Remove duplicate code from models
8. [ ] Add comprehensive service tests

### Risks
- View tests may break (need to update mocks)
- Management command behavior might differ slightly

### Rollback
Each step is a separate PR. Revert individual PRs if issues arise.
```

### Step 3: Small, Safe Steps

Each commit should:
- Pass all tests
- Be deployable independently
- Be revertable without affecting other changes

```bash
# Good commit sequence
git commit -m "Add empty SubscriptionService class"
git commit -m "Extract create_subscription to service"
git commit -m "Update CreateSubscriptionView to use service"
git commit -m "Remove create logic from view"
```

### Step 4: Verify Behavior Unchanged

After refactoring:
- All existing tests pass
- Manual smoke test of affected features
- Compare logs/metrics before and after (same patterns?)

---

## Prioritization Framework

Not all refactoring is equal. Prioritize by impact:

### High Priority (Do Soon)
| Condition | Why |
|-----------|-----|
| High complexity + High churn | Frequently changed, hard to change safely |
| Security-related code | Risk of introducing vulnerabilities |
| Missing critical tests | Can't safely change anything |
| Blocking new features | Opportunity cost of not fixing |

### Medium Priority (Plan for It)
| Condition | Why |
|-----------|-----|
| Moderate complexity, stable code | Painful but not urgent |
| Inconsistent patterns | Cognitive load for team |
| Outdated dependencies | Security/compatibility risk growing |

### Low Priority (Opportunistic)
| Condition | Why |
|-----------|-----|
| Working code with tests | If it ain't broke... |
| Style-only improvements | Low value, low risk |
| Rarely touched code | Effort exceeds benefit |

### The Refactoring Backlog

Maintain a living document:

```markdown
# Refactoring Backlog

## High Priority
- [ ] #123 Extract PaymentService (complexity: 25, churn: high)
- [ ] #124 Add tests for authentication flow (coverage: 20%)

## Medium Priority  
- [ ] #125 Consolidate user notification methods (3 duplicates)
- [ ] #126 Replace raw SQL queries in reports module

## Low Priority / Opportunistic
- [ ] #127 Rename confusing variable names in legacy module
- [ ] #128 Convert old-style string formatting to f-strings

## Completed
- [x] #120 Extract SubscriptionService (2024-01-15)
- [x] #121 Remove deprecated API endpoints (2024-01-10)
```

---

## Metrics to Track

### Code Health Metrics

Track these monthly:

| Metric | Tool | Target |
|--------|------|--------|
| Cyclomatic complexity (avg) | radon | < 5 |
| Test coverage | pytest-cov | > 80% |
| Duplication | pylint | < 5% |
| Dependency depth | pydeps | < 4 levels |
| Tech debt ratio | SonarQube | < 5% |

### Refactoring Impact

After major refactors, measure:

- **Time to implement features** in refactored area (should decrease)
- **Bug rate** in refactored area (should decrease)  
- **Code review time** (should decrease)
- **Onboarding feedback** ("is this area confusing?")

---

## Common Refactoring Mistakes

| Mistake | Consequence | Prevention |
|---------|-------------|------------|
| Refactoring without tests | Bugs introduced silently | Tests first, always |
| Big bang rewrites | Never ships, loses context | Small incremental steps |
| Refactoring during feature work | Confusing PRs, mixed concerns | Separate PRs |
| Refactoring stable code | Wasted effort, risk for no gain | Focus on high-churn areas |
| Changing behavior "while we're here" | Hidden bugs | Strict behavior preservation |
| Not communicating | Merge conflicts, duplicated work | Announce refactoring plans |

---

## Quality Checklist

Before completing a refactoring:

- [ ] All tests pass (no new test failures)
- [ ] Test coverage maintained or improved
- [ ] No behavior changes (verified by tests + manual check)
- [ ] Code complexity reduced (measured)
- [ ] Changes are in small, reviewable commits
- [ ] Each commit is independently deployable
- [ ] PR description explains the "why" not just the "what"
- [ ] Rollback plan documented