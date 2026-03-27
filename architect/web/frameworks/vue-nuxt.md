## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Vue / Nuxt — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses Vue or Nuxt.

---

## When to Choose Vue / Nuxt

Vue is the right call when:

- **Progressive adoption** — you're adding interactivity to an existing server-rendered app or migrating from jQuery/vanilla JS. Vue's single-file components drop in without rearchitecting everything.
- **Smaller teams** — Vue's learning curve is gentler than React's ecosystem sprawl. One developer can be productive on day one.
- **Template syntax is preferred** — the team thinks in HTML, not JSX. Vue templates are closer to the document.
- **SSR/SSG is needed** — Nuxt provides file-based routing, server-side rendering, and static generation with zero configuration. It is the full-stack answer for Vue.

**Vue standalone (SPA)** when SEO doesn't matter, the app lives behind a login, and you want a lightweight Vite-powered build without server runtime.

**Nuxt** when you need SSR, SSG, hybrid rendering, server routes, or any combination of these. Nuxt is to Vue what Next.js is to React — the production framework.

### When NOT to Choose Vue / Nuxt

- **Large enterprise teams already invested in React** — don't introduce Vue as a second frontend framework. Pick one.
- **Heavy ecosystem lock-in needed** — React's third-party ecosystem (component libraries, hiring pool, tooling) is larger. If you need a specific React library with no Vue equivalent, that matters.
- **Mobile + web code sharing** — React Native exists; Vue's mobile story (Capacitor, NativeScript) is weaker.
- **You need bleeding-edge React Server Components patterns** — Vue has no equivalent. If RSCs are core to your architecture, use Next.js.

---

## Project Structure

### Nuxt (Default — Full-Stack)

```
my-app/
├── app.vue                    — root component (replaces App.vue)
├── nuxt.config.ts             — framework configuration
├── pages/                     — file-based routing (each file = a route)
│   ├── index.vue              — /
│   ├── pricing.vue            — /pricing
│   └── subscriptions/
│       ├── index.vue          — /subscriptions
│       └── [id].vue           — /subscriptions/:id (dynamic)
├── components/                — auto-imported components
│   ├── ui/                    — generic: Button, Input, Modal, Card
│   └── features/              — domain: PlanSelector, PaymentForm, InvoiceTable
├── composables/               — shared Composition API logic (auto-imported)
│   ├── useSubscription.ts     — subscription state and actions
│   └── useAuth.ts             — authentication composable
├── server/                    — Nitro server routes
│   ├── api/                   — API endpoints (server/api/plans.get.ts → GET /api/plans)
│   │   ├── plans.get.ts
│   │   ├── subscriptions/
│   │   │   ├── index.post.ts  — POST /api/subscriptions
│   │   │   └── [id].get.ts    — GET /api/subscriptions/:id
│   │   └── webhooks/
│   │       └── stripe.post.ts
│   ├── middleware/             — server middleware (runs on every request)
│   └── utils/                 — server-only utilities
├── stores/                    — Pinia stores
│   └── subscription.ts
├── middleware/                 — route middleware (client + server)
│   └── auth.ts
├── layouts/                   — page layouts
│   ├── default.vue
│   └── dashboard.vue
├── plugins/                   — Nuxt plugins (run before app mounts)
├── public/                    — static files (served as-is)
├── assets/                    — processed assets (CSS, images Vite handles)
└── types/                     — shared TypeScript types
    └── subscription.ts
```

### Vue Standalone (SPA) Differences

When using Vue + Vite without Nuxt:

- No `pages/` — use `vue-router` with explicit route definitions in `router/index.ts`
- No `server/` — backend is a separate service
- No auto-imports — import composables and components explicitly
- No `nuxt.config.ts` — use `vite.config.ts`
- Structure follows `src/` convention: `src/components/`, `src/composables/`, `src/stores/`, `src/views/`

---

## Routing

### File-Based Routing (Nuxt)

Nuxt generates routes from the `pages/` directory automatically.

```vue
<!-- pages/subscriptions/[id].vue -->
<script setup lang="ts">
const route = useRoute()
const { data: subscription } = await useFetch(`/api/subscriptions/${route.params.id}`)
</script>

<template>
  <div>
    <h1>{{ subscription?.planName }}</h1>
    <p>Status: {{ subscription?.status }}</p>
  </div>
</template>
```

Dynamic route conventions:

| File Path | Route | Example |
|---|---|---|
| `pages/index.vue` | `/` | Home |
| `pages/subscriptions/index.vue` | `/subscriptions` | List |
| `pages/subscriptions/[id].vue` | `/subscriptions/:id` | Detail (dynamic) |
| `pages/subscriptions/[id]/invoices.vue` | `/subscriptions/:id/invoices` | Nested |
| `pages/[...slug].vue` | `/*` (catch-all) | 404 / wildcard |

