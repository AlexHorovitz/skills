## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Headless Architecture Guide

Headless systems have no UI. This covers backend APIs, microservices, data pipelines, worker processes, CLIs, and any server-side component consumed by other systems rather than directly by humans. The defining characteristics: correctness is paramount, failure modes must be explicit, and observability is not optional.

---

## What Is "Headless"?

This guide applies to:
- **REST / GraphQL / gRPC APIs** — consumed by web frontends, mobile apps, or other services
- **Background workers** — queue consumers, scheduled jobs, data processing pipelines
- **CLI tools** — developer tools, deployment scripts, data migration utilities
- **Internal services** — microservices, service mesh components, event-driven consumers
- **Webhooks / event handlers** — inbound HTTP from third-party systems (Stripe, GitHub, Twilio)

---

## Architecture Decision: Monolith vs Services

Make this decision explicitly and early. The default is almost always a monolith.

| Architecture | When to Choose |
|---|---|
| **Modular Monolith (default)** | Single team, early stage, unclear service boundaries, < ~20 engineers |
| **Microservices** | Different scaling requirements per component, multiple autonomous teams, proven bounded contexts |
| **Serverless (Functions)** | Event-driven workloads, highly variable traffic, ops burden is a primary constraint |

**The monolith-first rule:** Start with a well-structured modular monolith. Extract services when you have a specific, proven scaling or organizational reason. Premature decomposition into microservices is the single most common architectural mistake in backend systems.

A well-structured monolith with clear module boundaries is extractable to services later. A premature microservice architecture is nearly impossible to consolidate.

---

## The 12-Factor App

Every headless service must satisfy the 12-factor principles. Non-negotiable.

| Factor | What It Means | Common Violation |
|---|---|---|
| **1. Codebase** | One repo per deployable service | Monorepo with shared mutable state across services |
| **2. Dependencies** | Explicitly declared, never system-global | Assuming a library exists in the environment |
| **3. Config** | Stored in environment, not code | Hardcoded URLs, credentials, or flags in source |
| **4. Backing services** | Treated as attached resources, swappable | Hardcoded DB hostnames, region-specific paths |
| **5. Build, release, run** | Strictly separate stages | Building assets at runtime |
| **6. Processes** | Stateless, share-nothing | Storing session state in process memory |
| **7. Port binding** | Services self-contained, export via port | Requiring a specific web server installed |
| **8. Concurrency** | Scale out via process model | Vertical scaling only, threading complexity |
| **9. Disposability** | Fast startup, graceful shutdown | Long startup time, unhandled SIGTERM |
| **10. Dev/prod parity** | Keep environments as similar as possible | "Works on my machine" |
| **11. Logs** | Treat as event streams, never manage log files | Writing to a local log file inside the container |
| **12. Admin processes** | Run as one-off processes | Embedding migrations in the app startup path |

---

## Service Structure

```
service-name/
├── cmd/                     — Entry points
│   ├── server/              — HTTP server main
│   ├── worker/              — Queue consumer main
│   └── migrate/             — Database migration runner (separate binary)
│
├── internal/                — Not importable by other services
│   ├── domain/              — Business logic, domain models, interfaces
│   │   ├── model/
│   │   ├── service/         — Business operations
│   │   └── repository/      — Interfaces only (no implementations)
│   │
│   ├── handler/             — HTTP handlers (thin: validate → call service → respond)
│   │   ├── middleware/      — Auth, logging, rate limiting, request ID injection
│   │   └── response/        — Shared response helpers
│   │
│   ├── repository/          — Database implementations of domain interfaces
│   ├── queue/               — Queue consumer/producer implementations
│   └── config/              — Config loading from environment
│
├── pkg/                     — Importable by other services (shared types, clients)
│
├── migrations/              — SQL migration files (numbered, never modified after merge)
│
├── Dockerfile
├── docker-compose.yml       — Local development stack
└── .env.example             — Documents all required environment variables
```

**Language:** Use what your team knows. Python, Go, TypeScript/Node, Ruby, Java/Kotlin, Rust — all are valid. The patterns in this guide apply across languages.

---

## API Design

### REST (Default)

Follow the resource-oriented REST design from the web guide. Key additions for headless APIs:

**Authentication:**
- API keys for server-to-server communication (not JWTs — simpler and auditable)
- OAuth 2.0 / OIDC for user-delegated access
- JWT bearer tokens for client-facing APIs with short expiry

**Idempotency:**
State-changing requests (POST, PATCH, DELETE) must be idempotent or support idempotency keys:

```
POST /v1/payments
Idempotency-Key: client-generated-uuid

# Server: if this key has been seen, return the previous response. Don't charge twice.
```

Required for: payment processing, email sending, any operation where duplicate execution has consequences.

