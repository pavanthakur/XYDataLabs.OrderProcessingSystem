# Phase 10 Implementation Checklist

This checklist turns the Phase 10 kickoff into a repo-specific transport plan.
It intentionally does **not** reopen Phase 1-9 work; any new enterprise refinements must be captured here in Phase 10 or pushed into later phases.

Anchor flow for the first slice:
- `Orders` emits the `OrderCreatedV1` integration event.
- `Service Bus` carries the durable handoff.
- `Inventory` and `Notifications` consume the downstream event.
- `SharedContracts` stays deferred unless the transport slice proves a real duplication need.
- `infra/modules/servicebus.bicep` owns the transport topology, auth-rule naming, and connection-string lookup, while `infra/main.phase10.bicep` consumes that module output instead of exposing a secret from a child lookup.

## Tracker Status

| Area | Status | Notes |
|---|---|---|
| Phase 10 repo transport wiring | Verified in dev | The Service Bus topology, transport adapter layer, startup seam, and DLQ replay path are in the repo and proved by the July 13, 2026 Azure dev transport smoke. |
| Phase 10 docs and runbooks | Done | The checklist, smoke runbook, DLQ replay guide, and progress tracker are aligned with the transport-first order. |
| Phase 10 operator-experience hardening | Verified in dev | Accepted-host echo, deploy-summary traceability, skip-reason logging, cleanup symmetry, local-vs-CI mapping, and per-service build logs are present in the active workflow path. |
| SharedContracts extraction | Deferred | Keep it out unless transport work proves real duplication across multiple services. |
| Earlier phase scope | Frozen | Do not back-port new enterprise refinements into Phases 1-9; keep them in Phase 10 or later only. |
| Azure dev deploy | Verified | GitHub Actions run `29273224237` built the Phase 10 images and deployed the dev Container Apps transport stack successfully. |
| Phase 10 runtime smoke | Verified | GitHub Actions run `29273711615` proved gateway health, gateway-routed API JSON, UI static route, and UI API proxy bootstrap. |
| Phase 10 transport / replay smoke | Verified | GitHub Actions run `29273881488` proved Service Bus publish, fan-out consume, controlled DLQ forwarding, DLQ replay receive, and replay publish/consume. |
| SQL / Redis baseline wiring | Automatic baseline | The wrapper and child deploy workflows include SQL and Redis as part of the default Phase 10 path; no manual parity toggle is required in the normal operator form. |
| Cleanup policy closeout | Covered for Phase 10 | Historical GHCR retention, ACR stale-tag cleanup, and stale artifact cleanup are scheduled by `phase10-retention-cleanup.yml`, Phase 10 smoke artifacts use `retention-days: 14`, Azure teardown remains manual through `cleanupInfra=true`, and Log Analytics defaults to `30` days in the workspace module. |
| ACR image cleanup policy | Implemented with ACR cutover | The retention workflow cleans dev/staging/prod ACR tags while preserving images referenced by active Container App revisions. |

### Enterprise Standard Placement

Use this table to keep the enterprise plan aligned with the current Phase 10 scope instead of mixing everything into the same release slice.

| Enterprise item | Where it fits | Why |
|---|---|---|
| Single `runId` correlation, one run folder, one summary, one artifact packet | Phase 10 now | This is the execution model and operator UX standard for the current repo flow. |
| GitHub Actions summary and per-run artifact packet | Phase 10 now | This shortens diagnosis and makes CI output deterministic. |
| Secure secrets via GitHub Secrets / Key Vault | Phase 10 now | Required for the live Azure deploy and local parity paths already in the repo. |
| Structured logging with `runId` | Phase 10 now | Needed for the current deploy / smoke / transport traceability. |
| Clean/reuse local validation modes | Phase 10 now | Keeps the operator flow fast while still allowing full rebuilds when needed. |
| ACR lifecycle cleanup plus artifact retention | Phase 10 now | Required to keep image and log storage under control for the live Phase 10 path. |
| Azure platform foundation ACR and pull identity | Phase 10 now | Supports the persistent registry/runtime-pull model without manual RG-level IAM. |
| SQL / Redis parity in Azure | Phase 10 now | Covered by the active Phase 10 baseline and should remain part of the default deploy path. |
| Managed Identity for SQL runtime access | Phase 11+ hardening | Valuable enterprise hardening, but it is not required for the current Phase 10 transport/operator baseline. |
| OpenTelemetry trace/span expansion | Phase 11+ observability | Best treated as the next observability layer after runId-based correlation is stable. |
| SharedContracts extraction | Deferred unless duplication is proven | Keep module boundaries clean until transport code proves real cross-service duplication. |

