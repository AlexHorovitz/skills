<!-- License: See /LICENSE -->


# Next.js (App Router) — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses Next.js.

Covers Next.js 14+ with App Router. Pages Router is legacy — do not start new projects on it.

---

## When to Choose Next.js

**Choose it when:** SSR/SSG hybrid needed, SEO matters for public pages, team knows React, you want one deployable for frontend + API + server logic.

**Do not choose it when:** purely a backend API (use FastAPI/Rails), simple static site (use Astro), team does not know React, primary feature is real-time WebSocket-heavy UI (SPA + dedicated server is simpler).

---

## Project Structure

```
my-app/
├── app/                            — Routes, layouts, pages only
│   ├── layout.tsx                  — Root layout (html, body, providers)
│   ├── page.tsx                    — / (home)
│   ├── loading.tsx                 — Root Suspense fallback
│   ├── error.tsx                   — Root error boundary
│   ├── not-found.tsx               — 404
│   ├── (marketing)/                — Route group: public pages
│   │   ├── layout.tsx              — Marketing header + footer
│   │   ├── pricing/page.tsx        — /pricing
│   │   └── about/page.tsx          — /about
│   ├── (app)/                      — Route group: authenticated shell
│   │   ├── layout.tsx              — Sidebar + auth guard
│   │   ├── dashboard/page.tsx      — /dashboard
│   │   └── settings/billing/page.tsx
│   └── api/
│       ├── webhooks/stripe/route.ts
│       └── health/route.ts
├── components/
│   ├── ui/                         — Generic (Button, Input, Modal)
│   └── features/                   — Domain-specific (PricingTable, SubscriptionCard)
├── lib/                            — Utilities, constants, Zod schemas
├── services/                       — External adapters (Stripe, email, S3)
├── data/                           — DB client, queries, repositories
├── actions/                        — Server Actions grouped by domain
├── middleware.ts                    — Edge middleware
└── drizzle.config.ts               — ORM config
```

**Rules:** `app/` contains only route files — no components. Business logic lives in `data/` and `actions/`. Every file in `services/` wraps an external dependency. Never call Stripe or S3 directly from a Server Action.

---

## Routing

**File-based routes:** `app/pricing/page.tsx` maps to `/pricing`. Dynamic: `app/blog/[slug]/page.tsx`. Catch-all: `app/docs/[...path]/page.tsx`.

**Route groups:** Parenthesized folders (`(marketing)`, `(app)`) apply different layouts without affecting URLs.

**Layouts** persist across navigation and do not re-render when children change:

```tsx
// app/(app)/layout.tsx — auth guard + app shell
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await getSession();
  if (!session) redirect("/login");
  return (
    <div className="flex min-h-screen">
      <Sidebar user={session.user} />
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}
```

**Parallel routes:** Use `@slot` folders for independently loading sections (e.g., `@revenue/page.tsx` and `@subscribers/page.tsx` in a dashboard layout).

**Intercepting routes:** Use `(.)` prefix for modal-over-list patterns — click opens modal, direct URL loads full page.

---

## Data Layer

**Server Components fetch data directly** — no `useEffect`, no loading spinners:

```tsx
// app/(app)/settings/billing/page.tsx
export default async function BillingPage() {
  const session = await getSession();
  const subscription = await getSubscription(session.user.id);
  return <SubscriptionDetails subscription={subscription} />;
}
```

**TanStack Query for client-side mutations** — optimistic updates, polling, infinite scroll. Pass server-fetched `initialData` to avoid loading flashes. Do not use it for initial page loads.

**ORM: Drizzle (default).** Thin SQL wrapper, edge-compatible, schema-as-TypeScript-code. Use Prisma only in existing Prisma codebases.

```ts
// data/subscriptions.ts
export async function cancelSubscription(subscriptionId: string) {
  return db.update(subscriptions)
    .set({ status: "canceled", canceledAt: new Date() })
    .where(eq(subscriptions.id, subscriptionId))
    .returning();
}
```