**Pagination:** Always. No unbounded list responses. Default page size ≤ 100. Cursor pagination for high-volume feeds.

**Rate limiting:** Always. Return `429 Too Many Requests` with `Retry-After` header. Apply per API key, per IP, per user — based on the sensitivity of the endpoint.

### GraphQL

Use GraphQL when:
- Client data requirements vary significantly across consumers
- Multiple clients (web, mobile, third-party) with different field needs
- You want a single typed schema as the contract

Do not use GraphQL to avoid designing a good REST API.

GraphQL-specific rules:
- Depth-limit all queries to prevent abuse (max depth 10)
- Cost analysis / rate limiting on query complexity, not just request count
- Never expose root-level mutations without authentication
- Persisted queries for production clients (prevents arbitrary query injection)

### gRPC

Use gRPC for:
- Service-to-service communication in polyglot environments
- High-throughput, low-latency internal APIs
- Streaming use cases (server-push, bidirectional)

gRPC is not appropriate as a public-facing API (poor browser support without gRPC-Web proxy).

---

## Data Layer

### Database Design for Headless Services

Apply the same data modeling rules as web apps, plus:

**Connection pooling is mandatory.** Every service that talks to a database uses a connection pool. Opening a new connection per request kills your database under load.

```
# PostgreSQL connection pool sizing
pool_size = (num_cpu_cores * 2) + effective_spindle_count
# For most cloud VMs: 10–20 connections per service instance
# Set pool_max_overflow to handle spikes (20–50% above pool_size)
```

**Read replicas.** For read-heavy workloads, route reads to replicas. Use the primary only for writes. Implement this at the repository layer so it's transparent to the service layer.

**Database per service (for microservices).** If you have true microservices, each owns its database. Services do not query each other's databases. Data shared between services is exposed via API, not via direct DB access.

### Migrations

- Migrations are versioned, numbered, and immutable after merge
- Run migrations as a separate pre-deploy step, not in app startup
- All schema changes must be backwards-compatible with the previous app version (blue/green and rolling deploys require this)
- Safe migration order for removing a column: (1) stop using it in code + deploy, (2) add migration to drop column + deploy

```
# Safe migration sequence for adding a NOT NULL column:
Step 1: Add column as nullable                    → deploy
Step 2: Backfill all existing rows               → deploy
Step 3: Add NOT NULL constraint                  → deploy
```

---

## Asynchronous Processing

Move slow, unreliable, or retryable work out of the request path.

### When to Use a Queue

| Work Type | Sync (Request Path) | Async (Queue) |
|---|---|---|
| Read data and return it | ✅ | |
| Write user data, immediate confirmation | ✅ | |
| Send email | | ✅ |
| Send push notification | | ✅ |
| Process payment | ✅ (then queue for reconciliation) | |
| Generate a report | | ✅ |
| Call a slow third-party API | | ✅ |
| Process an uploaded file | | ✅ |
| Fan-out to multiple services | | ✅ |

### Queue Design Rules

**Idempotency.** Every job handler must be safe to run twice. The queue may deliver a message more than once (at-least-once delivery is the standard guarantee).

**Poison pill handling.** Jobs that consistently fail must not block the queue. Use a dead letter queue (DLQ) with alerting.

**Retry strategy.** Exponential backoff with jitter. Never retry immediately at full rate.

```
Attempt 1: immediate
Attempt 2: 30 seconds
Attempt 3: 5 minutes
Attempt 4: 30 minutes
Attempt 5: 2 hours
→ Move to DLQ
```

**Job timeout.** Every job has a maximum runtime. A job that hangs indefinitely must be forcibly terminated and retried.

---

## Observability: The Non-Negotiable Triad

A headless service that isn't observable is not production-ready.

### 1. Structured Logging

Every log line is a JSON object. No raw string logs in production.

```json
{
  "timestamp": "2026-03-25T14:32:01.123Z",
  "level": "error",
  "service": "payment-service",
  "version": "1.4.2",
  "request_id": "req_abc123",
  "user_id": "usr_xyz789",
  "message": "Payment charge failed",
  "stripe_error": "card_declined",
  "amount_cents": 2999,
  "duration_ms": 342
}
```

Rules:
- Include `request_id` on every log line in a request's scope
- Never log credentials, tokens, PII, or card numbers
- Log at the right level: `DEBUG` for dev noise, `INFO` for expected operations, `WARN` for recoverable anomalies, `ERROR` for failures requiring attention

### 2. Metrics

Expose a metrics endpoint (`/metrics` in Prometheus format or push to a metrics service). Minimum metric set:

