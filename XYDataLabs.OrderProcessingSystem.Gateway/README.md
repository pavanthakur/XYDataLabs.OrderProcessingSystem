# Gateway

YARP reverse proxy for the Phase 10 containerized service graph. Locally it routes to Docker service names or localhost ports; in Azure Container Apps the deployment injects same-environment Container Apps service names through configuration.

For Azure Container Apps, forwarded requests use the destination service host instead of preserving the original public gateway host. ACA routes internal calls by service host, so the gateway accepts its public ACA hostname and its internal `orderprocessing-gate-<env>` service-name shape, then forwards to `orderprocessing-<service>-<env>` destinations.

## Routes

| Route | Match | Forwards to |
|-------|-------|-------------|
| `orders-path` | `/api/*` | Orders API |
| `inventory-path` | `/inventory/*` | Inventory API |
| `notifications-path` | `/notifications/*` | Notifications API |
| `ui-path` | `/app/*` | UI |

## Verification

- Gateway health: `/`
- Orders API smoke through gateway: `/api/v1/Info/runtime-configuration`

## Purpose

- Experiments with modular monolith routing and future microservice decomposition patterns.
- Used in Gateway launch profiles, Phase 10 Docker profiles, and the Azure Container Apps Phase 10 deployment.

## Rules

- No business logic — pure routing config in `appsettings.json`.
- Gateway tests in `tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests/` verify routing behaviour.
