## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# Django — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses Django.

For pure Python patterns (naming, type hints, dataclasses, error handling), see `coder/languages/python.md`.
For universal web architecture (API design, auth strategy, performance), see `architect/web/GUIDE.md`.

---

## When to Choose Django

Django is the right tool when you need a **batteries-included server-rendered application** and want to ship fast without assembling a framework from parts.

**Choose Django when:**

- The project needs an admin interface on Day 1 (Django admin is unmatched for internal tools)
- Rapid prototyping — models, migrations, admin, and auth in an afternoon
- Multi-page applications with server-rendered HTML and progressive enhancement
- REST APIs backed by relational data (with Django REST Framework)
- Content management, editorial workflows, or anything with complex CRUD
- The team knows Python and values convention over configuration

**Do NOT choose Django when:**

- You need async-first with WebSockets as a primary transport (use FastAPI or Channels as a bolt-on, not the core)
- The application is a pure microservice with no database (use FastAPI or Flask)
- You need sub-millisecond latency on every request (use Go or Rust)
- The frontend is a standalone SPA that only consumes a JSON API and you want maximum flexibility (consider FastAPI for a leaner contract)

Django's ORM, migration system, and admin panel are its competitive advantages. If you are not using at least two of those three, you are paying the framework tax for nothing.

---

## Project Structure

Organize by **domain**, not by layer. Each Django app owns one bounded context.

```
myproject/
├── manage.py
├── config/                      # Project-level settings (renamed from myproject/)
│   ├── __init__.py
│   ├── settings/
│   │   ├── __init__.py          # Imports from base, detects environment
│   │   ├── base.py              # Shared settings (INSTALLED_APPS, MIDDLEWARE, etc.)
│   │   ├── local.py             # DJANGO_SETTINGS_MODULE=config.settings.local
│   │   ├── staging.py
│   │   └── production.py
│   ├── urls.py                  # Root URL conf — only includes, never patterns
│   ├── wsgi.py
│   └── asgi.py
├── apps/
│   ├── users/                   # Custom user model, profiles, auth
│   │   ├── models.py
│   │   ├── services.py          # Business logic
│   │   ├── selectors.py         # Read-only queries (optional, for complex reads)
│   │   ├── admin.py
│   │   ├── urls.py
│   │   ├── views.py             # Thin — validate, delegate, respond
│   │   ├── serializers.py       # DRF serializers (API mode)
│   │   ├── templates/users/     # Templates (MPA mode)
│   │   ├── tests/
│   │   │   ├── __init__.py
│   │   │   ├── test_models.py
│   │   │   ├── test_services.py
│   │   │   └── test_views.py
│   │   ├── factories.py         # factory_boy factories
│   │   └── migrations/
│   ├── subscriptions/           # Plans, subscriptions, billing events
│   │   ├── models.py
│   │   ├── services.py
│   │   ├── admin.py
│   │   ├── urls.py
│   │   ├── views.py
│   │   ├── serializers.py
│   │   ├── tests/
│   │   ├── factories.py
│   │   └── migrations/
│   └── core/                    # Shared utilities, base models, middleware
│       ├── models.py            # TimeStampedModel, SoftDeleteModel
│       ├── middleware.py
│       ├── permissions.py
│       └── exceptions.py
├── templates/                   # Project-level templates (base.html, 404.html)
├── static/                      # Project-level static files
├── requirements/
│   ├── base.txt
│   ├── local.txt                # -r base.txt + debug-toolbar, factory-boy, etc.
│   └── production.txt           # -r base.txt + gunicorn, sentry-sdk, etc.
├── Dockerfile
├── docker-compose.yml
├── pytest.ini                   # or pyproject.toml [tool.pytest.ini_options]
└── .env.example
```

**Rules:**
- The `config/` directory replaces the Django default of naming it after your project. Cleaner imports: `config.settings`, `config.urls`.
- Each app under `apps/` is self-contained. An app should never import models from a sibling app's `models.py` directly — go through services or use the model via `get_user_model()`.
- `services.py` holds all business logic. Views call services. Services call the ORM. This is non-negotiable.
- `selectors.py` is optional — use it when read queries become complex enough to warrant their own module.

---

## Routing

The root `urls.py` is a table of contents. It includes app URLs and nothing else.

```python
# config/urls.py
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/users/", include("apps.users.urls", namespace="users")),
    path("api/v1/subscriptions/", include("apps.subscriptions.urls", namespace="subscriptions")),
]
```