| Metric | Type | Labels |
|---|---|---|
| `http_requests_total` | Counter | `method`, `path`, `status_code` |
| `http_request_duration_seconds` | Histogram | `method`, `path` |
| `http_requests_in_flight` | Gauge | |
| `queue_jobs_processed_total` | Counter | `queue`, `status` |
| `queue_job_duration_seconds` | Histogram | `queue` |
| `db_query_duration_seconds` | Histogram | `query_name` |
| `cache_hit_total` / `cache_miss_total` | Counter | |

### 3. Distributed Tracing

Use OpenTelemetry (vendor-neutral). Propagate trace context across service boundaries via `traceparent` header. Every outbound HTTP call and database query should be a span.

Tracing is mandatory for any system with more than one service. Without it, debugging cross-service failures is guesswork.

### Alerting Thresholds (Minimum)

| Signal | Alert When |
|---|---|
| HTTP 5xx error rate | > 1% over 5 minutes |
| HTTP p99 latency | > 2× baseline over 5 minutes |
| Queue depth | > N pending jobs (tune per queue) |
| DLQ message count | > 0 (any failure worth investigating) |
| Database connection pool exhaustion | > 80% utilized |
| Disk space | > 80% used |

---

## Security

### Authentication & Authorization

- **API keys**: Generate cryptographically random, store hashed (never plaintext), support rotation
- **JWT validation**: Always verify signature with the public key. Never trust the payload without verification. Check `exp`, `iss`, `aud`.
- **OAuth 2.0**: Use a proven library. Never implement the protocol yourself.
- **Authorization**: Check permissions at the service layer, not just the route layer. Defense in depth.

### Input Validation

Every input is untrusted. Validate at the boundary (handler layer) before it reaches business logic.

```
Max string lengths enforced
Numeric ranges checked
Enum values validated against whitelist
UUIDs validated as valid UUIDs
Dates validated as parseable dates
File uploads: MIME type, size, extension validated server-side
```

### Secrets Management

| Where | How |
|---|---|
| Local development | `.env` file (never committed), `.env.example` committed |
| CI/CD | CI environment variables or secrets manager integration |
| Production | AWS Secrets Manager, GCP Secret Manager, Vault, or platform-native secrets |

**Rules:**
- Secrets rotate. Build rotation support into every secret consumer from day one.
- Audit log every secret access in production.
- Never hardcode a secret. Never log a secret. Never return a secret in an API response.

---

## Deployment

### Container-First

Every headless service ships as a Docker container. The `Dockerfile` is part of the service, not an afterthought.

```dockerfile
# Multi-stage build — keep the final image minimal
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY . .

# Non-root user
RUN useradd --no-create-home appuser
USER appuser

EXPOSE 8000
CMD ["gunicorn", "app:create_app()", "--bind", "0.0.0.0:8000", "--workers", "4"]
```

**Rules:**
- Non-root user inside the container
- No secrets in the image (inject at runtime via environment)
- Health check endpoint: `GET /health` returns `200 OK` when ready to serve traffic
- Graceful shutdown: handle `SIGTERM` — drain in-flight requests before exiting (30-second grace period)

### Health Endpoints

```
GET /health      — liveness: is the process alive?
GET /ready       — readiness: can it serve traffic? (checks DB, cache connections)
```

Use both in Kubernetes. Liveness restarts stuck processes. Readiness gates traffic during startup and when dependencies are unavailable.

---

## Architecture Decisions for Headless Services

Decisions to make explicitly before building:

1. **Monolith vs services**: default monolith — what is the specific reason to split?
2. **API style**: REST vs GraphQL vs gRPC — based on consumers and usage pattern
3. **Auth strategy**: API keys, JWT, OAuth 2.0 — based on who the clients are
4. **Database**: PostgreSQL (default), MySQL, or specialized (time-series, graph, document) — what does your query pattern require?
5. **Queue technology**: Redis (Sidekiq, BullMQ, Celery), RabbitMQ, SQS, Kafka — start with Redis unless you need Kafka's guarantees
6. **Deployment target**: containers on VMs (ECS, Cloud Run, Railway), Kubernetes, serverless (Lambda)
7. **Observability stack**: where do logs, metrics, and traces go? (Datadog, Grafana Cloud, OpenTelemetry Collector)
8. **Multi-tenancy**: row-level tenant isolation, schema-per-tenant, or service-per-tenant

---

## Walking Skeleton for Headless Services

Day 1 must include:

1. Service containerized and deployed to production environment (even returning `{"status": "ok"}`)
2. Health endpoints (`/health`, `/ready`) responding correctly
3. Database provisioned, connected, and one migration applied
4. Structured logging with `request_id` propagation on every request
5. Error tracking (Sentry or equivalent) capturing unhandled exceptions
6. One authenticated endpoint working end-to-end
7. CI/CD: push to main → container built, tests run, deployed to staging automatically
8. `.env.example` documenting every required environment variable
9. Basic alerting wired: 5xx error rate and p99 latency monitored
