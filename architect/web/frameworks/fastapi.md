## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# FastAPI — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses FastAPI.

FastAPI is async-first Python built on Starlette and Pydantic. It is not batteries-included — you assemble the pieces yourself, and this guide tells you which pieces to pick.

---

## When to Choose FastAPI

**Choose it when:** async API services, microservices, ML model serving, high-throughput backends with many concurrent connections, or any Python API where you want automatic OpenAPI docs from type hints.

**Do not choose it when:** you need admin panel, ORM, auth, and forms out of the box (use **Django**), server-rendered HTML as the primary UI (use **Django** or **Flask**), or a batteries-included monolith. FastAPI is for teams that want control over every layer.

---

## Project Structure

Organize by domain, not by technical role. Each feature module owns its router, service, repository, models, and schemas.

```
subscription-api/
├── app/
│   ├── main.py                 — App factory, lifespan, middleware
│   ├── config.py               — pydantic-settings (reads env vars)
│   ├── database.py             — Async engine, session factory, Base
│   ├── dependencies.py         — Shared deps (get_db, get_current_user)
│   ├── subscriptions/          — Feature module
│   │   ├── router.py           — Path operations (thin)
│   │   ├── service.py          — Business logic (no HTTP awareness)
│   │   ├── repository.py       — Database queries (async SQLAlchemy)
│   │   ├── models.py           — SQLAlchemy ORM models
│   │   └── schemas.py          — Pydantic request/response models
│   ├── payments/
│   │   ├── router.py / service.py / repository.py / models.py / schemas.py
│   │   └── stripe_client.py    — External service adapter
│   ├── auth/
│   │   ├── router.py / service.py / schemas.py
│   │   └── security.py         — Token creation, password hashing
│   └── shared/
│       ├── middleware.py        — Request ID, timing, error handling
│       └── exceptions.py       — Domain exceptions → HTTP mapping
├── migrations/                  — Alembic
├── tests/conftest.py            — Fixtures, dependency overrides
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

**Rules:** No cross-module imports of models or repositories — communicate through services. `main.py` wires routers, middleware, and lifespan only. Feature-specific dependencies live in their module.

---

## Routing

Routers are thin. Validate input (Pydantic does this automatically), call a service, return. No business logic in routers.

```python
# app/subscriptions/router.py
router = APIRouter(prefix="/api/v1/subscriptions", tags=["subscriptions"])

@router.post("/", status_code=201, response_model=schemas.SubscriptionOut)
async def create_subscription(
    payload: schemas.SubscriptionCreate, db=Depends(get_db), current_user=Depends(get_current_user),
):
    return await service.create_subscription(db, user=current_user, data=payload)

@router.get("/{subscription_id}", response_model=schemas.SubscriptionOut)
async def get_subscription(
    subscription_id: int, db=Depends(get_db), current_user=Depends(get_current_user),
):
    return await service.get_subscription(db, subscription_id=subscription_id, user=current_user)

@router.post("/{subscription_id}/cancel", response_model=schemas.SubscriptionOut)
async def cancel_subscription(
    subscription_id: int, db=Depends(get_db), current_user=Depends(get_current_user),
):
    return await service.cancel_subscription(db, subscription_id=subscription_id, user=current_user)
