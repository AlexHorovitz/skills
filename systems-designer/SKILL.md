# Systems Designer Skill

<!-- License: See /LICENSE -->

**Version:** 1.2.1

## Purpose
Ensure every feature and system change is production-ready by systematically evaluating operational concerns: reliability, observability, security, performance, deployment safety, and failure recovery.

## When to Use
- Before any feature ships to production
- When reviewing architectural proposals
- During incident post-mortems
- When planning infrastructure changes
- Before major releases or migrations

## Interface

| | |
|---|---|
| **Input** | `.ssd/features/<slug>/01-architect.md` (primary) or a provided spec/description. Can also run independently against a deployed system. |
| **Output** | `.ssd/features/<slug>/02-systems-designer.md` — three-tier production readiness output (machine-checkable / human-review / block-conditions) with YAML frontmatter |
| **Consumed by** | `ssd` (`/ssd ship` reads `block_conditions_met` from frontmatter; any block condition false refuses to ship) |
| **SSD Phase** | `/ssd start`, `/ssd feature`, `/ssd ship` |

**Required output frontmatter:**
```yaml
---
skill: systems-designer
version: 1.2.0
produced_at: <ISO-8601>
produced_by: <agent-name>
project: <project-name>
scope: <feature-slug>
consumed_by: [ssd]
machine_checked:
  tests_exist: true
  indexes_declared: true
  flag_wired: true
  migration_reversible: true
human_review:
  load_test: required|pass|fail|waived
  runbook_accuracy: required|pass|waived
  security_review: required|pass|waived
block_conditions_met: true       # false if ANY block condition fails
block_conditions:
  rollback_plan_exists: true
  observability_hooks: true
  dependency_failure_modes_documented: true
---
```

### Phase 0 — Input Validation

Before performing any production-readiness analysis, verify the architect spec input is complete. If
`.ssd/features/<slug>/01-architect.md` is present, check that every Quality Gate section has real
content (not stub text). If any required section is missing, produce a "send back to architect" summary
listing the gaps and return. Do NOT fill speculative content into an empty spec — that produces false
confidence.

---

> **Language note:** Examples in this skill are written in Python/Django for illustration. When evaluating production readiness for other stacks, adapt the patterns to the project's actual language, framework, and infrastructure. The *concerns* (failure modes, observability, deployment safety) are universal — the implementation details are not.

---

## Core Philosophy

### Production Is Not Just "It Works"

Code that works in development is maybe 30% of the journey. Production-ready means:

| Concern | Question |
|---------|----------|
| **Reliability** | What happens when it fails? |
| **Observability** | How do we know it's failing? |
| **Security** | Who can access what? What's the blast radius? |
| **Performance** | Does it scale? What's the breaking point? |
| **Deployment** | Can we ship it without downtime? Roll it back? |
| **Operations** | Can the on-call engineer fix it at 3am? |

---

## The Production Readiness Checklist

### 1. Failure Modes

**Every external dependency will fail.** Document how.

```markdown
## Failure Mode Analysis: Subscription Service

### Database (PostgreSQL)
| Failure | Detection | Impact | Mitigation |
|---------|-----------|--------|------------|
| Connection pool exhausted | Connection timeout errors | All requests fail | Circuit breaker, queue requests |
| Primary down | Health check fails | Write operations fail | Promote replica, read-only mode |
| Slow queries | p99 latency spike | Degraded performance | Query timeout, kill long queries |

### Payment Provider (Stripe)
| Failure | Detection | Impact | Mitigation |
|---------|-----------|--------|------------|
| API timeout | HTTP timeout | Payments fail | Retry with backoff, queue for later |
| Rate limited | 429 response | Bulk operations fail | Exponential backoff, spread load |
| Webhook delay | Missing events | State mismatch | Periodic reconciliation job |

### Cache (Redis)
| Failure | Detection | Impact | Mitigation |
|---------|-----------|--------|------------|
| Connection refused | Connection error | Cache miss storm | Fallback to DB, circuit breaker |
| Memory full | Eviction warnings | Unpredictable evictions | Memory alerts, eviction policy |
```

**For each failure mode, answer:**
1. How do we detect it? (Metric, log, alert)
2. What's the user impact? (Error page, degraded feature, nothing)
3. What's the mitigation? (Automatic recovery, manual intervention)
4. What's the recovery procedure? (Runbook steps)