### Server Actions vs Route Handlers

| Caller is... | Use |
|---|---|
| Your own Next.js UI (forms, buttons) | Server Actions |
| External webhook (Stripe, etc.) | Route Handlers |
| Mobile app or third-party API consumer | Route Handlers |
| File upload with progress | Route Handlers |

**Decision rule:** your frontend calls Server Actions. Everything else calls Route Handlers.

---

## Middleware

Runs at the edge before every matched request. Define `config.matcher` to exclude static assets.

```ts
// middleware.ts
export function middleware(request: NextRequest) {
  const token = request.cookies.get("session-token")?.value;
  const isProtected = request.nextUrl.pathname.startsWith("/dashboard") ||
    request.nextUrl.pathname.startsWith("/settings");
  if (isProtected && !token) return NextResponse.redirect(new URL("/login", request.url));
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
```

**Use for:** auth redirects, geo/locale detection, A/B test rewrites. **Not for:** data fetching, complex auth validation, anything needing full Node.js runtime.

---

## Authentication

Auth.js (NextAuth v5) is the default. Do not roll your own session management.

```ts
// lib/auth.ts
export const { handlers, signIn, signOut, auth } = NextAuth({
  adapter: DrizzleAdapter(db),
  providers: [GitHub],
  callbacks: {
    session({ session, user }) { session.user.id = user.id; return session; },
  },
});

export async function requireSession() {
  const session = await auth();
  if (!session?.user) throw new Error("Unauthorized");
  return session;
}
```

Validate sessions server-side in layouts, Server Components, and Server Actions. Never rely on a client-side auth check as your only gate.

---

## Component Patterns

### Server vs Client Decision Tree

```
Does it need useState/useEffect/useRef/onClick/onChange? → "use client"
Does it need browser APIs (window, localStorage)?       → "use client"
Does it use a hook-based library (TanStack Query, RHF)? → "use client"
None of the above?                                      → Server Component (default)
```

Push `"use client"` as far down the tree as possible. The page is a Server Component that fetches data and passes it to small Client Component leaves:

```tsx
// Server Component (page) — fetches data
export default async function BillingPage() {
  const subscription = await getSubscription((await requireSession()).user.id);
  return (
    <div>
      <h1>Plan: {subscription.plan.name}</h1>
      <CancelSubscriptionButton subscriptionId={subscription.id} />
    </div>
  );
}
```

```tsx
// Client Component — only the interactive part
"use client";
export function CancelSubscriptionButton({ subscriptionId }: { subscriptionId: string }) {
  const [isPending, startTransition] = useTransition();
  return (
    <button
      disabled={isPending}
      onClick={() => startTransition(() => cancelSubscriptionAction(subscriptionId))}
    >
      {isPending ? "Canceling..." : "Cancel Subscription"}
    </button>
  );
}
```

---

## API Patterns

**Route Handlers** — webhooks, external consumers:

```ts
// app/api/webhooks/stripe/route.ts
export async function POST(request: Request) {
  const body = await request.text();
  const signature = (await headers()).get("stripe-signature")!;
  const event = stripe.webhooks.constructEvent(body, signature, process.env.STRIPE_WEBHOOK_SECRET!);

  if (event.type === "customer.subscription.updated") {
    await handleSubscriptionUpdated(event.data.object);
  }
  return new Response("OK", { status: 200 });
}
```

**Server Actions** — mutations from your UI. Always validate session and input:

```ts
// actions/subscriptions.ts
"use server";
export async function cancelSubscriptionAction(subscriptionId: string) {
  const session = await requireSession();
  const subscription = await getSubscription(session.user.id);
  if (!subscription || subscription.id !== subscriptionId) throw new Error("Not found");

  await cancelStripeSubscription(subscription.stripeSubscriptionId);
  await cancelSubscription(subscriptionId);
  revalidatePath("/settings/billing");
}
```

