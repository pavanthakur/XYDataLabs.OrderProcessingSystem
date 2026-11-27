# Phase 10 Local-To-Azure Parity Matrix

This document records the next implementation slice after the Phase 10 transport/operator baseline.

The acceptance baseline keeps distributed caching enabled. A lower-cost Azure-dev learning profile is available for limited no-payment learning checks; it is not equivalent to Redis or full Phase 10 acceptance.

The next change set should use the local Docker container graph as the contract and then reintroduce Azure SQL and Azure Redis only when the workflow wiring is ready.

## Contract Summary

| Concern | Local Docker reference | Azure Phase 10 target | Owner | Current status |
|---|---|---|---|---|
| SQL | `Resources/Docker/docker-compose.database.yml` + `docker-compose.dev.yml`; connection string key `ConnectionStrings__OrderProcessingSystemDbConnection`; secret source `LOCAL_SQL_PASSWORD` | Part of the automatic Phase 10 baseline path in Azure | `01 Phase 10 Azure Deploy Orchestrator` | Automatic baseline |
| Redis | Compose-managed `redis:7-alpine` service; app config points at `Redis: localhost:6379` | `managed-redis`: Azure Managed Redis `Balanced_B0`, TLS; `in-memory-single-replica-dev`: omit Redis and use the existing in-memory `IDistributedCache` fallback on cache-using apps constrained to one replica | `01 Phase 10 Azure Deploy Orchestrator` + `04 Phase 10 Azure Service Preflight` | Managed profile required for acceptance; in-memory profile is dev-only learning |
| ACR | Local build/pull parity is represented by the Docker hook and image build logs | Persistent platform ACR in `rg-orderprocessing-platform` with scoped pull-token runtime auth | `00 Azure Platform Foundation` + deploy wrapper | Implemented |
| ACR cleanup | Local parity keeps the container graph disposable between runs | Manual read-only manifest/revision inventory; digest planner protects active and verified rollback images; deletion is disabled | `Phase 10 Retention Cleanup (Internal)` + `scripts/phase10-acr-retention.mjs` | Preview implemented; deletion blocked |
| App RG cleanup | `docker compose down` and local cleanup hook reset the dev stack | `cleanupInfra=true` deletes the environment RG only | `01 Phase 10 Azure Deploy Orchestrator` | Implemented |

## Azure Parity Rules

1. Do not move SQL or Redis into the platform foundation RG unless a shared-platform need appears.
2. Keep `00 Azure Platform Foundation` focused on persistent ACR and the runtime pull identity.
3. Keep `Assign AcrPull=false` for the normal path; the privileged fallback remains optional only.
4. Keep ACR inventory and any future reviewed digest-retention operation separate from the deploy wrapper. Current ACR workflow is manual and read-only; it does not delete manifests.
5. Redeploy `dev` only after the parity matrix and workflow inputs are committed and reviewed.

6. The in-memory profile is allowed only in `dev`, only for workflow `04` no-payment service preflight, and only when the Redis resource and `ConnectionStrings__Redis` settings are absent. Cache-using Container Apps must have `maxReplicas=1`; staging and production are guarded to require Managed Redis.
7. `deployRedis=false` is an incremental deployment choice, not a delete operation. It does not remove a previously created Redis resource; the in-memory profile preflight fails while that resource remains. Remove it only through a separately reviewed cleanup operation.

## Suggested Next Change Set

1. Keep Managed Redis enabled for complete Phase 10 acceptance and for staging/prod.
2. Use the in-memory profile only for a deliberate dev learning session where Redis-specific behavior is not under test.
3. Keep the one-replica limit in sync with the process-local fallback; never represent it as distributed-cache or horizontal-scale proof.
4. Keep the wrapper summary explicit about selected Redis/cache mode and cleanup scope.
5. Keep the retention workflow responsible for scheduled historical GHCR/artifact cleanup and manual ACR inventory. Do not describe ACR manifest deletion as implemented.

## Operating Notes

- The full acceptance profile requires SQL and Managed Redis. The explicitly selected dev learning profile is a documented exception and cannot produce a full Azure acceptance PASS.
- The parity branch is for closing the gap between the local Docker contract and Azure, not for broadening the transport slice.
- If a later review decides Redis is unnecessary for a specific dev learning run, keep it documented as a deliberate profile selection rather than a silent omission.
