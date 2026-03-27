# Refactoring Patterns & Scanning Techniques

Reference material for the refactor skill. Loaded when scanning for opportunities or applying specific refactoring patterns.

> **Language note:** Examples and tooling references below are Python-centric for illustration. Adapt patterns and tools to the project's actual stack. The *principles* are universal — the syntax and tool names are not.

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