```python
# apps/subscriptions/urls.py
from django.urls import path
from . import views

app_name = "subscriptions"

urlpatterns = [
    path("", views.SubscriptionListView.as_view(), name="list"),
    path("<int:pk>/", views.SubscriptionDetailView.as_view(), name="detail"),
    path("<int:pk>/cancel/", views.CancelSubscriptionView.as_view(), name="cancel"),
    path("plans/", views.PlanListView.as_view(), name="plan-list"),
]
```

**Conventions:**
- Always set `app_name` and use `namespace` in `include()`. Reverse URLs as `subscriptions:detail`.
- Use `path()` with typed converters (`<int:pk>`, `<slug:slug>`, `<uuid:id>`). Never use bare `<pk>` without a type.
- Non-CRUD actions get their own endpoint: `/cancel/`, `/pause/`, `/renew/`. Do not overload `PATCH`.
- Version the API in the URL path (`/api/v1/`). When v2 arrives, v1 keeps working.

---

## Data Layer

### Models

Field ordering convention: **relationships first, domain fields, then audit fields.**

```python
# apps/subscriptions/models.py
from django.conf import settings
from django.db import models
from apps.core.models import TimeStampedModel


class Plan(TimeStampedModel):
    """A subscription plan that users can subscribe to."""

    class Interval(models.TextChoices):
        MONTHLY = "monthly", "Monthly"
        YEARLY = "yearly", "Yearly"

    name = models.CharField(max_length=100, unique=True)
    slug = models.SlugField(unique=True)
    interval = models.CharField(max_length=10, choices=Interval.choices)
    price_cents = models.PositiveIntegerField()
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["price_cents"]

    def __str__(self) -> str:
        return f"{self.name} ({self.get_interval_display()})"


class Subscription(TimeStampedModel):
    """A user's subscription to a plan."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        CANCELLED = "cancelled", "Cancelled"
        EXPIRED = "expired", "Expired"

    # --- Relationships first ---
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="subscriptions",
    )
    plan = models.ForeignKey(
        Plan,
        on_delete=models.PROTECT,
        related_name="subscriptions",
    )

    # --- Domain fields ---
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.ACTIVE,
        db_index=True,
    )
    started_at = models.DateTimeField()
    expires_at = models.DateTimeField()
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancellation_reason = models.TextField(blank=True, default="")

    # --- Audit fields inherited from TimeStampedModel ---

    class Meta:
        ordering = ["-started_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["user"],
                condition=models.Q(status="active"),
                name="one_active_subscription_per_user",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "status"]),
            models.Index(fields=["expires_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.user} — {self.plan.name} ({self.status})"
```

```python
# apps/core/models.py
from django.db import models


class TimeStampedModel(models.Model):
    """Abstract base with created_at / updated_at audit fields."""

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True
```

**Model rules:**
- Always use `settings.AUTH_USER_MODEL`, never import the User model directly in a ForeignKey.
- `on_delete` is required and must be an explicit choice: `CASCADE` for owned data, `PROTECT` for reference data, `SET_NULL` for optional references.
- Store money as integer cents. Never use `DecimalField` or `FloatField` for money unless you have a currency library enforcing precision.
- Every model gets a `__str__`. The admin is unusable without it.
- Use `TextChoices` / `IntegerChoices` for all status and type fields. Never store raw strings.
- Declare constraints and indexes in `Meta`. The database enforces your invariants, not your application code.

### Custom Managers and QuerySets

Push reusable query logic into custom QuerySets. Chain them like Django built-ins.

```python
class SubscriptionQuerySet(models.QuerySet):
    def active(self):
        return self.filter(status=Subscription.Status.ACTIVE)

    def expiring_soon(self, days: int = 7):
        from django.utils import timezone
        cutoff = timezone.now() + timezone.timedelta(days=days)
        return self.active().filter(expires_at__lte=cutoff)

    def for_user(self, user):
        return self.filter(user=user)


class Subscription(TimeStampedModel):
    # ... fields ...
    objects = SubscriptionQuerySet.as_manager()
```

Usage: `Subscription.objects.active().expiring_soon(days=3)` — reads like English.

### N+1 Prevention

Every view that touches related objects must use `select_related` (foreign keys) or `prefetch_related` (reverse FKs, M2M).