### 2. Observability

**If you can't see it, you can't fix it.**

#### Logging Requirements

```python
# Every significant operation must log:
# - WHO: User/system initiating action
# - WHAT: Action being taken
# - CONTEXT: IDs to trace through system
# - RESULT: Success/failure with details

logger.info(
    "Subscription created",
    extra={
        "user_id": user.id,
        "subscription_id": subscription.id,
        "plan_id": plan.id,
        "amount": amount,
        "coupon_used": coupon_code is not None,
        "duration_ms": duration_ms,
    }
)

# Errors must include stack trace and context
logger.exception(
    "Payment processing failed",
    extra={
        "user_id": user.id,
        "payment_method_id": payment_method_id,
        "amount": amount,
        "stripe_error_code": e.code,
    }
)
```

#### Required Metrics

| Category | Metrics | Alert Threshold |
|----------|---------|-----------------|
| **Availability** | Request success rate | < 99.5% |
| **Latency** | p50, p95, p99 response time | p99 > 2s |
| **Throughput** | Requests per second | > 80% capacity |
| **Errors** | Error rate by type | > 1% for 5xx |
| **Saturation** | CPU, memory, connections | > 80% |

#### Dashboard Requirements

Every service needs a dashboard showing:
```
┌─────────────────────────────────────────────────────────┐
│                  Service Health                          │
├──────────────┬──────────────┬──────────────┬────────────┤
│ Request Rate │ Error Rate   │ p99 Latency  │ Saturation │
│   150/s ✓    │   0.1% ✓     │   180ms ✓    │   45% ✓    │
├──────────────┴──────────────┴──────────────┴────────────┤
│                  Request Latency (p50, p95, p99)        │
│  [====================================] Time series     │
├─────────────────────────────────────────────────────────┤
│                  Error Breakdown by Type                │
│  [====================================] Stacked chart   │
├─────────────────────────────────────────────────────────┤
│                  Dependency Health                       │
│  PostgreSQL: ✓   Redis: ✓   Stripe: ✓   S3: ✓         │
└─────────────────────────────────────────────────────────┘
```

#### Distributed Tracing

```python
# Every request must have a trace ID that flows through all services
# Headers: X-Request-ID, X-Trace-ID

@middleware
def tracing_middleware(get_response):
    def middleware(request):
        trace_id = request.headers.get("X-Trace-ID") or generate_trace_id()
        
        with tracer.start_span("http_request") as span:
            span.set_tag("trace_id", trace_id)
            span.set_tag("path", request.path)
            span.set_tag("user_id", request.user.id if request.user.is_authenticated else None)
            
            response = get_response(request)
            
            span.set_tag("status_code", response.status_code)
            response["X-Trace-ID"] = trace_id
            
            return response
    return middleware
```

### 3. Security

**Defense in depth. Assume every layer will be breached.**

#### Authentication & Authorization

```python
# Every endpoint must explicitly declare its auth requirements
# No "auth by obscurity" (hoping attackers don't find the URL)

class SubscriptionViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated, IsSubscriptionOwner]
    
    def get_queryset(self):
        # ALWAYS scope queries to the current user
        # Never trust URL parameters for access control
        return Subscription.objects.filter(user=self.request.user)
```

#### Data Protection

| Data Type | At Rest | In Transit | In Logs | Retention |
|-----------|---------|------------|---------|-----------|
| Passwords | Argon2 hash | HTTPS | Never | Until changed |
| API keys | AES-256 | HTTPS | Masked | Until rotated |
| PII (email, name) | Encrypted | HTTPS | Masked | Per policy |
| Payment tokens | Tokenized (Stripe) | HTTPS | Never | Until expired |

#### Security Checklist

- [ ] SQL injection: Using ORM parameterized queries
- [ ] XSS: Output encoding enabled, CSP headers set
- [ ] CSRF: Tokens on all state-changing operations
- [ ] Authentication: Rate limiting on login, secure session config
- [ ] Authorization: Row-level security verified, no IDOR vulnerabilities
- [ ] Secrets: No secrets in code, environment variables or vault
- [ ] Dependencies: No known vulnerabilities (npm audit, safety check)
- [ ] Headers: Security headers set (HSTS, X-Frame-Options, etc.)

### 4. Performance

**Know your limits before production discovers them.**

#### Load Testing Requirements

Before any feature ships:

