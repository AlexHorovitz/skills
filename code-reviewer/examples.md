# Code Review Examples — What to Look For

Reference material for the code-reviewer skill. Loaded when performing detailed line-by-line reviews.

> **Language note:** Examples below are in Python/Django for illustration. Adapt patterns to the project's actual stack. The *concepts* are universal — the syntax is not.

---

## 1. Correctness Bugs

**Off-by-one errors:**
```python
# ❌ Bug: Misses last item
for i in range(len(items) - 1):
    process(items[i])

# ❌ Bug: Index out of bounds
for i in range(len(items) + 1):
    process(items[i])
```

**Null/None handling:**
```python
# ❌ Bug: Crashes if user.subscription is None
def get_plan_name(user):
    return user.subscription.plan.name

# ✓ Ask: What should happen when subscription is None?
def get_plan_name(user):
    if user.subscription is None:
        return "No Plan"
    return user.subscription.plan.name
```

**Race conditions:**
```python
# ❌ Bug: TOCTOU race condition
if not Subscription.objects.filter(user=user, status='active').exists():
    Subscription.objects.create(user=user, status='active')
# Another request could create one between check and create!

# ✓ Fixed: Use database constraint or atomic operation
Subscription.objects.get_or_create(
    user=user,
    status='active',
    defaults={...}
)
```

**Boundary conditions:**
```python
# Questions to ask:
# - What if the list is empty?
# - What if the value is 0? Negative? MAX_INT?
# - What if the string is empty? Very long? Contains Unicode?
# - What if the date is in the past? Far future?
```

## 2. Security Vulnerabilities

**SQL Injection:**
```python
# ❌ CRITICAL: SQL injection
User.objects.raw(f"SELECT * FROM users WHERE email = '{email}'")

# ✓ Safe: Parameterized
User.objects.raw("SELECT * FROM users WHERE email = %s", [email])

# ✓ Better: Use ORM
User.objects.filter(email=email)
```

**Insecure Direct Object Reference (IDOR):**
```python
# ❌ CRITICAL: Any user can access any subscription
@api_view(['GET'])
def get_subscription(request, subscription_id):
    return Subscription.objects.get(id=subscription_id)

# ✓ Safe: Scoped to current user
@api_view(['GET'])
def get_subscription(request, subscription_id):
    return Subscription.objects.get(
        id=subscription_id,
        user=request.user  # Always scope to user
    )
```

**Information disclosure:**
```python
# ❌ Leaks internal information
except Exception as e:
    return JsonResponse({"error": str(e)}, status=500)
    # Could leak: stack traces, SQL queries, file paths

# ✓ Safe: Generic error to user, detailed log internally
except Exception as e:
    logger.exception("Unexpected error in subscription creation")
    return JsonResponse({"error": "An unexpected error occurred"}, status=500)
```

**Mass assignment:**
```python
# ❌ CRITICAL: User can set any field including is_admin
@api_view(['POST'])
def update_profile(request):
    User.objects.filter(id=request.user.id).update(**request.data)

# ✓ Safe: Explicit field list
@api_view(['POST'])
def update_profile(request):
    allowed_fields = ['name', 'email', 'timezone']
    updates = {k: v for k, v in request.data.items() if k in allowed_fields}
    User.objects.filter(id=request.user.id).update(**updates)
```

## 3. Performance Issues

**N+1 queries:**
```python
# ❌ N+1: One query per subscription
subscriptions = Subscription.objects.filter(status='active')
for sub in subscriptions:
    print(sub.user.email)  # Query for each user!
    print(sub.plan.name)   # Query for each plan!

# ✓ Fixed: Eager loading
subscriptions = Subscription.objects.filter(
    status='active'
).select_related('user', 'plan')
```

**Unbounded queries:**
```python
# ❌ Dangerous: Could return millions of rows
def get_all_users():
    return list(User.objects.all())

# ✓ Safe: Always paginate
def get_users(page=1, per_page=100):
    return User.objects.all()[(page-1)*per_page:page*per_page]
```

**Missing indexes:**
```python
# If you see this query pattern frequently:
Subscription.objects.filter(user=user, status='active')

# Ask: Is there an index on (user_id, status)?
# Check the model's Meta.indexes
```

