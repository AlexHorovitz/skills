# Web Application Architecture Guide

World-class web applications are fast, resilient, and deployable at any moment. This guide covers the architecture of full-stack browser-based applications: frontend UI, backend API, database, and the glue between them.

---

## Platform Decision: Rendering Strategy First

Before choosing a framework, decide the rendering model. This drives everything else.

| Strategy | When to Use | Examples |
|---|---|---|
| **SSR (Server-Side Rendering)** | SEO matters, content is dynamic, auth-gated content | Next.js, Nuxt, SvelteKit |
| **SSG (Static Site Generation)** | Content changes infrequently, maximum performance | Astro, Next.js static export |
| **SPA (Single Page App)** | Authenticated app, SEO not needed, rich interactivity | React + Vite, Vue + Vite |
| **MPA (Multi-Page App / Server-rendered)** | Forms-heavy, progressive enhancement, no JS required | Django templates, Rails, Laravel |
| **Hybrid** | Marketing pages SSG, app pages SSR/SPA | Next.js App Router |

**Default choice for most apps:** Next.js (App Router) or a backend-rendered MPA with a thin JS layer. SPAs are often chosen by default when they shouldn't be.

---

## Stack Defaults

Choose boring. Deviate only with a written justification.

### Frontend

| Concern | Default | Only Reach For Alternative When |
|---|---|---|
| UI framework | React (with Next.js) | Specific reason (existing team expertise, bundle size, etc.) |
| Styling | Tailwind CSS | Team has strong preference for CSS Modules or styled-components |
| State management | React context + `useReducer` or Zustand | Global state is complex and cross-cutting |
| Data fetching | TanStack Query (React Query) | SWR for simpler apps; raw `fetch` + `useEffect` is almost never right |
| Forms | React Hook Form + Zod | Simple forms can use controlled inputs |
| Type safety | TypeScript — always, no exceptions | None |

### Backend

| Concern | Default | Notes |
|---|---|---|
| Language | Match team expertise: Python, TypeScript (Node), Go, Ruby | No wrong answer here — pick what the team knows |
| API style | REST with JSON | GraphQL only when the client has highly variable data needs |
| Auth | Sessions (cookie-based) for web; JWT for APIs consumed by non-browser clients | Don't roll your own auth. Use a library. |
| Database | PostgreSQL | MySQL acceptable. MongoDB only for document-store use cases, not general apps. |
| Cache | Redis | For sessions, rate limiting, expensive query results |
| Background jobs | Language-appropriate queue (Celery, BullMQ, Sidekiq, etc.) | Never do slow work in a request handler |
| Search | PostgreSQL full-text search → Typesense → Elasticsearch | Use the simplest thing that works. Elasticsearch is rarely needed. |

### Infrastructure

| Concern | Default |
|---|---|
| Hosting | Railway, Render, or Fly.io for early stage; AWS/GCP/Azure when you need control |
| CDN | Cloudflare (always — even for small apps) |
| File storage | S3 or compatible (Cloudflare R2 for cost) |
| Email | Resend or Postmark (transactional), not your own SMTP |
| Monitoring | Sentry (errors) + Datadog or Grafana (metrics) |

---

## Application Layers

Every web application has the same layers. Name them consistently.

```
┌────────────────────────────────────────────────┐
│                  Client (Browser)               │
│         UI Components / Pages / Routes          │
└──────────────────────┬─────────────────────────┘
                       │ HTTP / WebSocket
┌──────────────────────▼─────────────────────────┐
│                  API Layer                       │
│        Route handlers / Controllers             │
│     (validate input, call service, return)      │
└──────────────────────┬─────────────────────────┘
                       │
┌──────────────────────▼─────────────────────────┐
│               Service / Domain Layer            │
│    Business logic, transactions, side effects   │
└──────────┬──────────────────────────┬──────────┘
           │                          │
┌──────────▼──────┐          ┌────────▼──────────┐
│  Data Access    │          │  External Services  │
│  (ORM / query)  │          │  (email, payments,  │
│                 │          │   storage, etc.)    │
└──────────┬──────┘          └────────────────────┘
           │
┌──────────▼──────┐
│   PostgreSQL    │   Redis    Queue
└─────────────────┘
```

**Rules:**
- Route handlers contain zero business logic. They validate, call a service, and return.
- Services contain all business logic. They are testable without HTTP.
- Data access lives in repositories or a query layer — not scattered across services.
- External services (Stripe, SendGrid, S3) are always behind an interface/adapter. Never call them directly from a service.