Practical rule:

- **Phase 10 now** owns execution shape, operator UX, cleanup hygiene, platform foundation, SQL/Redis parity, and live Azure proof.
- **Phase 11+** should own security hardening and distributed tracing once the current Phase 10 baseline is stable.
- **Deferred** items only move forward when the repo proves the need with real duplication or an explicit hardening gate.

### Verified Azure Dev Proof

| Proof | Run | Result | What it proves |
|---|---|---|---|
| Deploy orchestrator | `29273224237` | PASS | Preflight, per-service image build, and Azure dev resource deployment completed through the wrapper path. |
| Runtime smoke | `29273711615` | PASS | Gateway health, gateway-routed API runtime configuration, UI route, and UI API proxy returned `200`. |
| Transport smoke | `29273881488` | PASS | Service Bus topic/subscriptions, fan-out consume, controlled DLQ forwarding, DLQ replay receive, and replay publish/consume passed. |
| Local/CI container parity | `29268434294` | PASS | Docker Dev HTTP E2E passed smoke, integration, payment matrix, and cleanup on the optional CI parity workflow. |

### Cleanup Policy Snapshot

| Area | Current state | Remaining? |
|---|---|---|
| Azure resource-group teardown | Covered by `cleanupInfra=true` in the Phase 10 wrapper | No |
| GHCR package cleanup | Covered by `phase10-retention-cleanup.yml`; weekly schedule keeps latest `10` historical package versions and deletes older versions after `30` days | No |
| ACR package cleanup | Covered by `phase10-retention-cleanup.yml`; weekly schedule keeps latest `10` tags per service, deletes stale tags after `30` days, and skips active Container App revision images | No |
| GitHub artifact retention | Covered by `retention-days: 14` on Phase 10 uploads plus scheduled stale-artifact cleanup after `30` days | No |
| Azure Log Analytics retention | Covered by `infra/modules/loganalytics.phase10.bicep` default `30` day workspace retention | No blocker |
| Azure resource-group scheduled deletion | Intentionally not automated | No; keep destructive cleanup manual |

### ACR Cleanup Implementation Plan

ACR is the enterprise target for Phase 10 runtime images. The ACR cutover is not complete unless image cleanup is implemented alongside image publishing and runtime pull changes.

| Step | Implementation requirement | Done when |
|---|---|---|
| 1 | Provision the persistent platform ACR and runtime pull identity from `00 Azure Platform Foundation` | The platform resource group contains the registry and pull identity; `AcrPull` is granted only when the privileged platform path is allowed to manage RBAC |
| 2 | Build and push gateway, Orders, Inventory, Notifications, and UI images to ACR | The Phase 10 build workflow publishes service-specific ACR image refs |
| 3 | Point the app deployment at the platform ACR and pull identity | Container Apps pull ACR images without `GHCR_READ_TOKEN` and without the app deployment itself creating RG-level role assignments |
| 4 | Keep SQL and Redis in the automatic deploy baseline | The wrapper and child workflow provision SQL and Redis as part of the default Phase 10 path so the operator does not need to toggle them on |
| 5 | Add ACR image cleanup automation | `phase10-retention-cleanup.yml` keeps the latest approved image versions and deletes stale tags/manifests |
| 6 | Retire GHCR runtime dependency | `GHCR_READ_TOKEN` is no longer required by the active Azure deployment path |
| 7 | Update summaries and runbooks | Deploy summary identifies ACR image refs, parity flags, and the cleanup policy owner |

