# Python / Django — Language Reference

Loaded by `coder/SKILL.md` when the project is Python or Django.

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Functions | snake_case, verb phrase | `get_user_by_email()`, `validate_subscription()` |
| Classes | PascalCase, noun phrase | `UserSubscription`, `PaymentProcessor` |
| Modules | snake_case | `subscription_service.py` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_RETRY_ATTEMPTS`, `DEFAULT_TIMEOUT_SECONDS` |
| Private | Leading underscore | `_calculate_internal_score()` |
| Booleans | is_, has_, can_, should_ prefix | `is_active`, `has_subscription` |

---

## File Organization

```python
"""
Module docstring explaining purpose and responsibility.
"""

# Standard library
import logging
from datetime import datetime, timedelta
from typing import Optional, List

# Third-party
from django.db import models, transaction
from django.core.exceptions import ValidationError

# Local
from apps.users.models import User
from apps.core.utils import normalize_email

# Constants
MAX_LOGIN_ATTEMPTS = 5
SESSION_TIMEOUT_HOURS = 24

logger = logging.getLogger(__name__)

# Classes and functions below...
```

---

## Type Hints

Always use type hints. They are documentation the linter checks.

```python
from typing import Optional, List
from django.db.models import QuerySet

def get_active_users(
    organization_id: int,
    include_admins: bool = False,
    limit: Optional[int] = None
) -> QuerySet["User"]:
    """
    Retrieve active users for an organization.

    Args:
        organization_id: The organization to query
        include_admins: Whether to include admin users
        limit: Maximum number of users to return (None for all)

    Returns:
        QuerySet of active User objects

    Raises:
        Organization.DoesNotExist: If organization_id is invalid
    """
    queryset = User.objects.filter(
        organization_id=organization_id,
        is_active=True
    )
    if not include_admins:
        queryset = queryset.exclude(role=User.Role.ADMIN)
    if limit is not None:
        queryset = queryset[:limit]
    return queryset
```

---

## Django Patterns

### Models

```python
class Subscription(models.Model):
    class Status(models.TextChoices):
        ACTIVE    = "active",    "Active"
        PAUSED    = "paused",    "Paused"
        CANCELLED = "cancelled", "Cancelled"
        EXPIRED   = "expired",   "Expired"

    # Relationships first
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="subscriptions")
    plan = models.ForeignKey("plans.Plan", on_delete=models.PROTECT, related_name="subscriptions")

    # Fields grouped logically
    status    = models.CharField(max_length=20, choices=Status.choices, default=Status.ACTIVE, db_index=True)
    started_at = models.DateTimeField()
    expires_at = models.DateTimeField(db_index=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)

    # Audit fields last
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "status"]),
            models.Index(fields=["expires_at", "status"]),
        ]

    def __str__(self) -> str:
        return f"{self.user.email} — {self.plan.name} ({self.status})"

    @property
    def is_valid(self) -> bool:
        return self.status == self.Status.ACTIVE and self.expires_at > timezone.now()

    def cancel(self, reason: Optional[str] = None) -> None:
        """Cancel this subscription immediately."""
        self.status = self.Status.CANCELLED
        self.cancelled_at = timezone.now()
        self.save(update_fields=["status", "cancelled_at", "updated_at"])
        subscription_cancelled.send(sender=self.__class__, subscription=self, reason=reason)
```

### Services (Business Logic)

Business logic lives in service classes, not views or models.

```python
# services/subscription_service.py

class SubscriptionService:
    def __init__(self, user: User):
        self.user = user

    def create_subscription(self, plan: Plan, payment_method_id: str) -> Subscription:
        if self.user.has_active_subscription:
            raise SubscriptionError("User already has an active subscription")

        with transaction.atomic():
            payment = PaymentService.charge(
                user=self.user,
                amount=plan.price,
                payment_method_id=payment_method_id,
            )
            subscription = Subscription.objects.create(
                user=self.user,
                plan=plan,
                status=Subscription.Status.ACTIVE,
                started_at=timezone.now(),
                expires_at=timezone.now() + plan.duration,
                initial_payment=payment,
            )

        self._send_welcome_email(subscription)  # outside transaction
        return subscription
```

### Views (Class-Based)

```python
class SubscriptionDetailView(LoginRequiredMixin, View):
    def get(self, request: HttpRequest, subscription_id: int) -> HttpResponse:
        subscription = self._get_subscription_or_404(request.user, subscription_id)
        context = {
            "subscription": subscription,
            "available_plans": Plan.objects.active(),
            "can_cancel": subscription.is_valid,
        }
        return render(request, "subscriptions/detail.html", context)

    def _get_subscription_or_404(self, user: User, subscription_id: int) -> Subscription:
        return get_object_or_404(
            Subscription.objects.select_related("plan"),
            id=subscription_id,
            user=user,
        )
```

---

## Error Handling

Define a hierarchy of specific exceptions per domain:

```python
# exceptions.py
class SubscriptionError(Exception):
    """Base exception for subscription operations."""

class SubscriptionNotFoundError(SubscriptionError):
    pass

class SubscriptionExpiredError(SubscriptionError):
    pass
```

Handle at boundaries; let domain exceptions propagate up to views:

```python
def create_subscription_view(request):
    try:
        subscription = SubscriptionService(request.user).create_subscription(...)
        return JsonResponse({"subscription_id": subscription.id})
    except SubscriptionError as e:
        logger.info("Subscription creation failed: %s", e, extra={"user_id": request.user.id})
        return JsonResponse({"error": str(e)}, status=400)
    except Exception:
        logger.exception("Unexpected error in subscription creation")
        return JsonResponse({"error": "An unexpected error occurred"}, status=500)
```

---

## Testing (pytest + pytest-django)

```python
@pytest.mark.django_db
class TestSubscriptionService:
    def test_create_subscription_happy_path(self, user, plan, mock_payment):
        service = SubscriptionService(user)
        sub = service.create_subscription(plan, payment_method_id="pm_test")
        assert sub.status == Subscription.Status.ACTIVE
        assert sub.user == user

    def test_create_subscription_fails_if_already_subscribed(self, user_with_subscription, plan):
        service = SubscriptionService(user_with_subscription)
        with pytest.raises(SubscriptionError, match="already has an active subscription"):
            service.create_subscription(plan, payment_method_id="pm_test")
```

---

## Python-Specific Quality Checklist

- [ ] All functions have type hints
- [ ] All public functions have docstrings
- [ ] No `print()` statements — use `logging`
- [ ] No bare `except:` — catch specific exceptions
- [ ] Database queries use `select_related`/`prefetch_related` where needed
- [ ] Related database operations wrapped in `transaction.atomic()`
- [ ] No mutable default arguments (`def f(x=[])` is a trap)

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| N+1 queries | Missing `select_related` | Add to queryset definition |
| Silent failures | Bare `except` | Catch specific exceptions, log others |
| Flaky tests | Order-dependent results | Use explicit ordering or sort in assertions |
| Memory issues | Full queryset loaded | Use `.iterator()` or paginate |
| Race conditions | Missing transactions | Wrap in `transaction.atomic()` |
| Mutable default arg bug | `def f(x=[])` | Use `def f(x=None): if x is None: x = []` |
