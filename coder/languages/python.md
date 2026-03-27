## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# Python — Language Reference

Loaded by `coder/SKILL.md` when the project is Python.

For Django-specific patterns (models, views, DRF), see `architect/web/frameworks/django.md`.
For FastAPI-specific patterns (Pydantic, async endpoints), see `architect/web/frameworks/fastapi.md`.

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
from pathlib import Path
from typing import Optional

# Third-party
import httpx

# Local
from myapp.users.models import User
from myapp.core.utils import normalize_email

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

## Dataclasses and Domain Models

Use dataclasses for data transfer objects and domain models. Prefer frozen for immutability.

```python
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum


class SubscriptionStatus(StrEnum):
    ACTIVE = "active"
    PAUSED = "paused"
    CANCELLED = "cancelled"
    EXPIRED = "expired"


@dataclass(frozen=True)
class Subscription:
    id: int
    user_id: int
    plan_name: str
    status: SubscriptionStatus
    started_at: datetime
    expires_at: datetime
    cancelled_at: datetime | None = None

    @property
    def is_valid(self) -> bool:
        return self.status == SubscriptionStatus.ACTIVE and self.expires_at > datetime.now()
```

### Service Pattern

Business logic lives in service classes, not in API handlers or data access code.

```python
class SubscriptionService:
    def __init__(self, repository: SubscriptionRepository):
        self._repo = repository

    def create_subscription(self, user_id: int, plan: Plan) -> Subscription:
        existing = self._repo.get_active_for_user(user_id)
        if existing is not None:
            raise SubscriptionError("User already has an active subscription")

        subscription = Subscription(
            id=0,
            user_id=user_id,
            plan_name=plan.name,
            status=SubscriptionStatus.ACTIVE,
            started_at=datetime.now(),
            expires_at=datetime.now() + plan.duration,
        )
        return self._repo.save(subscription)
```

### Context Managers

Use context managers for resource lifecycle management.

```python
from contextlib import contextmanager

@contextmanager
def database_transaction(conn: Connection):
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
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
- [ ] No mutable default arguments (`def f(x=[])` is a trap)
- [ ] Dataclasses used for data transfer objects
- [ ] `pathlib.Path` used instead of `os.path` string manipulation
- [ ] Context managers used for resource lifecycle

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Silent failures | Bare `except` | Catch specific exceptions, log others |
| Flaky tests | Order-dependent results | Use explicit ordering or sort in assertions |
| Memory issues | Large collection loaded | Use generators or itertools |
| Mutable default arg bug | `def f(x=[])` | Use `def f(x: list | None = None)` |
| Import cycle | Circular module dependencies | Move shared types to a separate module |
| Type errors at runtime | Missing type hints | Enable mypy strict mode in CI |
