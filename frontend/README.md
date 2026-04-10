# Frontend Workspace

Track U React web implementation lives here.

## Commands

```powershell
cd frontend
npm install
npm run build
npm run dev:web
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

## OpenAPI Snapshot

`packages/api-sdk/openapi/order-processing.v1.json` is the checked-in contract snapshot for the
current migration window. Refresh it from a running local API before regenerating types.