ACR retention default for dev:
- Keep the latest `10` image versions per service.
- Delete untagged or stale image manifests older than `30` days.
- Keep cleanup in dry-run mode for the first manual validation, then enable the schedule after one successful ACR-backed deploy.

ACR retention posture for staging/prod:
- Use a longer retention window than dev.
- Keep release tags that map to deployed revisions.
- Do not delete images referenced by active or rollback Container App revisions.

Use the existing envelope and metadata types as the canonical shape:
- `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelope.cs`
- `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelopeMetadata.cs`
- `XYDataLabs.OrderProcessingSystem.Orders.Features/Events/OrderCreatedV1.cs`
- `XYDataLabs.OrderProcessingSystem.Orders.Features/Events/OrderCreatedDomainEventMapper.cs`

## Phase 10 Exit Gate

Phase 10 is ready to call complete only when all of the following are true:

- The first transport slice is anchored on the order-created path and still uses the canonical envelope contract.
- `SharedContracts` is still deferred unless the transport slice proves real duplication across services.
- Cleanup policy is explicit: historical GHCR retention is enforced by the scheduled cleanup workflow, artifact retention is handled at upload plus scheduled cleanup, Azure Log Analytics retention is set at the workspace module default, and destructive Azure resource cleanup stays manual through `cleanupInfra=true`.
- If ACR is included in the Phase 10 closeout, ACR image cleanup is included in the same implementation slice and GHCR cleanup is left only as historical housekeeping.
- `infra/modules/servicebus.bicep` defines the topic/subscription topology, TTL, dead-letter forwarding, ownership rules, and transport credentials needed by the first flow.
- `ServiceBusOptions.cs`, `MessageMetadataMapper.cs`, `ServiceBusMessageFactory.cs`, `ServiceBusEventPublisher.cs`, and `DlqReplayWorker.cs` exist and are wired together as the broker-facing adapter layer.
- `StartupHelper.cs` registers the Service Bus adapter and DLQ worker while preserving the in-memory publisher as the local fallback.
- The supporting Azure modules, parameter files, and docs all describe the same transport-first order.
- The regression/architecture tests prove the new transport work does not blur module boundaries, idempotency, or replay behavior.
- The dev Azure proof remains green across the deploy orchestrator, runtime smoke, and transport smoke workflows listed above.

If any one of those items is not true, Phase 10 is still in progress.

## File-by-File Checklist

