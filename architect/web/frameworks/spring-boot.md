## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes
at no cost. Redistribution, resale, or incorporation into commercial products or
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful,
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.

# Spring Boot — Web Framework Architecture Guide

Loaded by `architect/web/GUIDE.md` when the project uses Spring Boot.

---

## When to Choose Spring Boot

**Choose it when:** the team knows Java or Kotlin, the domain is complex (long transaction chains, strict compliance, deep integrations), you need microservices at scale (Spring Cloud gives you service discovery, circuit breakers, config server), or the org already runs JVM infrastructure.

**Do not choose it when:** you are building a five-endpoint CRUD API (use FastAPI or Express), the team has no JVM experience and a deadline, you need sub-100ms serverless cold starts, or you are prototyping and need minimal ceremony.

---

## Project Structure

Package-by-feature, not package-by-layer. A `subscription` package contains its controller, service, repository, DTOs, and entity — not scattered across `controllers/`, `services/`, `repositories/`.

```
src/main/java/com/example/subscriptions/
├── SubscriptionApplication.java        — @SpringBootApplication entry point
├── subscription/                       — Feature: controller, service, repo, entity, DTOs, mapper
├── payment/                            — Feature: same pattern
├── shared/                             — config/, error/, security/ (cross-cutting)
└── infrastructure/                     — Adapters: Stripe, email providers

src/main/resources/
├── application.yml / application-dev.yml / application-prod.yml
└── db/migration/                       — Flyway SQL (V1__create_subscriptions.sql)

src/test/java/...                       — Mirrors main: unit, @WebMvcTest, integration/
build.gradle | Dockerfile | docker-compose.yml
```

**Initializr deps:** Spring Web, Spring Data JPA, Spring Security, Actuator, Flyway, PostgreSQL Driver, Validation.

---

## Routing

Controllers are thin — validate, delegate, return. Zero business logic.

```java
@RestController
@RequestMapping("/api/v1/subscriptions")
public class SubscriptionController {
    private final SubscriptionService service;
    public SubscriptionController(SubscriptionService service) { this.service = service; }

    @GetMapping
    ResponseEntity<Page<SubscriptionDto>> list(@RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(service.findAll(PageRequest.of(page, Math.min(size, 100))));
    }
    @GetMapping("/{id}")
    ResponseEntity<SubscriptionDto> getById(@PathVariable UUID id) {
        return ResponseEntity.ok(service.findById(id));
    }
    @PostMapping
    ResponseEntity<SubscriptionDto> create(@Valid @RequestBody CreateSubscriptionRequest req) {
        SubscriptionDto created = service.create(req);
        return ResponseEntity.created(URI.create("/api/v1/subscriptions/" + created.id())).body(created);
    }
    @PostMapping("/{id}/cancel")
    ResponseEntity<SubscriptionDto> cancel(@PathVariable UUID id) {
        return ResponseEntity.ok(service.cancel(id));
    }
}
```

Use `@GetMapping`/`@PostMapping`/`@PatchMapping`/`@DeleteMapping` — never generic `@RequestMapping(method = ...)`. Non-CRUD actions: `POST /{id}/action`. Always return `ResponseEntity` for explicit status codes.

---

## Data Layer

Spring Data JPA with Flyway. Hibernate generates nothing — Flyway owns the schema.

```java
@Entity @Table(name = "subscriptions")
public class Subscription {
    @Id @GeneratedValue(strategy = GenerationType.UUID) private UUID id;
    @Column(nullable = false) private UUID userId;
    @Column(nullable = false) private String planId;
    @Enumerated(EnumType.STRING) @Column(nullable = false) private SubscriptionStatus status;
    @Column(nullable = false, updatable = false) private Instant createdAt;
    @Column(nullable = false) private Instant updatedAt;
    private Instant cancelledAt;
    @PrePersist void onCreate() { createdAt = updatedAt = Instant.now(); }
    @PreUpdate  void onUpdate() { updatedAt = Instant.now(); }
    public void cancel() {  // Domain method — not a setter
        if (this.status == SubscriptionStatus.CANCELLED) throw new IllegalStateException("Already cancelled");
        this.status = SubscriptionStatus.CANCELLED;
        this.cancelledAt = Instant.now();
    }
}

public interface SubscriptionRepository extends JpaRepository<Subscription, UUID> {
    Page<Subscription> findByUserId(UUID userId, Pageable pageable);  // Derived query
    @Query("SELECT s FROM Subscription s WHERE s.status = :status AND s.updatedAt < :cutoff")
    List<Subscription> findStaleByStatus(@Param("status") SubscriptionStatus status,
                                         @Param("cutoff") Instant cutoff);
}
```

