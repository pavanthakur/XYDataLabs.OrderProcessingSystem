# Application Insights Setup (Legacy Manual Approach)

> ⚠️ **DEPRECATED - Use Automated Setup Instead**
> 
> **As of November 2025**, this manual setup approach is no longer recommended. 
> 
> **Please use the automated enterprise approach instead:**
> - **[APP_INSIGHTS_AUTOMATED_SETUP.md](./APP_INSIGHTS_AUTOMATED_SETUP.md)** ⭐ NEW - Automated environment-wise configuration
> - **[AZURE_DEPLOYMENT_GUIDE.md](./AZURE_DEPLOYMENT_GUIDE.md)** → "Step 7: Application Insights (Enterprise)" - Main deployment guide
>
> **Why switch to automated?**
> - ✅ Environment isolation (separate App Insights per dev/staging/prod)
> - ✅ Zero manual configuration - fully automated via GitHub Actions
> - ✅ Secure secret management via GitHub App authentication
> - ✅ Infrastructure as Code with Bicep templates
> - ✅ Follows Azure Well-Architected Framework best practices

---

## Legacy Manual Setup (For Reference Only)

This section is maintained for reference and troubleshooting existing manual setups only. **Do not use for new deployments.**

### Quick run (workspace-based, per-app, with diagnostics + auto-instrumentation):

```powershell
# Legacy approach - not recommended for new deployments
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

### Notes:
- No code changes required when using App Service auto-instrumentation.
- `APPLICATIONINSIGHTS_CONNECTION_STRING` is set on both apps.
- Diagnostics (HTTP/App/Console/Platform + AllMetrics) are routed to the workspace.
- Allow 2–5 minutes after first traffic for telemetry to appear in queries.

### KQL snippets:
- Requests: `requests | where timestamp > ago(30m) | summarize count() by cloud_RoleName`
- HTTP Logs: `AppServiceHTTPLogs | where TimeGenerated > ago(30m) | summarize count()`

### Troubleshooting:
- Verify app settings contain `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- Tail logs: `az webapp log tail -n <app> -g rg-orderprocessing-dev`.

### Migrating to Automated Setup

If you have existing manual App Insights setup and want to migrate to the automated approach:

1. Review the automated setup documentation: [APP_INSIGHTS_AUTOMATED_SETUP.md](./APP_INSIGHTS_AUTOMATED_SETUP.md)
2. Run the Azure Bootstrap workflow with `bootstrapInfra = true`
3. The automated setup will:
   - Create new App Insights resources if they don't exist
   - Configure connection strings as environment secrets
   - Update App Service settings automatically

### References:
- **[APP_INSIGHTS_AUTOMATED_SETUP.md](./APP_INSIGHTS_AUTOMATED_SETUP.md)** - Modern automated setup (recommended)
- **[AZURE_DEPLOYMENT_GUIDE.md](./AZURE_DEPLOYMENT_GUIDE.md)** - Complete deployment guide
- Azure Monitor Application Insights documentation
- ASP.NET Core Applications with Application Insights