| File | Phase 10 action | Done when |
|---|---|---|
| `docs/internal/phase9-remaining-roadmap.md` | Replace the long Phase 10 kickoff notes with a short pointer to this checklist and keep `SharedContracts` deferred until transport duplication is proven. | The roadmap points here as the single detailed Phase 10 plan. |
| `docs/internal/README.md` | Add this checklist to the internal tracker list so it is discoverable with the other live internal docs. | The internal index links directly to this file. |
| `docs/guides/deployment/aca-migration-plan.md` | Rewrite the phase narrative so the first Phase 10 execution slice is transport-first instead of hosting-first. | The long-form migration guide matches the repo's current Phase 10 order. |
| `docs/internal/AZURE-PROGRESS-EVALUATION.md` | Update the active Azure progress snapshot after the first transport slice is defined or implemented. | The tracker reflects the same order and scope as this plan. |
| `docs/internal/DEFERRED-WORK-LOG.md` | Keep `SharedContracts` and any Azure-side Keycloak parity outside the numbered roadmap until they are genuinely needed. | Deferred work remains recorded separately from Phase 10. |
| `docs/runbooks/servicebus-dlq-replay.md` | Document DLQ triage, poison-message quarantine, and replay decisions for operators. | A reviewer can follow the replay flow without guessing. |
| `docs/runbooks/phase10-azure-smoke.md` (new) | Document the first Azure what-if, deployment, and transport smoke checks for the Phase 10 slice. | A reviewer can run the live transport proof without guessing. |
| `infra/main.phase10.bicep` | Convert the subscription-scope entrypoint from the current App Service topology into the Phase 10 Azure transport stack. | The deployment entrypoint composes Log Analytics, ACA, Service Bus, Functions, Key Vault, and Insights modules. |
| `infra/modules/containerapps.bicep` (new) | Add the ACA environment and the initial container apps for the gateway, Orders, Inventory, Notifications, and UI. | The first transport slice has a deployable ACA compute layer. |
| `infra/modules/servicebus.bicep` (new) | Declare the order-created topic/subscription topology, dead-letter forwarding, TTL, `maxDeliveryCount`, queue/topic ownership rules, and a transport auth rule for the first slice. | The first flow can be provisioned end-to-end from Bicep. |
| `infra/modules/loganalytics.phase10.bicep` (new) | Provision the Log Analytics workspace that backs ACA logging and workspace-based observability for the transport slice. | ACA logs and App Insights share the same observability workspace. |
| `infra/modules/functions.bicep` (new) | Add the DLQ intake/replay worker and any timer-based reconciliation function required by the first slice. | DLQ classification and replay can run outside request handlers. |
| `infra/modules/keyvault.phase10.bicep` | Grant the new runtime identities access to the secrets required by ACA and transport code. | Managed identity can resolve secrets without new hardcoded values. |
| `infra/modules/insights.phase10.bicep` | Extend diagnostics for ACA, Service Bus, Functions, and replay traces. | Correlation and DLQ depth are observable. |
| `infra/modules/identity.phase10.bicep` | Add the identity wiring needed for ACA deployment/runtime access without introducing long-lived secrets. | Deployment and runtime access work with federated identity or managed identity only. |
| `infra/parameters/dev.json` | Add Phase 10 values for ACA sizing, Service Bus, Functions, and diagnostics in dev. | Dev can express the full transport slice. |
| `infra/parameters/staging.json` | Add the same Phase 10 values for staging. | Staging mirrors the same topology with environment-specific sizing. |
| `infra/parameters/prod.json` | Add the same Phase 10 values for prod. | Production can be configured from the same transport contract. |
| `XYDataLabs.OrderProcessingSystem.AppHost/Program.cs` | Keep the local inner-loop graph aligned with the first transport slice and add stand-ins only if the transport work needs them. | Local development still runs while transport code is introduced. |
| `XYDataLabs.OrderProcessingSystem.Gateway/Program.cs` | Keep correlation headers, host rules, rate limiting, and auth propagation ready for the later APIM/YARP rollout. | Gateway behavior stays stable before and after the transport switch. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/StartupHelper.cs` | Register the Service Bus publisher, DLQ/replay workers, and any new transport adapters alongside the current in-memory and outbox services. | The app can switch transport by composition instead of by rewriting the domain model. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Events/InMemoryEventPublisher.cs` | Keep as the local fallback publisher; do not move cloud transport concerns into this class. | Existing local tests continue to pass without Azure dependencies. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusEventPublisher.cs` (new) | Implement the `IEventPublisher` adapter that writes the canonical envelope to Service Bus. | The first flow can publish to Service Bus through a dedicated adapter. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusOptions.cs` (new) | Hold the topology and subscription settings for the first transport slice. | Queue/topic names and retry settings are configurable per environment. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusMessageFactory.cs` (new) | Map the canonical envelope and metadata to the Service Bus message body/properties. | The Service Bus payload matches the existing envelope contract. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/DlqReplayWorker.cs` (new) | Classify dead-lettered messages and replay or quarantine them according to policy. | DLQ handling is an explicit worker, not an ad hoc script. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/MessageMetadataMapper.cs` (new) | Map correlation, causation, tenant, attempt, and failure data into broker metadata. | The broker message carries the transport metadata needed for replay and tracing. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Webhooks/InboxProcessorWorker.cs` | Reuse the existing consumer-side idempotency pattern where the transport slice needs it. | Duplicate deliveries do not create duplicate state. |
| `XYDataLabs.OrderProcessingSystem.Infrastructure/Events/SqlIdempotencyGuard.cs` | Reuse the existing idempotency guard pattern for replay-sensitive operations. | Retry and replay can stay harmless. |
| `XYDataLabs.OrderProcessingSystem.Application.Tests/Events/IntegrationEventMapperRegistryTests.cs` | Extend the mapper registry tests so the order-created event still produces the metadata the transport slice needs. | The mapper registry proves the first transport payload is stable. |
| `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/OutboxPublisherWorkerIntegrationTests.cs` | Add publish/replay assertions for the first transport flow. | Restart and retry behavior is proven for message publication. |
| `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/InboxDeduplicationTests.cs` | Add consumer-idempotency assertions for the Service Bus subscription path. | Duplicate deliveries do not create duplicate writes or state transitions. |
| `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/StartupHelperTransportRegistrationTests.cs` | Prove the startup seam picks the Service Bus publisher when enabled and the in-memory publisher when disabled. | Transport registration switches by configuration instead of by code edits. |
| `XYDataLabs.OrderProcessingSystem.Architecture.Tests/ModuleBoundaryTests.cs` | Keep the API/module surface checks explicit while transport wiring lands. | The module-facing contracts stay stable. |
| `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/SharedContractsGuardTests.cs` | Guard against premature `SharedContracts` extraction or cross-module drift. | The core assemblies do not start depending on `SharedContracts` too early. |
| `XYDataLabs.OrderProcessingSystem.Architecture.Tests/ModuleSchemaAndMigratorTests.cs` | Keep schema ownership and migrator discipline explicit while the transport slice is added. | The new transport work does not blur schema ownership. |