**Expensive operations in loops:**
```python
# ❌ Slow: API call in loop
for user in users:
    stripe.Customer.retrieve(user.stripe_id)  # N API calls!

# ✓ Better: Batch operation or async
customer_ids = [u.stripe_id for u in users]
customers = stripe.Customer.list(ids=customer_ids)  # 1 API call
```

## 4. Maintainability Issues

**Magic numbers:**
```python
# ❌ What does 7 mean?
if (now - user.last_login).days > 7:
    send_reminder()

# ✓ Self-documenting
INACTIVE_REMINDER_DAYS = 7
if (now - user.last_login).days > INACTIVE_REMINDER_DAYS:
    send_reminder()
```

**Complex conditionals:**
```python
# ❌ Hard to understand
if user.is_active and user.subscription and user.subscription.status == 'active' and user.subscription.expires_at > now and not user.is_banned:
    allow_access()

# ✓ Readable
def user_has_valid_access(user: User) -> bool:
    if not user.is_active or user.is_banned:
        return False
    if not user.subscription:
        return False
    return user.subscription.is_valid

if user_has_valid_access(user):
    allow_access()
```

**God functions:**
```python
# ❌ Function doing too many things
def process_order(order):
    # Validate order (20 lines)
    # Calculate pricing (30 lines)
    # Process payment (25 lines)
    # Update inventory (15 lines)
    # Send notifications (20 lines)
    # Generate invoice (25 lines)

# ✓ Single responsibility
def process_order(order):
    validate_order(order)
    pricing = calculate_pricing(order)
    payment = process_payment(order, pricing)
    update_inventory(order)
    send_order_notifications(order, payment)
    return generate_invoice(order, payment)
```

**Poor error messages:**
```python
# ❌ Useless
raise ValueError("Invalid input")

# ✓ Actionable
raise ValueError(
    f"Invalid subscription status '{status}'. "
    f"Expected one of: {', '.join(VALID_STATUSES)}"
)
```

## 5. Testing Gaps

**Missing edge cases:**
```python
# If I see a function like:
def calculate_discount(price, discount_percent):
    return price * (1 - discount_percent / 100)

# I expect tests for:
# - Normal case (price=100, discount=10)
# - Zero discount (discount=0)
# - 100% discount (discount=100)
# - Over 100% discount (discount=150) - should this be allowed?
# - Negative discount (discount=-10) - should this be allowed?
# - Zero price (price=0)
# - Negative price (price=-100) - should this be allowed?
# - Floating point precision (price=19.99, discount=33.33)
```

**Testing implementation, not behavior:**
```python
# ❌ Fragile: Tests implementation details
def test_create_user():
    with patch('app.services.user_service._hash_password') as mock_hash:
        mock_hash.return_value = 'hashed'
        user = create_user('test@example.com', 'password')
        mock_hash.assert_called_once_with('password')

# ✓ Robust: Tests behavior
def test_create_user():
    user = create_user('test@example.com', 'password')
    assert user.email == 'test@example.com'
    assert user.check_password('password') == True
    assert user.check_password('wrong') == False
```

---

## Review Comment Examples

**Be specific:**
```
# ❌ Vague
This doesn't look right.

# ✓ Specific
🟠 MAJOR: This query lacks an index on (user_id, status).
With 1M rows, this will cause full table scans.
Add: `class Meta: indexes = [models.Index(fields=['user', 'status'])]`
```

**Explain why:**
```
# ❌ Just what
Change this to use select_related.

# ✓ Why it matters
🟠 MAJOR: This causes N+1 queries - one query per subscription to fetch the user.
With 100 subscriptions, that's 101 queries instead of 1.
Use `Subscription.objects.select_related('user')` to eager load.
```

**Provide solutions:**
```
# ❌ Just the problem
This is vulnerable to race conditions.

# ✓ Problem + solution
🔴 BLOCKER: Race condition - two concurrent requests could both pass the
existence check and create duplicate subscriptions.

Fix with atomic operation:
```python
subscription, created = Subscription.objects.get_or_create(
    user=user,
    status='active',
    defaults={'plan': plan, 'started_at': now()}
)
if not created:
    raise SubscriptionError("Already has active subscription")
```
```