### Vue Router (Standalone)

```typescript
// router/index.ts
import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: () => import('@/views/HomePage.vue') },
    { path: '/subscriptions', component: () => import('@/views/SubscriptionList.vue') },
    { path: '/subscriptions/:id', component: () => import('@/views/SubscriptionDetail.vue') },
    { path: '/:pathMatch(.*)*', component: () => import('@/views/NotFound.vue') },
  ],
})

export default router
```

Always lazy-load route components with dynamic `import()`. Never bundle the entire app into a single chunk.

### Route Middleware (Nuxt)

```typescript
// middleware/auth.ts
export default defineNuxtRouteMiddleware((to, from) => {
  const { user } = useAuth()

  if (!user.value) {
    return navigateTo('/login', { redirectCode: 302 })
  }
})
```

Apply to a page:

```vue
<!-- pages/subscriptions/index.vue -->
<script setup lang="ts">
definePageMeta({
  middleware: 'auth',
  layout: 'dashboard',
})
</script>
```

---

## Data Layer

### State Management: Pinia (Always)

Pinia is the official Vue state manager. Use it for global client state. Do not use Vuex — it is legacy.

```typescript
// stores/subscription.ts
import { defineStore } from 'pinia'
import type { Subscription, Plan } from '~/types/subscription'

export const useSubscriptionStore = defineStore('subscription', () => {
  // State
  const currentPlan = ref<Plan | null>(null)
  const subscriptions = ref<Subscription[]>([])
  const isLoading = ref(false)

  // Getters (computed)
  const activeSubscriptions = computed(() =>
    subscriptions.value.filter(s => s.status === 'active')
  )

  const monthlyRevenue = computed(() =>
    activeSubscriptions.value.reduce((sum, s) => sum + s.monthlyAmount, 0)
  )

  // Actions
  async function cancelSubscription(subscriptionId: string) {
    await $fetch(`/api/subscriptions/${subscriptionId}/cancel`, { method: 'POST' })
    const sub = subscriptions.value.find(s => s.id === subscriptionId)
    if (sub) sub.status = 'cancelled'
  }

  return { currentPlan, subscriptions, isLoading, activeSubscriptions, monthlyRevenue, cancelSubscription }
})
```

**Rules:**
- Always use the setup syntax (`defineStore('name', () => { ... })`), never the options syntax.
- Pinia is for **client-side global state** (auth user, UI preferences, cross-component communication). Do not duplicate server data into Pinia when `useFetch` or TanStack Query handles it.

### Data Fetching: useFetch / useAsyncData (Nuxt)

```vue
<script setup lang="ts">
// useFetch — shorthand for useAsyncData + $fetch
const { data: plans, pending, error, refresh } = await useFetch<Plan[]>('/api/plans', {
  transform: (response) => response.sort((a, b) => a.price - b.price),
})

// useAsyncData — when you need more control
const { data: subscription } = await useAsyncData(
  `subscription-${route.params.id}`,
  () => $fetch<Subscription>(`/api/subscriptions/${route.params.id}`),
  { watch: [() => route.params.id] }
)
</script>
```

`useFetch` and `useAsyncData` handle SSR data hydration automatically. Data fetched on the server transfers to the client without re-fetching. Always use them in Nuxt — never raw `fetch` in a component.

### TanStack Query (Complex Client-Side Needs)

When you need polling, optimistic updates, infinite scroll, or fine-grained cache control, add `@tanstack/vue-query`:

```typescript
// composables/useSubscriptionQuery.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'

export function useSubscriptionQuery(subscriptionId: Ref<string>) {
  return useQuery({
    queryKey: ['subscription', subscriptionId],
    queryFn: () => $fetch<Subscription>(`/api/subscriptions/${subscriptionId.value}`),
    staleTime: 30_000,
  })
}

export function useCancelSubscription() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: string) => $fetch(`/api/subscriptions/${id}/cancel`, { method: 'POST' }),
    onSuccess: (_data, id) => {
      queryClient.invalidateQueries({ queryKey: ['subscription', id] })
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] })
    },
  })
}
```

**Default to `useFetch`/`useAsyncData` in Nuxt.** Reach for TanStack Query only when you need its cache invalidation, polling, or optimistic update features.

---

## Middleware

### Route Middleware (Client + Server)

Runs during navigation. Use for auth guards, redirects, and route validation.