## Recommended Implementation Order

Use this order so the first slice stays transport-first and the repo does not drift into a hosting-only refactor.

1. Lock the transport contract on paper:
   - `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelope.cs`
   - `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelopeMetadata.cs`
   - `XYDataLabs.OrderProcessingSystem.Orders.Features/Events/OrderCreatedV1.cs`
   - `XYDataLabs.OrderProcessingSystem.Orders.Features/Events/OrderCreatedDomainEventMapper.cs`
2. Create the Service Bus topology module:
   - `infra/modules/servicebus.bicep`
3. Add the broker-facing messaging adapter layer:
   - `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusOptions.cs`
   - `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/MessageMetadataMapper.cs`
   - `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusMessageFactory.cs`
   - `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusEventPublisher.cs`
   - `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/DlqReplayWorker.cs`
4. Wire the new transport layer into the app runtime wiring:
   - `XYDataLabs.OrderProcessingSystem.Infrastructure/StartupHelper.cs`
   - `XYDataLabs.OrderProcessingSystem.Infrastructure/Events/InMemoryEventPublisher.cs` stays as the local fallback
5. Add the supporting Azure stack around that first flow:
   - `infra/modules/loganalytics.phase10.bicep`
   - `infra/modules/containerapps.bicep`
   - `infra/modules/functions.bicep`
   - `infra/main.phase10.bicep`
   - `infra/parameters/dev.json`
   - `infra/parameters/staging.json`
   - `infra/parameters/prod.json`
   - `infra/modules/keyvault.phase10.bicep`
   - `infra/modules/insights.phase10.bicep`
   - `infra/modules/identity.phase10.bicep`
6. Re-validate the runtime seam and tests:
   - `XYDataLabs.OrderProcessingSystem.Application.Tests/Events/IntegrationEventMapperRegistryTests.cs`
   - `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/OutboxPublisherWorkerIntegrationTests.cs`
   - `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/InboxDeduplicationTests.cs`
   - `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/StartupHelperTransportRegistrationTests.cs`
   - `XYDataLabs.OrderProcessingSystem.Architecture.Tests/ModuleBoundaryTests.cs`
   - `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/SharedContractsGuardTests.cs`
   - `XYDataLabs.OrderProcessingSystem.Architecture.Tests/ModuleSchemaAndMigratorTests.cs`