```python
# BAD — N+1: one query per subscription to fetch plan and user
subscriptions = Subscription.objects.all()

# GOOD — 1 query with JOINs
subscriptions = Subscription.objects.select_related("user", "plan").all()
```

Add `django-debug-toolbar` in local settings. If you see more than 10 queries on a page, you have an N+1.

### Migration Discipline

- One migration per logical change. Do not squash during active development.
- Name migrations descriptively: `python manage.py makemigrations --name add_cancellation_reason_to_subscription`.
- Never edit a migration that has been applied to staging or production. Create a new one.
- Data migrations (`RunPython`) go in their own migration file, separate from schema changes.
- Run `python manage.py showmigrations` in CI to catch unapplied migrations.

---

## Middleware

Django middleware runs on every request/response. Keep the pipeline short.

```python
# config/settings/base.py
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",       # Static files
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "apps.core.middleware.RequestIDMiddleware",          # Custom — add last
]
```

### Custom Middleware Pattern

```python
# apps/core/middleware.py
import uuid
import logging

logger = logging.getLogger(__name__)


class RequestIDMiddleware:
    """Attach a unique request ID to every request for tracing."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request.request_id = request.headers.get(
            "X-Request-ID", str(uuid.uuid4())
        )
        response = self.get_response(request)
        response["X-Request-ID"] = request.request_id
        return response
```

**Rules:**
- Middleware is for cross-cutting concerns only: logging, request IDs, security headers, rate limiting.
- Never put business logic in middleware. If your middleware checks subscription status, it belongs in a permission class or a decorator.
- Order matters. Auth middleware must come after session middleware. Your custom middleware goes last unless it must wrap everything.

---

## Authentication

### Custom User Model (Non-Negotiable)

Always define a custom user model before the first migration. Retrofitting is painful.

```python
# apps/users/models.py
from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """Custom user model. Extend this, never extend AbstractBaseUser unless
    you genuinely need to remove username/email fields."""

    email = models.EmailField(unique=True)

    # Use email as the login field
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["username"]

    class Meta:
        ordering = ["-date_joined"]

    def __str__(self) -> str:
        return self.email
```

```python
# config/settings/base.py
AUTH_USER_MODEL = "users.User"
```

### Permissions and Groups

Use Django's built-in permission framework. Define custom permissions on models:

```python
class Subscription(TimeStampedModel):
    # ... fields ...

    class Meta:
        permissions = [
            ("can_cancel_subscription", "Can cancel any user's subscription"),
            ("can_extend_subscription", "Can extend subscription expiry"),
        ]
```

For DRF, map permissions to permission classes:

```python
# apps/core/permissions.py
from rest_framework.permissions import BasePermission


class IsSubscriptionOwner(BasePermission):
    """Only the subscription owner or staff can access."""

    def has_object_permission(self, request, view, obj):
        return obj.user == request.user or request.user.is_staff
```

**Rules:**
- Never check `user.is_staff` or `user.role` inline in views. Use permission classes.
- Create Groups in a data migration, not in fixtures or manual admin clicks.
- For complex authorization (row-level, multi-tenant), use `django-guardian` or `django-rules`.

---

## Template / Serializer Patterns

### API Mode: DRF Serializers

Serializers are the contract between your API and the outside world. Keep them honest.

```python
# apps/subscriptions/serializers.py
from rest_framework import serializers
from .models import Subscription, Plan


class PlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = Plan
        fields = ["id", "name", "slug", "interval", "price_cents", "is_active"]
        read_only_fields = ["id"]


class SubscriptionSerializer(serializers.ModelSerializer):
    plan = PlanSerializer(read_only=True)
    plan_id = serializers.PrimaryKeyRelatedField(
        queryset=Plan.objects.filter(is_active=True),
        source="plan",
        write_only=True,
    )

    class Meta:
        model = Subscription
        fields = [
            "id", "user", "plan", "plan_id", "status",
            "started_at", "expires_at", "cancelled_at", "created_at",
        ]
        read_only_fields = ["id", "user", "status", "started_at", "expires_at", "cancelled_at", "created_at"]


class CancelSubscriptionSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, max_length=1000)
```

**Rules:**
- Use `ModelSerializer` for CRUD. Use plain `Serializer` for actions (cancel, pause).
- Always declare `read_only_fields`. Never trust the client to not send fields you did not expect.
- Nested serializers are read-only by default. Accept `plan_id` (write) and return `plan` (read).
- Serializer validation (`validate_*`, `validate`) is for field-level and cross-field checks. Business rule validation stays in services.