Server Actions are public HTTP endpoints. Always check auth. Always validate with Zod. Always `revalidatePath` after mutations.

---

## Testing Strategy

**Vitest + React Testing Library** for components and data layer. **Playwright** for E2E.

```tsx
// Component test
describe("PricingCard", () => {
  it("renders plan name and price", () => {
    render(<PricingCard plan={{ name: "Pro", price: 29, interval: "month" }} />);
    expect(screen.getByText("Pro")).toBeInTheDocument();
    expect(screen.getByText("$29/month")).toBeInTheDocument();
  });
});
```

```ts
// E2E — critical path only
test("user can cancel subscription", async ({ page }) => {
  await loginAsTestUser(page);
  await page.click('a[href="/settings/billing"]');
  await expect(page.getByText("$29/month")).toBeVisible();
  await page.click("text=Cancel Subscription");
  await page.click("text=Confirm");
  await expect(page.getByText("Canceled")).toBeVisible();
});
```

Test data-layer functions against a real test database, not mocks. Test pyramid: many data/unit tests, moderate component tests, few E2E tests on critical paths.

---

## Deployment (Walking Skeleton)

Complete all seven before writing features:

1. **Scaffold** — `npx create-next-app` with TypeScript, Tailwind, App Router
2. **Deploy** — Vercel (default), or Docker standalone for Railway/Fly.io (`output: "standalone"` in `next.config.ts`)
3. **Database** — Neon, Supabase, or Railway Postgres. ORM configured, initial migration run.
4. **Auth** — Auth.js with one provider, session persists across page loads
5. **CI** — GitHub Actions runs `tsc --noEmit && vitest run && next build` on every push
6. **Error tracking** — `@sentry/nextjs` installed, errors verified in dashboard
7. **Domain + SSL** — Custom domain configured (Vercel handles SSL automatically)

---

## Next.js-Specific Quality Checklist

- [ ] No unnecessary `"use client"` — Server Component unless it genuinely needs interactivity
- [ ] No data fetching in Client Components when a parent Server Component could pass props
- [ ] Static pages use `generateStaticParams` (blog posts, docs, pricing tiers)
- [ ] Dynamic pages export `generateMetadata` with title, description, OG tags
- [ ] `loading.tsx` at every route segment that fetches data — no blank screens
- [ ] `error.tsx` at root and major route group levels
- [ ] All images use `next/image` — no raw `<img>` tags
- [ ] Server-only env vars have no `NEXT_PUBLIC_` prefix; client vars contain no secrets
- [ ] Server Actions validate input (Zod) and check authorization before mutations
- [ ] No `fetch()` in Client Components duplicating data already available from the server

---

## Common Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| Hydration mismatch errors | Server/client render different output (`Date.now()`, browser APIs in initial render) | Move dynamic values to `useEffect`. Never call browser APIs during SSR. |
| Waterfall fetching, slow page loads | Sequential `await` calls in one Server Component | `Promise.all()` for independent fetches, or parallel `<Suspense>` boundaries |
| Entire page re-renders on navigation | One giant Client Component wraps the page | Keep page as Server Component, compose small Client children |
| `"use client"` in every file | Devs assume all components need it | Audit: only add for hooks, events, or browser APIs |
| Stale data after mutation | Missing `revalidatePath`/`revalidateTag` in Server Action | Always revalidate at the end of every write action |
| Stripe webhook 500 errors | Body parser consumes raw body before signature check | Use `request.text()` in Route Handler — App Router does not auto-parse |
| Bloated JS bundle | Barrel exports or large libs imported where not needed | Avoid `index.ts` re-exports. Use `next/dynamic` for heavy client components. Run `@next/bundle-analyzer`. |
| Middleware slows every request | No `matcher` — processes static assets and images | Always define `config.matcher` to exclude `_next/static`, `_next/image`, `favicon.ico` |