7. Update the docs to reflect the new phase order:
   - `docs/internal/phase9-remaining-roadmap.md`
   - `docs/internal/README.md`
   - `docs/guides/deployment/aca-migration-plan.md`
   - `docs/internal/AZURE-PROGRESS-EVALUATION.md`
   - `docs/internal/DEFERRED-WORK-LOG.md`
   - `docs/runbooks/servicebus-dlq-replay.md`
   - `docs/runbooks/phase10-azure-smoke.md` (new)

## Wave 1 Minimum Deliverables

Treat these as the smallest useful implementation slice for the first order-created transport path.

### 1. Contract freeze

- `EventEnvelope.cs` and `EventEnvelopeMetadata.cs` remain the canonical transport shape for message id, correlation, causation, trace, tenant, and occurred time.
- `OrderCreatedV1.cs` remains the integration-event payload for the first flow.
- `OrderCreatedDomainEventMapper.cs` remains the single mapper that bridges the domain event to the first integration event.
- No `SharedContracts` project is introduced in this wave.

### 2. Service Bus topology

- `infra/modules/servicebus.bicep` declares the order-created topic/subscription shape.
- The module parameterizes queue/topic names, `maxDeliveryCount`, TTL, dead-letter forwarding, and a transport auth rule.
- The module stays resource-group scoped so the namespace, topics, and subscriptions are created where the app resource group lives.
- The module makes the first flow explicit for `Orders`, `Inventory`, and `Notifications` without introducing a generic shared-contract layer.

### 3. Messaging adapter layer

- `ServiceBusOptions.cs` stores the topology names and retry policy for the first flow.
- `MessageMetadataMapper.cs` maps correlation id, causation id, tenant id, message id, attempt count, and failure category into broker metadata.
- `ServiceBusMessageFactory.cs` turns the canonical envelope into a broker message body/properties pair.
- `ServiceBusEventPublisher.cs` implements `IEventPublisher` for Service Bus and uses the options, metadata mapper, and factory.
- `DlqReplayWorker.cs` classifies dead letters and separates replayable messages from poison or expired messages.

### 4. App runtime wiring

- `XYDataLabs.OrderProcessingSystem.Infrastructure/StartupHelper.cs` registers the Service Bus transport adapter and DLQ worker.
- `XYDataLabs.OrderProcessingSystem.Infrastructure/Events/InMemoryEventPublisher.cs` remains as the local fallback implementation.
- The new runtime wiring does not change the existing module/public API boundaries.

### 5. Azure stack around the first flow

- `infra/modules/containerapps.bicep` supplies the ACA compute layer for the first slice.
- `infra/modules/containerapps.bicep` now requires explicit image references for the gateway, Orders, Inventory, Notifications, and UI instead of falling back to the hello-world placeholder, and the backend service images are now split per service.
- `XYDataLabs.OrderProcessingSystem.Gateway/`, `XYDataLabs.OrderProcessingSystem.Orders.API/`, `XYDataLabs.OrderProcessingSystem.Inventory.API/`, and `XYDataLabs.OrderProcessingSystem.Notifications.API/` now each have a minimal ASP.NET Core host so the image refs map to real runnable containers.
- `infra/modules/loganalytics.phase10.bicep` supplies the workspace used by ACA logs and workspace-based observability.
- `infra/modules/functions.bicep` supplies the DLQ intake/replay function and any reconciliation helper the first slice needs.
- `infra/main.phase10.bicep` composes the Log Analytics, ACA, Service Bus, Functions, Key Vault, and Insights modules and wires the Service Bus transport connection into the runtime from the Service Bus module output.
- The Phase 10 deployment parameters must supply real image refs for the Container Apps so the gateway and UI revisions can become healthy, with distinct backend images for Orders, Inventory, and Notifications.
- `phase10-deploy-orchestrator.yml` calls `build-phase10-images.yml` to publish those host images to ACR so the deployment parameters can point at real service-specific tags.
- `infra/modules/keyvault.phase10.bicep`, `infra/modules/insights.phase10.bicep`, and `infra/modules/identity.phase10.bicep` are extended only enough to support the first transport slice.
- Before smoke testing, verify the gateway revision is using the intended image and has at least one running replica.
- `infra/parameters/dev.json`, `infra/parameters/staging.json`, and `infra/parameters/prod.json` carry the Phase 10 configuration values for that slice.

