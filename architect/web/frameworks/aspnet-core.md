<!-- License: See /LICENSE -->

# ASP.NET Core — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses ASP.NET Core.

---

## When to Choose ASP.NET Core

**Choose it when:**
- The team already knows C# and .NET — this is the single strongest signal.
- You need high-throughput APIs — Kestrel is among the fastest web servers in TechEmpower benchmarks.
- The organization is Azure-centric (App Service, Entra ID, Key Vault integrate with minimal glue).
- You want one runtime for APIs, background workers, and real-time (SignalR).

**Do not choose it when:**
- The team is a Python, Node, or Ruby shop — .NET has a steep onboarding curve.
- You need a batteries-included MPA framework with admin panel — Django or Rails are more productive.
- You are building a lightweight prototype — Go or FastAPI will get there with less ceremony.

---

## Project Structure

Clean architecture for complex domains; vertical slices for smaller services. Never mix both.

```
src/
├── Subscriptions.Api/              — host, DI, middleware, Program.cs
│   ├── Endpoints/                  — minimal API endpoint groups
│   └── Middleware/
├── Subscriptions.Application/      — commands, queries, handlers (no framework deps)
│   └── Subscriptions/
│       ├── CreateSubscription.cs   — command + handler + validator
│       └── GetSubscriptionById.cs
├── Subscriptions.Domain/           — entities, value objects (zero NuGet deps)
│   ├── Subscription.cs
│   └── SubscriptionStatus.cs
├── Subscriptions.Infrastructure/   — EF Core, Stripe, external services
│   └── Persistence/
│       ├── AppDbContext.cs
│       ├── Configurations/
│       └── Repositories/
└── tests/
    ├── Api.Tests/                  — integration (WebApplicationFactory)
    └── Application.Tests/          — unit tests for handlers
```

**Dependency rules:** Domain has zero NuGet dependencies. Application references only Domain. Infrastructure references Application + Domain. API references everything — it is the composition root. Never reference Infrastructure from Application.

---

## Routing

Minimal APIs are the default for new projects. Use controllers only in existing controller-based codebases. Do not mix both.

```csharp
// Program.cs — group routes, apply auth to entire group
app.MapGroup("/api/v1/subscriptions").MapSubscriptionEndpoints().RequireAuthorization();

// Endpoints/SubscriptionEndpoints.cs
public static class SubscriptionEndpoints
{
    public static RouteGroupBuilder MapSubscriptionEndpoints(this RouteGroupBuilder group)
    {
        group.MapGet("/{id:guid}", GetById);
        group.MapPost("/", Create);
        group.MapPost("/{id:guid}/cancel", Cancel);
        return group;
    }

    private static async Task<IResult> Create(
        CreateSubscriptionRequest request, ISender sender, CancellationToken ct)
    {
        var id = await sender.Send(new CreateSubscription.Command(request.PlanId, request.UserId), ct);
        return Results.Created($"/api/v1/subscriptions/{id}", new { id });
    }
}
```

For legacy controller codebases only: `[ApiController, Route("api/v1/[controller]")]` with `[HttpGet("{id:guid}")]` attribute routing.

---

## Data Layer

Entity Framework Core is the default ORM. Add Dapper only for read-heavy queries where EF generates suboptimal SQL.

```csharp
public class AppDbContext : DbContext, IUnitOfWork
{
    public DbSet<Subscription> Subscriptions => Set<Subscription>();
    public DbSet<Payment> Payments => Set<Payment>();

    protected override void OnModelCreating(ModelBuilder modelBuilder) =>
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

    public override async Task<int> SaveChangesAsync(CancellationToken ct = default)
    {
        foreach (var entry in ChangeTracker.Entries<BaseEntity>())
        {
            if (entry.State == EntityState.Added) entry.Entity.CreatedAt = DateTime.UtcNow;
            if (entry.State is EntityState.Added or EntityState.Modified)
                entry.Entity.UpdatedAt = DateTime.UtcNow;
        }
        return await base.SaveChangesAsync(ct);
    }
}
```

Use Fluent API configuration (always over data annotations):

```csharp
public void Configure(EntityTypeBuilder<Subscription> builder)
{
    builder.ToTable("subscriptions");
    builder.Property(s => s.Status).HasConversion<string>().HasMaxLength(32);
    builder.HasIndex(s => s.UserId);
    builder.HasMany(s => s.Payments).WithOne(p => p.Subscription)
        .HasForeignKey(p => p.SubscriptionId).OnDelete(DeleteBehavior.Cascade);
}
```

**Migrations:** `dotnet ef migrations add AddPaymentTable --project src/Subscriptions.Infrastructure --startup-project src/Subscriptions.Api`. Never edit a migration after it has been applied to any shared environment.