### MPA Mode: Template Inheritance

```
templates/
├── base.html              <!-- DOCTYPE, <head>, nav, footer, {% block content %} -->
├── subscriptions/
│   ├── list.html          <!-- {% extends "base.html" %} -->
│   └── detail.html
```

Keep templates dumb. No business logic in templates. If you need an `{% if %}` longer than one line, the view should have computed the value.

---

## API Patterns

### Django REST Framework: ViewSets and Routers

```python
# apps/subscriptions/views.py
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.core.permissions import IsSubscriptionOwner
from .models import Subscription
from .serializers import SubscriptionSerializer, CancelSubscriptionSerializer
from .services import SubscriptionService


class SubscriptionViewSet(viewsets.ModelViewSet):
    """
    Thin viewset. Validates input, delegates to service, returns response.
    """
    serializer_class = SubscriptionSerializer
    permission_classes = [IsAuthenticated, IsSubscriptionOwner]

    def get_queryset(self):
        return (
            Subscription.objects
            .filter(user=self.request.user)
            .select_related("plan")
        )

    def perform_create(self, serializer):
        SubscriptionService.create_subscription(
            user=self.request.user,
            plan=serializer.validated_data["plan"],
        )

    @action(detail=True, methods=["post"], url_path="cancel")
    def cancel(self, request, pk=None):
        subscription = self.get_object()
        cancel_serializer = CancelSubscriptionSerializer(data=request.data)
        cancel_serializer.is_valid(raise_exception=True)

        SubscriptionService.cancel_subscription(
            subscription=subscription,
            reason=cancel_serializer.validated_data.get("reason", ""),
        )
        return Response(
            SubscriptionSerializer(subscription.refresh_from_db() or subscription).data,
            status=status.HTTP_200_OK,
        )
```

```python
# apps/subscriptions/urls.py (router version)
from rest_framework.routers import DefaultRouter
from . import views

router = DefaultRouter()
router.register("", views.SubscriptionViewSet, basename="subscription")

urlpatterns = router.urls
```

### Pagination

Set it globally, override per-view when needed:

```python
# config/settings/base.py
REST_FRAMEWORK = {
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 20,
    "DEFAULT_FILTER_BACKENDS": [
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.OrderingFilter",
        "rest_framework.filters.SearchFilter",
    ],
}
```

### Filtering

Use `django-filter` for declarative filtering:

```python
# apps/subscriptions/filters.py
import django_filters
from .models import Subscription


class SubscriptionFilter(django_filters.FilterSet):
    status = django_filters.ChoiceFilter(choices=Subscription.Status.choices)
    expires_before = django_filters.DateTimeFilter(field_name="expires_at", lookup_expr="lte")

    class Meta:
        model = Subscription
        fields = ["status", "plan"]
```

---

## Services Pattern

This is the heart of the architecture. Business logic lives here, not in views, not in models, not in serializers.

```python
# apps/subscriptions/services.py
import logging
from django.db import transaction
from django.utils import timezone

from .models import Subscription, Plan
from .exceptions import (
    SubscriptionError,
    ActiveSubscriptionExistsError,
    SubscriptionNotCancellableError,
)

logger = logging.getLogger(__name__)


class SubscriptionService:
    """
    All subscription business logic. Stateless — every method is a classmethod
    or a standalone function. No __init__, no instance state.
    """

    @staticmethod
    @transaction.atomic
    def create_subscription(user, plan: Plan) -> Subscription:
        if Subscription.objects.filter(user=user, status=Subscription.Status.ACTIVE).exists():
            raise ActiveSubscriptionExistsError("User already has an active subscription.")

        subscription = Subscription.objects.create(
            user=user,
            plan=plan,
            status=Subscription.Status.ACTIVE,
            started_at=timezone.now(),
            expires_at=_calculate_expiry(plan),
        )

        logger.info(
            "Subscription created",
            extra={"user_id": user.id, "plan_id": plan.id, "subscription_id": subscription.id},
        )
        return subscription

    @staticmethod
    @transaction.atomic
    def cancel_subscription(subscription: Subscription, reason: str = "") -> Subscription:
        if subscription.status != Subscription.Status.ACTIVE:
            raise SubscriptionNotCancellableError(
                f"Cannot cancel subscription in '{subscription.status}' status."
            )

        subscription.status = Subscription.Status.CANCELLED
        subscription.cancelled_at = timezone.now()
        subscription.cancellation_reason = reason
        subscription.save(update_fields=["status", "cancelled_at", "cancellation_reason", "updated_at"])

        logger.info(
            "Subscription cancelled",
            extra={"subscription_id": subscription.id, "reason": reason},
        )
        return subscription

    @staticmethod
    def renew_subscription(subscription: Subscription) -> Subscription:
        if subscription.status != Subscription.Status.ACTIVE:
            raise SubscriptionError("Can only renew an active subscription.")

        subscription.expires_at = _calculate_expiry(subscription.plan)
        subscription.save(update_fields=["expires_at", "updated_at"])
        return subscription


def _calculate_expiry(plan: Plan):
    from dateutil.relativedelta import relativedelta

    now = timezone.now()
    if plan.interval == Plan.Interval.MONTHLY:
        return now + relativedelta(months=1)
    elif plan.interval == Plan.Interval.YEARLY:
        return now + relativedelta(years=1)
    raise ValueError(f"Unknown interval: {plan.interval}")
```

