# Phase 10 Implementation Checklist

This checklist turns the Phase 10 kickoff into a repo-specific transport plan.

Anchor flow for the first slice:
- `Orders` emits the `OrderCreatedV1` integration event.
- `Service Bus` carries the durable handoff.
- `Inventory` and `Notifications` consume the downstream event.
- `SharedContracts` stays deferred unless the transport slice proves a real duplication need.
- `infra/modules/servicebus.bicep` owns the transport topology, auth-rule naming, and connection-string lookup, while `infra/main.phase10.bicep` consumes that module output instead of exposing a secret from a child lookup.

## Tracker Status

| Area | Status | Notes |
|---|---|---|
| Phase 10 repo transport wiring | In progress | The Service Bus topology, transport adapter layer, startup seam, and DLQ replay path are in the repo; Azure proof is still pending. |
| Phase 10 docs and runbooks | Done | The checklist, smoke runbook, DLQ replay guide, and progress tracker are aligned with the transport-first order. |
| SharedContracts extraction | Deferred | Keep it out unless transport work proves real duplication across multiple services. |
| Azure dev what-if / deploy | Pending Azure auth | The Bicep shape is updated and locally compiled, but the cloud validation still needs a working Azure login/session and deployment run. |
| Phase 10 smoke / replay testing | Pending deployment | Start after a successful dev deployment and verify publish, consume, DLQ, and replay behavior end to end. |
| Cleanup policy closeout | Separate follow-up | GHCR cleanup, artifact retention, and Log Analytics retention stay outside the deploy wrapper; finalize the workspace policy choice last. |

### Cleanup Policy Snapshot

| Area | Current state | Remaining? |
|---|---|---|
| Azure resource-group teardown | Covered by `cleanupInfra=true` in the Phase 10 wrapper | No |
| GHCR package cleanup | Covered by `phase10-retention-cleanup.yml` | No |
| GitHub artifact retention | Covered by `retention-days` plus optional cleanup in the housekeeping workflow | No for the updated workflows |
| Azure Log Analytics retention | Separate workspace/Bicep/Azure Policy decision | Yes, optional follow-up |

Use the existing envelope and metadata types as the canonical shape:
- `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelope.cs`
- `XYDataLabs.OrderProcessingSystem.Application/Events/EventEnvelopeMetadata.cs`
- `XYDataLabs.OrderProcessingSystem.Orders.Features/Events/OrderCreatedV1.cs`
- `XYDataLabs.OrderProcessingSystem.Orders.Features/Events/OrderCreatedDomainEventMapper.cs`

## Phase 10 Exit Gate

Phase 10 is ready to call complete only when all of the following are true:

- The first transport slice is anchored on the order-created path and still uses the canonical envelope contract.
- `SharedContracts` is still deferred unless the transport slice proves real duplication across services.
- Cleanup policy remains a final follow-up item after the Phase 10 transport and deploy path are stable: GHCR cleanup is enforced by the scheduled cleanup workflow, artifact retention is handled at upload plus cleanup, and Log Analytics retention is decided separately at the workspace/IaC/policy layer.
- `infra/modules/servicebus.bicep` defines the topic/subscription topology, TTL, dead-letter forwarding, ownership rules, and transport credentials needed by the first flow.
- `ServiceBusOptions.cs`, `MessageMetadataMapper.cs`, `ServiceBusMessageFactory.cs`, `ServiceBusEventPublisher.cs`, and `DlqReplayWorker.cs` exist and are wired together as the broker-facing adapter layer.
- `StartupHelper.cs` registers the Service Bus adapter and DLQ worker while preserving the in-memory publisher as the local fallback.
- The supporting Azure modules, parameter files, and docs all describe the same transport-first order.
- The regression/architecture tests prove the new transport work does not blur module boundaries, idempotency, or replay behavior.

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
- `build-phase10-images.yml` publishes those host images to GHCR so the deployment parameters can point at real service-specific tags.
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