**Change tracking rules:** Use `AsNoTracking()` on all read-only queries. Call `SaveChangesAsync` exactly once per request — never inside repositories or loops.

---

## Middleware

Pipeline order matters. The first registered middleware is the outermost layer.

```csharp
var app = builder.Build();
app.UseExceptionHandler();                    // 1. catch everything
if (!app.Environment.IsDevelopment()) app.UseHsts();
app.UseHttpsRedirection();                    // 2. HTTPS
app.UseSerilogRequestLogging();               // 3. request logging
app.UseCors("DefaultPolicy");                 // 4. CORS before auth
app.UseAuthentication();                      // 5. authn
app.UseAuthorization();                       // 6. authz
app.UseRateLimiter();                         // 7. rate limiting
app.MapEndpoints();                           // 8. endpoints last
```

### Custom Exception Middleware

```csharp
public async Task InvokeAsync(HttpContext context)
{
    try { await _next(context); }
    catch (ValidationException ex)
    {
        context.Response.StatusCode = 400;
        await context.Response.WriteAsJsonAsync(
            new { error = new { code = "validation_error", message = ex.Message } });
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Unhandled: {Method} {Path}", context.Request.Method, context.Request.Path);
        context.Response.StatusCode = 500;
        await context.Response.WriteAsJsonAsync(
            new { error = new { code = "internal_error", message = "An unexpected error occurred" } });
    }
}
```

Never leak stack traces to the client. Log them; return a generic message.

---

## Authentication

### JWT Bearer + Policy-Based Authorization

```csharp
// Program.cs — JWT setup
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opt => {
        opt.TokenValidationParameters = new TokenValidationParameters {
            ValidateIssuer = true, ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidateAudience = true, ValidAudience = builder.Configuration["Jwt:Audience"],
            ValidateLifetime = true, ClockSkew = TimeSpan.Zero,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"]!))
        };
    });

// Policy registration — resource-based authorization
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("SubscriptionOwner", p => p.Requirements.Add(new SubscriptionOwnerRequirement()));

// Handler checks resource ownership via claims
public class SubscriptionOwnerHandler
    : AuthorizationHandler<SubscriptionOwnerRequirement, Subscription>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        SubscriptionOwnerRequirement requirement, Subscription resource)
    {
        if (resource.UserId.ToString() == context.User.FindFirstValue(ClaimTypes.NameIdentifier))
            context.Succeed(requirement);
        return Task.CompletedTask;
    }
}
```

**Rules:** Never hardcode role checks — use policies. Store signing keys in Key Vault or env vars, never committed config. Access tokens: 15 min. Refresh tokens: 30 days, single-use, rotated.

---

## API Patterns

### CQRS with MediatR + FluentValidation

Command, validator, and handler live in a single file per use case:

```csharp
public static class CreateSubscription
{
    public sealed record Command(Guid PlanId, Guid UserId) : IRequest<Guid>;

    public sealed class Validator : AbstractValidator<Command>
    {
        public Validator() { RuleFor(c => c.PlanId).NotEmpty(); RuleFor(c => c.UserId).NotEmpty(); }
    }

    internal sealed class Handler(ISubscriptionRepository subscriptions, IUnitOfWork uow)
        : IRequestHandler<Command, Guid>
    {
        public async Task<Guid> Handle(Command cmd, CancellationToken ct)
        {
            var sub = Subscription.Create(cmd.PlanId, cmd.UserId);
            subscriptions.Add(sub);
            await uow.SaveChangesAsync(ct);
            return sub.Id;
        }
    }
}
```

Wire a `ValidationBehavior<TRequest, TResponse>` as an `IPipelineBehavior` that collects all `IValidator<TRequest>` failures before calling the next handler — throw `ValidationException` if any fail. Register via `AddMediatR(cfg => cfg.AddOpenBehavior(typeof(ValidationBehavior<,>)))`.

Never expose domain entities in API responses. Map to DTOs:

```csharp
public sealed record SubscriptionResponse(
    Guid Id, string PlanName, string Status, DateTime CreatedAt, DateTime? CancelledAt);
```

---

## Testing Strategy

Integration tests are the highest-value tests for ASP.NET Core APIs. Write more integration tests than unit tests.

```csharp
// Integration test — full pipeline via WebApplicationFactory
public class SubscriptionTests(CustomWebApplicationFactory factory)
    : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task Create_subscription_returns_201()
    {
        var response = await _client.PostAsJsonAsync("/api/v1/subscriptions",
            new { PlanId = Guid.NewGuid(), UserId = Guid.NewGuid() });
        response.StatusCode.Should().Be(HttpStatusCode.Created);
    }
}

// Swap real DB for Testcontainers PostgreSQL, replace external services with fakes
public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.ConfigureServices(services => {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(o => o.UseNpgsql(PostgresContainer.ConnectionString));
            services.RemoveAll<IPaymentGateway>();
            services.AddSingleton<IPaymentGateway, FakePaymentGateway>();
        });
}
```