```

Wire routers in `main.py` with `app.include_router(router)`. Use `tags` for OpenAPI grouping. Use `prefix` on the router, not individual paths.

---

## Data Layer

### SQLAlchemy 2.0 with Async Sessions

Async sessions are non-negotiable. Sync ORM calls in an async framework block the event loop.

```python
# app/database.py — engine + session factory
engine = create_async_engine(settings.database_url, pool_size=20, max_overflow=10, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

# app/dependencies.py — session dependency with commit/rollback
async def get_db() -> AsyncGenerator[AsyncSession]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

### Pydantic Models for Validation

Pydantic schemas are the API contract. SQLAlchemy models are the database schema. Separate. Never return ORM objects from endpoints.

```python
# app/subscriptions/schemas.py
class SubscriptionCreate(BaseModel):
    plan_tier: PlanTier           # PlanTier is a str Enum: free, pro, enterprise
    payment_method_id: str

class SubscriptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    user_id: int
    plan_tier: PlanTier
    is_active: bool
    current_period_end: datetime
    cancelled_at: datetime | None
    created_at: datetime
```

### Repository Pattern

Repositories encapsulate all database queries. Services never construct SQL directly.

```python
# app/subscriptions/repository.py
async def get_by_id(db: AsyncSession, subscription_id: int) -> Subscription | None:
    result = await db.execute(select(Subscription).where(Subscription.id == subscription_id))
    return result.scalar_one_or_none()
```

---

## Middleware

FastAPI middleware is Starlette middleware. Register in the app factory. Order matters — first added is outermost.

```python
# CORS — explicit origins, never ["*"] in production
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
    allow_credentials=True, allow_methods=["GET", "POST", "PATCH", "DELETE"], allow_headers=["*"])

# Request lifecycle
class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response
```

Add `RequestIdMiddleware` before `TimingMiddleware` so timing logs include the request ID. Use `structlog` with JSON output — every log line gets `request_id`, method, path, status, and duration.

---

## Authentication

OAuth2 with password bearer. Auth is a dependency — never check it inside business logic.

```python
# app/dependencies.py
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

async def get_current_user(token: str = Depends(oauth2_scheme), db=Depends(get_db)) -> User:
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        user_id = int(payload["sub"])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Invalid token")
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user
```

Every protected route declares `current_user=Depends(get_current_user)`. The chain handles extraction, validation, and lookup. Token creation lives in `auth/security.py` using `python-jose` + `passlib[bcrypt]`. If auth fails, the request never reaches the handler.

---

## API Patterns

### Pydantic Request/Response Models

Every endpoint has explicit models for input and output. No raw dicts. No ORM objects in responses.

```python
# app/payments/schemas.py
class PaymentIntentCreate(BaseModel):
    subscription_id: int
    amount_cents: int = Field(gt=0, description="Amount in cents")
    currency: str = Field(default="usd", pattern="^[a-z]{3}$")

class PaymentIntentOut(BaseModel):
    model_config = {"from_attributes": True}
    id: int
    subscription_id: int
    amount_cents: int
    currency: str
    stripe_payment_intent_id: str
    status: str
    created_at: datetime
```

### Dependency Injection for Services

Use `Depends` for everything a handler needs. This makes testing trivial — override any dependency.

```python
# app/payments/router.py
def get_stripe_client() -> StripeClient:
    return StripeClient()

@router.post("/intents", status_code=201, response_model=schemas.PaymentIntentOut)
async def create_payment_intent(
    payload: schemas.PaymentIntentCreate,
    background_tasks: BackgroundTasks,
    db=Depends(get_db), current_user=Depends(get_current_user), stripe=Depends(get_stripe_client),
):
    intent = await service.create_payment_intent(db, user=current_user, data=payload, stripe=stripe)
    background_tasks.add_task(service.send_payment_receipt, user=current_user, intent=intent)
    return intent
```

### Background Tasks

`BackgroundTasks` is for fire-and-forget work (receipts, analytics). For anything that must retry or survive a restart, use a real queue (Celery, ARQ).

---

## Testing Strategy

`pytest` + `httpx.AsyncClient`. Integration tests through HTTP. Unit tests on services directly.

```python
# tests/conftest.py — key fixtures
@pytest.fixture
async def client(db_session, fake_user):
    app.dependency_overrides[get_db] = lambda: db_session
    app.dependency_overrides[get_current_user] = lambda: fake_user
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

# tests/subscriptions/test_router.py
@pytest.mark.anyio
async def test_create_subscription(client: AsyncClient):
    resp = await client.post("/api/v1/subscriptions/", json={"plan_tier": "pro", "payment_method_id": "pm_test_123"})
    assert resp.status_code == 201
    assert resp.json()["plan_tier"] == "pro"
    assert resp.json()["is_active"] is True
```

**Rules:** `dependency_overrides` swaps DB, auth, and external services — FastAPI's killer testing feature. Never hit real external services; override the Stripe dependency with a fake. Use `pytest-anyio` for async support. Test services directly for edge cases, test through HTTP for integration confidence.

---

## Deployment (Walking Skeleton)

All seven before writing business logic:

1. **Uvicorn running.** `uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4`. Never `--reload` in production.
2. **Dockerfile built.** Multi-stage, non-root user, `EXPOSE 8000`.
3. **Health endpoint.** `GET /health` returns `{"status": "ok"}`. `GET /ready` runs `SELECT 1` against the database.
4. **Database connected.** PostgreSQL provisioned, async engine configured, Alembic initialized with one migration.
5. **CI/CD pipeline.** Push to main runs tests, builds container, deploys to staging.
6. **Structured logging.** `structlog` with JSON output. Every line includes `request_id`.
7. **Error tracking.** Sentry SDK initialized. Unhandled exceptions captured automatically.

If any are missing, that is what you build next.

---

## FastAPI-Specific Quality Checklist

- [ ] Every endpoint has explicit Pydantic `response_model` — no untyped dict returns
- [ ] Every request body uses a Pydantic model with field constraints (`Field(gt=0)`, `Field(max_length=255)`)
- [ ] All database sessions are async — no sync SQLAlchemy in an async app
- [ ] Dependencies that open resources use `yield` and clean up in `finally`
- [ ] `expire_on_commit=False` on the session factory — prevents `DetachedInstanceError`
- [ ] External services (Stripe, email, S3) behind adapter classes injected via `Depends`
- [ ] Services raise domain exceptions (`SubscriptionNotFound`), not `HTTPException` — exception handlers do the mapping
- [ ] `lifespan` context manager disposes engine and cleans up connection pools on shutdown
- [ ] Alembic migrations run as a separate deploy step, never on app startup
- [ ] OpenAPI schema reviewed — auto-generated docs are your API contract, treat them as a deliverable

---

## Common Failure Modes

| Failure | What Goes Wrong | Prevention |
|---|---|---|
| **Sync in async context** | `time.sleep()` or sync ORM in `async def` blocks the event loop for all requests | Async SQLAlchemy, `httpx.AsyncClient`, `asyncio.sleep()`. Use `run_in_executor` for unavoidable sync. |
| **Missing dependency cleanup** | `Depends` without `yield` + cleanup leaks connections until pool exhaustion | `try/yield/finally` or `async with` in every resource-managing dependency. |
| **Pydantic v1/v2 confusion** | `.dict()` vs `.model_dump()`, `orm_mode` vs `from_attributes`, stale imports | Pin v2. Use `ConfigDict(from_attributes=True)`. Grep for `.dict()` and `orm_mode`. |
| **N+1 queries (async ORM)** | Lazy loads raise errors in async SQLAlchemy; devs blanket-apply `lazy="selectin"` | Set `lazy="raise"` as default. Use `selectinload()`/`joinedload()` explicitly per query. |
| **No response_model** | Untyped returns leak internal fields (password hashes, IDs), break OpenAPI docs | Always set `response_model`. Let Pydantic filter outbound data. |
| **Silent background task failure** | `BackgroundTasks` swallows exceptions. Failed receipts vanish. | Log all errors in task functions. Use a real queue for must-succeed work. |
| **Oversized request bodies** | No default body size limit. Malicious POST can exhaust memory. | `--limit-request-body` in uvicorn or middleware rejecting bodies > 10 MB. |
| **Shared mutable state** | Module-level variables work with one worker, break with four. | State in DB or Redis. Never module globals for request-scoped data. |