---

## Data Modeling

### The Base Entity Pattern

Every persistent entity needs audit fields:

```
id          — surrogate primary key (bigint auto-increment or UUID)
created_at  — immutable, set on insert
updated_at  — updated on every write
```

Add soft delete (`deleted_at`) only when you have a genuine requirement to recover deleted records. It complicates every query. Default to hard deletes.

### Naming Conventions

- Tables: `snake_case`, plural nouns (`users`, `subscription_plans`)
- Foreign keys: `{entity}_id` (`user_id`, `plan_id`)
- Boolean columns: `is_` or `has_` prefix (`is_active`, `has_verified_email`)
- Timestamps: `_at` suffix (`created_at`, `cancelled_at`)
- Status columns: use an enum, not an integer code

### Index Strategy

Add indexes for:
1. Every foreign key column (your ORM may not do this automatically)
2. Every column that appears in a `WHERE` clause in a frequent query
3. Every column used for sorting on a list endpoint
4. Composite indexes when you always filter on two columns together

Do not add indexes speculatively. Every index slows writes. Add them when you know the query.

### Schema Migration Rules

- Migrations must be backwards-compatible: never rename or drop a column in a single migration
- Order: Add new column (nullable) → deploy → backfill data → deploy → add constraint → deploy → remove old column → deploy
- Never run DDL (schema changes) and DML (data changes) in the same migration in production
- Test migrations against a production-size dataset before deploying

---

## API Design

### REST Resource Structure

```
GET    /api/v1/resources              — list (paginated)
POST   /api/v1/resources              — create
GET    /api/v1/resources/:id          — get one
PATCH  /api/v1/resources/:id          — partial update
DELETE /api/v1/resources/:id          — delete
POST   /api/v1/resources/:id/action   — non-CRUD action (e.g. /cancel, /publish)
```

Use `PATCH` for updates, not `PUT`. `PUT` requires sending the full resource; `PATCH` sends only changed fields.

### Standard Response Envelope

```json
// Success (single)
{
  "data": { ... },
  "meta": { "request_id": "req_abc123" }
}

// Success (list)
{
  "data": [ ... ],
  "meta": {
    "total": 150,
    "page": 1,
    "per_page": 20,
    "total_pages": 8,
    "request_id": "req_abc123"
  }
}

// Error
{
  "error": {
    "code": "validation_error",
    "message": "Invalid input",
    "details": [
      { "field": "email", "message": "Must be a valid email address" }
    ]
  },
  "meta": { "request_id": "req_abc123" }
}
```

Always return `request_id`. It makes debugging in production tractable.

### Versioning

- Version in the URL path: `/api/v1/`, `/api/v2/`
- Maintain v1 until all clients have migrated. Never silently break it.
- Do not version in headers — it's harder to test and debug.

### Pagination

- **Offset pagination** (`?page=2&per_page=20`): Use for admin panels, small datasets, any UI with page numbers.
- **Cursor pagination** (`?cursor=<opaque_token>&limit=50`): Use for feeds, infinite scroll, and any dataset that changes while the user is paginating.

Never return an unpaginated list endpoint. Set a hard max (`per_page` capped at 100).

---

## Authentication & Authorization

### Web Sessions (Default for Browser Clients)

- Store session ID in an `HttpOnly`, `Secure`, `SameSite=Lax` cookie
- Use a server-side session store (Redis or DB) — not client-side JWTs for session state
- Rotate session ID on login (prevents session fixation)
- Invalidate all sessions on password change

### JWTs (for API Clients / Mobile)

- Access token: short-lived (15 min). Refresh token: long-lived (30 days), stored `HttpOnly` cookie or secure storage.
- Never store JWTs in `localStorage` for sensitive apps (XSS risk)
- Always verify signature server-side. Never trust the payload without verification.
- Include `iat`, `exp`, `sub` (user id), `jti` (unique token id for revocation)

### Authorization Pattern

Separate authentication (who are you?) from authorization (what can you do?):

```
Request → Auth Middleware (validates identity) → Route Handler →
  → Permission Check (can this user do this action on this resource?) →
  → Service
```

Use a consistent pattern: `can_user_do(user, action, resource)`. Never scatter `if user.role == "admin"` checks through business logic.

---

## Frontend Architecture

