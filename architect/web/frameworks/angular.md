## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Angular — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses Angular.

---

## When to Choose Angular

- **Large enterprise SPA** — dozens of views, complex forms, deep RBAC, multi-year lifecycle. Angular's opinions pay for themselves at scale.
- **Teams with Java/C# backgrounds** — dependency injection, typed services, and the class-based model feel natural.
- **Strict structure is a feature** — you want the framework to enforce conventions so 30 engineers write code the same way.
- **First-party batteries** — routing, forms, HTTP, i18n, animations, and testing are built in. No stitching together six libraries.

**When NOT:** Small apps, marketing sites, or content pages — use Astro or Next.js. Rapid prototypes — boilerplate-to-feature ratio is too high. Teams that resist TypeScript — Angular is all-in.

---

## Project Structure

Standalone components are the default since v17. Do not use NgModules for new code.

```
src/
├── app/
│   ├── app.component.ts             — root (standalone)
│   ├── app.config.ts                — provideRouter, provideHttpClient
│   ├── app.routes.ts                — top-level lazy route definitions
│   ├── core/                        — singletons: auth/, api/ (guards, interceptors, services)
│   ├── features/                    — one folder per domain feature
│   │   ├── subscriptions/           — list/, detail/, models/, services/, routes.ts
│   │   └── payments/                — same shape
│   └── shared/                      — stateless components/, pipes/, directives/
└── main.ts                          — bootstrapApplication(AppComponent, appConfig)
```

**Rules:** Features own their routes, services, and models — nothing leaks upward. `core/` holds singletons. `shared/` components are dumb: no injected services, pure inputs/outputs.

---

## Routing

Lazy-load everything. Never eager-load feature routes.

```typescript
// app.routes.ts — top-level only lazy-loads features
export const routes: Routes = [
  { path: 'subscriptions', canActivate: [authGuard],
    loadChildren: () => import('./features/subscriptions/subscriptions.routes')
      .then(m => m.SUBSCRIPTION_ROUTES) },
  { path: 'payments', canActivate: [authGuard],
    loadChildren: () => import('./features/payments/payments.routes')
      .then(m => m.PAYMENT_ROUTES) },
  { path: '', redirectTo: 'subscriptions', pathMatch: 'full' },
  { path: '**', loadComponent: () => import('./shared/components/not-found/not-found.component')
      .then(m => m.NotFoundComponent) },
];

// features/subscriptions/subscriptions.routes.ts
export const SUBSCRIPTION_ROUTES: Routes = [
  { path: '', loadComponent: () => import('./subscription-list/subscription-list.component')
      .then(m => m.SubscriptionListComponent) },
  { path: ':id', resolve: { subscription: subscriptionResolver },
    loadComponent: () => import('./subscription-detail/subscription-detail.component')
      .then(m => m.SubscriptionDetailComponent) },
];

// Functional resolver — prefetches data so component never renders in loading state
export const subscriptionResolver: ResolveFn<Subscription> = (route) =>
  inject(SubscriptionService).getById(route.paramMap.get('id')!);
```

`loadComponent` for leaves, `loadChildren` for groups. Guards and resolvers are always functional (`inject()`).

---

## Data Layer

Components never touch `HttpClient`. Services own HTTP calls and map responses to domain models.

```typescript
@Injectable({ providedIn: 'root' })
export class SubscriptionService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = `${environment.apiUrl}/api/v1/subscriptions`;
  getAll(): Observable<Subscription[]> {
    return this.http.get<{ data: SubscriptionResponse[] }>(this.baseUrl)
      .pipe(map(res => res.data.map(this.mapToDomain)));
  }
  cancel(id: string): Observable<Subscription> {
    return this.http.post<{ data: SubscriptionResponse }>(`${this.baseUrl}/${id}/cancel`, {})
      .pipe(map(res => this.mapToDomain(res.data)));
  }
  private mapToDomain(raw: SubscriptionResponse): Subscription {
    return { id: raw.id, planName: raw.plan_name, status: raw.status,
      currentPeriodEnd: new Date(raw.current_period_end),
      monthlyAmount: raw.monthly_amount_cents / 100 };
  }
}
```

**Signals over RxJS for component state.** `toSignal()` bridges observables from services. RxJS stays in services; signals stay in components.