```markdown
## Load Test Results: Subscription Creation

### Test Conditions
- Duration: 10 minutes sustained
- Target: 100 requests/second (10x expected peak)
- Data: Realistic mix of plans, coupons, payment methods

### Results
| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Throughput | 100 rps | 120 rps | ✓ |
| p50 latency | < 200ms | 85ms | ✓ |
| p99 latency | < 1000ms | 450ms | ✓ |
| Error rate | < 0.1% | 0.02% | ✓ |
| CPU utilization | < 70% | 55% | ✓ |
| Memory utilization | < 80% | 62% | ✓ |
| DB connections | < 80% pool | 45% | ✓ |

### Bottlenecks Identified
1. Payment API calls are serialized - consider async processing
2. Email sending adds 50ms - already async, acceptable

### Breaking Point
System degrades at ~180 rps (CPU saturation)
```

#### Capacity Planning

```markdown
## Capacity Model: Subscription Service

### Current Usage
- Peak requests: 50/second
- Database size: 10 GB
- Daily growth: 100 MB

### Projections (12 months)
- Peak requests: 200/second (4x)
- Database size: 50 GB (5x)
- Requires: 2 additional app servers, DB upgrade to larger instance

### Scaling Triggers
| Metric | Current | Upgrade At | Action |
|--------|---------|------------|--------|
| Request rate | 50/s | 80/s | Add app server |
| DB CPU | 30% | 60% | Upgrade instance |
| DB size | 10 GB | 40 GB | Upgrade storage |
| Redis memory | 2 GB | 4 GB | Upgrade instance |
```

### 5. Deployment Safety

**Every deploy is a potential incident. Plan accordingly.**

#### Deployment Checklist

```markdown
## Pre-Deployment
- [ ] All tests passing in CI
- [ ] Code reviewed and approved
- [ ] Database migrations tested in staging
- [ ] Feature flags configured (if applicable)
- [ ] Rollback procedure documented
- [ ] Monitoring dashboards open

## Deployment
- [ ] Deploy during low-traffic window
- [ ] Run migrations before code deploy
- [ ] Canary deploy to subset of servers (if applicable)
- [ ] Monitor error rates for 10 minutes
- [ ] Verify key user flows manually

## Post-Deployment
- [ ] Monitor for 30 minutes
- [ ] Check error rates, latency, throughput
- [ ] Verify no increase in support tickets
- [ ] Update deployment log
```

#### Migration Safety

```python
# UNSAFE: Locks table for duration of migration
class Migration(migrations.Migration):
    operations = [
        migrations.AddField(
            model_name='subscription',
            name='new_field',
            field=models.CharField(max_length=255, default=''),
        ),
        migrations.RunSQL(
            "UPDATE subscription SET new_field = computed_value"  # Locks table!
        ),
    ]

# SAFE: Add nullable field, backfill separately, then add constraint
# Migration 1: Add nullable field
class Migration(migrations.Migration):
    operations = [
        migrations.AddField(
            model_name='subscription',
            name='new_field',
            field=models.CharField(max_length=255, null=True),
        ),
    ]

# Migration 2: Backfill in batches (run as management command)
def backfill_new_field():
    batch_size = 1000
    while True:
        ids = list(
            Subscription.objects
            .filter(new_field__isnull=True)
            .values_list('id', flat=True)[:batch_size]
        )
        if not ids:
            break
        
        Subscription.objects.filter(id__in=ids).update(new_field=computed_value)
        time.sleep(0.1)  # Don't hammer the DB

# Migration 3: Add NOT NULL constraint (after backfill complete)
```

#### Feature Flags

```python
# Major features should be behind flags for safe rollout

class FeatureFlags:
    NEW_CHECKOUT_FLOW = "new_checkout_flow"
    ASYNC_PAYMENTS = "async_payments"

def create_subscription(user, plan):
    if feature_flags.is_enabled(FeatureFlags.NEW_CHECKOUT_FLOW, user=user):
        return new_checkout_flow(user, plan)
    else:
        return legacy_checkout_flow(user, plan)

# Flag rollout stages:
# 1. Internal team only
# 2. 1% of users
# 3. 10% of users
# 4. 50% of users
# 5. 100% of users
# 6. Remove flag, delete old code
```

### 3b. Compliance & Data Lifecycle

OWASP basics are covered in §3. Compliance is separate and deploy-blocking for most production systems.
Document each of the following or declare the item not applicable:

