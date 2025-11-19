# Application Insights Setup (Enterprise)

This doc defers to the single source of truth: see `AZURE_DEPLOYMENT_GUIDE.md` → "Application Insights (Enterprise)" for full steps.

Quick run (workspace-based, per-app, with diagnostics + auto-instrumentation):

```powershell
.
Resources\Azure-Deployment\setup-appinsights-dev.ps1 `
  -ResourceGroup rg-orderprocessing-dev `
  -Location centralindia `
  -WorkspaceName logs-orderprocessing-dev `
  -ApiAppName orderprocessing-api-xyapp-dev `
  -UiAppName orderprocessing-ui-xyapp-dev `
  -ApiAppInsights ai-orderprocessing-api-dev `
  -UiAppInsights ai-orderprocessing-ui-dev
```

Notes:
- No code changes required when using App Service auto-instrumentation.
- `APPLICATIONINSIGHTS_CONNECTION_STRING` is set on both apps.
- Diagnostics (HTTP/App/Console/Platform + AllMetrics) are routed to the workspace.
- Allow 2–5 minutes after first traffic for telemetry to appear in queries.

KQL snippets:
- Requests: `requests | where timestamp > ago(30m) | summarize count() by cloud_RoleName`
- HTTP Logs: `AppServiceHTTPLogs | where TimeGenerated > ago(30m) | summarize count()`

Troubleshooting:
- Verify app settings contain `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- Tail logs: `az webapp log tail -n <app> -g rg-orderprocessing-dev`.

References:
- Azure Monitor Application Insights
- ASP.NET Core Applications with Application Insights