```typescript
// middleware/subscription-active.ts
export default defineNuxtRouteMiddleware(async (to) => {
  const { data: subscription } = await useFetch<Subscription>(
    `/api/subscriptions/${to.params.id}`
  )

  if (!subscription.value || subscription.value.status === 'cancelled') {
    return navigateTo('/subscriptions', { redirectCode: 301 })
  }
})
```

### Server Middleware (HTTP-Level)

Runs on every server request before route handlers. Use for logging, CORS, rate limiting.

```typescript
// server/middleware/log.ts
export default defineEventHandler((event) => {
  const start = Date.now()
  event.node.res.on('finish', () => {
    const duration = Date.now() - start
    console.log(`${event.method} ${getRequestURL(event)} — ${duration}ms`)
  })
})
```

### Global vs Named Middleware

| Type | Location | Applied |
|---|---|---|
| Global | `middleware/*.global.ts` | Every route, automatically |
| Named | `middleware/*.ts` | Per page via `definePageMeta({ middleware: 'name' })` |
| Inline | Inside `definePageMeta` | One-off, defined in the page itself |

---

## Authentication

### Composable-Based Auth

```typescript
// composables/useAuth.ts
import type { User } from '~/types/user'

export function useAuth() {
  const user = useState<User | null>('auth-user', () => null)
  const isAuthenticated = computed(() => !!user.value)

  async function login(email: string, password: string) {
    const response = await $fetch<{ user: User; token: string }>('/api/auth/login', {
      method: 'POST',
      body: { email, password },
    })
    user.value = response.user
    await navigateTo('/dashboard')
  }

  async function logout() {
    await $fetch('/api/auth/logout', { method: 'POST' })
    user.value = null
    await navigateTo('/login')
  }

  async function fetchUser() {
    try {
      user.value = await $fetch<User>('/api/auth/me')
    } catch {
      user.value = null
    }
  }

  return { user, isAuthenticated, login, logout, fetchUser }
}
```

### Server-Side Auth Check

```typescript
// server/utils/auth.ts
import { H3Event } from 'h3'

export async function requireAuth(event: H3Event) {
  const session = await getSession(event)

  if (!session?.userId) {
    throw createError({ statusCode: 401, statusMessage: 'Unauthorized' })
  }

  return session
}
```

```typescript
// server/api/subscriptions/index.get.ts
export default defineEventHandler(async (event) => {
  const session = await requireAuth(event)

  const subscriptions = await db.subscription.findMany({
    where: { userId: session.userId },
  })

  return { data: subscriptions }
})
```

**Rules:**
- Store session state server-side (cookie + server session). Do not put auth tokens in `localStorage`.
- Use `useState` (not `ref`) for auth state in Nuxt — it serializes across SSR and client.
- Initialize auth state in a plugin or layout so it is available before any page renders.

---

## Component Patterns

### Composition API Only

Never use the Options API. Every component uses `<script setup lang="ts">`. No exceptions.

```vue
<!-- components/features/PlanSelector.vue -->
<script setup lang="ts">
import type { Plan } from '~/types/subscription'

const props = defineProps<{
  plans: Plan[]
  currentPlanId?: string
}>()

const emit = defineEmits<{
  select: [plan: Plan]
}>()

const selectedPlan = ref<Plan | null>(null)

const sortedPlans = computed(() =>
  [...props.plans].sort((a, b) => a.monthlyPrice - b.monthlyPrice)
)

function handleSelect(plan: Plan) {
  selectedPlan.value = plan
  emit('select', plan)
}
</script>

<template>
  <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
    <div
      v-for="plan in sortedPlans"
      :key="plan.id"
      :class="[
        'rounded-lg border p-6 cursor-pointer',
        plan.id === currentPlanId ? 'border-blue-500 bg-blue-50' : 'border-gray-200',
      ]"
      @click="handleSelect(plan)"
    >
      <h3 class="text-lg font-semibold">{{ plan.name }}</h3>
      <p class="text-3xl font-bold mt-2">${{ plan.monthlyPrice }}/mo</p>
      <ul class="mt-4 space-y-2">
        <li v-for="feature in plan.features" :key="feature">{{ feature }}</li>
      </ul>
    </div>
  </div>
</template>
```

### Provide / Inject for Deep Props

When props would drill through 3+ levels, use provide/inject:

```typescript
// composables/useSubscriptionContext.ts
import type { Subscription } from '~/types/subscription'

const SUBSCRIPTION_KEY = Symbol('subscription') as InjectionKey<Ref<Subscription>>

export function provideSubscription(subscription: Ref<Subscription>) {
  provide(SUBSCRIPTION_KEY, subscription)
}

export function useSubscriptionContext(): Ref<Subscription> {
  const subscription = inject(SUBSCRIPTION_KEY)
  if (!subscription) throw new Error('useSubscriptionContext must be used within a provider')
  return subscription
}
```