**Service rules:**
- Services are stateless. Use `@staticmethod` or module-level functions. No `self` state.
- Wrap write operations in `@transaction.atomic`. If any step fails, the whole operation rolls back.
- Always use `save(update_fields=[...])`. Never call bare `.save()` on an existing object — it overwrites every column and hides race conditions.
- Log business events with structured `extra` data, not f-strings.
- Raise domain-specific exceptions. Let DRF exception handlers convert them to HTTP responses.

---

## Testing Strategy

Use `pytest-django` and `factory_boy`. No `unittest.TestCase`, no Django's `TestCase` (it swallows too much).

```python
# apps/subscriptions/factories.py
import factory
from django.utils import timezone
from apps.users.factories import UserFactory
from .models import Subscription, Plan


class PlanFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Plan

    name = factory.Sequence(lambda n: f"Plan {n}")
    slug = factory.LazyAttribute(lambda obj: obj.name.lower().replace(" ", "-"))
    interval = Plan.Interval.MONTHLY
    price_cents = 999
    is_active = True


class SubscriptionFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Subscription

    user = factory.SubFactory(UserFactory)
    plan = factory.SubFactory(PlanFactory)
    status = Subscription.Status.ACTIVE
    started_at = factory.LazyFunction(timezone.now)
    expires_at = factory.LazyFunction(
        lambda: timezone.now() + timezone.timedelta(days=30)
    )
```

```python
# apps/subscriptions/tests/test_services.py
import pytest
from apps.subscriptions.factories import SubscriptionFactory, PlanFactory
from apps.subscriptions.services import SubscriptionService
from apps.subscriptions.exceptions import (
    ActiveSubscriptionExistsError,
    SubscriptionNotCancellableError,
)
from apps.users.factories import UserFactory


@pytest.mark.django_db
class TestCreateSubscription:
    def test_creates_active_subscription(self):
        user = UserFactory()
        plan = PlanFactory(interval="monthly", price_cents=1999)

        subscription = SubscriptionService.create_subscription(user=user, plan=plan)

        assert subscription.status == "active"
        assert subscription.user == user
        assert subscription.plan == plan
        assert subscription.expires_at > subscription.started_at

    def test_rejects_duplicate_active_subscription(self):
        subscription = SubscriptionFactory(status="active")

        with pytest.raises(ActiveSubscriptionExistsError, match="already has an active"):
            SubscriptionService.create_subscription(
                user=subscription.user,
                plan=PlanFactory(),
            )


@pytest.mark.django_db
class TestCancelSubscription:
    def test_cancels_active_subscription(self):
        subscription = SubscriptionFactory(status="active")

        result = SubscriptionService.cancel_subscription(
            subscription=subscription,
            reason="Too expensive",
        )

        assert result.status == "cancelled"
        assert result.cancelled_at is not None
        assert result.cancellation_reason == "Too expensive"

    def test_cannot_cancel_already_cancelled(self):
        subscription = SubscriptionFactory(status="cancelled")

        with pytest.raises(SubscriptionNotCancellableError):
            SubscriptionService.cancel_subscription(subscription=subscription)
```

