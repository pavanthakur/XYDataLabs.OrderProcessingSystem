# Frontend Workspace

Track U React web implementation lives here.

## Commands

```powershell
cd frontend
npm install
npm run test:web
npm run build
npm run dev:web
```

## Tenant Bootstrap Smoke Checks

The browser smoke test seeds a stale tenant into local storage and verifies the UI still resolves the
runtime bootstrap tenant returned by the API, then confirms follow-up customer requests use that same tenant.

Examples:

```powershell
# Current local HTTP shell
npm run smoke:web:tenant -- --url http://localhost:5173/customers

# Current Docker dev HTTP shell
npm run smoke:web:tenant -- --url http://localhost:5022/customers

# Current Azure dev deployment
npm run smoke:web:tenant -- --url https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net/customers
```

Or use the PowerShell wrapper for named targets:

```powershell
pwsh -File .\scripts\test-frontend-tenant-bootstrap.ps1 -ListTargets
pwsh -File .\scripts\test-frontend-tenant-bootstrap.ps1 -Target all-docker -InstallBrowser
```

## Local API Connectivity

The web app calls relative `/api/*` paths and the Vite development server proxies those requests to
`http://localhost:5010` by default.

Override the proxy target when needed:

```powershell
$env:ORDERPROCESSING_API_BASE_URL = 'http://localhost:5020'
npm run dev:web
```

## Azure App Service Deployment

The Azure deployment workflow builds the SPA with an explicit API origin so the UI App Service can
serve static files while API calls still target the environment-specific API App Service.

Builds accept the following environment variable:

```powershell
$env:VITE_ORDERPROCESSING_API_BASE_URL = 'https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net'
npm run build
```

The generated build artifact also includes an IIS `web.config` so Azure App Service rewrites client
routes back to `index.html`.

Important note:

- `apps/web/public/web.config` is an intentional source file and should stay committed.
- `apps/web/dist/web.config` is generated build output copied from `public/` and should remain ignored with the rest of `dist/`.
- This file matters only because the Azure UI deployment runs on App Service/IIS-style hosting, where SPA route rewrites are needed for deep links such as `/customers` or `/payments/new`.

## OpenAPI Snapshot

`packages/api-sdk/openapi/order-processing.v1.json` is the checked-in contract snapshot for the
current migration window. Refresh it from a running local API before regenerating types.