### 6. Verification

- `IntegrationEventMapperRegistryTests.cs` prove the first transport payload still maps correctly.
- `OutboxPublisherWorkerIntegrationTests.cs` prove publish/replay behavior remains deterministic for the first flow.
- `InboxDeduplicationTests.cs` prove the consumer side stays idempotent under duplicate deliveries.
- `ModuleBoundaryTests.cs`, `SharedContractsGuardTests.cs`, `StartupHelperTransportRegistrationTests.cs`, and `ModuleSchemaAndMigratorTests.cs` prove the new transport work does not blur module, contract, startup, or schema ownership.

## Wave 1 File Edit Order

Use this exact order when starting implementation so the repo changes stay anchored to the first flow.

1. `infra/modules/servicebus.bicep`
   - Add the Service Bus namespace or module inputs needed for the order-created topic/subscription topology.
   - Surface the names and dead-letter settings that the runtime adapter will consume.
2. `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusOptions.cs`
   - Define the options object that carries topic, subscription, retry, and replay settings.
3. `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/MessageMetadataMapper.cs`
   - Map `EventEnvelope` metadata to broker message/application properties.
4. `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusMessageFactory.cs`
   - Build the broker message body and attach metadata using the canonical envelope shape.
5. `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/ServiceBusEventPublisher.cs`
   - Implement `IEventPublisher` for Service Bus using the options, mapper, and factory.
6. `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/DlqReplayWorker.cs`
   - Classify dead letters, quarantine poison payloads, and leave replayable messages on a clear operator path.
7. `XYDataLabs.OrderProcessingSystem.Infrastructure/StartupHelper.cs`
   - Register the transport adapter, worker, and any supporting options while leaving the in-memory publisher as the local fallback.
8. `infra/modules/loganalytics.phase10.bicep`
   - Provision the workspace that backs ACA logging and workspace-based observability.
9. `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/OutboxPublisherWorkerIntegrationTests.cs`
   - Add a publish/replay assertion that proves the first transport flow survives restart or retry.
10. `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/InboxDeduplicationTests.cs`
    - Add a duplicate-delivery assertion for the Service Bus subscription path.
11. `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/StartupHelperTransportRegistrationTests.cs`
    - Prove the startup seam selects the right publisher based on transport configuration.
12. `XYDataLabs.OrderProcessingSystem.Architecture.Tests/ModuleBoundaryTests.cs`
    - Keep the module surface checks explicit while transport wiring lands.
13. `XYDataLabs.OrderProcessingSystem.Integration.Tests/Scenarios/SharedContractsGuardTests.cs`
    - Add a guard so the transport work cannot silently introduce `SharedContracts` or cross-module drift.

## Deferred Until Duplication Proves It

If the first transport slice shows that the same event or DTO shape is being copied across more than one service, add a thin `XYDataLabs.OrderProcessingSystem.SharedContracts/` project.

Only then should the repo gain:
- shared integration-event DTOs
- versioned envelope helpers
- any common message contracts that would otherwise drift

Do not create that project early. The default Phase 10 position is still service-local contracts until real duplication appears.

## Next Parity Expansion Track

The transport baseline is proven in dev, so the next implementation branch should align Azure with the current local Docker parity without adding new operator toggles or ad hoc switches.

Use [docs/internal/phase10-parity-matrix.md](./phase10-parity-matrix.md) as the single source of truth for the SQL / Redis / ACR follow-up.