```typescript
export class SubscriptionListComponent {
  private readonly svc = inject(SubscriptionService);
  readonly subscriptions = toSignal(this.svc.getAll(), { initialValue: [] });
  readonly filter = signal<'all' | 'active' | 'cancelled'>('all');
  readonly filtered = computed(() => this.filter() === 'all'
    ? this.subscriptions()
    : this.subscriptions().filter(s => s.status === this.filter()));
}
```

**NgRx** is a last resort — only when state is shared across features with complex updates and you need time-travel debugging.

---

## Middleware-like Patterns

Angular uses HTTP interceptors, guards, and resolvers instead of Express-style middleware. All functional — no classes.

```typescript
// HTTP error interceptor — redirect on 401/403
export const httpErrorInterceptor: HttpInterceptorFn = (req, next) =>
  next(req).pipe(catchError((error: HttpErrorResponse) => {
    const router = inject(Router);
    if (error.status === 401) router.navigate(['/login']);
    if (error.status === 403) router.navigate(['/forbidden']);
    return throwError(() => error);
  }));

// Auth guard — redirect unauthenticated users
export const authGuard: CanActivateFn = () =>
  inject(AuthService).isAuthenticated() || inject(Router).createUrlTree(['/login']);

// Registration — app.config.ts (interceptors execute in array order)
export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor, httpErrorInterceptor])),
  ],
};
```

---

## Authentication

Guards protect routes. Interceptors inject tokens. Never mix the two responsibilities.

```typescript
// Token injection — only attach to your own API domain
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const token = inject(AuthService).getAccessToken();
  return token && req.url.startsWith('/api')
    ? next(req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }))
    : next(req);
};

// Auth service — signals for reactive state
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly currentUser = signal<AuthUser | null>(null);
  readonly user = this.currentUser.asReadonly();
  readonly isAuthenticated = computed(() => this.currentUser() !== null);
  getAccessToken(): string | null { return localStorage.getItem('access_token'); }

  login(email: string, password: string) {
    return this.http.post<{ data: { token: string; user: AuthUser } }>(
      '/api/v1/auth/login', { email, password }
    ).pipe(tap(res => {
      localStorage.setItem('access_token', res.data.token);
      this.currentUser.set(res.data.user);
    }));
  }
}
```

Apply `authGuard` at the feature level so child routes inherit protection. Never attach tokens to third-party requests.

---

## Component Patterns

Every component: `standalone: true`, `ChangeDetectionStrategy.OnPush`. No exceptions.

```typescript
@Component({
  standalone: true, changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, CurrencyPipe, StatusBadgeComponent],
  template: `
    @for (sub of filtered(); track sub.id) {
      <div class="subscription-card" [routerLink]="[sub.id]">
        <h3>{{ sub.planName }}</h3>
        <app-status-badge [status]="sub.status" />
        <p>{{ sub.monthlyAmount | currency }} / month</p>
      </div>
    } @empty { <p>No subscriptions found.</p> }
  `,
})
export class SubscriptionListComponent { /* signals — see Data Layer */ }

// Presentational — lives in shared/, inputs only, no services
@Component({ standalone: true, changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="badge" [class]="'badge--' + status()">{{ status() }}</span>` })
export class StatusBadgeComponent { readonly status = input.required<string>(); }
```

**Smart** components (`features/`) inject services and manage state. **Presentational** components (`shared/`) take `input()` + `output()` only, no side effects. Use `input()` signal function (v17.1+), `@for` / `@if` control flow — not `@Input()` or `*ngFor` / `*ngIf`.

---

## API Patterns

Map snake_case API responses to camelCase domain models at the service boundary. Never use `any`.

```typescript
// Typed response shape → domain model (always define both)
export interface PaymentResponse {
  id: string; subscription_id: string; amount_cents: number;
  currency: string; status: 'succeeded' | 'failed' | 'pending' | 'refunded';
  created_at: string;
}
export interface Payment {
  id: string; subscriptionId: string; amount: number;
  currency: string; status: Payment['status']; createdAt: Date;
}