### Component Structure

```
src/
├── app/                  — pages / routes (Next.js App Router or file-based routing)
├── components/
│   ├── ui/               — generic, reusable UI (Button, Input, Modal)
│   └── features/         — feature-specific composed components (UserCard, CheckoutForm)
├── hooks/                — custom React hooks
├── lib/                  — utilities, constants, type definitions
├── services/             — API client functions (one file per resource)
└── stores/               — global state (Zustand or Context)
```

### State Management Tiers

| State Type | Where It Lives | Example |
|---|---|---|
| Server state | TanStack Query | User profile, list of items |
| URL state | Search params | Filters, pagination, selected tab |
| Local UI state | `useState` | Modal open/closed, input focus |
| Global app state | Zustand / Context | Auth user, theme, feature flags |

The most common mistake: putting server state in a global store. Use TanStack Query for anything that comes from an API.

### Error Boundaries

Every page-level route needs an error boundary. Users must never see an unhandled React error in production — show a useful fallback with a way to recover (retry, go home).

---

## Performance

### Core Web Vitals Targets

| Metric | Target |
|---|---|
| LCP (Largest Contentful Paint) | < 2.5s |
| INP (Interaction to Next Paint) | < 200ms |
| CLS (Cumulative Layout Shift) | < 0.1 |

### Checklist

- [ ] Images: use `<img>` with `width`/`height` set, or `next/image`. Never serve unoptimized originals.
- [ ] Fonts: use `font-display: swap`. Preload critical fonts.
- [ ] JS bundle: code-split at the route level. Lazy-load heavy components.
- [ ] Critical CSS: inline above-the-fold CSS. Load the rest async.
- [ ] API responses: cache aggressively where data doesn't change per-user. Use `stale-while-revalidate`.
- [ ] Database: run `EXPLAIN ANALYZE` on every slow query. N+1 queries kill web apps.
- [ ] CDN: all static assets (JS, CSS, images) served from CDN edge, not origin.

---

## Security Checklist

- [ ] HTTPS everywhere, HSTS enabled
- [ ] CSP headers set (restrict script sources)
- [ ] All user input validated server-side (client validation is UX, not security)
- [ ] SQL: use parameterized queries / ORM. Never interpolate user input into SQL.
- [ ] XSS: never render raw user HTML. Sanitize if you must.
- [ ] CSRF: validate CSRF token on all state-changing requests (or use `SameSite=Strict` cookies)
- [ ] Secrets in environment variables, never in source code
- [ ] Dependencies audited (`npm audit`, `pip-audit`) in CI
- [ ] Rate limiting on auth endpoints (login, password reset, registration)
- [ ] Sensitive data (passwords, tokens) never logged

---

## Feature Flags

Use feature flags for any work that takes more than one session. Never leave incomplete work visible in production.

```
is_enabled("new_checkout", user) → bool
```

Flag lifecycle:
1. Add flag (default off) → commit to main
2. Build feature behind flag
3. Enable for internal team
4. Enable for beta users
5. Enable for 100%
6. Remove flag and dead code (this step is mandatory — flag debt compounds fast)

---

## Architecture Decisions for Web Apps

Decisions that must be made explicitly before building:

1. **Rendering strategy**: SSR / SSG / SPA / MPA — see top of this guide
2. **Auth strategy**: session cookies vs JWT, provider (auth library, Auth.js, Clerk, etc.)
3. **API style**: REST vs GraphQL vs tRPC — default REST
4. **Real-time needs**: polling vs WebSocket vs SSE — default polling unless latency matters
5. **File uploads**: direct-to-S3 (presigned URLs) vs server-proxied — default direct-to-S3
6. **Multi-tenancy**: row-level (tenant_id column) vs schema-per-tenant vs database-per-tenant
7. **Search**: full-text in DB vs dedicated search service
8. **Background job queue**: which technology, retry strategy, dead letter queue

---

## Walking Skeleton for Web Apps

Your Day 1 skeleton must include:

1. Frontend deployed to a real URL (even if it just renders a title)
2. Backend API deployed and reachable from the frontend
3. Database provisioned and migrated
4. CI/CD pipeline: push to main → deploy to staging automatically
5. One authenticated route working end-to-end (login → see something real → logout)
6. Error tracking (Sentry) wired up in both frontend and backend
7. Domain + SSL configured

If you don't have all seven on Day 1, that is what you build first.
