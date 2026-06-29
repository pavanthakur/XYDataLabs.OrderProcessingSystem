# ADR-017: Phase Plan Extensions for Cloud-Portable Enterprise Patterns

**Status:** Accepted

## Context
The Phase 8.5 → Phase 14 architecture roadmap in `ARCHITECTURE-EVOLUTION.md` was Azure-native
and end-to-end production-grade, but reviewing it against the modern .NET cloud-native enterprise
stack (per the Julio Casal bootcamp / .NET 10 + Aspire 13 reference) surfaced three gaps that an
enterprise architect role is expected to demonstrate:

1. **Asynchronous payment lifecycle handling.** Phase 8.5 introduced a second-provider path,
   but did not call out a webhook receiver as a first-class deliverable. Real production payment
   integrations cannot rely on synchronous SDK responses alone — refunds, disputes, delayed 3DS
   authorisation, and bank-confirmed captures all arrive asynchronously through signed provider
   events.

2. **Identity-provider portability.** Phase 10 wires Microsoft Entra ID + JWT for the cloud
   deployment. The architecture is technically IdP-agnostic, but the plan never proves that
   portability with a runnable demo. Modern enterprise hiring increasingly expects hands-on
   Keycloak experience as the canonical OSS OIDC reference.

3. **Persistence-engine portability.** Phase 11 establishes database-per-service on Azure SQL.
   The plan never demonstrates that the EF Core abstraction holds against a different RDBMS
   provider. PostgreSQL is the dominant OSS RDBMS in the .NET cloud-native ecosystem (Aspire
   integrations, Azure Database for PostgreSQL Flexible Server, AWS RDS, GCP Cloud SQL) and is
   a routine cost-driven alternative to Azure SQL at scale.

A fourth observation: **.NET Aspire was deferred to Phase 13** as a polish-phase adoption.
Modern cloud-native developer experience expects Aspire to be the inner-loop orchestrator the
moment microservices exist — not an end-state luxury after data ownership and platform
engineering are complete.

## Decision
Insert three new sub-phases and pull Aspire's local orchestration role forward:

| Sub-phase | Insert after | Focus |
|-----------|--------------|-------|
| **Phase 8.7 — Provider Webhook Receiver & Event-Driven Payment Lifecycle** | Phase 8.5 | Signed, idempotent, tenant-aware webhook receiver feeding the Outbox pipeline |
| **Phase 9.5 — Cloud-Portable Identity Showcase (Keycloak Local)** | Phase 9 | Local Keycloak container proving the JWT pipeline accepts any compliant OIDC provider |
| **Phase 11.5 — Polyglot Persistence Showcase (PostgreSQL Module)** | Phase 11 | Notifications module migrated to PostgreSQL while Orders/Inventory/Payments remain on Azure SQL |

Additionally, **Aspire-Lite is introduced in Phase 9** alongside Docker Compose. Both
orchestrators target the same containerized service set; Phase 13 then deepens Aspire with
`DistributedApplicationTestingBuilder` integration tests, manifest-based ACA deployment, and
advanced resource composition.

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Add the three sub-phases (chosen) | Closes enterprise portability gaps; runnable proof of IdP and RDBMS abstraction; production-grade payment lifecycle | Adds three phase boundaries; ~3-4 weeks additional engineering | ✅ Selected |
| Fold the work into existing phases | No new phase boundaries | Diluted focus; bigger PRs; harder to demonstrate the portability proofs as standalone milestones | ❌ Rejected |
| Defer all three to a post-Phase-14 stretch track | Keeps the 14-phase narrative intact | The portability gaps would never close because no business pressure forces them once Phase 14 ships | ❌ Rejected |
| Replace Entra ID with Keycloak in Phase 10 | Single IdP to operate | Loses managed-identity integration with Azure SQL and Key Vault; introduces an OSS IdP that the team must operate themselves; weakens the Azure-native production story | ❌ Rejected |
| Replace Azure SQL with PostgreSQL across the platform | Single RDBMS | Disrupts the established operational baseline on revenue-critical paths; provides no isolation between the migration risk and Orders/Payments | ❌ Rejected |

**Why webhooks live in Phase 8.7 rather than Phase 8.5:** Phase 8.5 is already substantial
(provider-neutral routing, retry classification, provider-aware idempotency, composition-root cleanup). Splitting the webhook
receiver into its own phase keeps each milestone independently reviewable and lets webhook
infrastructure ship before microservice extraction (Phase 9) without coupling the two changes.

**Why Keycloak is local-only:** The cloud production story remains Entra ID + managed identity.
Keycloak runs in Docker Compose `dev` profile only; its purpose is to prove portability of the
auth pipeline, not to operate an OSS IdP at production scale.

**Why Notifications is the PostgreSQL pilot:** It owns its own data after Phase 11, has the
lowest cross-module read coupling, and its data shape (event log, JSONB delivery metadata,
template full-text search) actively benefits from native PostgreSQL features. Failure of this
experiment does not affect Orders or Payments revenue paths.

## Consequences

**Positive:**
- Production-grade provider lifecycle: refunds, disputes, async 3DS, and replay flows all converge
  on the same Outbox-backed event stream as locally-originated events
- Demonstrable identity-provider portability with a runnable local Keycloak demo
- Demonstrable persistence-engine portability with one module on PostgreSQL end-to-end
- Aspire becomes the inner-loop orchestrator the moment services exist (Phase 9), matching
  modern cloud-native developer experience expectations
- Three additional ADR-worthy milestones strengthen the enterprise-architect portfolio narrative

**Negative / Trade-offs:**
- Three additional phase boundaries to plan, document, and verify
- ~3-4 weeks of additional engineering before Phase 14
- Two persistence engines to operate from Phase 11.5 onward (Azure SQL + PostgreSQL) — operational
  surface area increases for the Notifications module specifically
- Two orchestrators in Phase 9 (Docker Compose + Aspire) — contributors must know both until
  Phase 13 deepens the Aspire-only path

**Future obligations:**
- Webhook secret rotation runbook (Phase 8.7)
- Keycloak realm export/import scripts for reproducible local dev (Phase 9.5)
- Azure follow-up for any Keycloak-shaped parity or migration test should be tracked as deferred work and must not replace Entra ID as the production identity model
- PostgreSQL backup and DR parity documentation alongside Azure SQL (Phase 11.5)
- Architecture test enforcing no provider-specific types leak above the Notifications
  Infrastructure layer (Phase 11.5)
- Aspire AppHost project added to the solution and CI build matrix (Phase 9)

## Related
- ADR-014: Azure service coverage rationale (informs which Azure services remain authoritative
  after these portability extensions)
- ADR-015: Deployment readiness probes (webhook receiver health/readiness contract follows
  the same rules)
- `ARCHITECTURE-EVOLUTION.md` — Phases 8.5, 8.7, 9, 9.5, 10, 11, 11.5, 12-14
- Selected-provider webhook security guidance and signature-validation notes captured when the provider is chosen
- Keycloak OIDC: <https://www.keycloak.org/docs/latest/securing_apps/#_oidc>
- Npgsql EF Core provider: <https://www.npgsql.org/efcore/>