// Error handling + retry (GET only — never retry mutations)
@Injectable({ providedIn: 'root' })
export class PaymentService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = `${environment.apiUrl}/api/v1/payments`;
  getForSubscription(subscriptionId: string): Observable<Payment[]> {
    return this.http.get<{ data: PaymentResponse[] }>(
      `${this.baseUrl}?subscription_id=${subscriptionId}`
    ).pipe(
      retry({ count: 2, delay: 1000 }),
      map(res => res.data.map(this.mapToDomain)),
      catchError(this.handleError),
    );
  }
}
```

Common error handling goes in `httpErrorInterceptor`. Service-level `catchError` is for domain-specific recovery only.

---

## Testing Strategy

Use **Vitest** for modern Angular (v17+). Fall back to Jasmine+Karma only if already in use.

```typescript
// Component test — mock service, assert behavior
beforeEach(async () => {
  await TestBed.configureTestingModule({
    imports: [SubscriptionListComponent],
    providers: [
      provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
      { provide: SubscriptionService, useValue: { getAll: () => of(mockSubscriptions) } },
    ],
  }).compileComponents();
  fixture = TestBed.createComponent(SubscriptionListComponent);
  fixture.detectChanges();
});
it('filters to active', () => {
  fixture.componentInstance.filter.set('active');
  fixture.detectChanges();
  expect(fixture.nativeElement.querySelectorAll('.subscription-card').length).toBe(1);
});

// Service test — verify HTTP + mapping
it('maps API response to domain model', () => {
  service.getForSubscription('sub_1').subscribe(p => {
    expect(p[0].amount).toBe(29.99);
    expect(p[0].createdAt).toBeInstanceOf(Date);
  });
  httpMock.expectOne(r => r.url.includes('/payments'))
    .flush({ data: [{ id: 'pay_1', subscription_id: 'sub_1',
      amount_cents: 2999, currency: 'usd', status: 'succeeded',
      created_at: '2026-03-01T00:00:00Z' }] });
});
```

| Layer | Tool |
|---|---|
| Components | TestBed + ComponentFixture |
| Services | TestBed + HttpTestingController |
| Guards / Interceptors | TestBed + functional test |
| E2E | Playwright or Cypress |

Test behavior, not implementation. `provideHttpClientTesting()` always. Component harnesses for Angular Material.

---

## Deployment (Walking Skeleton)

Day 1 checklist — nothing else gets built until all seven are done:

1. **`ng build --configuration=production`** — optimized bundle, initial JS under 200 KB
2. **Docker + nginx** — static build with `try_files $uri $uri/ /index.html` SPA fallback
3. **Environment config** — `environment.ts` at build time, or runtime `env.js` for config without rebuilds
4. **CI pipeline** — push to main triggers lint, test, build; block merges on failure
5. **Staging deployment** — Docker image deploys to a real URL on merge
6. **Error tracking** — Sentry wired to Angular `ErrorHandler`, sourcemaps uploaded at build
7. **SSR (optional)** — Angular Universal only if you need SEO; skip for auth-gated SPAs

```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY . .
RUN npm ci && npm run build -- --configuration=production
FROM nginx:alpine
COPY --from=build /app/dist/your-app/browser /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
```

---

## Angular-Specific Quality Checklist

- [ ] `OnPush` change detection on every component, no exceptions
- [ ] All components standalone — zero NgModules
- [ ] Signals for component state; `toSignal()` at the service boundary
- [ ] No orphan subscriptions — `takeUntilDestroyed()`, `toSignal()`, or `async` pipe
- [ ] Feature routes lazy-loaded via `loadComponent` / `loadChildren`
- [ ] Interceptors and guards are functional, not class-based
- [ ] `@for` / `@if` control flow with `track` — no `*ngFor` / `*ngIf`
- [ ] Bundle budget enforced in `angular.json`
- [ ] No direct `HttpClient` in components — always through a service

---

## Common Failure Modes

| Failure | Symptom | Fix |
|---|---|---|
| Unsubscribed observables | App slows over time, DOM nodes pile up | `toSignal()`, `takeUntilDestroyed()`, or `DestroyRef`. Never `.subscribe()` without cleanup. |
| Default change detection | UI stutters, excessive re-renders | `OnPush` on every component. Signals for targeted updates. |
| Bundle bloat / barrel chains | Initial load > 500 KB, slow TTI | Lazy-load all features. Direct file imports, not barrel re-exports. Audit with `source-map-explorer`. |
| Zone.js noise | Third-party libs trigger unnecessary CD | `NgZone.runOutsideAngular()`. Consider zoneless mode (v18+). |
| NgRx for simple state | Boilerplate for what a signal handles | Default to signals + services. NgRx only for cross-cutting complex state. |
| RxJS soup in components | 20-line pipe chains nobody can debug | Move RxJS to services. Signals + `computed()` in components. |