`@Transactional` belongs on the service layer. Use `readOnly = true` on reads — it changes connection routing and disables dirty-checking.

```java
@Service
public class SubscriptionService {
    private final SubscriptionRepository repo;
    private final PaymentGateway payments;
    public SubscriptionService(SubscriptionRepository repo, PaymentGateway payments) {
        this.repo = repo; this.payments = payments;
    }
    @Transactional(readOnly = true)
    public SubscriptionDto findById(UUID id) {
        return SubscriptionMapper.INSTANCE.toDto(
            repo.findById(id).orElseThrow(() -> new ResourceNotFoundException("Subscription", id)));
    }
    @Transactional
    public SubscriptionDto cancel(UUID id) {
        Subscription sub = repo.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Subscription", id));
        sub.cancel();
        payments.cancelRecurring(sub.getId());
        return SubscriptionMapper.INSTANCE.toDto(repo.save(sub));
    }
}
```

**Flyway migrations** in `src/main/resources/db/migration/`. Never modify after applied. Default Flyway over Liquibase — plain SQL is simpler. Liquibase only for DB-vendor-agnostic migrations.

```sql
-- V1__create_subscriptions.sql
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY, user_id UUID NOT NULL, plan_id VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    cancelled_at TIMESTAMPTZ);
CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
```

---

## Middleware-like Patterns

Spring's equivalents: servlet filters, `HandlerInterceptor`, and `@ControllerAdvice`.

**Servlet filter** — request/response transformation (request ID, MDC propagation):

```java
@Component @Order(1)
public class RequestIdFilter extends OncePerRequestFilter {
    @Override protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
            FilterChain chain) throws ServletException, IOException {
        String id = Optional.ofNullable(req.getHeader("X-Request-Id")).orElse(UUID.randomUUID().toString());
        MDC.put("requestId", id);
        res.setHeader("X-Request-Id", id);
        try { chain.doFilter(req, res); } finally { MDC.clear(); }
    }
}
```

**@ControllerAdvice** — one class handles all exceptions. No try-catch in controllers.

```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(ResourceNotFoundException.class)
    ResponseEntity<ErrorResponse> notFound(ResourceNotFoundException ex) {
        return ResponseEntity.status(404).body(new ErrorResponse("not_found", ex.getMessage()));
    }
    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorResponse> validation(MethodArgumentNotValidException ex) {
        var details = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> new FieldError(e.getField(), e.getDefaultMessage())).toList();
        return ResponseEntity.badRequest().body(new ErrorResponse("validation_error", "Invalid input", details));
    }
    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> unexpected(Exception ex) {
        log.error("Unhandled exception", ex);
        return ResponseEntity.internalServerError().body(new ErrorResponse("internal_error", "Unexpected error"));
    }
}
```

---

## Authentication

Use Spring Security. Do not build your own auth framework.

```java
@Configuration @EnableWebSecurity
public class SecurityConfig {
    @Bean SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(csrf -> csrf.disable())   // Stateless API — no CSRF needed
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                .requestMatchers("/api/v1/public/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .build();
    }
}
```

Method-level security with `@PreAuthorize` — add `@EnableMethodSecurity` to a config class:

```java
@PreAuthorize("hasAuthority('subscriptions:write')")
@Transactional
public SubscriptionDto cancel(UUID id) { /* ... */ }
```

Default deny (`anyRequest().authenticated()`). Health/info actuator always public. Never disable CORS in prod. Stateless only.

---

## API Patterns

**DTOs as records** — immutable, concise, built into the language. No Lombok `@Data` for DTOs.

```java
public record SubscriptionDto(UUID id, UUID userId, String planId,
        SubscriptionStatus status, Instant createdAt, Instant cancelledAt) {}
public record CreateSubscriptionRequest(
        @NotNull UUID userId, @NotBlank @Size(max = 50) String planId,
        @NotNull @Positive BigDecimal amount, @NotBlank @Email String billingEmail) {}
```

**MapStruct** for entity-to-DTO mapping — generates boilerplate at compile time, never map manually:

```java
@Mapper(componentModel = "spring")
public interface SubscriptionMapper {
    SubscriptionMapper INSTANCE = Mappers.getMapper(SubscriptionMapper.class);
    SubscriptionDto toDto(Subscription entity);
}
```

**Pagination:** always, cap at 100. **Bean Validation:** `@Valid` on `@RequestBody` at the controller boundary; errors flow to `GlobalExceptionHandler`.

---

## Testing Strategy

Three levels, each with a clear purpose.

**Unit tests** — fast, no Spring context. Mockito for dependencies.

