# Gateway

YARP reverse proxy — local entry point that routes requests to the API and UI. Not deployed to Azure (Azure uses direct App Service URLs).

## Routes (local only — port 5080)

| Route | Match | Forwards to |
|-------|-------|-------------|
| `orders-host` | `orders.localhost/*` | API `http://localhost:5010/` |
| `orders-path` | `localhost/api/*` | API `http://localhost:5010/` |
| `orders-swagger` | `localhost/swagger/*` | API `http://localhost:5010/` |
| `ui-host` | `ui.localhost/*` | UI `http://localhost:5173/` |
| `ui-path` | `localhost/app/*` → strips `/app` prefix | UI `http://localhost:5173/` |

## Purpose

- Experiments with modular monolith routing and future microservice decomposition patterns.
- Used in Gateway launch profiles: `1 Run: 06 Gateway Baseline Http` and Docker gateway profiles.

## Rules

- No business logic — pure routing config in `appsettings.json`.
- Gateway tests in `tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests/` verify host-based routing behaviour.