- **PII inventory.** Which fields in the data model contain PII? Where are they read and written?
- **Retention policy.** How long is each PII field retained? What triggers deletion?
- **Deletion mechanism.** On user request (GDPR Art. 17 / CCPA opt-out), which systems are touched?
  Is there a runbook?
- **Audit log retention.** How long are access/auth events retained? Who can read them?
- **Data residency.** For each category of data, in which regions is it stored / processed / backed up?

### 6. Operational Readiness

**The on-call engineer at 3am is the ultimate stakeholder.**

#### Runbook Template

```markdown
# Runbook: Subscription Creation Failures

## Overview
This runbook covers diagnosis and resolution of subscription creation failures.

## Symptoms
- Alert: `subscription_creation_error_rate > 5%`
- User reports: "Payment went through but no subscription"
- Dashboard shows spike in creation errors

## Quick Diagnosis

### Step 1: Check Error Breakdown
```sql
SELECT error_type, count(*) 
FROM subscription_errors 
WHERE created_at > now() - interval '1 hour'
GROUP BY error_type
ORDER BY count DESC;
```

### Step 2: Check Dependencies
| Dependency | Health Check | Status |
|------------|--------------|--------|
| PostgreSQL | `pg_isready -h db.internal` | |
| Redis | `redis-cli ping` | |
| Stripe | Check status.stripe.com | |

### Step 3: Check Recent Deployments
```bash
kubectl get deployments -o wide
# Look for recent restart times
```

## Common Issues and Fixes

### Issue: Stripe API Errors
**Symptoms:** Error logs show Stripe connection timeouts
**Fix:** 
1. Check status.stripe.com for outages
2. If Stripe is down, enable maintenance mode for payments
3. If our issue, check API key validity

### Issue: Database Connection Pool Exhausted
**Symptoms:** "connection pool exhausted" in logs
**Fix:**
1. Check for long-running queries: `SELECT * FROM pg_stat_activity WHERE state = 'active';`
2. Kill blocking queries if safe
3. Consider temporary pool size increase

## Escalation
- L1: On-call engineer (this runbook)
- L2: Backend team lead (Slack: @backend-lead)
- L3: VP Engineering (phone: xxx-xxx-xxxx)
```

#### Incident Response

```markdown
## Incident Severity Levels

### P1 - Critical
- Complete service outage
- Data loss or corruption
- Security breach
- Response: All hands, exec notification, status page update

### P2 - Major
- Significant feature unavailable
- Performance severely degraded (>50% slower)
- Response: On-call + backup, status page update

### P3 - Minor
- Single feature degraded
- Affecting <5% of users
- Response: On-call, internal tracking

### P4 - Low
- Cosmetic issues
- Minimal user impact
- Response: Normal ticket queue
```

### 7. AI / LLM Integration

Required when the system calls a hosted LLM (Claude, OpenAI, etc.) or embeds a local model in a hot
path. For production-readiness, evaluate:

- **Prompt injection surface.** Every place user-controlled content enters a prompt must be escaped or
  delimited. See `code-reviewer/examples.md` §2a for the pattern.
- **Output schema validation.** Is the model's structured output validated (pydantic, jsonschema,
  field-by-field) before it's trusted?
- **Cost dashboards.** `$/request`, `$/user`, daily spend, tokens/request. Alert on >20% daily
  deviation.
- **Rate-limit alerts.** Alert on sustained 429s or throttling signals. Do retries compound the problem
  or mitigate it?
- **Schema validation failures as an SLO.** Treat a schema-validation failure rate > X% as a
  production incident, not a warning.
- **Model drift detection.** If outputs are scored / graded, track the score distribution over time.
  A sudden shift is a model update or a prompt regression.
- **Cache-key scoping.** If prompt caching is used, verify keys are user-scoped and system prompts
  don't contain user-specific data.

### 8. Chaos / Failure Injection

Failure modes documented in §1 must be *exercised*, not just catalogued. For each documented failure
mode, declare a periodic exercise (manual or automated). Even a quarterly "flip the flag off and verify"
counts — untested fallbacks rot.

Minimal exercise cadence:
- Each external-dependency circuit breaker opens in a staging game-day ≥ quarterly
- Each rollback procedure is dry-run ≥ quarterly
- Each deploy-order migration is tested against a production snapshot ≥ per migration