```ini
# pytest.ini
[pytest]
DJANGO_SETTINGS_MODULE = config.settings.local
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = --reuse-db --no-migrations -q
```

**Testing rules:**
- `@pytest.mark.django_db` on every test class or function that touches the database. No exceptions.
- Use `factory_boy` for all test data. Never create objects with raw `Model.objects.create()` in tests — factories handle defaults and relationships.
- Test services directly, not through views. Service tests are fast and stable. View tests are for integration only.
- `--reuse-db` keeps the test database between runs. `--no-migrations` uses `syncdb` for speed. Drop both flags in CI.
- Never mock the ORM. If your test needs a database, use the database. Mock external services (Stripe, email), not your own code.

---

## Deployment (Walking Skeleton)

Your Day 1 Django deployment checklist:

1. **gunicorn + nginx/Caddy** — `gunicorn config.wsgi:application --workers 3 --bind 0.0.0.0:8000`. Never run `runserver` in production.
2. **collectstatic in build** — `python manage.py collectstatic --noinput` runs in your Dockerfile or CI, not at startup. Serve with WhiteNoise or nginx.
3. **Environment-based settings** — `DJANGO_SETTINGS_MODULE=config.settings.production`. Secrets in env vars, never in code.
4. **Database migrations in deploy** — Run `python manage.py migrate` as a release command (Heroku) or init container (Kubernetes), not in the web process.
5. **Docker image** — Multi-stage build. Pin the Python version. Copy only what you need.
6. **Health check endpoint** — `/api/health/` returns 200 and checks DB connectivity. Load balancers need this.
7. **Sentry + structured logging** — `sentry-sdk[django]` in production requirements. Configure `LOGGING` to output JSON in production.

```dockerfile
# Dockerfile
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

FROM base AS deps
COPY requirements/production.txt .
RUN pip install --no-cache-dir -r production.txt

FROM deps AS app
COPY . .
RUN python manage.py collectstatic --noinput

EXPOSE 8000
CMD ["gunicorn", "config.wsgi:application", "--workers", "3", "--bind", "0.0.0.0:8000"]
```

---

## Django-Specific Quality Checklist

- [ ] Custom user model defined before first migration (`AUTH_USER_MODEL` set)
- [ ] No business logic in views — views call services, services call the ORM
- [ ] `select_related` / `prefetch_related` used on every queryset that accesses related objects
- [ ] `save(update_fields=[...])` used on all partial updates (never bare `.save()`)
- [ ] All write operations wrapped in `@transaction.atomic`
- [ ] Migrations are backwards-compatible (no column renames or drops in a single step)
- [ ] `DEBUG = False` in production settings, `ALLOWED_HOSTS` is explicit
- [ ] `SECRET_KEY` loaded from environment variable, not hardcoded
- [ ] Admin site is registered for all models with meaningful `list_display`, `search_fields`, and `list_filter`
- [ ] No raw SQL unless the ORM genuinely cannot express the query (and it is parameterized)

---

## Common Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| Pages slow, hundreds of queries | N+1 queries — accessing related objects without prefetching | Add `select_related()` / `prefetch_related()` to the queryset. Use `django-debug-toolbar` to count queries. |
| Views are 500+ lines, untestable | Fat views — business logic in request handlers | Extract to `services.py`. Views validate input, call service, return response. |
| Circular import at startup | App A imports model from App B which imports from App A | Use string references in ForeignKey (`"users.User"`), move shared types to `core`, or import inside functions. |
| Data corruption on concurrent writes | Missing transactions or bare `.save()` overwriting fields | Wrap in `@transaction.atomic`, use `save(update_fields=[...])`, use `F()` expressions for counters. |
| Migration conflicts on every PR | Multiple developers adding migrations to the same app | Rebase and `makemigrations --merge`. Use CI check: `python manage.py makemigrations --check --dry-run`. |
| Tests are slow (minutes for a small suite) | Every test rebuilds the database and runs migrations | Use `pytest-django` with `--reuse-db`. Use factories instead of fixtures. Avoid `TransactionTestCase` unless testing transaction behavior. |
| Settings leak between environments | Single `settings.py` with `if DEBUG` conditionals | Split into `settings/base.py`, `local.py`, `production.py`. No conditionals — each file is authoritative for its environment. |
| Admin site is useless | Models registered with no customization | Add `list_display`, `search_fields`, `list_filter`, `readonly_fields`. The admin should be a useful internal tool, not a raw table dump. |
