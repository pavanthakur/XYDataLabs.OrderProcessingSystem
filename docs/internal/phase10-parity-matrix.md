# Phase 10 Local-To-Azure Parity Matrix

This document records the next implementation slice after the Phase 10 transport/operator baseline.

The baseline is already proven in dev:
- local Docker Dev HTTP uses compose-managed SQL Server and Redis
- Azure dev now treats SQL and Azure Managed Redis as part of the active Phase 10 baseline stack

The next change set should use the local Docker container graph as the contract and then reintroduce Azure SQL and Azure Redis only when the workflow wiring is ready.

## Contract Summary

| Concern | Local Docker reference | Azure Phase 10 target | Owner | Current status |
|---|---|---|---|---|
| SQL | `Resources/Docker/docker-compose.database.yml` + `docker-compose.dev.yml`; connection string key `ConnectionStrings__OrderProcessingSystemDbConnection`; secret source `LOCAL_SQL_PASSWORD` | Part of the automatic Phase 10 baseline path in Azure | `01 Phase 10 Azure Deploy Orchestrator` | Automatic baseline |
| Redis | Compose-managed `redis:7-alpine` service; app config points at `Redis: localhost:6379` | Azure Managed Redis `Balanced_B0` with TLS port `10000` as part of the automatic Phase 10 baseline path | `01 Phase 10 Azure Deploy Orchestrator` | Automatic baseline |
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

1. Keep SQL and Redis in the automatic baseline path and verify they remain aligned with the local Docker contract.
2. Reintroduce or remove the Azure SQL and Redis modules only if a future architecture review changes the contract.
3. Keep Azure Managed Redis aligned with the local Docker contract only if the runtime still needs it after the dev proof.
4. Update the wrapper summary to show SQL/Redis ownership and cleanup scope.
5. Keep the retention workflow responsible for stale image and artifact cleanup.

## Operating Notes

- The current Azure deployment should be treated as the automatic baseline only when SQL and Redis are present in the default path; if they are absent, the workflow or parameter set needs correction rather than a new operator toggle.
- The parity branch is for closing the gap between the local Docker contract and Azure, not for broadening the transport slice.
- If a later review decides Redis is unnecessary in Azure, keep it documented as a deliberate exclusion instead of a silent omission.