```java
@ExtendWith(MockitoExtension.class)
class SubscriptionServiceTest {
    @Mock SubscriptionRepository repo;
    @Mock PaymentGateway payments;
    @InjectMocks SubscriptionService service;

    @Test void cancel_active_setsStatusCancelled() {
        Subscription sub = createActiveSubscription();
        when(repo.findById(sub.getId())).thenReturn(Optional.of(sub));
        when(repo.save(any())).thenAnswer(i -> i.getArgument(0));
        assertThat(service.cancel(sub.getId()).status()).isEqualTo(SubscriptionStatus.CANCELLED);
        verify(payments).cancelRecurring(sub.getId());
    }
}
```

**@WebMvcTest** — controller layer only. Validates routing, serialization, security.

```java
@WebMvcTest(SubscriptionController.class) @Import(SecurityConfig.class)
class SubscriptionControllerTest {
    @Autowired MockMvc mockMvc;
    @MockBean SubscriptionService service;

    @Test @WithMockUser(authorities = "subscriptions:read")
    void getById_returns200() throws Exception {
        when(service.findById(any())).thenReturn(testDto());
        mockMvc.perform(get("/api/v1/subscriptions/{id}", UUID.randomUUID()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ACTIVE"));
    }
}
```

**@SpringBootTest + Testcontainers** — full stack, real PostgreSQL in Docker. Use sparingly.

```java
@SpringBootTest(webEnvironment = RANDOM_PORT) @Testcontainers
class SubscriptionIntegrationTest {
    @Container static PostgreSQLContainer<?> pg = new PostgreSQLContainer<>("postgres:16-alpine");
    @DynamicPropertySource static void props(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", pg::getJdbcUrl);
        r.add("spring.datasource.username", pg::getUsername);
        r.add("spring.datasource.password", pg::getPassword);
    }
    @Autowired TestRestTemplate rest;
    @Test void createAndCancel_fullLifecycle() { /* POST create → POST cancel → assert CANCELLED */ }
}
```

Never mock the database in integration tests. Use builder patterns for test data, not shared mutable state.

---

## Deployment (Walking Skeleton)

All seven before writing business logic:

1. **Embedded Tomcat** — `./gradlew bootRun` serves a health endpoint locally
2. **Docker image** — multi-stage Dockerfile, minimal JRE, non-root user
3. **Gradle wrapper committed** — `./gradlew build` works on a clean checkout
4. **Health actuator** — `GET /actuator/health` returns `{"status":"UP"}`
5. **PostgreSQL connected** — Flyway runs first migration on startup
6. **CI green** — push to main triggers build, test, container publish
7. **Deployed to staging** — container runs with `application-prod.yml` active

```yaml
management:
  endpoints.web.exposure.include: health, info, prometheus
  endpoint.health:
    show-details: when-authorized
    probes.enabled: true   # /actuator/health/liveness + /readiness
```

---

## Spring Boot-Specific Quality Checklist

- [ ] Constructor injection only — no `@Autowired` on fields or setters
- [ ] Records for all DTOs — no Lombok `@Data` on request/response objects
- [ ] Profiles for environment config — `application.yml` defaults, `-dev`/`-prod` overrides
- [ ] `@Transactional(readOnly = true)` on every read — changes routing and flush behavior
- [ ] `ddl-auto=validate` in prod — Flyway owns the schema, Hibernate validates
- [ ] All secrets externalized — nothing sensitive in `application.yml`
- [ ] Actuator secured — only `/health` and `/info` public
- [ ] Graceful shutdown — `server.shutdown=graceful`, 30s drain timeout
- [ ] No circular dependencies — refactor, never suppress with `@Lazy`
- [ ] `spring.jpa.open-in-view=false` set explicitly

---

## Common Failure Modes

| Failure | Symptom | Fix |
|---|---|---|
| **LazyInitializationException** | `no Session` outside a transaction | `@Transactional` on the service method, or `JOIN FETCH`. Never enable `open-in-view`. |
| **N+1 queries** | 1 + N queries on list endpoints | `@EntityGraph` or `JOIN FETCH`. Detect with `show-sql=true`. |
| **Circular dependencies** | `beans form a cycle` on startup | Extract shared logic into a new service. Never use `@Lazy`. |
| **Field injection** | Untestable without full Spring context | Constructor injection. Class becomes a plain object. |
| **Fat controllers** | Logic in controllers, need `@SpringBootTest` | One service call per handler. All logic in service layer. |
| **Missing readOnly** | Write connections for reads, broken routing | `@Transactional(readOnly = true)` on every read method. |
| **Annotation overuse** | Cannot trace runtime behavior | Prefer explicit code when behavior is non-obvious. |
| **Monolithic test context** | 10+ min test suite | `@WebMvcTest`, `@DataJpaTest`. Reserve `@SpringBootTest` for integration. |
