# ADR-014: Azure Service Coverage Rationale

## Status
Accepted

## Context

The project curriculum expanded from Azure App Service and Azure SQL foundations into a broader
cloud-native platform roadmap. During that expansion, an internal analysis identified the Azure
service coverage that an enterprise-grade order-processing system should not skip: hosting,
secrets, serverless/event handling, messaging, relational data, NoSQL read models, and API
gateway capabilities.

That analysis originally lived in a standalone historical note. Deleting the note without
preserving its reasoning would keep the resulting plan changes but lose the explanation for why
those services were added and what gaps were being closed.

## Decision

The repository adopts the following Azure service coverage model as the architectural rationale for
the curriculum and roadmap:

1. App Service / Container Apps are mandatory hosting coverage.
2. Key Vault is mandatory secrets-management coverage.
3. Azure Functions are mandatory serverless and background-processing coverage.
4. Service Bus plus Storage Queue comparison are mandatory messaging coverage.
5. Azure SQL Database remains the primary transactional store.
6. Cosmos DB is required for NoSQL/read-model scenarios.
7. API Management is required for production-grade API gateway coverage.

The curriculum and roadmap must continue to show where each of these appears. If a future edit
removes one of these coverage areas, it must either replace it with an equivalent capability or
update this ADR with the new rationale.

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Keep the analysis only as an archived note | Keeps historical wording intact | Archive was retired; rationale would be lost from active docs | ❌ Rejected |
| Fold only the outcomes into the master curriculum | Keeps the plan lean | Loses why the gaps mattered and why the services were added | ❌ Rejected |
| Preserve the rationale as an ADR and link it from the curriculum | Keeps one active architectural explanation without restoring archive noise | Adds one more ADR to maintain | ✅ Selected |

### Service-by-Service Rationale

| Service | Why it matters | Current coverage path |
|--------|----------------|-----------------------|
| App Service / Container Apps | Core hosting path from monolith to container platform | `1_MASTER_CURRICULUM.md` Days 15-28, 87-93 |
| Key Vault | Passwordless secrets management is non-negotiable | `1_MASTER_CURRICULUM.md` Days 32-40, 85-86 |
| Azure Functions | Serverless processing and background workflows | `1_MASTER_CURRICULUM.md` Days 44-47, 57-64 |
| Service Bus / Storage Queues | Messaging patterns, command vs. queue trade-offs, DLQ handling | `1_MASTER_CURRICULUM.md` Days 48-52, 58-59 |
| Azure SQL Database | Primary relational transactional store | ADR-004 + `1_MASTER_CURRICULUM.md` Days 32-38 |
| Cosmos DB | NoSQL/read-model and high-scale document scenarios | `1_MASTER_CURRICULUM.md` Days 66-70, Architecture Phase 14 |
| API Management | Production-grade external API gateway and policy layer | `1_MASTER_CURRICULUM.md` Days 94-101 |

### Gap-Closure Logic

- Storage Queues were originally underrepresented next to Service Bus, so the curriculum now
  explicitly includes the comparison and queue-triggered work.
- Cosmos DB was originally absent, so it was added as a dedicated week tied to the CQRS read-model
  phase.
- API Management was originally only approximated by YARP concepts, so it was added as explicit
  platform-engineering coverage for external API governance.

## Consequences

**Positive:**
- The reasoning for Azure service selection is now active, not implicit.
- Future maintainers can see why Cosmos DB, APIM, and queue-comparison work exist in the roadmap.
- Archive deletion no longer removes the only coverage-rationale artifact for these services.

**Negative / Trade-offs:**
- This adds one more ADR to the documentation set.
- Future curriculum changes now have an extra architectural checkpoint to keep aligned.

**Future obligations:**
- Keep `docs/learning/curriculum/1_MASTER_CURRICULUM.md` aligned with this coverage model.
- If service coverage changes materially, update this ADR and the curriculum in the same session.

## Related

- ADR-004: EF Core 8 + Azure SQL
- `ARCHITECTURE-EVOLUTION.md`
- `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
- `docs/internal/AZURE-PROGRESS-EVALUATION.md`