Unit tests with NSubstitute for handler logic:

```csharp
[Fact]
public async Task Handler_creates_subscription_and_saves()
{
    var repo = Substitute.For<ISubscriptionRepository>();
    var uow = Substitute.For<IUnitOfWork>();
    var id = await new CreateSubscription.Handler(repo, uow)
        .Handle(new(Guid.NewGuid(), Guid.NewGuid()), CancellationToken.None);
    id.Should().NotBeEmpty();
    repo.Received(1).Add(Arg.Any<Subscription>());
    await uow.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
}
```

**Rules:** Use Testcontainers with real PostgreSQL — never InMemory provider (it lies about SQL behavior). One `Fact` per behavior. Use FluentAssertions.

---

## Deployment (Walking Skeleton)

Your Day 1 skeleton must include all seven. If any are missing, this is what you build first.

1. **Health endpoint** — `/healthz` returning 200 when app + database are reachable.
2. **Dockerfile** — multi-stage build (`sdk` for publish, `aspnet` runtime). Target < 120 MB.
3. **CI pipeline** — push to `main` triggers build, test, deploy. Tests must pass before deploy.
4. **Database provisioned** — PostgreSQL on Azure Flexible Server, Railway, or Neon. Migrations run before app startup, never on boot.
5. **Hosting** — Azure App Service (container), Railway, or Fly.io for early stage.
6. **Structured logging** — Serilog writing JSON to stdout, forwarded to Seq/Datadog/Azure Monitor.
7. **Error tracking** — Sentry SDK capturing unhandled exceptions from Day 1.

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY src/**/*.csproj ./
RUN dotnet restore "Subscriptions.Api/Subscriptions.Api.csproj"
COPY src/ .
RUN dotnet publish "Subscriptions.Api/Subscriptions.Api.csproj" -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app .
EXPOSE 8080
ENTRYPOINT ["dotnet", "Subscriptions.Api.dll"]
```

---

## ASP.NET Core-Specific Quality Checklist

- [ ] **Async all the way.** Every I/O call uses `await`. No `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` — these cause threadpool starvation.
- [ ] **CancellationToken propagated.** Every endpoint, handler, and repository accepts and passes `CancellationToken` downstream.
- [ ] **DbContext is scoped.** Registered via `AddDbContext<T>` (scoped by default). Never singleton. Never injected into singleton services.
- [ ] **No service locator.** Never call `IServiceProvider.GetService<T>()` in business logic. Constructor injection only. Exception: `IServiceScopeFactory` in background services.
- [ ] **Configuration validated at startup.** `AddOptions<T>().BindConfiguration().ValidateDataAnnotations().ValidateOnStart()` — fail fast.
- [ ] **Health checks registered.** `/healthz` checks DB and critical deps. Used by load balancers and orchestrators.
- [ ] **Structured logging.** Serilog message templates only: `Log.Information("Subscription {SubscriptionId} cancelled", id)`. No string interpolation in log calls.
- [ ] **No ambient static state.** No `static HttpClient` without `IHttpClientFactory`. No `static DbContext`.
- [ ] **Response compression enabled.** Brotli + Gzip via `AddResponseCompression()`.
- [ ] **Global exception handler.** Unhandled exceptions return generic 500 with correlation ID. No stack traces to clients.

---

## Common Failure Modes

| Failure | Symptom | Fix |
|---|---|---|
| **Sync-over-async deadlock** | App hangs under load, threadpool at zero | Remove every `.Result` / `.Wait()`. Async all the way. |
| **DbContext in singleton** | `ObjectDisposedException` on second request | Use `IServiceScopeFactory` in background services. Never inject scoped into singleton. |
| **N+1 from lazy loading** | Hundreds of queries per request, 3-10s page loads | Disable lazy loading. Use `.Include()` or `.Select()` projections. |
| **Missing CancellationToken** | Cancelled requests keep running, wasting resources | Accept and propagate `CancellationToken` in every async method. |
| **Middleware order wrong** | Auth skipped, CORS missing, exceptions unhandled | Follow exact order: ExceptionHandler → HTTPS → CORS → Auth → Authz → Endpoints. |
| **Secrets in appsettings.json** | Credentials committed to source control | Use env vars, Key Vault, or `dotnet user-secrets` for local dev. |
| **SaveChanges per entity** | Write endpoints 10x slower than expected | Call `SaveChangesAsync` once per unit of work, not in loops. |
| **InMemory DB in tests** | Tests pass, production fails | Use Testcontainers with real PostgreSQL. Match production exactly. |
