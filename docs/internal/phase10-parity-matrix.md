# Phase 10 Local-To-Azure Parity Matrix

This document records the next implementation slice after the Phase 10 transport/operator baseline.

The baseline is already proven in dev:
- local Docker Dev HTTP uses compose-managed SQL Server and Redis
- Azure dev currently proves the transport/operator path without SQL or Redis in the active Phase 10 stack

The next change set should use the local Docker container graph as the contract and then reintroduce Azure SQL and Azure Redis only when the workflow wiring is ready.

## Contract Summary

| Concern | Local Docker reference | Azure Phase 10 target | Owner | Current status |
|---|---|---|---|---|
| SQL | `Resources/Docker/docker-compose.database.yml` + `docker-compose.dev.yml`; connection string key `ConnectionStrings__OrderProcessingSystemDbConnection`; secret source `LOCAL_SQL_PASSWORD` | Reintroduce as an environment-scoped Azure app resource when the parity branch lands | `01 Phase 10 Azure Deploy Orchestrator` | Not in active Azure baseline |
| Redis | Compose-managed `redis:7-alpine` service; app config points at `Redis: localhost:6379` | Reintroduce as an environment-scoped Azure cache only if a real Azure runtime need is confirmed | `01 Phase 10 Azure Deploy Orchestrator` | Not in active Azure baseline |
| ACR | Local build/pull parity is represented by the Docker hook and image build logs | Persistent platform ACR in `rg-orderprocessing-platform` with scoped pull-token runtime auth | `00 Azure Platform Foundation` + deploy wrapper | Implemented |
| ACR cleanup | Local parity keeps the container graph disposable between runs | Scheduled image cleanup keeps active Container App revisions safe while pruning stale tags | `Phase 10 Retention Cleanup (Internal)` | Implemented |
| App RG cleanup | `docker compose down` and local cleanup hook reset the dev stack | `cleanupInfra=true` deletes the environment RG only | `01 Phase 10 Azure Deploy Orchestrator` | Implemented |

## Azure Parity Rules

1. Do not move SQL or Redis into the platform foundation RG unless a shared-platform need appears.
2. Keep `00 Azure Platform Foundation` focused on persistent ACR and the runtime pull identity.
3. Keep `Assign AcrPull=false` for the normal path; the privileged fallback remains optional only.
4. Keep ACR lifecycle tightening in the scheduled retention workflow, not in the deploy wrapper.
5. Redeploy `dev` only after the parity matrix and workflow inputs are committed and reviewed.

## Suggested Next Change Set

1. Add explicit SQL and Redis workflow inputs to the Phase 10 deploy path.
2. Reintroduce the Azure SQL module only where the runtime actually needs it.
3. Add Azure Cache for Redis only if the current Azure runtime path still requires it.
4. Update the wrapper summary to show SQL and Redis ownership and cleanup scope.
5. Keep the retention workflow responsible for stale image and artifact cleanup.

## Operating Notes

- The current Azure deployment should not be treated as incomplete just because SQL and Redis are absent; that is the current baseline.
- The parity branch is for closing the gap between the local Docker contract and Azure, not for broadening the transport slice.
- If a later review decides Redis is unnecessary in Azure, keep it documented as a deliberate exclusion instead of a silent omission.