### Auto-Imports (Nuxt)

Nuxt auto-imports Vue APIs (`ref`, `computed`, `watch`), composables from `composables/`, and components from `components/`. Do not add manual imports for these — it is unnecessary noise.

For standalone Vue, import everything explicitly. No magic.

---

## API Patterns

### Nuxt Server Routes (Nitro)

Server routes live in `server/api/` and map to HTTP endpoints by filename convention.

```typescript
// server/api/subscriptions/index.post.ts — POST /api/subscriptions
import { z } from 'zod'

const CreateSubscriptionSchema = z.object({
  planId: z.string().uuid(),
  paymentMethodId: z.string(),
})

export default defineEventHandler(async (event) => {
  const session = await requireAuth(event)
  const body = await readValidatedBody(event, CreateSubscriptionSchema.parse)

  const subscription = await subscriptionService.create({
    userId: session.userId,
    planId: body.planId,
    paymentMethodId: body.paymentMethodId,
  })

  setResponseStatus(event, 201)
  return { data: subscription }
})
```

### File Naming Convention

| File | Method | Route |
|---|---|---|
| `server/api/plans.get.ts` | GET | `/api/plans` |
| `server/api/plans.post.ts` | POST | `/api/plans` |
| `server/api/subscriptions/[id].get.ts` | GET | `/api/subscriptions/:id` |
| `server/api/subscriptions/[id].patch.ts` | PATCH | `/api/subscriptions/:id` |
| `server/api/subscriptions/[id]/cancel.post.ts` | POST | `/api/subscriptions/:id/cancel` |

### Client-Side $fetch

```typescript
// In a composable or component
const subscription = await $fetch<Subscription>('/api/subscriptions', {
  method: 'POST',
  body: { planId: selectedPlan.value.id, paymentMethodId: pm.id },
})
```

Use `$fetch` for client-initiated requests. It handles JSON serialization, error throwing, and works isomorphically (server and client). Never use raw `fetch` in a Nuxt app.

---

## Testing Strategy

### Unit Tests: Vitest + Vue Test Utils

```typescript
// tests/components/PlanSelector.spec.ts
import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import PlanSelector from '~/components/features/PlanSelector.vue'

const mockPlans = [
  { id: '1', name: 'Starter', monthlyPrice: 9, features: ['5 users'] },
  { id: '2', name: 'Pro', monthlyPrice: 29, features: ['50 users', 'API access'] },
  { id: '3', name: 'Enterprise', monthlyPrice: 99, features: ['Unlimited', 'SSO', 'SLA'] },
]

describe('PlanSelector', () => {
  it('renders plans sorted by price', () => {
    const wrapper = mount(PlanSelector, {
      props: { plans: mockPlans },
    })

    const prices = wrapper.findAll('[class*="text-3xl"]')
    expect(prices[0].text()).toContain('$9')
    expect(prices[1].text()).toContain('$29')
    expect(prices[2].text()).toContain('$99')
  })

  it('emits select event when plan is clicked', async () => {
    const wrapper = mount(PlanSelector, {
      props: { plans: mockPlans },
    })

    await wrapper.findAll('[class*="cursor-pointer"]')[1].trigger('click')

    expect(wrapper.emitted('select')).toBeTruthy()
    expect(wrapper.emitted('select')![0][0]).toMatchObject({ id: '2', name: 'Pro' })
  })

  it('highlights the current plan', () => {
    const wrapper = mount(PlanSelector, {
      props: { plans: mockPlans, currentPlanId: '2' },
    })

    const cards = wrapper.findAll('[class*="rounded-lg"]')
    expect(cards[1].classes()).toContain('border-blue-500')
  })
})
```

### Nuxt Integration Tests

```typescript
// tests/server/api/subscriptions.spec.ts
import { describe, it, expect } from 'vitest'
import { setup, $fetch } from '@nuxt/test-utils'

describe('/api/subscriptions', async () => {
  await setup({ server: true })

  it('returns 401 without auth', async () => {
    await expect($fetch('/api/subscriptions')).rejects.toThrow('401')
  })

  it('creates a subscription for authenticated user', async () => {
    const result = await $fetch('/api/subscriptions', {
      method: 'POST',
      body: { planId: 'plan_starter', paymentMethodId: 'pm_test_123' },
      headers: { cookie: 'session=valid-test-session' },
    })

    expect(result.data.status).toBe('active')
    expect(result.data.planId).toBe('plan_starter')
  })
})
```