### 9. Cost Observability

Beyond availability/latency/throughput, required metrics include cost:

| Metric | Purpose | Alert Threshold |
|---|---|---|
| Monthly cloud spend (per env) | Budget adherence | > budget × 1.1 |
| Cost per request ($) | Unit economics | > target × 1.5 |
| Cost per user ($) | LTV sanity | > target × 1.5 |
| Daily deviation vs 7-day avg | Runaway detection | > 20% |
| LLM tokens per request | Drift / prompt bloat | > baseline × 1.5 |

---

## Production Readiness Review Template

Before any major feature ships:

```markdown
# Production Readiness Review: [Feature Name]

## Overview
Brief description of what's shipping.

## Checklist

### Failure Modes
- [ ] All external dependencies identified
- [ ] Failure mode for each dependency documented
- [ ] Circuit breakers in place for external calls
- [ ] Graceful degradation implemented
- [ ] Retry logic with exponential backoff

### Observability
- [ ] Structured logging for all significant operations
- [ ] Key metrics exposed (latency, throughput, errors)
- [ ] Dashboard created/updated
- [ ] Alerts configured with appropriate thresholds
- [ ] Trace IDs flow through all operations

### Security
- [ ] Authentication required for all endpoints
- [ ] Authorization checks at data access layer
- [ ] No sensitive data in logs
- [ ] Input validation on all user inputs
- [ ] Security review completed (if applicable)

### Performance
- [ ] Load tested at 10x expected traffic
- [ ] Database queries analyzed (no N+1, proper indexes)
- [ ] Caching strategy implemented
- [ ] Resource limits set (timeouts, memory)

### Deployment
- [ ] Database migrations are safe (no locks, reversible)
- [ ] Feature flag in place for rollout control
- [ ] Rollback procedure documented and tested
- [ ] Canary deployment configured

### Operations
- [ ] Runbook created/updated
- [ ] On-call team briefed
- [ ] Support team documentation updated
- [ ] Monitoring reviewed during staging deployment

## Sign-off
- [ ] Engineering Lead
- [ ] SRE/Platform
- [ ] Security (if applicable)
```

### Three-Tier Output (new)

The checklist above is the long-form narrative. For machine-readable gate decisions, the skill also
produces a three-tier summary that maps into frontmatter:

**Tier 1 — Machine-checkable (the skill verifies these itself):**
- Tests exist for the new code path
- Indexes declared for new query patterns
- Feature flag is wired (flag name appears in code + config)
- Migration is reversible (no destructive DDL without two-phase pattern)
- Structured logging present at decision points

**Tier 2 — Human-review (the skill flags these for a reviewer):**
- Load-test results (pass/fail/waived)
- Runbook accuracy (pass/waived)
- Security review (pass/waived — required for auth/PII changes)

**Tier 3 — Block conditions (any failure → cannot ship):**
- Rollback plan exists and is documented
- Observability hooks (logs, metrics, dashboard) exist for the new path
- Dependency failure modes are documented
- Destructive migrations have a tested two-phase plan

A Tier 3 failure sets `block_conditions_met: false` in frontmatter. `/ssd ship` refuses to proceed.

---

## Changelog

- **1.2.1** (2026-04-28) — Working-tree path references updated from `ssd/` to `.ssd/` per repo-wide convention change. See repo CHANGELOG [1.4.0]. No behavior change.

- **1.2.0** (2026-04-18) — Declared output artifact path and YAML frontmatter; added Phase 0 input
  validation against architect spec (S1); three-tier output with machine-check/human-review/block
  conditions (S2); new Concern 3b Compliance & Data Lifecycle (S4); Concern 7 AI/LLM Integration (S3);
  Concern 8 Chaos / Failure Injection (S6); Concern 9 Cost Observability (S5).
- **1.1.0** — Added migration-safety patterns and runbook template.
- **1.0.0** — Initial release.

---

## Common Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Cascading failures | Missing circuit breakers | Add circuit breakers with fallbacks |
| Silent failures | Errors swallowed, no alerts | Add error logging and alerting |
| Slow recovery | No runbooks | Create runbooks for all failure modes |
| Incidents repeat | No post-mortem | Run post-mortem, implement fixes |
| Can't diagnose | Missing observability | Add logging, metrics, tracing |
| Partial outages | No health checks | Add liveness/readiness probes |
