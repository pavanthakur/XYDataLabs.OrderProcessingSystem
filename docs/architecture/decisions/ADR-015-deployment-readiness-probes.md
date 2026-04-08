# ADR-015: Deployment Readiness Probes Must Use Health Endpoints, Not Swagger

## Status
Accepted

## Context

The API deployment workflow originally treated Swagger availability as the post-deploy health gate.
That probe had retry logic and a cold-start buffer, but it was still the wrong contract: Swagger is a
documentation surface, not a readiness signal for whether the application can safely receive traffic.

During the Phase 7 close-out, the repository added `/health/live` and `/health/ready` endpoints and
reviewed whether the workflow could simply switch from `/swagger` to `/health/ready`. That review
found a second trap: default ASP.NET Core health-check endpoint behavior returns HTTP 200 for
`HealthStatus.Degraded` unless `ResultStatusCodes` is overridden. Swapping the workflow URL without
changing the status-code mapping would have created false confidence by letting degraded dependencies
pass the deployment gate.

This decision exists to prevent future contributors from treating Swagger, a root URL, or a JSON body
with a degraded status as proof that the application is actually ready.

## Decision

All automated deployment readiness probes for the API must target `/health/ready`, not `/swagger` or
the application root.

The `/health/ready` endpoint must fail closed:

1. `HealthStatus.Healthy` returns HTTP 200.
2. `HealthStatus.Degraded` returns HTTP 503.
3. `HealthStatus.Unhealthy` returns HTTP 503.

Swagger remains a documentation and manual exploration surface only. It is not part of the deployment
readiness contract.

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Keep using `/swagger` as the deployment gate | Simple HTTP 200 probe, already present in the workflow | Proves documentation is reachable, not that dependencies are ready; can greenlight unhealthy deployments | ❌ Rejected |
| Switch to `/health/ready` but keep default ASP.NET Core status-code mapping | Uses the correct endpoint path | `Degraded` still returns HTTP 200 by default, so the workflow can pass when the app should not take traffic | ❌ Rejected |
| Use `/health/ready` and explicitly map degraded/unhealthy to HTTP 503 | Probe aligns with readiness semantics and fails closed on partial dependency failure | Requires explicit endpoint configuration and a regression test | ✅ Selected |

## Consequences

**Positive:**
- Deployment workflows now test the real readiness contract instead of a documentation endpoint.
- Partial dependency failures (`Degraded`) block deployment completion instead of being silently treated as success.
- The readiness contract is explicit and testable in both code and CI/CD.

**Negative / Trade-offs:**
- A degraded downstream dependency now fails the deployment gate, which can increase failed deploys until dependencies are stabilized.
- Future contributors must understand the difference between liveness, readiness, and documentation surfaces.

**Future obligations:**
- Keep deployment workflows pointed at `/health/ready` unless a new readiness contract supersedes it.
- Preserve explicit `ResultStatusCodes` mapping if health checks are refactored.
- Add regression coverage whenever new ready-tagged checks are introduced so fail-closed behavior remains intact.

## Related

- ADR-010: Runtime Environment Detection
- `XYDataLabs.OrderProcessingSystem.API/Program.cs`
- `.github/workflows/deploy-api-to-azure.yml`
- `tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/TenantMiddlewareTests.cs`