### E2E Tests: Playwright

```typescript
// e2e/subscription-flow.spec.ts
import { test, expect } from '@playwright/test'

test('user can subscribe to a plan', async ({ page }) => {
  await page.goto('/login')
  await page.fill('[name="email"]', 'test@example.com')
  await page.fill('[name="password"]', 'password123')
  await page.click('button[type="submit"]')

  await page.goto('/pricing')
  await page.click('text=Pro')
  await page.click('text=Subscribe')

  await expect(page).toHaveURL(/\/subscriptions\//)
  await expect(page.locator('text=Active')).toBeVisible()
})
```

### Test File Placement

| Test Type | Location | Runner |
|---|---|---|
| Unit (components, composables) | `tests/components/`, `tests/composables/` | Vitest |
| Server API | `tests/server/` | Vitest + `@nuxt/test-utils` |
| E2E | `e2e/` | Playwright |

---

## Deployment (Walking Skeleton)

Your Day 1 checklist — all seven items before writing any feature code:

1. **Nuxt app deployed** to Vercel, Netlify, or Cloudflare Pages (renders the homepage at a real URL)
2. **SSR working** — verify by viewing page source; HTML is rendered, not an empty `<div id="app">`
3. **Database provisioned** — PostgreSQL on Railway, Neon, or Supabase; first migration applied
4. **CI/CD pipeline** — push to `main` triggers build + deploy to staging automatically
5. **One authenticated route** — login, see a dashboard page with real data, logout
6. **Error tracking** — Sentry Nuxt module installed and capturing errors in both client and server
7. **Domain + SSL** — custom domain configured with HTTPS enforced

For **Vue SPA** (no Nuxt):
- Build with `vite build`, serve via Docker + Nginx, or deploy static output to Vercel/Netlify
- Backend is a separate service — ensure CORS is configured
- Verify the SPA fallback (all routes resolve to `index.html`)

---

## Vue/Nuxt-Specific Quality Checklist

- [ ] **Composition API only** — no `export default { data(), methods: {} }` anywhere in the codebase
- [ ] **Pinia over Vuex** — Vuex is legacy. Every store uses `defineStore` with setup syntax.
- [ ] **`:key` on every `v-for`** — use a stable unique identifier, never the array index
- [ ] **TypeScript strict mode** — `strict: true` in `tsconfig.json`, no `any` types
- [ ] **`useFetch` / `useAsyncData` for SSR data** — never raw `fetch` in components; it breaks hydration
- [ ] **`useState` for cross-component reactive state in Nuxt** — not plain `ref` at module scope (causes SSR cross-request contamination)
- [ ] **Props are typed with `defineProps<T>()`** — not the runtime array/object syntax
- [ ] **No business logic in components** — components call composables or stores; complex logic lives in `composables/` or `server/`
- [ ] **Auto-import hygiene** — if using Nuxt auto-imports, ensure `components/` and `composables/` directories are flat or well-organized to avoid name collisions
- [ ] **Bundle analyzed** — run `npx nuxi analyze` before launch; no single chunk exceeds 200KB gzipped

---

## Common Failure Modes

| Failure | Symptom | Fix |
|---|---|---|
| **Reactivity lost on destructure** | Value stops updating after `const { count } = store` | Use `storeToRefs(store)` for Pinia, or keep the `.value` access on refs |
| **Missing `:key` on `v-for`** | List re-renders incorrectly, inputs lose focus, animations break | Always bind `:key` to a stable unique ID — never use array index |
| **Hydration mismatch** | Console warning, UI flickers on load, SSR content replaced by client | Wrap browser-only code in `<ClientOnly>`, avoid `Date.now()` or `Math.random()` in SSR |
| **Raw `fetch` in Nuxt component** | Data fetched twice (server + client), no SSR hydration benefit | Replace with `useFetch` or `useAsyncData` — they deduplicate and transfer server data |
| **Shared state across SSR requests** | User A sees User B's data on server-rendered pages | Use `useState()` instead of module-level `ref()` — `useState` is scoped per request |
| **Mutating props directly** | Console warning, unpredictable parent/child state | Emit an event and let the parent update; or use a local copy with `toRef` |
| **Watching reactive object shallowly** | Watcher doesn't fire on nested property changes | Use `watch(() => obj.nested.value, callback)` or `{ deep: true }` (but prefer targeted watchers) |
| **Pinia store used before plugin registers** | `getActivePinia was called with no active Pinia` error | Ensure Pinia plugin is installed before any store is accessed; in Nuxt use the `@pinia/nuxt` module |