### Target order

1. Reintroduce SQL as an explicit Azure app-resource concern where the runtime actually needs it.
2. Reintroduce Redis as an explicit Azure app-resource concern only if the current service configuration proves it is still required in Azure.
3. Tighten ACR lifecycle policy so image publishing, active revision protection, and stale-tag cleanup stay in the same workflow family.
4. Keep platform foundation persistent and keep app cleanup scoped to the environment RG.
5. Redeploy `dev` only after the next change set is reviewed and ready for smoke validation.

### Implementation guardrails

- Treat the local Docker SQL/Redis composition as the comparison baseline for environment variables, secret naming, and service boundaries, while keeping the Azure deploy path automatic.
- Keep SQL and Redis out of the platform foundation RG unless a real shared-platform requirement appears.
- Keep `00 Azure Platform Foundation` focused on persistent ACR, pull identity, and subscription-level Azure resource-provider registration, with `Assign AcrPull=false` as the default.
- Keep image lifecycle tightening in the scheduled retention workflow, not in the deploy wrapper.
- Update wrapper summaries only after the Azure and local contract are aligned.

## Enterprise Execution Packet Track

Use this track to absorb the enterprise run-correlation plan without reopening Phases 1-9. Phase 10 owns the operator-facing proof packet for the transport and Azure parity lane; later phases can deepen the same convention for broader CI/CD and observability.

| Enterprise plan item | Roadmap home | Phase 10 decision | Later-phase carry-forward |
|---|---|---|---|
| Commit current runhook and integration fixes | Phase 10 | Keep the Docker dev HTTP hook and Azure smoke workflow changes as the stable transport/operator baseline. | Use the same baseline as regression evidence before Phase 11 data autonomy work. |
| Single `runId` / run-root convention | Phase 10 | Keep local Phase 10 Docker validation output under one generated run folder and one summary path. | Phase 12 extends the convention to broader CI evidence packets. |
| GitHub Actions artifact packet | Phase 10 + Phase 12 | Phase 10 workflows should publish or summarize one run packet per execution where test artifacts are produced. | Phase 12 standardizes artifact retention, coverage, release evidence, and failure links across non-Phase-10 workflows. |
| GitHub workflow summary | Phase 10 | Current wrapper and smoke workflows must show run ID, resource links, endpoint links, status, and next operator action. | Phase 12 turns this into a repo-wide summary contract. |
| Secret management | Phase 10 + Phase 12 | Use Key Vault, GitHub environment secrets, OIDC, and generated SQL credentials only through workflow-controlled paths. | Phase 12 hardens rotation, options validation, and rollout safety. |
| SQL managed identity hardening | Phase 12 | Not required to close the current transport baseline; do not block Phase 10 on removing SQL admin bootstrap credentials. | Replace stored SQL credentials with managed identity once the Azure parity path is stable. |
| Structured logging with `runId` | Phase 10 + Phase 12 | Keep run-level correlation in validation hooks and workflow summaries. | Phase 12 standardizes Serilog enrichment across services and operators. |
| OpenTelemetry trace/span expansion | Phase 13+ | Do not add new tracing complexity just to close Phase 10; keep existing correlation and App Insights proof intact. | Add deeper cross-service trace/span mapping when distributed app testing and orchestration maturity justify it. |

Phase 10 exit remains focused on transport/operator proof. Anything that broadens governance across the whole repo belongs in Phase 12; anything that deepens distributed tracing and orchestration belongs in Phase 13+.

### Suggested next change-set deliverables

- A SQL/Redis parity matrix that lists the local Docker source, the Azure owner, and the environment-specific value source.
- A Phase 10 workflow update that carries SQL and Redis only when they are intentionally reintroduced into Azure.
- A retention policy note that explains how ACR image tags, historical GHCR cleanup-only packages, and artifacts are pruned without touching the active runtime image set.
- A redeploy checklist for `dev` so the next run happens only after the new contract is committed and reviewed.
